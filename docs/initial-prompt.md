# KiloCode Master Prompt: Implement Rube Goldberg Hello World

You are implementing a polyglot, event-driven project called `rube-goldberg-hello-world`.

The full architecture and requirements are defined in:

```text
docs/architecture.md
```

Treat that document as authoritative.

## Objective

Implement a completely local distributed system that eventually prints:

```text
Hello World
```

to standard output and exits successfully.

The final phrase must be derived from:

```text
vector glyph blueprints
→ explicit line geometry
→ normalized SVG
→ raster images
→ composed phrase image
→ OCR observations
→ adjudicated symbols
→ assembled UTF-8
```

Do not introduce a code path that simply prints the input argument or a hard-coded phrase.

## Mandatory technology ownership

Use these exact language responsibilities:

```text
Go:
- CLI
- vector normalizer

Kotlin:
- run orchestrator

Java:
- SOAP glyph catalog

C++:
- geometry expansion

C#/.NET:
- gRPC rasterizer

Python:
- phrase composition and OCR preprocessing

TypeScript/Node.js:
- OCR worker
- browser event gateway

Ruby:
- OCR adjudicator
- HTMX artifact inspector

Rust:
- final phrase assembler
```

Infrastructure:

```text
Docker
k3d/k3s Kubernetes
Apache Kafka in KRaft mode
PostgreSQL
Redis Streams
MinIO
Terraform
OpenTelemetry Collector
Prometheus
Loki
Tempo
Grafana
```

Front end:

```text
React shell with React Flow
Angular custom-element telemetry panel
HTMX artifact inspector isolated in an iframe
```

Protocols:

```text
REST
SOAP
gRPC
Kafka events
Server-Sent Events
```

## Non-negotiable integrity requirements

1. Only the CLI, orchestrator, and glyph catalog may see the complete requested plaintext before final validation.
2. No downstream event may contain:
  - `targetText`
  - `expectedCharacter`
  - `unicodeCodePoint`
  - `characterName`
  - equivalent fields
3. The OCR worker and Ruby adjudicator must not have access to the expected output.
4. The Rust assembler must assemble only accepted OCR-derived symbols.
5. The CLI must print only the orchestrator’s terminal `assembledText`.
6. Every primary transformation must increase the artifact maturity rank.
7. Every output artifact must record its input artifact IDs and SHA-256 hashes.
8. Kafka consumers must be idempotent.
9. No paid service or external runtime API may be used.
10. The full acceptance environment must run on one local laptop.

## Engineering rules

- Work contract-first.
- Pin all dependency and container versions.
- Never use floating `latest` tags.
- Prefer deterministic outputs.
- Use structured JSON logging.
- Propagate OpenTelemetry trace context through HTTP, SOAP, gRPC, and Kafka.
- Keep large payloads in MinIO rather than Kafka, PostgreSQL logs, Redis, or command output.
- Do not make unapproved architecture changes.
- Record unavoidable changes as ADRs under `docs/adr/`.
- Do not combine service implementations into one language merely to accelerate development.
- Do not bypass a protocol required by the architecture.
- Do not replace Kafka with Redis or vice versa.
- Do not replace Kubernetes with Docker Compose in the acceptance environment.
- Docker Compose may be added only as an optional focused-development aid.

## Agent workflow

Implement one milestone at a time in the exact order described in `docs/architecture.md`.

For each milestone:

1. Read the relevant architecture sections.
2. Update `docs/implementation-status.md` with:
  - Scope.
  - Tasks.
  - Acceptance conditions.
3. Implement the smallest complete milestone.
4. Add tests before proceeding.
5. Run only targeted checks during iteration.
6. Run the milestone’s full checks before completion.
7. Update documentation.
8. Commit the milestone as one coherent change when source-control actions are authorized.

Do not begin the next milestone while the current milestone’s acceptance conditions fail.

## Context and output discipline

Avoid generating enormous tool output that consumes the agent context.

- Use quiet test modes.
- Capture complete logs in files.
- Show only the relevant failure excerpt.
- Do not dump entire dependency trees.
- Do not print complete Kubernetes manifests when a focused diff is sufficient.
- Use `kubectl logs --tail`.
- Use bounded `grep`, `sed`, and `head` output.
- Store diagnostics under `.local/diagnostics/`.
- Summarize command results rather than repeating thousands of lines.
- Maintain `docs/implementation-status.md` so work can resume after context compression.

## Required repository commands

The final repository must support:

```bash
make prerequisites
make contracts
make format
make lint
make unit
make integration
make build
make images
make cluster
make infra
make deploy
make wait
make run
make demo
make e2e
make chaos
make diagnostics
make down
make destroy
```

## First implementation task

Begin with Milestone 0 only:

```text
Repository skeleton
```

Create:

- Directory structure.
- Root Makefile.
- Version-management files.
- Formatter and linter configurations.
- Minimal compilable projects for every required language.
- `docs/architecture.md`.
- `docs/implementation-status.md`.
- Initial ADR directory.
- A CI workflow that compiles and unit-tests each skeleton service.
- A clear root README explaining that functionality is not yet implemented.

Do not implement Kafka, Kubernetes, SOAP, gRPC, OCR, or business functionality during Milestone 0.

Milestone 0 is complete only when:

```bash
make format
make lint
make unit
make build
```

all succeed from the repository root.

At completion, report:

- Files created.
- Commands executed.
- Test results.
- Remaining Milestone 0 limitations.
- The next milestone, without starting it.
