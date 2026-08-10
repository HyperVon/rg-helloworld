---
name: open-pr
description: >-
  Open a GitHub PR with gh — complete every verification in the PR test plan
  before creating the PR (never defer checks to after merge), pre-PR quality
  gates, mandatory adaptive bounded adversarial review, conventional title, and
  structured body. Use when the user asks to open or create a pull request.
---

# Open Pull Request Skill

## Non-negotiable: verify before `gh pr create`

**Always complete all verifications for a PR prior to creating the PR.** Prefer
taking the time to be sure the change definitely works over shipping faster
with unchecked boxes.

- Every item in the PR **Test plan** (and **Verification Results**) must be
  **actually run** and marked `[x]` **before** `gh pr create`.
- Do **not** list a check and leave it `[ ]` for "after merge", "CI will catch
  it", or "user can spot-check later".
- Do **not** open a PR with known incomplete manual/e2e/anti-cheating
  verification just because unit gates passed.
- If a check is not applicable, **omit it** from the body (or note N/A with
  reason) — do not leave an unfinished checkbox.
- k3d/e2e runs, integration tests, and anti-cheating suite runs that the
  change needs belong **here**, not post-merge.

See [.kilo/operating.md](../../../.kilo/operating.md) § Complete verifications
before opening a PR.

## Step 0: Branch & remote

```bash
git branch --show-current
git status
```

- Do **not** open a PR from `main`.
- Push the **current** feature branch before creating the PR.

## Step 1: Existing PRs

```bash
gh pr list --head "$(git branch --show-current)"
```

If one exists, return its URL instead of duplicating.

## Step 2: Quality gates

```bash
./.agents/skills/commit-and-push/scripts/pre_commit_check.sh
```

Must pass: markdown lint, `STRICT=1 make prerequisites`, and `STRICT=1 make format`,
`STRICT=1 make lint`, `STRICT=1 make unit`, `STRICT=1 make coverage`,
`STRICT=1 make build`. Plus milestone-relevant gates when the change
touches cross-service behavior: `make integration` and `make e2e`
(anti-cheating suite must pass).

## Step 3: Change-specific verification

Run whatever the change requires **before** drafting checked boxes:

| Change kind | Verify with |
| :--- | :--- |
| Milestone implementation | `make e2e` + the milestone's acceptance conditions in `docs/implementation-status.md` |
| Contract changes | `make contracts` regenerated; `make contract-test` green; generated code not hand-edited |
| Cross-service integration | `make integration`; artifact lineage matches `docs/artifact-lineage.md` |
| Orchestrator / SSE / CLI behavior | Targeted service tests plus a bounded `rghw run` smoke (see `/acceptance-smoke`) |

Do not invent a Test plan item you have not executed.

## Step 4: Adversarial review (mandatory)

Follow [adversarial-pr-review](../adversarial-pr-review/SKILL.md) on the full
branch diff vs base **before** creating the PR. The parent must partition the
diff into bounded concern tracks, fix legitimate findings, and re-review
affected tracks until that skill converges.

## Step 5: Title & body

Conventional title (`feat:`, `fix:`, `docs:`, …). Structured body: overview,
changes, verification results (gates, coverage, e2e), and a **Test plan**
section.

**Test plan rule:** only checked items. Every `[x]` must already be done.

## Step 6: Create via `gh`

```bash
BRANCH=$(git branch --show-current)
gh auth setup-git
env -u GITHUB_TOKEN gh pr create --base main --head "$BRANCH" --title "<title>" --body "<body>"
```

Or use the checked-in helper (runs the pre-commit gate and assembles the body
from `docs/implementation-status.md`):

```bash
./.agents/skills/open-pr/scripts/create_pr.sh
```

## Step 7: Return URL

Give the user the clickable PR link.

## Checklist

- [ ] Not on `main`; current branch pushed
- [ ] `STRICT=1 make prerequisites`, `STRICT=1 make format`, `STRICT=1 make
      lint`, `STRICT=1 make unit`, `STRICT=1 make coverage`, and `STRICT=1
      make build` green; e2e/anti-cheating green when applicable
- [ ] All change-specific verifications done (no deferred "after merge" checks)
- [ ] [adversarial-pr-review](../adversarial-pr-review/SKILL.md) converged
- [ ] PR body Test plan / Verification Results all `[x]` or omitted as N/A
- [ ] Conventional title + structured body; `gh pr create` succeeded
