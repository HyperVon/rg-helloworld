# CLAUDE.md

This file is a pointer for Claude Code. The authoritative invariants and skill
index live in `AGENTS.md`; the always-on operating norms live in
`.kilo/operating.md`. Read both before making changes and follow them.

Key facts:

- Milestone-driven development: implement one milestone at a time per
  `docs/architecture.md` section 29; never start the next milestone while the
  current one's acceptance conditions fail.
- Track everything in `docs/implementation-status.md`.
- Required gates from the repo root: `make prerequisites`, `make format`,
  `make lint`, `make unit`, `make coverage`, `make build` (all must pass; use
  `STRICT=1` to fail on missing toolchains).
- Integrity rules (anti-cheating boundaries) are non-negotiable — see
  `AGENTS.md` and `docs/architecture.md` section 7.
- Complete every required PR verification before opening a PR; do not defer
  visual, integration, or e2e checks to after merge.
- Keep independent workstreams on disjoint files or isolated worktrees, run
  final gates serially, and keep long-lived processes in the background.
- Never commit unless explicitly authorized.
- Do not add explanatory comments; write idiomatic, readable code per
  language.
