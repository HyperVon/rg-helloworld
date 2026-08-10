# ADR-0005: Anti-cheating boundary enforcement

- Status: Accepted
- Date: 2026-08-04

## Context

The final output must be *derived* through OCR and adjudication, not copied.
Only the CLI, orchestrator, and glyph catalog may ever see the requested
plaintext. Downstream workers must not receive `targetText`,
`expectedCharacter`, `unicodeCodePoint`, or equivalent fields.

## Decision

Enforce the boundary at four layers:

1. **Static**: a repository test scans post-planning event schemas for
   prohibited field names and fails if any occur (architecture 7.4).
2. **Runtime**: a Kafka-event validator rejects prohibited fields.
3. **Contract test**: deliberately send `{"expectedCharacter":"H"}` to a
   downstream schema and verify validation fails.
4. **Printer**: the Go CLI's only successful print path uses the terminal
   response's `assembledText`; no `fmt.Println(options.Message)`-style path
   exists.

## Consequences

- Downstream services (C++, Go normalizer, C#, Python, Node, Ruby, Rust)
  cannot cheat even if modified.
- Event schemas must be reviewed whenever new fields are proposed.
- This ADR is the standing justification for the prohibited-field scans in
  `tests/anti-cheating/` (directory reserved; tests deferred).
