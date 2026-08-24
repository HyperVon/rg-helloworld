# ADR-0004: Redis Streams as the UI projection layer

- Status: Accepted
- Date: 2026-08-04

## Context

The UI needs a low-latency, reconnect-friendly event feed, while PostgreSQL is
the authoritative control-plane store and Kafka is the durable domain-event
pipeline. The architecture requires both Kafka and Redis to be materially
used.

## Decision

Use **Redis Streams** as the browser event projection:

- `rg:run:{runId}:events` — UI event stream consumed by the TypeScript event
  gateway and replayed to SSE clients via the `?lastEventId=` query parameter.
- `rg:run:{runId}:summary` — current-state projection hash with a 24-hour TTL.
- Redis is never authoritative; PostgreSQL constraints provide final
  correctness and Kafka remains the domain-event backbone.

## Consequences

- Browser refresh and reconnection reconstruct run state from Redis.
- Large payloads stay in MinIO; Redis holds only small projection entries.
- Redis delivers distinct behavior from Kafka (consumer groups, pending
  entries, replay) as required by the architecture.
