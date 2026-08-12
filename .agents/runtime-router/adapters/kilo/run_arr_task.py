#!/usr/bin/env python3
"""Run one explicitly approved ARR-managed Kilo task.

This target-owned entrypoint performs fresh-cache routing, renders the native
Kilo command through ``KiloAdapter``, and starts ARR's supervised worker only
when ``--approve`` is present. It prints redacted worker output and never
persists prompts, credentials, or provider responses.
"""

from __future__ import annotations

import argparse
import re
import tempfile
from pathlib import Path

from agent_runtime_router import (
    ExecutionApproval,
    TaskRequest,
    Track,
    build_launch_plan,
    launch_worker,
    load_catalog_cache,
    load_target_policy,
    route_catalog_cache,
)

from kilo_adapter import KiloAdapter


DEFAULT_CANDIDATE = "kilo/cohere/north-mini-code:free"
TARGET_ROOT = Path(__file__).resolve().parents[4]


def _candidate_parts(value: str) -> tuple[str, str]:
    provider, separator, model = value.partition("/")
    if not separator or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._:+\-]*", provider) or not model:
        raise ValueError("candidate must be provider/model")
    return provider, model


def _approval(item, plan, command) -> ExecutionApproval:
    return ExecutionApproval(
        approval_id=f"manual-{item.task.task_id}",
        task_id=plan.task_id,
        candidate_id=plan.candidate_id,
        command_sha256=command.sha256,
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Run one approved ARR-managed Kilo task")
    parser.add_argument("prompt")
    parser.add_argument("--candidate", default=DEFAULT_CANDIDATE)
    parser.add_argument("--task-id", default="manual-kilo-task")
    parser.add_argument("--approve", action="store_true")
    args = parser.parse_args(argv)

    provider, model = _candidate_parts(args.candidate)
    task = TaskRequest(
        task_id=args.task_id,
        required_capabilities=frozenset({"chat"}),
        min_context_window=1,
        pinned_provider=provider,
        pinned_model=model,
        sensitive=False,
    )
    policy = load_target_policy(TARGET_ROOT / ".agents/runtime-router/policy.json")
    cache = load_catalog_cache(TARGET_ROOT / ".agents/runtime-router/catalog-cache.json")
    candidates = policy.filter_candidates(cache.candidates_for_route())
    decision = route_catalog_cache(task, cache, policy)
    if decision.selected is None:
        print({"status": "NO_ROUTE", "decision": decision.to_dict()})
        return 2
    track = Track(
        id="manual-kilo",
        task=args.prompt,
        profile="routine",
        agent="code",
        read_only=True,
    )
    records, prepared = build_launch_plan(
        [track],
        candidates,
        policy.routing_policy,
        lambda _track: task,
    )
    item = prepared[0]
    print({"status": "PLAN", "route": decision.selected.candidate_id, "records": records})
    if not args.approve:
        print("Execution not started. Re-run the same command with --approve after reviewing the route.")
        return 0
    # This smoke runner intentionally uses an empty disposable workspace.  It
    # proves ARR routing, approval binding, native Kilo argv, and supervision
    # without copying the target's large dependency trees or exposing the
    # target worktree to a provider task.  A future coding-task runner should
    # supply an explicitly reviewed snapshot instead.
    with tempfile.TemporaryDirectory(prefix="arr-kilo-task-") as directory:
        result = launch_worker(
            item,
            timeout=60,
            workspace=Path(directory),
            adapter=KiloAdapter(),
            approval_factory=_approval,
            max_output_bytes=4_000_000,
        )
    print({
        "status": "SUCCEEDED" if result.failure_kind is None else "FAILED",
        "route": result.route,
        "exit_code": result.exit_code,
        "failure_kind": result.failure_kind,
        "error_code": result.error_code,
        "report": result.report,
    })
    return 0 if result.failure_kind is None else 1


if __name__ == "__main__":
    raise SystemExit(main())
