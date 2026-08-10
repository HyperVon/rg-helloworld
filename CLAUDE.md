# CLAUDE.md

This file is a pointer for Claude Code. The authoritative agent guidance for
this repository lives in `AGENTS.md` — read it first and follow it.

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
- Never commit unless explicitly authorized.
- Do not add explanatory comments; write idiomatic, readable code per
  language.
