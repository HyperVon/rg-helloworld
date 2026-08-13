#!/usr/bin/env python3
"""Bounded, redacted Kilo model-listing discovery wrapper (target-owned).

This wrapper is invoked by ARR's subprocess discovery runner. It receives the
absolute Kilo executable as argv[0] (resolved once by gen_discovery.py) so it
never resolves `kilo` through a mutable PATH at discovery time.

It emits a DiscoveryReport JSON document on stdout. The report is always marked
secret-redacted and contains only structured fields accepted by
DiscoveryReport.from_mapping -- never raw stderr, exception text, provider
output, credentials, or command output. On any failure it emits a status=unknown
report with no candidates rather than crashing.

Format selection (Kilo v7.4.21 contract): the wrapper performs a bounded local
`kilo models --help` check. When `--verbose` is advertised it parses the
identifier-plus-JSON metadata stream, which supplies explicit cost, context,
status, capability, and variant evidence. Otherwise it selects the one-ID-per-
line table path. This is format selection, NOT fallback: authentication,
network, timeout, malformed output, and unrelated command failures never fall
back and never read credentials, tokens, or raw provider output into the report.

Diagnostics: every run writes the full redacted DiscoveryReport to
discovery-last-report.json (git-ignored, sibling to this script) before any
catalog-cache.json deletion, so an unusable discovery still exposes its safe
error_code and schema-approved fields. Quota is intentionally left unknown
unless Kilo exposes explicit quota evidence; listing status is treated only as
model-catalog availability evidence.

Timeout budget: the version probe (5s), model phase (20s), and optional quota
phase (30s) are separate budgets. The model phase covers a bounded local help
check plus the selected parse path (verbose metadata or table). The whole
operation (5 + 20 + 30 = 55s) fits inside discovery.json's 60s bound.

Quota: when gen_discovery.py finds the locally installed
@slkiser/opencode-quota package, it passes absolute Node/package paths to this
wrapper. The wrapper refreshes the plugin's redacted status JSON and reads its
redacted show JSON, then maps only provider-level remaining percentages or
explicit positive balance values to ARR quota fields. For OpenRouter it also
makes a bounded, redirect-free request to `/api/v1/credits` through the
plugin's own key resolver when the resolver module is available; the key and
response body never enter this process's report. OpenRouter is target-owned as
PAYG; quota entries with an explicit positive budget/credit make its paid
candidates eligible, while missing, stale, expired-auth, malformed, zero, or
failed evidence remains unknown/exhausted and is never promoted to available.
Providers whose plugin entries explicitly report quota/rate-limit windows are
labeled subscription. The plugin is optional so model discovery remains useful
on machines that do not use OpenCode/Kilo auth.

Capability contract: `chat` is the Kilo adapter's documented baseline contract;
`reasoning` and `tool_call` are added only when explicitly present in verbose
metadata.

Process-group cleanup: every child is launched in a new session and the entire
process group is killed on timeout or when the wrapper itself is terminated, so
no inherited stdout/stderr drain hangs and no descendant survives.
"""

import json
import os
import re
import signal
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

EXPECTED_KILO_VERSION = "7.4.21"
PROBE_ID = "kilo-models"
ADAPTER_ID = "kilo"
REPORT_VERSION = 1

_OUTER_BUDGET = 55.0
_VERSION_TIMEOUT = 5.0
_MODELS_TIMEOUT = 20.0
_QUOTA_TIMEOUT = _OUTER_BUDGET - _VERSION_TIMEOUT - _MODELS_TIMEOUT
# ``kilo models --verbose`` returns one JSON metadata object per model.  The
# current catalog is a little over 1 MiB, so retain a bounded 4 MiB ceiling
# while leaving headroom for catalog growth and ARR's own maximum.
MAX_OUTPUT_BYTES = 4 * 1024 * 1024
_HELP_TIMEOUT_CAP = 2.0

# Documented Kilo adapter contract (see module docstring): every listed model is
# chat-capable. Not observed evidence; tightened to real listing fields later.
KILO_MODEL_CONTRACT_CAPABILITIES = ["chat"]

REJECTION_WORDS = ("unknown", "invalid", "unsupported", "unrecognized")
AUTH_FAILURE_HINTS = (
    "401", "403", "unauthorized", "authentication required", "authentication failed",
    "auth failed", "invalid api key", "api key", "token required", "login required",
    "not authenticated", "forbidden",
)
NETWORK_FAILURE_HINTS = (
    "connection refused", "connection reset", "econnrefused", "dns", "getaddrinfo",
    "could not resolve", "host unreachable", "no route to host", "network is unreachable",
    "network", "timed out", "timeout",
)

# Kilo emits canonical IDs in the form ``kilo/<provider>/<model>``.  ARR's
# provider field is the first segment and its model field may contain further
# slash-separated segments (including the documented ``~`` free-model prefix).
# Keep these local validators aligned with ARR's portable identifier contract
# without importing the target-local virtualenv during parser self-tests.
_PROVIDER_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:+\-]{0,199}$")
_MODEL_RE = re.compile(r"^~?[A-Za-z0-9][A-Za-z0-9._:/+\-]*$")

DIAG_REPORT_FILENAME = "discovery-last-report.json"
USABLE_STATUSES = ("verified", "documented", "best_effort")
MAX_QUOTA_AGE_SECONDS = 300.0
PAYG_PROVIDERS = frozenset({"openrouter"})
_BALANCE_VALUE_RE = re.compile(
    r"^\s*[$€£]?\s*[+-]?(?:\d+(?:,\d{3})*|\d+)(?:\.\d+)?\s*$"
)


