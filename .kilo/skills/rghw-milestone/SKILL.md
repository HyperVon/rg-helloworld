---
name: rghw-milestone
description: Milestone workflow for the Rube Goldberg Hello World repository. Use when implementing a milestone, verifying acceptance gates, or resuming work after context compression.
---

# Milestone workflow

The repository is built one milestone at a time in the exact order of
`docs/architecture.md` section 29. `docs/implementation-status.md` is the
authoritative state; it must always be up to date so work can resume after
context compression.

## Steps

1. Read `AGENTS.md` and the relevant `docs/architecture.md` sections.
2. Read `docs/implementation-status.md`; confirm the current milestone and
   its acceptance conditions.
3. Update the status document with scope, tasks, and acceptance conditions
   before implementing.
4. Implement the smallest complete milestone; add tests before proceeding.
5. Iterate with targeted per-language targets (`make unit-<lang>`,
   `make build-<lang>`); finish with the full gates serially:
   `STRICT=1 make prerequisites`, `STRICT=1 make format`, `STRICT=1 make
   lint`, `STRICT=1 make unit`, `STRICT=1 make coverage`, and `STRICT=1 make
   build`.
6. Update documentation and the verification log.
7. Commit only when authorized, as one coherent change.

## Integrity checklist (every milestone)

- No plaintext/expected-character fields downstream of glyph planning.
- Maturity ranks only increase along the primary path.
- Artifacts record input IDs and SHA-256 hashes.
- Versions pinned; no `latest` tags.
- Coverage >= 90% per language where tooling exists.

## Context discipline

- Quiet test modes; full logs to `.local/diagnostics/`.
- Bounded output (`head`, `grep`, `kubectl logs --tail`).
- Summarize results; never dump dependency trees or full manifests.
