---
description: "Review current changes against repository safety and quality rules"
subtask: true
---

# Review Diff

Perform a read-only review of the current working-tree changes.

- Read `AGENTS.md`, `.kilo/operating.md`, and any domain skill that matches
  the changed files (e.g. `rghello-milestone` for milestone work,
  `adversarial-pr-review` conventions for review format).
- Inspect `git status --short`, `git diff --check`, the unstaged diff, the
  staged diff, and relevant untracked files.
- Review the full changed surface for correctness, regression risk, missing
  tests, integrity-rule compliance (no plaintext/expected-character fields
  downstream of glyph planning; maturity ranks only increase; artifacts
  record input IDs and SHA-256 hashes), secret handling, version pinning (no
  `latest` tags), and repository conventions.
- Do not read or print `.local/`, `.env` files, kubeconfigs, MinIO
  credentials, database files, logs, home-directory files, or unrelated
  external files.
- Do not edit, format, delete, commit, push, or run commands that mutate
  application data or the cluster.
- Never reproduce credentials, tokens, account identifiers, personal paths,
  hostnames, or personal or account data from the diff or tool output.
  Describe any exposure without quoting the value.
- Report findings first, ordered by severity, with `path:line` references
  and a concrete impact. State explicitly when no findings were found, then
  list residual testing gaps.

This command is a local project-specific pre-pass. It does not replace the
repository's mandatory adaptive bounded adversarial review before opening or
updating a pull request.