def _run_bounded(cmd, *, timeout: float, max_output_bytes: int):
    """Run cmd in a new process group with bounded stdout/stderr collection.

    Returns (stdout_bytes, stderr_bytes, returncode, timed_out). Large output is
    truncated at max_output_bytes so a huge provider response cannot consume
    unbounded memory. On timeout the entire child process group is killed so no
    descendant survives and the drain threads see EOF and terminate.
    """
    proc = subprocess.Popen(
        cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True
    )
    out: bytearray = bytearray()
    err: bytearray = bytearray()

    def _drain(stream, target: bytearray) -> None:
        for chunk in iter(lambda: stream.read(1 << 16), b""):
            if len(target) < max_output_bytes:
                target += chunk[: max_output_bytes - len(target)]

    t_out = threading.Thread(target=_drain, args=(proc.stdout, out))
    t_err = threading.Thread(target=_drain, args=(proc.stderr, err))
    t_out.start()
    t_err.start()
    timed_out = False
    try:
        proc.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        timed_out = True
        try:
            os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
        except ProcessLookupError:
            pass
        try:
            proc.wait(timeout=5)
        except Exception:  # noqa: BLE001
            pass
    t_out.join()
    t_err.join()
    # Popen does not close PIPE file objects when the reader threads finish;
    # close them explicitly so repeated quota/model probes do not accumulate
    # descriptors (and so offline tests stay warning-free).
    if proc.stdout is not None:
        proc.stdout.close()
    if proc.stderr is not None:
        proc.stderr.close()
    return bytes(out), bytes(err), proc.returncode, timed_out


def _install_group_cleanup() -> None:
    def _handler(signum, _frame):
        try:
            os.killpg(os.getpgid(os.getpid()), signal.SIGKILL)
        except Exception:  # noqa: BLE001
            pass
        os._exit(1)

    signal.signal(signal.SIGTERM, _handler)
    signal.signal(signal.SIGINT, _handler)


def _flag_supported(kilo, flag: str, *, timeout: float, max_output_bytes: int):
    """Bounded local help check for one Kilo models flag.

    Returns True/False when the help check succeeds, or None when the help check
    itself is indeterminate (timed out or non-zero). This is a local,
    provider-contact-free read.
    """
    out, err, rc, to = _run_bounded(
        [kilo, "models", "--help"], timeout=timeout, max_output_bytes=max_output_bytes
    )
    if to or rc != 0:
        return None
    return flag.lower() in (out + err).decode("utf-8", "replace").lower()


def _classify_models_failure(text: str) -> str:
    low = text.lower()
    if "--json" in low and any(word in low for word in REJECTION_WORDS):
        return "unsupported_json_option"
    if any(hint in low for hint in AUTH_FAILURE_HINTS):
        return "authentication_failed"
    if any(hint in low for hint in NETWORK_FAILURE_HINTS):
        return "network_failed"
    return "models_failed"


def _parse_version(stdout: str) -> str:
    for token in stdout.replace("\n", " ").split():
        if token and token[0].isdigit() and "." in token:
            return token.strip()
    return ""


def _candidate_from_id(model_id: str):
    if not isinstance(model_id, str) or "/" not in model_id:
        return None
    provider, _, model = model_id.partition("/")
    if not _PROVIDER_RE.fullmatch(provider) or not _MODEL_RE.fullmatch(model):
        return None
    return {
        "candidate_id": model_id,
        "provider": provider,
        "model": model,
        "capabilities": list(KILO_MODEL_CONTRACT_CAPABILITIES),
        "availability": "unknown",
        "cost_class": "unknown",
        "quota_status": "unknown",
        "context_window": None,
    }


def _require_candidate(model_id: str, *, raw):
    cand = _candidate_from_id(model_id)
    if cand is None:
        raise ValueError(f"unrecognized model id: {raw!r}")
    return cand


def _parse_json_models(text: str):
    data = json.loads(text)
    if isinstance(data, dict):
        for key in ("models", "data", "results"):
            if isinstance(data.get(key), list):
                data = data[key]
                break
    if not isinstance(data, list):
        raise ValueError("expected a JSON array of models")
    candidates = []
    for entry in data:
        if not isinstance(entry, dict):
            raise ValueError(f"non-object catalog entry: {entry!r}")
        model_id = entry.get("id") or entry.get("name")
        if isinstance(model_id, str):
            candidates.append(_require_candidate(model_id, raw=model_id))
            continue
        provider = entry.get("provider")
        model = entry.get("model")
        if isinstance(provider, str) and isinstance(model, str) and provider and model:
            candidates.append(_require_candidate(f"{provider}/{model}", raw=entry))
            continue
        raise ValueError(f"unrecognized catalog entry: {entry!r}")
    if not candidates or len({item["candidate_id"] for item in candidates}) != len(candidates):
        raise ValueError("catalog is empty or contains duplicate model IDs")
    return candidates


def _parse_table_models(text: str):
    candidates = []
    for raw_line in text.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        # Kilo 7.4.21 emits one canonical model ID per line, not a header or a
        # whitespace-delimited table.  Requiring exactly one token prevents a
        # future human-readable format from being partially accepted.
        tokens = line.split()
        if len(tokens) != 1:
            raise ValueError(f"unrecognized table row: {raw_line!r}")
        candidates.append(_require_candidate(tokens[0], raw=raw_line))
    if not candidates or len({item["candidate_id"] for item in candidates}) != len(candidates):
        raise ValueError("table catalog is empty or contains duplicate model IDs")
    return candidates


def _number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def _metadata_candidate(identifier: str, metadata: dict):
    """Apply only fields explicitly present in Kilo's verbose metadata."""
    candidate = _candidate_from_id(identifier)
    if candidate is None or not isinstance(metadata, dict):
        raise ValueError("unrecognized verbose model record")

    metadata_id = metadata.get("id")
    provider_id = metadata.get("providerID")
    if metadata_id is not None and metadata_id != candidate["model"]:
        raise ValueError("verbose model identity mismatch")
    if provider_id is not None and provider_id != candidate["provider"]:
        raise ValueError("verbose provider identity mismatch")

    status = metadata.get("status")
    if status == "active":
        candidate["availability"] = "available"
    elif status in {"inactive", "deprecated", "disabled"}:
        candidate["availability"] = "unavailable"

    cost = metadata.get("cost")
    if isinstance(cost, dict):
        input_cost = cost.get("input")
        output_cost = cost.get("output")
        if _number(input_cost) and _number(output_cost):
            candidate["cost_class"] = (
                "free" if input_cost == 0 and output_cost == 0 else "paid"
            )
            candidate["billing"] = candidate["cost_class"]

    limit = metadata.get("limit")
    if isinstance(limit, dict) and isinstance(limit.get("context"), int) and not isinstance(limit.get("context"), bool):
        if limit["context"] >= 1:
            candidate["context_window"] = limit["context"]

    capabilities = metadata.get("capabilities")
    if isinstance(capabilities, dict):
        if capabilities.get("reasoning") is True:
            candidate["reasoning"] = True
            candidate["capabilities"].append("reasoning")
        if capabilities.get("toolcall") is True:
            candidate["tool_call"] = True
            candidate["capabilities"].append("tool_call")

    variants = metadata.get("variants")
    if isinstance(variants, dict):
        candidate["variants"] = sorted(
            key for key in variants if isinstance(key, str) and key
        )

    return candidate


