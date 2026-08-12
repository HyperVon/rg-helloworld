#!/usr/bin/env python3
"""Plan several target-owned Kilo subagent routes without starting workers.

This is an explicit routing smoke path for agent-development use.  It uses the
capabilities ARR actually models for Kilo (``chat`` and, when evidenced,
``reasoning``); Kilo's ``--agent`` role labels are not ARR capabilities.  The
command is deliberately plan-only: review the selected candidates, then use a
separate approval-gated launch command for any real provider task.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from agent_runtime_router import (
    TaskRequest,
    load_catalog_cache,
    load_target_policy,
    route_with_target_policy,
)
from agent_runtime_router.errors import RouterInputError


TARGET_ROOT = Path(__file__).resolve().parents[4]
POLICY_PATH = TARGET_ROOT / ".agents/runtime-router/policy.json"
CACHE_PATH = TARGET_ROOT / ".agents/runtime-router/catalog-cache.json"

# These are human-facing workstream labels, not provider or model claims.
ROLE_TASKS: dict[str, tuple[str, bool]] = {
    "architecture-review": ("Map the repository architecture and identify boundaries.", True),
    "security-review": ("Review the target-owned routing and launch boundaries for unsafe behavior.", True),
    "documentation-review": ("Check the routing integration documentation against the repository.", False),
    "test-plan": ("Design a focused, non-destructive integration test plan.", False),
}


def _emit(value: object, *, pretty: bool) -> None:
    print(json.dumps(value, sort_keys=True, indent=2 if pretty else None))


def _state(policy_path: Path, cache_path: Path):
    try:
        policy_path = _target_owned_path(policy_path, "policy")
        cache_path = _target_owned_path(cache_path, "catalog_cache")
    except ValueError as exc:
        return None, None, str(exc)
    if not policy_path.is_file():
        return None, None, "policy_missing"
    if not cache_path.is_file():
        return None, None, "catalog_cache_missing"
    try:
        return load_target_policy(policy_path), load_catalog_cache(cache_path), None
    except (RouterInputError, OSError, ValueError, TypeError):
        return None, None, "target_router_state_invalid"


def _target_owned_path(value: Path, label: str) -> Path:
    """Resolve a state path and reject escapes from this target checkout."""

    candidate = value if value.is_absolute() else TARGET_ROOT / value
    resolved = candidate.resolve()
    try:
        resolved.relative_to(TARGET_ROOT)
    except ValueError as exc:
        raise ValueError(f"{label}_outside_target") from exc
    return resolved


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--role", action="append", choices=sorted(ROLE_TASKS))
    parser.add_argument("--policy", type=Path, default=POLICY_PATH)
    parser.add_argument("--cache", type=Path, default=CACHE_PATH)
    parser.add_argument("--pretty", action="store_true")
    args = parser.parse_args(argv)

    policy, cache, state_error = _state(args.policy, args.cache)
    if state_error is not None:
        _emit(
            {
                "schema_version": 1,
                "status": "INCOMPLETE",
                "execution": "not_started",
                "error_code": state_error,
                "next_step": "run bounded harness discovery and review the resulting cache",
            },
            pretty=args.pretty,
        )
        return 2
    assert policy is not None and cache is not None

    roles = args.role or list(ROLE_TASKS)
    try:
        available_candidates = cache.candidates_for_route()
    except RouterInputError:
        _emit(
            {
                "schema_version": 1,
                "status": "INCOMPLETE",
                "execution": "not_started",
                "error_code": "route_state_invalid",
            },
            pretty=args.pretty,
        )
        return 2
    used_candidates: set[str] = set()
    routes: list[dict[str, object]] = []
    for role in roles:
        description, requires_reasoning = ROLE_TASKS[role]
        task = TaskRequest(
            task_id=f"kilo-{role}",
            required_capabilities=frozenset({"chat"}),
            min_context_window=1,
            pinned_provider=None,
            pinned_model=None,
            requires_reasoning=requires_reasoning,
            sensitive=False,
        )
        try:
            # Each planned workstream gets a distinct candidate when the
            # catalog has enough eligible options. This keeps the output an
            # honest multi-route plan instead of silently reusing one model.
            candidates = tuple(
                candidate
                for candidate in available_candidates
                if candidate.candidate_id not in used_candidates
            )
            decision = route_with_target_policy(task, candidates, policy)
        except RouterInputError:
            _emit(
                {
                    "schema_version": 1,
                    "status": "INCOMPLETE",
                    "execution": "not_started",
                    "error_code": "route_state_invalid",
                },
                pretty=args.pretty,
            )
            return 2
        routes.append(
            {
                "role": role,
                "task": description,
                "required_capabilities": ["chat"],
                "requires_reasoning": requires_reasoning,
                "selected": decision.selected.candidate_id if decision.selected else None,
                "decision": decision.to_dict(),
            }
        )
        if decision.selected is not None:
            used_candidates.add(decision.selected.candidate_id)

    status = "READY" if all(route["selected"] is not None for route in routes) else "NO_ROUTE"
    _emit(
        {
            "schema_version": 1,
            "status": status,
            "execution": "not_started",
            "launch_mode": "plan_only",
            "active_harness": policy.active_harness,
            "routes": routes,
            "next_step": "review each selected route; launch only through an explicit approval-gated task command",
        },
        pretty=args.pretty,
    )
    return 0 if status == "READY" else 2


if __name__ == "__main__":
    raise SystemExit(main())
