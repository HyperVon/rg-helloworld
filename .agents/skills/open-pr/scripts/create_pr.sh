#!/usr/bin/env bash
set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/../../.." && pwd)"
cd "$ROOT"

BRANCH=$(git branch --show-current)

if [ "$BRANCH" = "main" ]; then
    echo "[!] Cannot open a Pull Request from 'main'. Please checkout a feature branch."
    exit 1
fi

echo "Opening pull request for branch: $BRANCH"

# Step 1: Check existing PR
EXISTING_PR=$(gh pr list --head "$BRANCH" --json url --jq '.[0].url' 2>/dev/null || true)
if [ -n "$EXISTING_PR" ] && [ "$EXISTING_PR" != "null" ]; then
    echo "[ok] Pull request already open for branch '$BRANCH':"
    echo "$EXISTING_PR"
    exit 0
fi

# Step 2: Run pre-commit checks
echo "--- Step 1: Pre-PR quality verification ---"
./.agents/skills/commit-and-push/scripts/pre_commit_check.sh

# Step 3: Extract commit summary for title
TITLE=$(git log -1 --pretty=%B | head -n 1)

# Step 4: Verification summary from the milestone status doc
VERIFICATION=$(grep -A 8 -i 'verification' docs/implementation-status.md 2>/dev/null | head -12 || true)

BODY=$(cat <<EOF
## Overview

Pull request for branch \`$BRANCH\`.

## Changes

$(git log origin/main..HEAD --pretty=format:"- %s")

## Verification

$VERIFICATION
EOF
)

# Step 5: Create the PR
gh auth setup-git
env -u GITHUB_TOKEN gh pr create --base main --head "$BRANCH" --title "$TITLE" --body "$BODY"