def _parse_verbose_models(text: str):
    """Parse Kilo's ``identifier`` + pretty JSON record stream.

    The parser requires every record to contain a canonical identifier and a
    matching metadata object.  It never accepts a partial catalog.
    """
    decoder = json.JSONDecoder()
    cursor = 0
    records = []
    while cursor < len(text):
        while cursor < len(text) and text[cursor].isspace():
            cursor += 1
        if cursor >= len(text):
            break
        line_end = text.find("\n", cursor)
        if line_end < 0:
            raise ValueError("verbose record is missing metadata")
        identifier = text[cursor:line_end].strip()
        if not identifier or identifier.startswith("{"):
            raise ValueError("verbose record identifier is invalid")
        cursor = line_end + 1
        while cursor < len(text) and text[cursor].isspace():
            cursor += 1
        try:
            metadata, end = decoder.raw_decode(text, cursor)
        except (TypeError, json.JSONDecodeError) as exc:
            raise ValueError("verbose metadata is invalid") from exc
        records.append(_metadata_candidate(identifier, metadata))
        cursor = end
    if not records or len({item["candidate_id"] for item in records}) != len(records):
        raise ValueError("verbose catalog is empty")
    return records


def _provider_rows(value):
    """Return provider rows from both quota-export v2 maps and legacy lists."""
    if not isinstance(value, dict):
        return {}
    providers = value.get("providers")
    if isinstance(providers, dict):
        return {
            str(provider): row
            for provider, row in providers.items()
            if isinstance(provider, str) and isinstance(row, dict)
        }
    if isinstance(providers, list):
        return {
            str(row["id"]): row
            for row in providers
            if isinstance(row, dict) and isinstance(row.get("id"), str)
        }
    return {}


def _live_probe_rows(value):
    if not isinstance(value, dict):
        return {}
    probes = value.get("liveProbes")
    if isinstance(probes, dict):
        return {
            str(provider): row
            for provider, row in probes.items()
            if isinstance(provider, str) and isinstance(row, dict)
        }
    if isinstance(probes, list):
        return {
            str(row["id"]): row
            for row in probes
            if isinstance(row, dict) and isinstance(row.get("id"), str)
        }
    return {}


def _entry_accounting_type(entry):
    if not isinstance(entry, dict):
        return None
    accounting = entry.get("accounting")
    if not isinstance(accounting, dict):
        return None
    result_type = accounting.get("resultType")
    return result_type if isinstance(result_type, str) else None


def _parse_balance_value(value):
    if _number(value):
        number = float(value)
        return number if number == number and abs(number) != float("inf") else None
    if not isinstance(value, str) or not _BALANCE_VALUE_RE.fullmatch(value):
        return None
    try:
        number = float(value.replace("$", "").replace("€", "").replace("£", "").replace(",", ""))
    except ValueError:
        return None
    return number if number == number and abs(number) != float("inf") else None


def _billing_kind(provider, entries):
    """Map only explicit account semantics into the generic billing contract."""
    if provider in PAYG_PROVIDERS:
        # OpenRouter's key endpoint is a metered budget/spend account rather
        # than a subscription quota. Its positive budget/credit evidence is
        # handled below; absent evidence remains quota=unknown and is rejected.
        return "payg"
    result_types = {
        result_type
        for entry in entries
        if (result_type := _entry_accounting_type(entry)) is not None
    }
    if "balance" in result_types:
        return "payg"
    if result_types & {"quota", "rate_limit"}:
        return "subscription"
    if result_types & {"budget", "spend"}:
        return "payg"
    return None


def _quota_rows(status_payload, show_payload):
    """Map quota-export provider rows to safe ARR quota evidence.

    The plugin intentionally exposes only account/provider-level quota. Kilo's
    model listing can contain models from several providers, so this evidence is
    joined by provider and never inferred from a model name.
    """
    show_rows = _provider_rows(show_payload)
    status_rows = _provider_rows(status_payload)
    live_rows = _live_probe_rows(status_payload)
    result = {}
    for provider in set(show_rows) | set(status_rows) | set(live_rows):
        show_row = show_rows.get(provider, {})
        status_row = status_rows.get(provider, {})
        live_row = live_rows.get(provider, {})
        state = "unknown"
        remaining = None
        show_status = str(show_row.get("status", "")).lower()
        status_available = status_row.get("available")
        live_ok = live_row.get("ok")
        if (
            show_status in {"unavailable", "error"}
            or status_available is False
            or live_ok is False
        ):
            # ARR has no provider-specific UNAVAILABLE enum. BLOCKED is the
            # fail-closed representation: even an owner who allows unknown
            # quota must not route through an explicitly failed auth/quota
            # source.
            state = "blocked"
        else:
            entries = show_row.get("entries", [])
            if not isinstance(entries, list):
                entries = []
            percentages = [
                float(entry["percentRemaining"])
                for entry in entries
                if isinstance(entry, dict)
                and isinstance(entry.get("percentRemaining"), (int, float))
                and not isinstance(entry.get("percentRemaining"), bool)
                and 0 <= float(entry["percentRemaining"]) <= 100
            ]
            balance_values = [
                balance
                for entry in entries
                if _entry_accounting_type(entry) == "balance"
                and (balance := _parse_balance_value(entry.get("value"))) is not None
            ]
            if percentages:
                remaining = min(percentages)
                state = "exhausted" if remaining <= 1 else "available"
                if balance_values and min(balance_values) <= 0:
                    state = "exhausted"
            elif balance_values:
                state = "exhausted" if min(balance_values) <= 0 else "available"
            elif show_status not in {"", "ok", "partial"}:
                state = "blocked"
        evidence = {"quota_status": state, "quota_percent": remaining}
        billing = _billing_kind(provider, show_row.get("entries", []))
        if billing is not None:
            evidence["billing"] = billing
        result[provider] = evidence
    return result


def _quota_error_report(error_code: str, *, timed_out: bool = False):
    return {
        "probe_id": "opencode-quota",
        "source": "opencode-quota",
        "status": "unknown",
        "freshness": "unknown",
        "timed_out": timed_out,
        "error_code": error_code,
        "secrets_redacted": True,
    }


