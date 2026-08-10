#!/usr/bin/env bash
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../../../.." && pwd)"
cd "$ROOT"

echo "==> Markdown lint"
if command -v markdownlint-cli2 >/dev/null 2>&1; then
    markdownlint-cli2 "AGENTS.md" "README.md" "CONTRIBUTING.md" "SECURITY.md" \
        "docs/**/*.md" ".agents/**/*.md" ".kilo/**/*.md"
elif command -v npx >/dev/null 2>&1; then
    npx --yes markdownlint-cli2 "AGENTS.md" "README.md" "CONTRIBUTING.md" "SECURITY.md" \
        "docs/**/*.md" ".agents/**/*.md" ".kilo/**/*.md"
else
    echo "WARN: markdownlint-cli2 not available; skipping markdown lint" >&2
fi

echo "==> make prerequisites"
STRICT=1 make prerequisites

echo "==> make format"
STRICT=1 make format

echo "==> make lint"
STRICT=1 make lint

echo "==> make unit"
STRICT=1 make unit

echo "==> make coverage"
STRICT=1 make coverage

echo "==> make build"
STRICT=1 make build

echo "==> Pre-commit checks passed"
