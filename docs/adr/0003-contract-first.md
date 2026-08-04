# ADR-0003: Contract-first design

- Status: Accepted
- Date: 2026-08-04

## Context

Ten services across nine languages must interoperate over REST, SOAP, gRPC,
and Kafka. Hand-written clients and event schemas would drift and break the
milestone ordering (the anti-cheating boundary depends on event-schema
enforcement).

## Decision

Commit all inter-service contracts before service implementations:

- `contracts/openapi/` — REST API.
- `contracts/asyncapi/` — event topics.
- `contracts/events/` — JSON Schemas per event type.
- `contracts/proto/` — gRPC.
- `contracts/soap/` — WSDL/XSD.

`make contracts` regenerates clients, server interfaces, and validation
models. Generated source is never hand-edited.

## Consequences

- Single source of truth for every protocol boundary.
- Event schemas can be statically scanned for prohibited plaintext fields
  (see ADR-0005).
- Contract tests are enforceable in CI from Milestone 1 onward.