_OPENROUTER_CREDITS_SCRIPT = r'''
import { pathToFileURL } from "node:url";

const modulePath = process.argv[1];
try {
  const { resolveOpenRouterApiKey } = await import(pathToFileURL(modulePath).href);
  const resolved = await resolveOpenRouterApiKey();
  const key = resolved && typeof resolved.key === "string" ? resolved.key : "";
  if (!key) {
    process.stdout.write(JSON.stringify({status: "unavailable"}));
    process.exit(0);
  }
  const response = await fetch("https://openrouter.ai/api/v1/credits", {
    method: "GET",
    redirect: "manual",
    headers: {Authorization: `Bearer ${key}`, Accept: "application/json"},
  });
  if (response.redirected || (response.status >= 300 && response.status < 400) || !response.ok) {
    process.stdout.write(JSON.stringify({status: "unavailable"}));
    process.exit(0);
  }
  const body = await response.json();
  const data = body && typeof body === "object" ? body.data : null;
  const total = data && typeof data.total_credits === "number" ? data.total_credits : null;
  const usage = data && typeof data.total_usage === "number" ? data.total_usage : null;
  if (!Number.isFinite(total) || total < 0 || !Number.isFinite(usage) || usage < 0) {
    process.stdout.write(JSON.stringify({status: "unavailable"}));
    process.exit(0);
  }
  process.stdout.write(JSON.stringify({
    status: total - usage > 0 ? "available" : "exhausted",
    remaining: Math.max(0, total - usage),
  }));
} catch {
  process.stdout.write(JSON.stringify({status: "unavailable"}));
}
'''


def _openrouter_credit_probe(node, module, *, timeout: float, max_output_bytes: int):
    """Fetch OpenRouter account credits through the plugin's key resolver."""
    if not node or not module:
        return None
    out, _err, rc, timed_out = _run_bounded(
        [node, "--input-type=module", "-e", _OPENROUTER_CREDITS_SCRIPT, module],
        timeout=timeout,
        max_output_bytes=max_output_bytes,
    )
    if timed_out or rc != 0:
        return None
    try:
        payload = json.loads(out.decode("utf-8", "replace"))
    except (TypeError, json.JSONDecodeError):
        return None
    if not isinstance(payload, dict) or payload.get("status") not in {"available", "exhausted"}:
        return None
    remaining = payload.get("remaining")
    if not _number(remaining) or float(remaining) < 0:
        return None
    return {
        "quota_status": payload["status"],
        "quota_percent": None,
        "billing": "payg",
    }


def _quota_probe(node, script, module=None, *, timeout: float, max_output_bytes: int):
    """Refresh and read plugin quota without exposing raw command output."""
    if not node or not script:
        return {}, _quota_error_report("quota_plugin_missing")
    deadline = time.monotonic() + timeout
    payloads = []
    for command in (("status", "--json"), ("show", "--json")):
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            return {}, _quota_error_report("quota_timeout", timed_out=True)
        out, _err, rc, timed_out = _run_bounded(
            [node, script, *command],
            timeout=remaining,
            max_output_bytes=max_output_bytes,
        )
        if timed_out:
            return {}, _quota_error_report("quota_timeout", timed_out=True)
        if rc != 0:
            return {}, _quota_error_report("quota_command_failed")
        try:
            payloads.append(json.loads(out.decode("utf-8", "replace")))
        except (TypeError, json.JSONDecodeError):
            return {}, _quota_error_report("quota_invalid_output")
    show_payload = payloads[1]
    cache_age = show_payload.get("cacheAgeSeconds") if isinstance(show_payload, dict) else None
    cache_fresh = (
        isinstance(cache_age, (int, float))
        and not isinstance(cache_age, bool)
        and cache_age >= 0
        and cache_age <= MAX_QUOTA_AGE_SECONDS
    )
    rows = _quota_rows(payloads[0], show_payload) if cache_fresh else {}
    credit_remaining = deadline - time.monotonic()
    credit = (
        _openrouter_credit_probe(
            node,
            module,
            timeout=credit_remaining,
            max_output_bytes=max_output_bytes,
        )
        if credit_remaining > 0
        else None
    )
    if credit is not None:
        existing = rows.get("openrouter")
        if not existing or existing.get("quota_status") not in {"blocked", "exhausted"}:
            rows["openrouter"] = {
                **(existing or {"quota_percent": None}),
                **credit,
            }
    if not cache_fresh and credit is None:
        return {}, _quota_error_report("quota_stale")
    if not rows:
        return {}, _quota_error_report("quota_no_data")
    return rows, {
        "probe_id": "opencode-quota",
        "source": "opencode-quota",
        "status": "best_effort",
        "freshness": "fresh",
        "timed_out": False,
        "error_code": None,
        "secrets_redacted": True,
    }


def _apply_quota(candidates, quota_rows):
    for candidate in candidates:
        evidence = quota_rows.get(candidate.get("provider"))
        if not evidence:
            continue
        candidate["quota_status"] = evidence["quota_status"]
        if evidence["quota_percent"] is not None:
            candidate["quota_percent"] = evidence["quota_percent"]
        if evidence.get("billing") is not None and candidate.get("cost_class") != "free":
            candidate["billing"] = evidence["billing"]
    return candidates


def _error_report(error_code: str, *, timed_out: bool = False, status: str = "unknown"):
    return {
        "schema_version": REPORT_VERSION,
        "adapter_id": ADAPTER_ID,
        "status": status,
        "candidate_count": 0,
        "candidates": [],
        "probes": [
            {
                "probe_id": PROBE_ID,
                "source": "kilo-cli",
                "status": status,
                "freshness": "unknown",
                "timed_out": timed_out,
                "error_code": error_code,
                "secrets_redacted": True,
            }
        ],
        "fallback_used": False,
        "error_code": error_code,
        "secrets_redacted": True,
    }


def _success_report(candidates, *, quota_probe=None):
    probes = [
        {
            "probe_id": PROBE_ID,
            "source": "kilo-cli",
            "status": "best_effort",
            "freshness": "fresh",
            "timed_out": False,
            "error_code": None,
            "secrets_redacted": True,
        }
    ]
    if quota_probe is not None and quota_probe.get("error_code") is None:
        probes.append(quota_probe)
    return {
        "schema_version": REPORT_VERSION,
        "adapter_id": ADAPTER_ID,
        "status": "best_effort",
        "candidate_count": len(candidates),
        "candidates": candidates,
        "probes": probes,
        "fallback_used": False,
        "error_code": None,
        "secrets_redacted": True,
    }


