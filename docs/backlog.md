# Project Backlog

This backlog contains optional work that must not delay the primary milestone
sequence in `docs/architecture.md`.

## Deferred

### Whitespace provenance attestation

Add a small, local Whitespace stage after the layout manifest is produced:

- Canonicalize an artifact attestation containing only opaque artifact IDs,
  maturity ranks, dimensions, operation IDs, and input/output SHA-256 hashes.
- Encode that attestation as a Whitespace program and persist it as a MinIO
  sidecar with its own SHA-256.
- Run a pinned local Whitespace interpreter at the next trust boundary and
  reject the pipeline event if the decoded attestation does not match the
  ordinary JSON manifest.
- Publish the attestation result as provenance metadata, never as user-facing
  text or a substitute for the existing artifact manifest.

This makes Whitespace a real provenance transformation and validation stage,
rather than an ornamental language cameo. Brainfuck remains a separate,
lower-priority optional experiment for a bounded artifact validator.

These languages are not security mechanisms. Whitespace source can be made
visually inconspicuous, and Brainfuck can make code difficult to read, but
neither provides encryption, access control, or safe secret storage. Passwords,
API keys, certificates, and other credentials must remain in the existing
secret-management path and must never be embedded in either language.

Before implementation, define and test:

- a minimal Whitespace instruction subset and pinned local interpreter;
- canonical encoding and byte-for-byte deterministic output;
- malformed programs, stack exhaustion, and resource limits;
- deterministic output, input IDs, and SHA-256 lineage for every artifact;
- bounded execution and explicit failure handling;
- scans proving no plaintext, expected-character data, credentials, or key
  material enter downstream events or logs.

This item belongs with the optional absurdity extensions in architecture
section 30 and should be considered only after the primary pipeline is
working, unless a later milestone gives it a concrete integrity-preserving
role.

### Artifact viewer renders JSON instead of intermediate artifacts (resolved)

The Web Shell previously showed JSON for each artifact rather than the rendered
intermediate artifact itself (vector glyphs -> geometry -> SVG -> raster ->
phrase image -> OCR -> assembly). Its old stage-based links could not identify
the generated image or binary.

The orchestrator now records only accepted event-derived MinIO object keys that
are scoped to the run. The artifact listing returns stable opaque `id` and
`artifactId` descriptors, and the descriptor proxy streams the corresponding
bytes with the recorded content type. PNG and SVG objects therefore render
inline, while JSON remains available for inspection. No cloud service or direct
Ruby-to-MinIO resolution is required.

Implementation:

- `GET /api/v1/runs/{runId}/artifacts` returns descriptors without credentials,
  object keys, or terminal assembled plaintext.
- `GET /api/v1/runs/{runId}/artifacts/{artifactId}` resolves only the internal
  run-scoped descriptor mapping and streams the MinIO object bytes.
- Content-type handling keeps PNG/SVG previews inline and rejects unknown or
  out-of-scope descriptor IDs.
