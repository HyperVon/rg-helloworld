# GitHub Copilot instructions

Read `AGENTS.md` before working in this repository and follow it.

## Project rules

- Milestone-driven development, one milestone at a time
  (`docs/architecture.md` section 29, tracked in
  `docs/implementation-status.md`).
- Required gates: `make format`, `make lint`, `make unit`, `make build`
  (plus `make coverage` for the 90% coverage gates) must all pass.
- Non-negotiable integrity rules: only the CLI, orchestrator, and glyph
  catalog may see the requested plaintext; downstream events must never
  contain expected-character fields (see `docs/architecture.md` section 7).
- Pin every dependency version; never use floating `latest` tags.
- Do not add explanatory comments; write idiomatic code per language and
  respect the per-language formatters and linters.
- Do not commit unless explicitly asked.