def run_discovery(
    kilo,
    *,
    quota_node=None,
    quota_script=None,
    quota_module=None,
    expected_version: str = EXPECTED_KILO_VERSION,
    max_output_bytes: int = MAX_OUTPUT_BYTES,
    version_timeout: float = _VERSION_TIMEOUT,
    models_timeout: float = _MODELS_TIMEOUT,
):
    ver_out, _ver_err, ver_rc, ver_to = _run_bounded(
        [kilo, "--version"], timeout=version_timeout, max_output_bytes=max_output_bytes
    )
    if ver_to or ver_rc != 0:
        return _error_report("version_check_failed", timed_out=ver_to)
    version = _parse_version(ver_out.decode("utf-8", "replace"))
    if version != expected_version:
        return _error_report("version_unexpected", status="unsupported")

    phase_start = time.monotonic()
    help_timeout = min(_HELP_TIMEOUT_CAP, models_timeout)
    verbose_ok = _flag_supported(
        kilo, "--verbose", timeout=help_timeout, max_output_bytes=max_output_bytes
    )
    elapsed = time.monotonic() - phase_start
    remaining = models_timeout - elapsed
    if remaining <= 0:
        return _error_report("models_failed", timed_out=True)

    if verbose_ok is True:
        v_out, v_err, v_rc, v_to = _run_bounded(
            [kilo, "models", "--verbose"],
            timeout=remaining,
            max_output_bytes=max_output_bytes,
        )
        if v_to:
            return _error_report("models_failed", timed_out=True)
        if v_rc == 0:
            try:
                candidates = _parse_verbose_models(v_out.decode("utf-8", "replace"))
            except (ValueError, json.JSONDecodeError):
                return _error_report("unparseable_output")
            quota_rows, quota_probe = _quota_probe(
                quota_node,
                quota_script,
                quota_module,
                timeout=_QUOTA_TIMEOUT,
                max_output_bytes=max_output_bytes,
            )
            return _success_report(
                _apply_quota(candidates, quota_rows), quota_probe=quota_probe
            )
        combined = (v_out + v_err).decode("utf-8", "replace")
        return _error_report(_classify_models_failure(combined))

    if verbose_ok is None:
        return _error_report("models_help_failed")

    # --verbose absent -> direct table path.  This is a format selection,
    # NEVER a fallback for command failures.
    t_out, t_err, t_rc, t_to = _run_bounded(
        [kilo, "models"], timeout=remaining, max_output_bytes=max_output_bytes
    )
    if t_to:
        return _error_report("models_failed", timed_out=True)
    if t_rc != 0:
        combined = (t_out + t_err).decode("utf-8", "replace")
        return _error_report(_classify_models_failure(combined))
    try:
        candidates = _parse_table_models(t_out.decode("utf-8", "replace"))
    except ValueError:
        return _error_report("unparseable_output")
    quota_rows, quota_probe = _quota_probe(
        quota_node,
        quota_script,
        quota_module,
        timeout=_QUOTA_TIMEOUT,
        max_output_bytes=max_output_bytes,
    )
    return _success_report(
        _apply_quota(candidates, quota_rows), quota_probe=quota_probe
    )


def _write_diagnostic(report: dict) -> None:
    try:
        path = Path(__file__).resolve().parent / DIAG_REPORT_FILENAME
        path.write_text(json.dumps(report, indent=2, sort_keys=True), encoding="utf-8")
    except Exception:  # noqa: BLE001
        pass


def is_report_cacheable(report: dict) -> bool:
    return report.get("status") in USABLE_STATUSES


def _emit(report: dict) -> None:
    _write_diagnostic(report)
    print(json.dumps(report, indent=2, sort_keys=True))
    sys.exit(0)


def _runtime_arguments(argv):
    if not argv:
        return None, None, None, None
    kilo = argv[0]
    quota_node = None
    quota_script = None
    quota_module = None
    rest = list(argv[1:])
    while rest:
        flag = rest.pop(0)
        if flag not in {"--quota-node", "--quota-script", "--quota-openrouter-module"} or not rest:
            return None, None, None, None
        value = rest.pop(0)
        if not Path(value).is_absolute():
            return None, None, None, None
        if flag == "--quota-node":
            if quota_node is not None:
                return None, None, None, None
            quota_node = value
        elif flag == "--quota-script":
            if quota_script is not None:
                return None, None, None, None
            quota_script = value
        else:
            if quota_module is not None:
                return None, None, None, None
            quota_module = value
    if (quota_node is None) != (quota_script is None):
        return None, None, None, None
    return kilo, quota_node, quota_script, quota_module


