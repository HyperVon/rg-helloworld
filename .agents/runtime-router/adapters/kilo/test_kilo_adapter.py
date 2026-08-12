#!/usr/bin/env python3
"""Offline contract tests for the target-owned Kilo launch adapter."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from agent_runtime_router import (
    Availability,
    Candidate,
    CostClass,
    QuotaStatus,
    TaskRequest,
)
from agent_runtime_router.errors import HarnessAdapterError

from kilo_adapter import KiloAdapter


def _candidate() -> Candidate:
    return Candidate(
        provider="kilo",
        model="cohere/north-mini-code:free",
        capabilities=frozenset({"chat"}),
        availability=Availability.AVAILABLE,
        cost_class=CostClass.FREE,
        quota_status=QuotaStatus.UNKNOWN,
        context_window=256_000,
        variants=("instant", "thinking"),
    )


def _task() -> TaskRequest:
    return TaskRequest(
        task_id="adapter-test",
        required_capabilities=frozenset({"chat"}),
        min_context_window=1,
        pinned_provider="kilo",
        pinned_model="cohere/north-mini-code:free",
    )


class KiloAdapterTests(unittest.TestCase):
    def test_render_launch_preserves_prompt_and_native_shape(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            spec = KiloAdapter().render_launch(
                _candidate(), _task(), Path(directory), "test prompt"
            )
        self.assertEqual("kilo", spec.adapter_id)
        self.assertEqual("test prompt", spec.command.argv[-1])
        self.assertEqual("run", spec.command.argv[1])
        self.assertEqual("-m", spec.command.argv[2])
        self.assertEqual(_candidate().candidate_id, spec.command.argv[3])
        self.assertIn("--format", spec.command.argv)
        self.assertEqual("json", spec.command.argv[spec.command.argv.index("--format") + 1])
        self.assertIn("--variant", spec.command.argv)
        self.assertEqual("instant", spec.command.argv[spec.command.argv.index("--variant") + 1])
        self.assertEqual((), spec.command.environment)

    def test_multiline_prompt_is_flattened_for_shell_free_argv(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            spec = KiloAdapter().render_launch(
                _candidate(), _task(), Path(directory), "first line\nsecond line"
            )
        self.assertEqual("first line second line", spec.command.argv[-1])

    def test_nul_prompt_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(HarnessAdapterError):
                KiloAdapter().render_launch(
                    _candidate(), _task(), Path(directory), "bad\x00prompt"
                )

    def test_discovery_is_explicitly_separate(self) -> None:
        with self.assertRaisesRegex(HarnessAdapterError, "use_explicit_discovery"):
            KiloAdapter().discover(object())

    def test_missing_resolution_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            adapter = KiloAdapter(resolved_path=Path(directory) / "missing.json")
            report = adapter.verify()
        self.assertFalse(report.passed)
        self.assertEqual("kilo_executable_unavailable", report.error_code)


if __name__ == "__main__":
    unittest.main()
