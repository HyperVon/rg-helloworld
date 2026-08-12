#!/usr/bin/env python3
"""Target-owned native Kilo launch adapter.

ARR owns routing, approval binding, and process supervision. This module owns
only the Kilo command shape and the machine-local executable resolution created
by ``gen_discovery.py``. It never reads credentials or constructs provider
policy.
"""

from __future__ import annotations

import json
import shutil
from pathlib import Path

from agent_runtime_router import (
    AbsoluteArgv,
    Candidate,
    CapabilityEvidence,
    DiscoveryReport,
    DiscoveryRequest,
    EvidenceStatus,
    HarnessProfile,
    LaunchSpec,
    TaskRequest,
    VerificationReport,
)
from agent_runtime_router.errors import HarnessAdapterError, RouterInputError


ADAPTER_ID = "kilo"
DEFAULT_AGENT = "code"
DEFAULT_FORMAT = "json"
DEFAULT_TIMEOUT_SECONDS = 60.0
DEFAULT_MAX_OUTPUT_BYTES = 4_000_000
RESOLVED_PATH = Path(__file__).resolve().parent / "kilo-resolved.json"


class KiloAdapter:
    """Bind one already-selected ARR candidate to Kilo's native argv."""

    def __init__(
        self,
        *,
        resolved_path: Path = RESOLVED_PATH,
        agent: str = DEFAULT_AGENT,
        output_format: str = DEFAULT_FORMAT,
        timeout_seconds: float = DEFAULT_TIMEOUT_SECONDS,
        max_output_bytes: int = DEFAULT_MAX_OUTPUT_BYTES,
    ) -> None:
        if agent not in {"code", "ask"}:
            raise HarnessAdapterError("unsupported_agent")
        if output_format not in {"default", "json"}:
            raise HarnessAdapterError("unsupported_output_format")
        self.resolved_path = Path(resolved_path)
        self.agent = agent
        self.output_format = output_format
        self.timeout_seconds = timeout_seconds
        self.max_output_bytes = max_output_bytes

    def describe(self) -> HarnessProfile:
        return HarnessProfile(
            harness_id=ADAPTER_ID,
            status=EvidenceStatus.BEST_EFFORT,
            capabilities=(
                CapabilityEvidence(
                    "native_launch",
                    EvidenceStatus.BEST_EFFORT,
                    "kilo-run-help",
                    "Kilo run supports an absolute model selector, agent, format, and positional message.",
                ),
            ),
            version="7.4.21",
            version_source="kilo-resolved",
        )

    def discover(self, request: DiscoveryRequest) -> DiscoveryReport:
        raise HarnessAdapterError("use_explicit_discovery")

    def render_launch(
        self,
        selection: Candidate,
        task: TaskRequest,
        workspace: Path,
        prompt: str,
    ) -> LaunchSpec:
        kilo = self._resolved_kilo()
        if not isinstance(prompt, str) or not prompt.strip():
            raise HarnessAdapterError("prompt_required")
        if selection.candidate_id != f"{selection.provider}/{selection.model}":
            raise HarnessAdapterError("candidate_identity_mismatch")
        try:
            # ARR's shell-free argv contract rejects CR/LF in every argument.
            # Kilo accepts the task as one positional message, so flatten the
            # generated multi-line supervisor prompt without introducing a
            # second command channel or changing its meaning materially.
            safe_prompt = " ".join(prompt.split())
            variant = selection.preferred_variant or (
                selection.variants[0] if selection.variants else None
            )
            argv = [
                kilo,
                "run",
                "-m",
                selection.candidate_id,
                "--agent",
                self.agent,
                "--format",
                self.output_format,
            ]
            if variant:
                argv.extend(("--variant", variant))
            argv.append(safe_prompt)
            command = AbsoluteArgv(
                argv=tuple(argv),
                cwd=str(Path(workspace).resolve()),
                timeout_seconds=self.timeout_seconds,
                max_output_bytes=self.max_output_bytes,
            )
        except RouterInputError as exc:
            raise HarnessAdapterError("invalid_launch_command") from exc
        return LaunchSpec(
            adapter_id=ADAPTER_ID,
            task_id=task.task_id,
            candidate_id=selection.candidate_id,
            command=command,
        )

    def verify(
        self,
        selection: Candidate | None = None,
        *,
        mode: str = "dry_run",
    ) -> VerificationReport:
        if mode not in {"dry_run", "local"}:
            raise HarnessAdapterError("unsupported_verification_mode")
        try:
            self._resolved_kilo()
        except HarnessAdapterError:
            return VerificationReport(
                ADAPTER_ID,
                mode,
                EvidenceStatus.UNKNOWN,
                False,
                "kilo_executable_unavailable",
            )
        return VerificationReport(
            ADAPTER_ID,
            mode,
            EvidenceStatus.BEST_EFFORT,
            True,
        )

    def _resolved_kilo(self) -> str:
        try:
            value = json.loads(self.resolved_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            raise HarnessAdapterError("kilo_resolution_missing") from exc
        executable = value.get("kilo_executable") if isinstance(value, dict) else None
        version = value.get("kilo_version") if isinstance(value, dict) else None
        if (
            not isinstance(executable, str)
            or not Path(executable).is_absolute()
            or not Path(executable).is_file()
            or version != "7.4.21"
        ):
            raise HarnessAdapterError("kilo_resolution_invalid")
        return executable


def load_adapter() -> KiloAdapter:
    return KiloAdapter()


if __name__ == "__main__":
    adapter = load_adapter()
    report = adapter.verify(mode="dry_run")
    print(report.to_dict())
