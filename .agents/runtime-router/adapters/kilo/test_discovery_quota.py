#!/usr/bin/env python3
"""Offline regression tests for target-owned quota classification."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import discover_kilo_models


def _status(provider: str) -> dict:
    return {
        "providers": [{"id": provider, "available": True}],
        "liveProbes": [{"id": provider, "ok": True}],
    }


class DiscoveryQuotaTests(unittest.TestCase):
    def test_openrouter_positive_balance_is_available_payg(self) -> None:
        rows = discover_kilo_models._quota_rows(
            _status("openrouter"),
            {
                "providers": {
                    "openrouter": {
                        "status": "ok",
                        "entries": [
                            {
                                "accounting": {"resultType": "balance"},
                                "value": "$3.70",
                            }
                        ],
                    }
                }
            },
        )
        self.assertEqual("available", rows["openrouter"]["quota_status"])
        self.assertEqual("payg", rows["openrouter"]["billing"])

    def test_zero_balance_is_exhausted_and_subscription_is_distinct(self) -> None:
        zero = discover_kilo_models._quota_rows(
            _status("openrouter"),
            {
                "providers": {
                    "openrouter": {
                        "status": "ok",
                        "entries": [
                            {
                                "accounting": {"resultType": "balance"},
                                "value": "$0.00",
                            }
                        ],
                    }
                }
            },
        )
        subscription = discover_kilo_models._quota_rows(
            _status("openai"),
            {
                "providers": {
                    "openai": {
                        "status": "ok",
                        "entries": [
                            {
                                "accounting": {"resultType": "quota"},
                                "percentRemaining": 80,
                            }
                        ],
                    }
                }
            },
        )
        self.assertEqual("exhausted", zero["openrouter"]["quota_status"])
        self.assertEqual("payg", zero["openrouter"]["billing"])
        self.assertEqual("subscription", subscription["openai"]["billing"])

    def test_quota_does_not_relabel_free_candidates(self) -> None:
        candidates = discover_kilo_models._apply_quota(
            [
                {"provider": "openrouter", "cost_class": "free", "billing": "free"},
                {"provider": "openrouter", "cost_class": "paid", "billing": "paid"},
            ],
            {"openrouter": {"quota_status": "available", "quota_percent": None, "billing": "payg"}},
        )
        self.assertEqual("free", candidates[0]["billing"])
        self.assertEqual("payg", candidates[1]["billing"])

    def test_direct_credit_probe_accepts_only_redacted_status(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            node = Path(directory) / "fake-node"
            node.write_text(
                "#!/usr/bin/env python3\n"
                "import json\n"
                "print(json.dumps({'status': 'available', 'remaining': 3.70}))\n",
                encoding="utf-8",
            )
            node.chmod(0o700)
            result = discover_kilo_models._openrouter_credit_probe(
                str(node), "/nonexistent/openrouter.js", timeout=2, max_output_bytes=4096
            )
        self.assertEqual(
            {"quota_status": "available", "quota_percent": None, "billing": "payg"},
            result,
        )


if __name__ == "__main__":
    unittest.main()
