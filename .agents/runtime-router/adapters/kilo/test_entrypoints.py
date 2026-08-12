#!/usr/bin/env python3
"""Regression checks for safe target-local router entrypoint failures."""

from __future__ import annotations

import contextlib
import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from agent_runtime_router import (
    Availability,
    Candidate,
    CostClass,
    DiscoveryReport,
    EvidenceStatus,
    Freshness,
    ProbeEvidence,
    QuotaStatus,
    build_catalog_cache,
    write_catalog_cache,
)

import run_arr_task
import route_subagents


class EntrypointTests(unittest.TestCase):
    def test_missing_or_stale_global_runtime_is_structured(self) -> None:
        output = io.StringIO()
        with patch.object(run_arr_task, "_RUNTIME_IMPORT_ERROR", True), contextlib.redirect_stdout(output):
            status = run_arr_task.main(["smoke"])
        self.assertEqual(2, status)
        self.assertEqual("target_runtime_unavailable", json.loads(output.getvalue())["error_code"])

    def test_missing_cache_is_structured_and_fail_closed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            policy = root / "policy.json"
            policy.write_text("{}", encoding="utf-8")
            output = io.StringIO()
            with patch.object(run_arr_task, "POLICY_PATH", policy), patch.object(
                run_arr_task, "CACHE_PATH", root / "missing.json"
            ), contextlib.redirect_stdout(output):
                status = run_arr_task.main(["smoke"])
        self.assertEqual(2, status)
        self.assertEqual(
            {
                "error_code": "catalog_cache_missing",
                "schema_version": 1,
                "status": "INCOMPLETE",
            },
            json.loads(output.getvalue()),
        )

    def test_invalid_candidate_is_structured_and_fail_closed(self) -> None:
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            status = run_arr_task.main(["smoke", "--candidate", "not-a-candidate"])
        self.assertEqual(2, status)
        self.assertEqual("candidate_invalid", json.loads(output.getvalue())["error_code"])

    def test_plan_loads_legacy_glob_blacklist_with_current_arr(self) -> None:
        candidate = Candidate(
            provider="kilo",
            model="cohere/north-mini-code:free",
            capabilities=frozenset({"chat", "reasoning", "tool_call"}),
            availability=Availability.AVAILABLE,
            cost_class=CostClass.FREE,
            quota_status=QuotaStatus.UNKNOWN,
            context_window=256_000,
            reasoning=True,
            tool_call=True,
        )
        report = DiscoveryReport(
            adapter_id="kilo",
            status=EvidenceStatus.BEST_EFFORT,
            candidates=(candidate,),
            probes=(
                ProbeEvidence(
                    probe_id="kilo-models",
                    source="synthetic",
                    status=EvidenceStatus.BEST_EFFORT,
                    freshness=Freshness.FRESH,
                ),
            ),
        )
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            policy = root / "policy.json"
            policy.write_text(run_arr_task.POLICY_PATH.read_text(encoding="utf-8"), encoding="utf-8")
            cache = root / "catalog-cache.json"
            write_catalog_cache(cache, build_catalog_cache(report, ttl_seconds=300))
            output = io.StringIO()
            with patch.object(run_arr_task, "POLICY_PATH", policy), patch.object(
                run_arr_task, "CACHE_PATH", cache
            ), contextlib.redirect_stdout(output):
                status = run_arr_task.main(
                    ["smoke", "--candidate", "kilo/cohere/north-mini-code:free"]
                )
        self.assertEqual(0, status)
        lines = [json.loads(line) for line in output.getvalue().splitlines()]
        self.assertEqual("PLAN", lines[0]["status"])
        self.assertEqual("kilo/cohere/north-mini-code:free", lines[0]["route"])

    def test_mismatched_cache_is_structured_and_fail_closed(self) -> None:
        candidate = Candidate(
            provider="other",
            model="free/chat",
            capabilities=frozenset({"chat"}),
            availability=Availability.AVAILABLE,
            cost_class=CostClass.FREE,
            quota_status=QuotaStatus.UNKNOWN,
            context_window=8_000,
        )
        report = DiscoveryReport(
            adapter_id="other",
            status=EvidenceStatus.BEST_EFFORT,
            candidates=(candidate,),
            probes=(
                ProbeEvidence(
                    probe_id="other-models",
                    source="synthetic",
                    status=EvidenceStatus.BEST_EFFORT,
                    freshness=Freshness.FRESH,
                ),
            ),
        )
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            cache = root / "catalog-cache.json"
            write_catalog_cache(cache, build_catalog_cache(report, ttl_seconds=300))
            output = io.StringIO()
            with patch.object(run_arr_task, "POLICY_PATH", run_arr_task.POLICY_PATH), patch.object(
                run_arr_task, "CACHE_PATH", cache
            ), contextlib.redirect_stdout(output):
                status = run_arr_task.main(["smoke", "--candidate", "other/free/chat"])
        self.assertEqual(2, status)
        self.assertEqual("route_state_invalid", json.loads(output.getvalue())["error_code"])

    def test_route_subagents_rejects_state_outside_target(self) -> None:
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            status = route_subagents.main(["--policy", "/tmp/policy.json"])
        self.assertEqual(2, status)
        self.assertEqual("policy_outside_target", json.loads(output.getvalue())["error_code"])

    def test_route_subagents_plans_distinct_candidates(self) -> None:
        candidates = tuple(
            Candidate(
                provider="demo",
                model=model,
                capabilities=frozenset({"chat"}),
                availability=Availability.AVAILABLE,
                cost_class=CostClass.FREE,
                quota_status=QuotaStatus.UNKNOWN,
                context_window=8_000,
            )
            for model in ("alpha", "beta")
        )
        report = DiscoveryReport(
            adapter_id="kilo",
            status=EvidenceStatus.BEST_EFFORT,
            candidates=candidates,
            probes=(
                ProbeEvidence(
                    probe_id="kilo-models",
                    source="synthetic",
                    status=EvidenceStatus.BEST_EFFORT,
                    freshness=Freshness.FRESH,
                ),
            ),
        )
        with tempfile.TemporaryDirectory(dir=route_subagents.TARGET_ROOT) as directory:
            root = Path(directory)
            policy = root / "policy.json"
            policy.write_text(route_subagents.POLICY_PATH.read_text(encoding="utf-8"), encoding="utf-8")
            cache = root / "catalog-cache.json"
            write_catalog_cache(cache, build_catalog_cache(report, ttl_seconds=300))
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                status = route_subagents.main(
                    [
                        "--policy",
                        str(policy),
                        "--cache",
                        str(cache),
                        "--role",
                        "documentation-review",
                        "--role",
                        "test-plan",
                    ]
                )
        self.assertEqual(0, status)
        routes = json.loads(output.getvalue())["routes"]
        self.assertEqual(2, len({route["selected"] for route in routes}))


if __name__ == "__main__":
    unittest.main()
