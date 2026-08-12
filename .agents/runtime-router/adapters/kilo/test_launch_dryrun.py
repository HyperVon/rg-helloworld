#!/usr/bin/env python3
"""Launch-shape-only dry-run test for the Kilo ARR adapter.

This is NOT a production adapter. It validates that, IF a Kilo launch spec is
built, ARR's launch binding accepts it (absolute, shell-free argv with matching
timeout/output limits and no environment overrides). It does NOT start a worker
and does NOT invoke kilo.

Native launch is exercised only by the separate approval-gated runner; this
test proves that an actual Kilo catalog identifier, including its nested model
path, binds to ARR's shell-free worker command shape.
"""

from pathlib import Path

from agent_runtime_router import Availability, Candidate, CostClass, QuotaStatus, TaskRequest
from agent_runtime_router.dispatch import DispatchPlan
from agent_runtime_router.harnesses.base import bind_launch_spec
from kilo_adapter import KiloAdapter

REPO_ROOT = Path(__file__).resolve().parents[3]
TIMEOUT_SECONDS = 60.0
MAX_OUTPUT_BYTES = 4_000_000
CANDIDATE_ID = "kilo/~anthropic/claude-sonnet-latest"


def main() -> None:
    selection = Candidate(
        provider="kilo",
        model="~anthropic/claude-sonnet-latest",
        capabilities=frozenset({"chat"}),
        availability=Availability.AVAILABLE,
        cost_class=CostClass.FREE,
        quota_status=QuotaStatus.UNKNOWN,
        context_window=256_000,
    )
    task = TaskRequest(
        task_id="dryrun",
        required_capabilities=frozenset({"chat"}),
        min_context_window=1,
        pinned_provider="kilo",
        pinned_model="~anthropic/claude-sonnet-latest",
    )
    spec = KiloAdapter(
        timeout_seconds=TIMEOUT_SECONDS,
        max_output_bytes=MAX_OUTPUT_BYTES,
    ).render_launch(selection, task, REPO_ROOT, "dry-run probe (no execution)")
    plan = DispatchPlan(
        task_id="dryrun",
        candidate_id=CANDIDATE_ID,
        provider=selection.provider,
        model=selection.model,
        payload_sha256="0" * 64,
        timeout_seconds=TIMEOUT_SECONDS,
        max_output_bytes=MAX_OUTPUT_BYTES,
    )

    command = bind_launch_spec(spec, plan)
    assert command is not None, "bind_launch_spec returned None"
    assert Path(command.argv[0]).is_absolute(), "launch executable must be absolute"
    assert command.argv[-1] == "dry-run probe (no execution)"
    assert "--agent" in command.argv and "code" in command.argv
    print("launch-shape-only bind OK:", command.argv[0], command.argv[1:3])
    print("PASS: native launch remains separate and approval-gated.")


if __name__ == "__main__":
    main()
