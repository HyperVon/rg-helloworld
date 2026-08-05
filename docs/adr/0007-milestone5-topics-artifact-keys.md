# ADR-0007: Milestone 5 event topic and artifact keys

- Status: Accepted
- Date: 2026-08-05

## Context

Milestone 5 adds two worker services: the C++ geometry engine (consumes
`rg.glyph-blueprints.v1`) and the Go vector-normalizer (consumes
`rg.geometry-expanded.v1`). Two decisions shape their integration:

1. Which Kafka topic carries the vector-normalizer's output events, and
2. How MinIO artifact object keys are derived so every artifact is
   addressable, deterministic, and traceable to the operation that produced
   it.

The AsyncAPI contract declares the normalized-glyph event as
`VectorNormalized` on `rg.glyph-normalized.v1`. The architecture's service
table (§13.2) lists `rg.glyph-rasterized.v1` as a future topic; the rasterizer
does not exist until Milestone 6, so the normalizer must not publish there yet.

§13.5 requires artifact keys to embed the deterministic operation ID so any
two runs of the same operation produce the same keys (idempotency) while
still distinguishing attempts.

## Decision

- The vector-normalizer publishes `VectorNormalized` CloudEvents to
  `rg.glyph-normalized.v1` (partition key `runId:glyphInstanceId`), matching
  the AsyncAPI contract. The `rg.glyph-rasterized.v1` row in the architecture
  service table remains reserved for Milestone 6.
- Artifact object keys embed the operation ID:
  - Geometry: `runs/{runId}/geometry-attempt-{attempt}-{operationId}.json`
  - Blueprint snapshot: `runs/{runId}/blueprint.json`
  - Normalized geometry: `runs/{runId}/glyphs/{position}-{glyphInstanceId}/normalized-attempt-1-{hash}.json`
  - SVG: `runs/{runId}/glyphs/{position}-{glyphInstanceId}/normalized-attempt-1-{hash}.svg`
- The operation ID is a SHA-256 hex digest over the run ID, operation name,
  glyph instance ID, attempt number, and the serialized input payload, e.g.
  the C++ engine uses
  `sha256Hex(runId + "expand-geometry" + glyphId + "1" + sha256Hex(data.serialize()))`.
  Identical inputs therefore yield identical keys and event IDs.
- CloudEvent `id` is a UUID deterministically derived from the operation ID,
  so re-processing an event does not generate a new envelope ID; envelope
  `time` and `causationid` are inherited from the triggering input event for
  byte-determinism.

## Consequences

- Consumers can deduplicate by `id` and can reconstruct or verify artifact
  keys from the event payload alone.
- `rg.glyph-normalized.v1` appears in the platform Kafka topic inventory in
  Milestone 5; the rasterizer topic lands with its service in Milestone 6.
- The orchestrator's fan-in consumers subscribe to
  `rg.geometry-expanded.v1` and `rg.glyph-normalized.v1`; both topics use the
  `runId:glyphInstanceId` partition key, keeping per-glyph ordering.
- Any future change to the operation-name string or the serialized payload
  shape changes derived keys; keys are tied to payload bytes by design.
