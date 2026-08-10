# GitHub Copilot instructions

Read `AGENTS.md` and `.kilo/operating.md` before working in this repository and
follow them. The root file owns invariants and skill routing; the operating file
owns portable always-on norms.

## Project rules

- Milestone-driven development, one milestone at a time
  (`docs/architecture.md` section 29, tracked in
  `docs/implementation-status.md`).
- Required gates: `make prerequisites`, `make format`, `make lint`, `make unit`,
  `make coverage`, and `make build` must all pass; use `STRICT=1` when checking
  for missing toolchains. Run integration/e2e gates when the change requires
  cross-service verification.
- Non-negotiable integrity rules: only the CLI, orchestrator, and glyph
  catalog may see the requested plaintext; downstream events must never
  contain expected-character fields (see `docs/architecture.md` section 7).
- Pin every dependency version; never use floating `latest` tags.
- Complete every required PR verification before opening the PR; do not defer
  visual, integration, or e2e checks to after merge.
- Parallelize only across disjoint ownership boundaries or isolated worktrees;
  keep final gates serial and long-lived processes in the background.
- For user-visible UI changes, provide fresh viewport evidence (phone/laptop at
  minimum; responsive changes also cover relevant tablet/desktop/wide widths)
  and verify the changed interactions before calling the change complete.
- Do not add explanatory comments; write idiomatic code per language and
  respect the per-language formatters and linters.
- Do not commit unless explicitly asked.
