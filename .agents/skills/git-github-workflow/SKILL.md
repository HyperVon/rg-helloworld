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

1. **Establish state and authority.** Read `git status --porcelain`, `git branch --show-current`,
   `git log --oneline -5`, remote, and protection rules. Confirm the canonical
   base is `main` and whether a clean worktree is required. Confirm the user has
   authorized any `push`, `publish`, or `PR` creation; otherwise stop after the
   draft.

   **Worktree safety and pre-flight checklist:**
   - Run `git status --porcelain` to identify untracked, modified, and staged files.
   - If uncommitted changes exist that do not belong to the current task:
     - Ask the user whether to commit, stash (`git stash -u` to include untracked files), or discard.
     - Never run destructive commands (`git checkout -- .`, `git clean -fd`, `git reset --hard`) without explicit approval.
   - Confirm the target branch does not already exist locally or remotely (`git branch --list <name>`, `git ls-remote --heads origin <name>`).
2. **Plan the branch and commits.** Use trunk-based branches (`feat/`, `fix/`,
   `docs/`) from `main`. Keep commits atomic and conventional
   (`feat:`, `fix:`, `docs:`, `chore:`). Never use `reset --hard`,
   `filter-branch`, `rebase --force`, or history rewriting on shared branches
   without explicit approval.

   **Author identity verification:**
   - Inspect `git config user.name` and `git config user.email` (or `git var GIT_AUTHOR_IDENT`).
   - Confirm the email matches the user's intended public identity or GitHub privacy email (e.g. `<id>+<username>@users.noreply.github.com`).
   - If identity is unconfigured or misconfigured, propose the appropriate local config command (`git config user.name "..." && git config user.email "..."`) and wait for confirmation. Never commit with an auto-generated local hostname email.
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
5. **Verify hygiene and target-local gates.** Check `git diff --stat`, relative
   links, no secrets or personal paths (using the target's documented hygiene
   check when one exists), and that the branch does not expose ignored runtime
   state such as `.kilo` or `.idea`. Discover the target repository's own
   documented format, lint, test, build, and coverage commands from its local
   guidance and build files, then run the smallest complete relevant gate.
   `make check` and `scripts/check.py --quick` are examples, not universal
   commands: never assume a helper, path, language toolchain, or quality
   threshold from the source project or from another repository. If no
   complete gate is available, report the exact checks that were run and the
   limitation rather than inventing or importing one.
6. **Apply repository-required adversarial review gates.** Inspect local
   policy before pushing a branch that will open or update a pull request. When
   that policy requires `adversarial-pr-review`, invoke it through at least one
   fresh, independent read-only subagent on the final diff before the initial
   PR push and every later update push. Parent-only self-review is insufficient.
   After authorized fixes, rerun affected tracks in a new fresh context until a
   final pass reports no additional findings; if the capability or convergence
   evidence is missing, block the push. Record the review verdict, findings,
   convergence pass, and any user decisions in the PR verification. This gate
   does not replace the separate user authorization to push.
7. **Publish only with approval.** Push to the approved remote/branch, set
   upstream only when requested, and open the PR with `gh pr create` using the
   approved body. Report branch, commit, remote, and checks.

## Boundaries and gotchas

- Never run `git add .` or `git add -A` from repository root. Explicitly stage only the files owned by the task (`git add path/to/file1 path/to/file2`).
- Check `git diff --cached` before committing to verify zero unintended files, debug logs, or credentials are staged.
- Use explicit issue closing keywords in PR bodies (`Fixes #123`, `Closes #456`) rather than vague issue references.
- Do not `push --force`, `push --force-with-lease` on `main`, or rewrite
  published history without explicit approval and a backup branch.
- Do not commit secrets, `.env`, `id_rsa`, `*.pem`, or personal filesystem
  paths. Redact examples.
- Do not create a remote, tag, or release (`git tag`/`gh release`) without
  separate explicit authorization per `docs/release.md`.
- When local policy requires adversarial review, do not push a branch intended
  to open or update a PR without a completed fresh-context review of its final
  diff and convergence evidence; a prior review does not cover later changes.
- Prefer `AGENTS.md` hierarchy over adding duplicate harness entrypoints.
- Keep commits focused: one logical change per commit, no bundled refactors.

## Report and stop condition

Report: branch/base, commit list, PR/issue draft, files changed, hygiene
results, exact commands run, and what was not run. Stop and ask when the
worktree is dirty in a way that would be lost, the base has diverged, an
approval is missing for a destructive or publishing action, or the next step
requires credentials. Do not claim a PR is ready merely because a draft exists.