def _fake_body(scenario: str) -> str:
    return (
        "import json, os, sys, time\n"
        "SCENARIO = " + repr(scenario) + "\n"
        "MARKER = os.environ.get('VERBOSE_MARKER_PATH')\n"
        "def mark_verbose():\n"
        "    if MARKER:\n"
        "        open(MARKER, 'w').write('1')\n"
        "def main():\n"
        "    args = sys.argv[1:]\n"
        "    if args and args[0] == '--version':\n"
        "        print('kilo 7.4.21')\n"
        "        return 0\n"
        "    if args and args[0] == 'models':\n"
        "        if len(args) >= 2 and args[1] == '--help':\n"
        "            if SCENARIO in ('help_with_json','authentication_failed','network_failed','other_command_failure','malformed_json','oversized','descendant_cleanup','model_phase_deadline','verbose_metadata','verbose_malformed','metadata_mismatch'):\n"
        "                print('Usage: kilo models [--verbose]')\n"
        "            else:\n"
        "                print('Usage: kilo models')\n"
        "            return 0\n"
        "        if '--verbose' in args:\n"
        "            mark_verbose()\n"
        "            if SCENARIO in ('help_with_json', 'verbose_metadata'):\n"
        "                print('openai/gpt-4o')\n"
        "                print(json.dumps({'id': 'gpt-4o', 'providerID': 'openai', 'status': 'active', 'cost': {'input': 1, 'output': 2}, 'limit': {'context': 128000}, 'capabilities': {'reasoning': True, 'toolcall': True}, 'variants': {'high': {}}}))\n"
        "                print('kilo/~anthropic/claude-sonnet-latest')\n"
        "                print(json.dumps({'id': '~anthropic/claude-sonnet-latest', 'providerID': 'kilo', 'status': 'active', 'cost': {'input': 0, 'output': 0}, 'limit': {'context': 100000}, 'capabilities': {'reasoning': True, 'toolcall': False}}))\n"
        "                return 0\n"
        "            if SCENARIO == 'malformed_json' or SCENARIO == 'verbose_malformed':\n"
        "                print('openai/gpt-4o')\n"
        "                print('this is definitely not json {{{')\n"
        "                return 0\n"
        "            if SCENARIO == 'oversized':\n"
        "                unit = 'openai/gpt-4o\\n' + json.dumps({'id': 'gpt-4o', 'providerID': 'openai', 'status': 'active'}) + '\\n'\n"
        "                print(unit * 50000)\n"
        "                return 0\n"
        "            if SCENARIO == 'descendant_cleanup':\n"
        "                pidfile = os.environ.get('DESC_PIDFILE')\n"
        "                if pidfile:\n"
        "                    import subprocess as _sp\n"
        "                    _sp.Popen([sys.executable, '-c',\n"
        "                        'import os,time\\nopen(os.environ[\"DESC_PIDFILE\"],\"w\").write(str(os.getpid()))\\ntime.sleep(300)'])\n"
        "                time.sleep(300)\n"
        "                return 0\n"
        "            if SCENARIO == 'model_phase_deadline':\n"
        "                time.sleep(5.0)\n"
        "                print(json.dumps({'models': [{'id': 'openai/gpt-4o'}]}))\n"
        "                return 0\n"
        "            if SCENARIO == 'metadata_mismatch':\n"
        "                print('openai/gpt-4o')\n"
        "                print(json.dumps({'id': 'other-model', 'providerID': 'openai', 'status': 'active'}))\n"
        "                return 0\n"
        "            if SCENARIO == 'authentication_failed':\n"
        "                sys.stderr.write('401 Unauthorized: authentication required LEAK_MARKER_12345\\n')\n"
        "                return 1\n"
        "            if SCENARIO == 'network_failed':\n"
        "                sys.stderr.write('fatal: connection refused LEAK_MARKER_12345\\n')\n"
        "                return 1\n"
        "            sys.stderr.write('internal error: boom LEAK_MARKER_12345\\n')\n"
        "            return 3\n"
        "        if '--json' in args:\n"
        "            sys.stderr.write('error: unknown flag --json\\n')\n"
        "            return 2\n"
        "        if SCENARIO == 'help_without_json':\n"
        "            print('openai/gpt-4o')\n"
        "            print('anthropic/claude-3-opus')\n"
        "            return 0\n"
        "        if SCENARIO == 'kilo_table_shape':\n"
        "            print('kilo/~anthropic/claude-sonnet-latest')\n"
        "            print('kilo/openai/gpt-mini-latest')\n"
        "            return 0\n"
        "        if SCENARIO == 'malformed_table':\n"
        "            print('kilo/openai/gpt-mini-latest extra-column')\n"
        "            return 0\n"
        "    return 0\n"
        "if __name__ == '__main__':\n"
        "    sys.exit(main())\n"
    )


