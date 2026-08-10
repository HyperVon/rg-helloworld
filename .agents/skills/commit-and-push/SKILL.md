---
name: commit-and-push
description: >-
  Finalize changes — update documentation and the milestone status, run quality
  gates, run adversarial PR review when updating an open PR, commit, and push
  the current branch with gh auth. Use when the user asks to commit and/or push
  (not for casual WIP).
---

# Commit and Push Workflow

When the user asks to "commit and push", "commit / push", or similar, follow
this workflow in order. Do NOT skip steps. The repository's milestones are
committed as one coherent change each, and only when the user explicitly
authorizes a commit.

## Step 0: Status & branch

```bash
git status
git branch --show-current
```

Ensure you are on the intended branch (not detached HEAD).

## Step 1: Documentation

- Update `docs/implementation-status.md` (scope, tasks, acceptance, and the
  verification log) when milestone work or behavior changes.
- Update `README.md` when features, stack, commands, or layout change.
- Add an ADR under `docs/adr/` for any architecture change (no unapproved
  architecture changes).
- Sync `docs/architecture.md`, `docs/runbook.md`, or `docs/troubleshooting.md`
  when behavior or commands change.
- Update `versions.env` and per-language lockfiles when dependencies move;
  never use floating `latest` tags.

## Step 2: Pre-commit checks

Run the pre-commit gate script (markdown lint + full milestone gates):

```bash
./.agents/skills/commit-and-push/scripts/pre_commit_check.sh
```

Or manually, serially:

```bash
STRICT=1 make prerequisites
STRICT=1 make format
STRICT=1 make lint
STRICT=1 make unit
STRICT=1 make coverage
STRICT=1 make build
```

Run the milestone's
acceptance/e2e gates (`make integration`, `make e2e`) when the change affects
cross-service behavior. Fix failures; do not proceed on red.

Before staging, inspect the change boundary:

```bash
git diff --check
git diff --stat
git diff --name-only
```

Confirm that every changed path is intentional and that no generated file
(regenerated `contracts/` output is fine when it matches the contract change),
credential, runtime state (`.local/`, kubeconfigs, databases), or unrelated
user change is included. Do not use a destructive cleanup command to make the
worktree appear clean.

Coverage expectation: >= 90% per language where tooling allows, enforced by
`make coverage`.

## Step 3: Commit

```bash
git add -- path/to/reviewed-file ...
git commit -m "$(cat <<'EOF'
<type>: <concise description>

EOF
)"
```

Types: `feat`, `fix`, `refactor`, `docs`, `style`, `test`, `build`, `chore`.
Match the repo's existing commit style (see `git log`).

## Step 4: Adversarial review when updating an open PR

```bash
gh pr list --head "$(git branch --show-current)" --state open
```

If an open PR exists for this branch, follow
[adversarial-pr-review](../adversarial-pr-review/SKILL.md) on the full PR diff
vs base **before** pushing. Partition it into bounded concern tracks, fix
legitimate findings (new commits as needed), re-run Step 2 quality gates, and
re-review affected tracks until that skill converges. Skip this step when
there is no open PR (WIP commit/push only).

When this push will **create** a PR (or you will open one next), also finish
every change-specific verification **before** `gh pr create` — see
[open-pr](../open-pr/SKILL.md) and `.kilo/operating.md` § Complete PR
verifications before opening. Do not push-then-open with unchecked "after
merge" test-plan items.

## Step 5: Push current branch

Push **the current branch**, not always `main`:

```bash
BRANCH=$(git branch --show-current)
gh auth setup-git
env -u GITHUB_TOKEN git push -u origin "$BRANCH"
```

If auth fails, `gh auth status` / `gh auth login`. Do not ask the user to
authenticate manually.

## Step 6: Verify

Verify both status and the exact pushed commit:

```bash
BRANCH=$(git branch --show-current)
git fetch --no-tags origin "$BRANCH"
test "$(git rev-parse HEAD)" = "$(git rev-parse "origin/$BRANCH")"
git status
```

`git status` should show the branch up to date with `origin/<branch>`. If the
SHA check fails, stop and investigate instead of claiming the push succeeded.

## Checklist

- [ ] Docs / implementation-status / ADR synced as needed
- [ ] `STRICT=1 make prerequisites`, `STRICT=1 make format`, `STRICT=1 make
      lint`, `STRICT=1 make unit`, `STRICT=1 make coverage`, and `STRICT=1
      make build` green
- [ ] If an open PR exists: [adversarial-pr-review](../adversarial-pr-review/SKILL.md) converged
- [ ] If opening a PR next: all Test plan verifications done first ([open-pr](../open-pr/SKILL.md))
- [ ] Tests green; pushed **current** branch via `gh`
