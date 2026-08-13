#!/usr/bin/env python3
"""Generate machine-local Kilo discovery configuration for ARR.

Resolves the absolute Kilo executable once, version-checks it, and writes:
  - discovery.json       (absolute command + cwd; git-ignored, machine-local)
  - kilo-resolved.json   (absolute path + observed version; git-ignored)

The wrapper (discover_kilo_models.py) receives the absolute executable as an
argument so discovery never resolves `kilo` through a mutable PATH.

Fails closed if the executable is missing or the version is unexpected.
"""

import json
import shutil
import subprocess
import sys
from pathlib import Path

EXPECTED_KILO_VERSION = "7.4.21"
ADAPTER_DIR = Path(__file__).resolve().parent
REPO_ROOT = ADAPTER_DIR.parents[3]
WRAPPER_PATH = ADAPTER_DIR / "discover_kilo_models.py"
DISCOVERY_PATH = ADAPTER_DIR / "discovery.json"
RESOLVED_PATH = ADAPTER_DIR / "kilo-resolved.json"
QUOTA_PACKAGE_GLOB = (
    "@slkiser/opencode-quota@*/node_modules/@slkiser/opencode-quota/"
    "dist/bin/opencode-quota.js"
)


def fail(message: str) -> None:
    print(f"gen_discovery: {message}", file=sys.stderr)
    sys.exit(1)


def parse_version(stdout: str) -> str:
    for token in stdout.replace("\n", " ").split():
        if token and token[0].isdigit() and "." in token:
            return token.strip()
    return ""


def resolve_quota_plugin() -> tuple[Path, Path, Path] | None:
    """Resolve Node and the installed quota plugin without invoking it."""
    node = shutil.which("node")
    if not node:
        return None
    node_path = Path(node).resolve()
    package_root = Path.home() / ".cache" / "kilo" / "packages"
    matches = list(package_root.glob(QUOTA_PACKAGE_GLOB))
    if not matches:
        return None
    script = max(matches, key=lambda path: path.stat().st_mtime).resolve()
    module = script.parent.parent / "lib" / "openrouter.js"
    if not node_path.is_file() or not script.is_file() or not module.is_file():
        return None
    return node_path, script, module


def main() -> None:
    kilo = shutil.which("kilo")
    if not kilo:
        fail("kilo executable not found on PATH")
    kilo = Path(kilo).resolve()
    if not kilo.is_file():
        fail(f"kilo executable missing: {kilo}")

    try:
        result = subprocess.run(
            [str(kilo), "--version"],
            capture_output=True,
            text=True,
            timeout=30,
        )
    except Exception as exc:  # noqa: BLE001
        fail(f"kilo --version failed: {exc}")
    if result.returncode != 0:
        fail(f"kilo --version exited {result.returncode}: {result.stderr.strip()}")

    version = parse_version(result.stdout)
    if version != EXPECTED_KILO_VERSION:
        fail(f"unexpected kilo version {version!r}, expected {EXPECTED_KILO_VERSION!r}")

    quota = resolve_quota_plugin()
    command = [sys.executable, str(WRAPPER_PATH), str(kilo)]
    resolved = {
        "kilo_executable": str(kilo),
        "kilo_version": version,
        "expected_version": EXPECTED_KILO_VERSION,
    }
    if quota is not None:
        node, script, module = quota
        command.extend(
            [
                "--quota-node",
                str(node),
                "--quota-script",
                str(script),
                "--quota-openrouter-module",
                str(module),
            ]
        )
        resolved["opencode_quota_node"] = str(node)
        resolved["opencode_quota_script"] = str(script)
        resolved["opencode_quota_openrouter_module"] = str(module)

    discovery = {
        "schema_version": 1,
        "kind": "subprocess",
        "adapter_id": "kilo",
        "probe_id": "kilo-models",
        "command": command,
        "cwd": str(REPO_ROOT),
        "timeout_seconds": 60.0,
        "max_output_bytes": 4_000_000,
    }
    RESOLVED_PATH.write_text(
        json.dumps(
            {
                **resolved,
            },
            indent=2,
        )
        + "\n"
    )
    DISCOVERY_PATH.write_text(json.dumps(discovery, indent=2) + "\n")
    quota_note = " with opencode-quota" if quota is not None else " (opencode-quota unavailable)"
    print(
        f"gen_discovery: resolved {kilo} (kilo {version}){quota_note}; "
        "wrote discovery.json + kilo-resolved.json"
    )


if __name__ == "__main__":
    main()
