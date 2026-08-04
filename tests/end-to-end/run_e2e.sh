#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

echo "Rube Goldberg Hello World - end-to-end test"
echo ""

if [ "${E2E_SKIP_GATES:-0}" != "1" ]; then
  echo ">> prerequisites"
  make prerequisites || exit 1
  echo ">> format"
  make format || exit 1
  echo ">> contracts"
  make contracts || exit 1
  echo ">> contract-test"
  make contract-test || exit 1
  echo ">> lint"
  make lint || exit 1
  echo ">> unit"
  make unit || exit 1
  echo ">> coverage"
  make coverage || exit 1
  echo ">> build"
  make build || exit 1
else
  echo ">> gates skipped (E2E_SKIP_GATES=1)"
fi

echo ">> integration"
bash tests/integration/run_integration.sh || exit 1

echo ""
echo "E2E acceptance: PASS"
