---
name: git-github-workflow
description: >-
  Maintain local Git hygiene and GitHub collaboration with approval-gated
  branches, atomic commits, PR and issue hygiene, and release safety. Use when
  creating branches, committing, pushing, opening or reviewing pull requests,
  triaging issues, or changing repository GitHub settings.
---

# Git GitHub Workflow

Keep Git history readable and GitHub collaboration safe with explicit approval
gates. The agent proposes branches, commits, and PRs; it does not rewrite
history or publish without authority.

## Contract

- **Input:** intent (branch/commit/PR/issue/release), current `git status`,
  target base, `.github/*` templates, and applicable local guidance.
- **Output:** branch plan, atomic commit set, PR/issue draft, settings change
  proposal, and verification evidence — or a blocked report.
- **Owner:** local Git hygiene and GitHub collaboration workflow.
- **Non-goals:** architecture decisions, code review of diff content, or
  provider/model selection.
- **Side effects:** read-only until approval; afterward only `git branch`,
  `commit`, `push`, and `gh`/`API` calls the user explicitly authorized.

## Workflow

1. **Establish state and authority.** Read `git status`, `git branch --show-current`,
   `git log --oneline -5`, remote, and protection rules. Confirm the canonical
   base is `main` and whether a clean worktree is required. Confirm the user has
   authorized any `push`, `publish`, or `PR` creation; otherwise stop after the
   draft.
2. **Plan the branch and commits.** Use trunk-based branches (`feat/`, `fix/`,
   `docs/`) from `main`. Keep commits atomic and conventional
   (`feat:`, `fix:`, `docs:`, `chore:`). Never use `reset --hard`,
   `filter-branch`, `rebase --force`, or history rewriting on shared branches
   without explicit approval. Verify author identity is the intended public
   identity before committing.
3. **Draft the change.** Keep PRs small, describe user-visible change,
   motivation, scope/safety checklist, and verification (`make check`,
   `gh pr checks`). Use `.github/pull_request_template.md` and
   `ISSUE_TEMPLATE/*` when present. Link issues, update `CHANGELOG.md` when
   user-visible.
4. **Improve existing prompts when useful.** If the target has weak `AGENTS.md`,
   `CLAUDE.md`, `.cursor/rules`, or copilot instructions, propose paste-ready
   text-level improvements derived from catalog decision procedures rather than
   copying a parallel skill. Keep always-loaded files concise via
   `skill-optimizer`.
5. **Verify hygiene.** Check `git diff --stat`, relative links, no secrets or
   personal paths (`scripts/public_hygiene_check.py`), and that the branch does
   not expose `.kilo`/`.idea` or other ignored state. Run the repository's
   relevant gate (`make check` or `scripts/check.py --quick`).
6. **Publish only with approval.** Push to the approved remote/branch, set
   upstream only when requested, and open the PR with `gh pr create` using the
   approved body. Report branch, commit, remote, and checks.

## Boundaries and gotchas

- Do not `push --force`, `push --force-with-lease` on `main`, or rewrite
  published history without explicit approval and a backup branch.
- Do not commit secrets, `.env`, `id_rsa`, `*.pem`, or personal filesystem
  paths. Redact examples.
- Do not create a remote, tag, or release (`git tag`/`gh release`) without
  separate explicit authorization per `docs/release.md`.
- Prefer `AGENTS.md` hierarchy over adding duplicate harness entrypoints.
- Keep commits focused: one logical change per commit, no bundled refactors.

## Report and stop condition

Report: branch/base, commit list, PR/issue draft, files changed, hygiene
results, exact commands run, and what was not run. Stop and ask when the
worktree is dirty in a way that would be lost, the base has diverged, an
approval is missing for a destructive or publishing action, or the next step
requires credentials. Do not claim a PR is ready merely because a draft exists.