def _selftest() -> int:
    tmp = Path(tempfile.mkdtemp(prefix="kilo-discover-selftest-"))
    failures = []

    def run_scenario(name: str, scenario: str, **overrides):
        fake = tmp / f"kilo_{name}"
        fake.write_text("#!/usr/bin/env python3\n" + _fake_body(scenario))
        fake.chmod(0o755)
        marker = tmp / f"{name}_verbose_marker"
        if marker.exists():
            marker.unlink()
        env_backup = os.environ.get("VERBOSE_MARKER_PATH")
        os.environ["VERBOSE_MARKER_PATH"] = str(marker)
        start = time.monotonic()
        try:
            report = run_discovery(str(fake), **overrides)
        finally:
            if env_backup is None:
                os.environ.pop("VERBOSE_MARKER_PATH", None)
            else:
                os.environ["VERBOSE_MARKER_PATH"] = env_backup
        elapsed = time.monotonic() - start
        try:
            from agent_runtime_router.harnesses.contracts import DiscoveryReport

            DiscoveryReport.from_mapping(report)
            schema_ok = "schema-valid"
        except ImportError:
            schema_ok = "schema-skip(no-arr)"
        except Exception as exc:  # noqa: BLE001
            schema_ok = f"SCHEMA-FAIL:{exc!r}"
        serialized = json.dumps(report)
        leaked = "LEAK_MARKER_12345" in serialized or "connection refused" in serialized
        verbose_path_used = marker.exists()
        print(f"[{name}] candidates={report.get('candidate_count')} status={report.get('status')} "
              f"error_code={report.get('error_code')} fallback={report.get('fallback_used')} "
              f"verbose_path={verbose_path_used} schema={schema_ok} leaked={leaked} elapsed={elapsed:.2f}s")
        return report, schema_ok, leaked, elapsed, verbose_path_used

    cases = {
        "help_without_json": ("help_without_json", {}),
        "kilo_table_shape": ("kilo_table_shape", {}),
        "malformed_table": ("malformed_table", {}),
        "help_with_json": ("help_with_json", {}),
        "verbose_metadata": ("verbose_metadata", {}),
        "metadata_mismatch": ("metadata_mismatch", {}),
        "authentication_failed": ("authentication_failed", {}),
        "network_failed": ("network_failed", {}),
        "other_command_failure": ("other_command_failure", {}),
        "malformed_json": ("malformed_json", {}),
        "oversized": ("oversized", {}),
        "descendant_cleanup": ("descendant_cleanup", {"version_timeout": 1.0, "models_timeout": 1.5}),
        "model_phase_deadline": ("model_phase_deadline", {"version_timeout": 0.5, "models_timeout": 1.0}),
        "unsupported_json_option": ("unsupported_json_option", {}),
    }
    expected = {
        "help_without_json": lambda r: r["candidate_count"] == 2 and r["error_code"] is None and not r["fallback_used"],
        "kilo_table_shape": lambda r: r["candidate_count"] == 2 and r["error_code"] is None and not r["fallback_used"]
        and r["candidates"][0]["provider"] == "kilo"
        and r["candidates"][0]["model"] == "~anthropic/claude-sonnet-latest",
        "malformed_table": lambda r: r["candidate_count"] == 0 and r["error_code"] == "unparseable_output",
        "help_with_json": lambda r: r["candidate_count"] == 2 and r["error_code"] is None and not r["fallback_used"],
        "verbose_metadata": lambda r: r["candidate_count"] == 2 and r["error_code"] is None
        and r["candidates"][0].get("cost_class") == "paid"
        and r["candidates"][0].get("context_window") == 128000
        and "reasoning" in r["candidates"][0].get("capabilities", []),
        "metadata_mismatch": lambda r: r["candidate_count"] == 0 and r["error_code"] == "unparseable_output",
        "authentication_failed": lambda r: r["candidate_count"] == 0 and r["error_code"] == "authentication_failed" and r["fallback_used"] is False,
        "network_failed": lambda r: r["candidate_count"] == 0 and r["error_code"] == "network_failed" and r["fallback_used"] is False,
        "other_command_failure": lambda r: r["candidate_count"] == 0 and r["error_code"] == "models_failed" and r["fallback_used"] is False,
        "malformed_json": lambda r: r["candidate_count"] == 0 and r["error_code"] == "unparseable_output",
        "oversized": lambda r: r["candidate_count"] == 0 and r["error_code"] in ("unparseable_output", "models_failed"),
        "descendant_cleanup": lambda r: r["error_code"] == "models_failed" and r.get("probes", [{}])[0].get("timed_out") is True,
        "model_phase_deadline": lambda r: r["error_code"] == "models_failed" and r["fallback_used"] is False
        and r.get("probes", [{}])[0].get("timed_out") is True,
        "unsupported_json_option": lambda r: r["candidate_count"] == 0 and r["error_code"] == "unparseable_output" and r["fallback_used"] is False,
    }
    verbose_path_expected = {
        "help_without_json": False,
        "kilo_table_shape": False,
        "malformed_table": False,
        "help_with_json": True,
        "verbose_metadata": True,
        "metadata_mismatch": True,
        "authentication_failed": True,
        "network_failed": True,
        "other_command_failure": True,
        "malformed_json": True,
        "oversized": True,
        "descendant_cleanup": True,
        "model_phase_deadline": True,
        "unsupported_json_option": False,
    }
    reports = {}
    for name, (scenario, overrides) in cases.items():
        pidfile = tmp / f"{name}_pid"
        env_backup = os.environ.get("DESC_PIDFILE")
        os.environ["DESC_PIDFILE"] = str(pidfile)
        try:
            report, schema_ok, leaked, elapsed, verbose_path_used = run_scenario(name, scenario, **overrides)
        finally:
            if env_backup is None:
                os.environ.pop("DESC_PIDFILE", None)
            else:
                os.environ["DESC_PIDFILE"] = env_backup
        reports[name] = report
        ok = (
            expected[name](report)
            and schema_ok == "schema-valid"
            and not leaked
            and verbose_path_used == verbose_path_expected[name]
        )
        if name == "descendant_cleanup" and pidfile.exists():
            try:
                os.kill(int(pidfile.read_text().strip()), 0)
                grandchild_alive = True
            except (OSError, ValueError):
                grandchild_alive = False
            print(f"  grandchild_alive={grandchild_alive}")
            ok = ok and not grandchild_alive
        if name == "model_phase_deadline":
            vt = overrides.get("version_timeout", _VERSION_TIMEOUT)
            mt = overrides.get("models_timeout", _MODELS_TIMEOUT)
            print(f"  model_phase_budget={mt}s; total<={vt + mt}s; elapsed={elapsed:.2f}s")
            ok = ok and elapsed <= vt + mt + 0.6
        print(f"  -> {'PASS' if ok else 'FAIL'}")
        if not ok:
            failures.append(name)

    quota_ok_rows = _quota_rows(
        {
            "providers": [{"id": "openai", "available": True}],
            "liveProbes": [{"id": "openai", "ok": True}],
        },
        {
            "providers": {
                "openai": {
                    "status": "ok",
                    "entries": [{"percentRemaining": 87.5}],
                }
            }
        },
    )
    quota_expired_rows = _quota_rows(
        {
            "providers": [{"id": "openai", "available": True}],
            "liveProbes": [{"id": "openai", "ok": False}],
        },
        {"providers": {"openai": {"status": "unavailable"}}},
    )
    quota_ok = (
        quota_ok_rows.get("openai") == {"quota_status": "available", "quota_percent": 87.5}
        and quota_expired_rows.get("openai") == {"quota_status": "blocked", "quota_percent": None}
    )
    print(f"[quota-parser] success_and_expired_auth={quota_ok} -> {'PASS' if quota_ok else 'FAIL'}")
    if not quota_ok:
        failures.append("quota-parser")

    quota_payg_rows = _quota_rows(
        {
            "providers": [{"id": "openrouter", "available": True}],
            "liveProbes": [{"id": "openrouter", "ok": True}],
        },
        {
            "providers": {
                "openrouter": {
                    "status": "ok",
                    "entries": [{
                        "accounting": {"resultType": "balance"},
                        "value": "$3.70",
                    }],
                }
            }
        },
    )
    quota_payg_zero_rows = _quota_rows(
        {
            "providers": [{"id": "openrouter", "available": True}],
            "liveProbes": [{"id": "openrouter", "ok": True}],
        },
        {
            "providers": {
                "openrouter": {
                    "status": "ok",
                    "entries": [{
                        "accounting": {"resultType": "balance"},
                        "value": "$0.00",
                    }],
                }
            }
        },
    )
    quota_subscription_rows = _quota_rows(
        {
            "providers": [{"id": "openai", "available": True}],
            "liveProbes": [{"id": "openai", "ok": True}],
        },
        {
            "providers": {
                "openai": {
                    "status": "ok",
                    "entries": [{
                        "accounting": {"resultType": "quota"},
                        "percentRemaining": 80,
                    }],
                }
            }
        },
    )
    quota_payg_ok = (
        quota_payg_rows.get("openrouter") == {
            "quota_status": "available",
            "quota_percent": None,
            "billing": "payg",
        }
        and quota_payg_zero_rows.get("openrouter") == {
            "quota_status": "exhausted",
            "quota_percent": None,
            "billing": "payg",
        }
        and quota_subscription_rows.get("openai") == {
            "quota_status": "available",
            "quota_percent": 80.0,
            "billing": "subscription",
        }
    )
    billing_candidates = _apply_quota(
        [
            {"provider": "openrouter", "cost_class": "free", "billing": "free"},
            {"provider": "openrouter", "cost_class": "paid", "billing": "paid"},
        ],
        quota_payg_rows,
    )
    quota_payg_ok = quota_payg_ok and (
        billing_candidates[0]["billing"] == "free"
        and billing_candidates[1]["billing"] == "payg"
    )
    print(f"[quota-billing] payg_balance_and_subscription={quota_payg_ok} -> "
          f"{'PASS' if quota_payg_ok else 'FAIL'}")
    if not quota_payg_ok:
        failures.append("quota-billing")

    quota_script = tmp / "quota_probe.py"
    quota_script.write_text(
        "import json, sys\n"
        "if sys.argv[1] == 'status':\n"
        "    print(json.dumps({'providers': [{'id': 'openai', 'available': True}], 'liveProbes': [{'id': 'openai', 'ok': True}]}))\n"
        "elif sys.argv[1] == 'show':\n"
        "    print(json.dumps({'cacheAgeSeconds': 10, 'providers': {'openai': {'status': 'ok', 'entries': [{'percentRemaining': 80}]}}}))\n",
        encoding="utf-8",
    )
    quota_rows, quota_probe = _quota_probe(
        sys.executable, str(quota_script), timeout=5, max_output_bytes=MAX_OUTPUT_BYTES
    )
    quota_probe_ok = (
        quota_rows.get("openai", {}).get("quota_status") == "available"
        and quota_probe.get("error_code") is None
    )
    quota_script.write_text(
        "import json, sys\n"
        "if sys.argv[1] == 'status': print('{}')\n"
        "else: print(json.dumps({'cacheAgeSeconds': 301, 'providers': {}}))\n",
        encoding="utf-8",
    )
    _stale_rows, stale_probe = _quota_probe(
        sys.executable, str(quota_script), timeout=5, max_output_bytes=MAX_OUTPUT_BYTES
    )
    stale_ok = not _stale_rows and stale_probe.get("error_code") == "quota_stale"
    quota_script.write_text("import sys; sys.exit(1)\n", encoding="utf-8")
    _failed_rows, failed_probe = _quota_probe(
        sys.executable, str(quota_script), timeout=5, max_output_bytes=MAX_OUTPUT_BYTES
    )
    failed_ok = not _failed_rows and failed_probe.get("error_code") == "quota_command_failed"
    print(f"[quota-probe] fresh={quota_probe_ok} stale={stale_ok} nonzero={failed_ok} -> "
          f"{'PASS' if quota_probe_ok and stale_ok and failed_ok else 'FAIL'}")
    if not (quota_probe_ok and stale_ok and failed_ok):
        failures.append("quota-probe")

    credits_node = tmp / "credits_node"
    credits_node.write_text(
        "#!/usr/bin/env python3\n"
        "import json\n"
        "print(json.dumps({'status': 'available', 'remaining': 3.70}))\n",
        encoding="utf-8",
    )
    credits_node.chmod(0o700)
    credits_ok = _openrouter_credit_probe(
        str(credits_node), str(tmp / "openrouter.js"), timeout=5, max_output_bytes=MAX_OUTPUT_BYTES
    ) == {"quota_status": "available", "quota_percent": None, "billing": "payg"}
    print(f"[openrouter-credits] positive_balance={credits_ok} -> "
          f"{'PASS' if credits_ok else 'FAIL'}")
    if not credits_ok:
        failures.append("openrouter-credits")

    missing_plugin_report = _success_report(
        [{
            "candidate_id": "kilo/example/free",
            "provider": "kilo",
            "model": "example/free",
            "capabilities": ["chat"],
            "availability": "available",
            "cost_class": "free",
            "billing": "free",
            "quota_status": "unknown",
            "context_window": 128000,
        }],
        quota_probe=_quota_error_report("quota_plugin_missing"),
    )
    missing_plugin_ok = (
        is_report_cacheable(missing_plugin_report)
        and not any(probe.get("probe_id") == "opencode-quota" for probe in missing_plugin_report["probes"])
    )
    print(f"[quota-plugin-missing] free_catalog_cacheable={missing_plugin_ok} -> "
          f"{'PASS' if missing_plugin_ok else 'FAIL'}")
    if not missing_plugin_ok:
        failures.append("quota-plugin-missing")

    from agent_runtime_router.harnesses.contracts import DiscoveryReport

    cacheable_names = {
        "help_with_json",
        "verbose_metadata",
        "help_without_json",
        "kilo_table_shape",
    }
    for name in cases:
        rep = reports[name]
        _write_diagnostic(rep)
        try:
            DiscoveryReport.from_mapping(rep)
            d_schema = "schema-valid"
        except Exception as exc:  # noqa: BLE001
            d_schema = f"SCHEMA-FAIL:{exc!r}"
        d_text = json.dumps(rep)
        d_leaked = "LEAK_MARKER_12345" in d_text or "connection refused" in d_text
        cacheable = is_report_cacheable(rep)
        want_cacheable = name in cacheable_names
        diag_ok = d_schema == "schema-valid" and not d_leaked and cacheable == want_cacheable
        print(f"[diag:{name}] schema={d_schema} leaked={d_leaked} cacheable={cacheable} "
              f"error_code={rep.get('error_code')} -> {'PASS' if diag_ok else 'FAIL'}")
        if not diag_ok:
            failures.append(f"diag:{name}")

    print("SELFTEST", "ALL PASS" if not failures else f"FAILURES: {failures}")
    return 0 if not failures else 1


def main(argv=None) -> None:
    argv = sys.argv[1:] if argv is None else list(argv)
    if argv and argv[0] == "--selftest":
        sys.exit(_selftest())
    _install_group_cleanup()
    kilo, quota_node, quota_script, quota_module = _runtime_arguments(argv)
    if kilo is None:
        _emit(_error_report("missing_executable"))
        return
    _emit(
        run_discovery(
            kilo,
            quota_node=quota_node,
            quota_script=quota_script,
            quota_module=quota_module,
        )
    )


if __name__ == "__main__":
    main()
