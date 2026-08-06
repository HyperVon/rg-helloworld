# Implementation Status

> Status of the Rube Goldberg Hello World project, milestone by milestone.
> Update this document whenever a milestone's scope, tasks, or acceptance
> conditions change, and mark tasks complete only after their checks pass.

## Milestone overview

| # | Milestone | Status |
| ---: | --- | --- |
| 0 | Repository skeleton | **COMPLETE** |
| 1 | Contracts (OpenAPI, AsyncAPI, JSON Schema, WSDL/XSD, protobuf) | **COMPLETE** |
| 2 | Local platform (k3d, Terraform, PostgreSQL, Kafka KRaft, Redis, MinIO) | **COMPLETE** |
| 3 | Thin vertical slice (CLI → REST → Kafka → SSE) | **COMPLETE** |
| 4 | SOAP planning (Java glyph catalog, `RUBE_SIMPLEX_V1`) | **COMPLETE** |
| 5 | Geometry and vector artifacts (C++, Go) | **COMPLETE** |
| 6 | gRPC rasterization (C#, ImageSharp) | **IN PROGRESS** |
| 7 | Composition and preprocessing (Python) | not started |
| 8 | OCR and adjudication (Node.js, Ruby) | not started |
| 9 | Rust assembly and true final output | not started |
| 10 | Mixed-framework UI (React Flow, Angular, HTMX) | not started |
| 11 | Observability (OTel, Prometheus, Loki, Tempo, Grafana) | not started |
| 12 | Hardening and demonstration | not started |

The authoritative architecture is [docs/architecture.md](architecture.md).
Milestone 0 scope below is derived from section 29 (Implementation Sequence) and
section 24 (Repository Structure) of that document.

---

## Milestone 0 — Repository skeleton

### Scope

- Repository directory structure matching section 24 of the architecture.
- Root `Makefile` exposing the full required target interface; Milestone 0
  targets (`prerequisites`, `format`, `lint`, `unit`, `build`, `clean`) are
  functional, later targets are placeholders.
- Version-management files: `versions.env`, `.tool-versions`, `.ruby-version`,
  `.nvmrc`, `global.json`, `rust-toolchain.toml`, `Directory.Packages.props`,
  `go.mod`, `gradle` wrapper, `Cargo.lock`, `package-lock.json`,
  `Gemfile.lock`, `requirements-dev.txt`.
- Formatter and linter configuration for every language:
  `gofmt`/`go vet`, Spotless (Java), ktlint (Kotlin), `clang-format` (C++),
  `dotnet format` (C#), ruff (Python), prettier + `tsc --noEmit`
  (TypeScript), rubocop (Ruby), `rustfmt` + clippy (Rust), plus markdownlint
  and shellcheck for documentation and scripts.
- Minimal compilable, unit-tested skeleton project for every required
  language (see table below), with 90% coverage gates per language
  (`make coverage`).
- Cross-language integration harness (`tests/integration/run_integration.sh`)
  that builds every service artifact and asserts each binary's version
  contract.
- Milestone acceptance e2e harness (`tests/end-to-end/run_e2e.sh`) that runs
  all gates plus the integration harness.
- `docs/architecture.md`, `docs/implementation-status.md`, initial ADR
  directory (`docs/adr/`), runbook/troubleshooting/artifact-lineage stubs.
- CI workflow (`.github/workflows/ci.yml`) that compiles and unit-tests each
  skeleton service, runs format checks and 90% coverage gates, and executes
  the integration and e2e harnesses.
- `scripts/prerequisites.sh` toolchain checker.
- Root `README.md` explaining that functionality is not yet implemented.
- Agent configuration for AI harnesses: `AGENTS.md`, `CLAUDE.md`,
  `.github/copilot-instructions.md`, `.cursor/rules/`, `.windsurfrules`,
  and Kilo commands/agents/skills under `.kilo/`.

Explicitly **not** in scope for Milestone 0: Kafka, Kubernetes, SOAP, gRPC,
OCR, MinIO, PostgreSQL, Redis, Terraform, observability, web front ends, and
any business functionality.

### Skeleton services

| Directory | Language | Version gate | Unit test |
| --- | --- | --- | --- |
| `cmd/rghello` | Go | `go build` | `go test` |
| `services/vector-normalizer-go` | Go | `go build` | `go test` |
| `services/glyph-catalog-java` | Java 25 | Maven `package` | JUnit Jupiter |
| `services/run-orchestrator-kotlin` | Kotlin 2.4 / JVM 21 | Gradle `assemble` | JUnit Jupiter |
| `services/geometry-engine-cpp` | C++20 | CMake | CTest |
| `services/rasterizer-dotnet` | .NET 10 | `dotnet build` | xUnit |
| `services/image-pipeline-python` | Python 3.14+ | `compileall` | unittest |
| `services/ocr-worker-node` | TypeScript 7.0 / Node 26 | `tsc` | `node --test` |
| `services/event-gateway-node` | TypeScript 7.0 / Node 26 | `tsc` | `node --test` |
| `services/adjudicator-ruby` | Ruby 4.0+ | `ruby -c` | minitest |
| `services/phrase-assembler-rust` | Rust 1.97 | `cargo build` | `cargo test` |

### Tasks

- [x] Create repository directory structure.
- [x] Write `docs/architecture.md` (committed with the initial repository).
- [x] Write root `Makefile` with the complete target interface.
- [x] Write version-management files.
- [x] Write formatter and linter configurations for all languages.
- [x] Create compilable skeleton projects for all required languages.
- [x] Add a unit test to every skeleton project.
- [x] Add a 90% coverage gate per language (`make coverage`).
- [x] Create the cross-language integration harness (`make integration`).
- [x] Create the milestone acceptance e2e harness (`make e2e`).
- [x] Write `docs/implementation-status.md`.
- [x] Create `docs/adr/` with the initial ADRs (0001–0005).
- [x] Create runbook/troubleshooting/artifact-lineage document stubs.
- [x] Write `scripts/prerequisites.sh`.
- [x] Write `.github/workflows/ci.yml` compiling and testing every skeleton.
- [x] Write root `README.md`.
- [x] Add agent configuration for AI harnesses (`AGENTS.md`, `CLAUDE.md`,
      Copilot, Cursor, Windsurf, Kilo commands/agents/skills).

### Acceptance conditions

```bash
make format
make lint
make unit
make coverage
make build
make integration
make e2e
```

must all pass from the repository root, with every required language toolchain
installed.

### Verification log

| Date | Check | Result |
| --- | --- | --- |
| 2026-08-04 | `make format` | PASS |
| 2026-08-04 | `make lint` | PASS |
| 2026-08-04 | `make unit` | PASS |
| 2026-08-04 | `make coverage` | PASS (all gates 90%+, Go 100%, Java 100%, Kotlin 100%, Python 94%, Node 100%, Ruby 100%, .NET 100%) |
| 2026-08-04 | `make build` | PASS |
| 2026-08-04 | `make integration` | PASS (11/11 banners) |
| 2026-08-04 | `make e2e` | PASS |

### Milestone 0 limitations

- `web/` (React, Angular) contains placeholder directories only; the web shell,
  telemetry element, and HTMX inspector arrive in Milestone 10.
- `contracts/` is empty; all contracts arrive in Milestone 1.
- Infrastructure directories (`infra/`, `observability/`, `scripts/*.sh`
  beyond `prerequisites.sh`) are placeholders.
- `make contracts/images/cluster/infra/deploy/wait/run/demo/chaos/diagnostics/
  down/destroy` are interface stubs and report not implemented.
- The integration harness covers skeleton artifacts only; platform-backed
  integration suites (Kafka, PostgreSQL, Redis, MinIO, SOAP, gRPC, SSE)
  arrive in Milestones 2–3. The true e2e (`rghello run` printing
  `Hello World`) arrives in Milestone 9; the current e2e proves the gates
  plus the cross-language artifact contract.
- Rust and C++ coverage gates run in CI (cargo-llvm-cov, gcovr); locally they
  report a skip when the tool or a GNU compiler is unavailable.
- The .NET rasterizer project uses a 3-project structure (library, CLI,
  tests) to achieve proper Coverlet coverage instrumentation.
- `rghello` does not accept `--message` or any other option yet.
- The Makefile skips a language whose toolchain is missing; CI runs strict
  with the full toolchain.

### Next milestone

Milestone 1 — Contracts: OpenAPI, AsyncAPI, JSON Schemas, WSDL/XSD, protobuf,
valid examples, the `make contracts` generation target, and prohibited-field
tests. Not started until Milestone 0 acceptance passes.

---

## Milestone 1 — Contracts

### Scope

- Commit all inter-service contracts before service implementations (per ADR-0003).
- `contracts/openapi/` — REST API specification for the CLI → gateway → orchestrator interface.
- `contracts/asyncapi/` — AsyncAPI specification for Kafka event topics.
- `contracts/events/` — JSON Schemas for every event type (CloudEvents-shaped envelope).
- `contracts/proto/` — Protobuf definitions for gRPC rasterizer.
- `contracts/soap/` — WSDL and XSD for SOAP glyph catalog (`urn:rube-goldberg:glyph-catalog:v1`).
- `contracts/examples/` — Valid example payloads for every event and API request/response.
- `make contracts` — target that validates all contract files parse correctly and generates documentation/examples.
- `make contract-test` — target that validates all examples against schemas and enforces prohibited-field tests.
- `tests/contract/` — test suite that scans schemas for prohibited fields (section 7.4) and validates examples.

### Tasks

- [x] Create OpenAPI 3.0 spec for REST API (section 10).
- [x] Create AsyncAPI 2.6 spec for Kafka event topics (section 13).
- [x] Create JSON Schemas for all event types (CloudEvents envelope, glyph blueprint, geometry, rasterized glyph, OCR observations, adjudicated symbols, assembled phrase, run events).
- [x] Create Protobuf v3 definitions for gRPC rasterizer (section 12).
- [x] Create WSDL/XSD for SOAP glyph catalog (section 11).
- [x] Create valid example payloads for every schema.
- [x] Implement `make contracts` target (validate schema syntax).
- [x] Implement `make contract-test` target (validate examples against schemas + prohibited-field tests).
- [x] Add contract validation tests in `tests/contract/` (prohibited-field test event).
- [x] Add prohibited-field tests that scan schemas and validate examples (section 7.4).
- [x] Update `Makefile` with `contracts` and `contract-test` targets.
- [x] Pin contract tooling versions in `versions.env`.
- [x] Update `docs/implementation-status.md`.

### Acceptance conditions

```bash
make contracts    # all contract files parse correctly
make contract-test  # all examples validate against schemas; prohibited-field tests pass
```

### Verification log

| Date | Check | Result |
| --- | --- | --- |
| 2026-08-04 | `make contracts` | PASS (13 schemas, OpenAPI, AsyncAPI, proto, WSDL/XSD parse) |
| 2026-08-04 | `make contract-test` | PASS (12 examples validate; prohibited-field detection works) |
| 2026-08-04 | `make format` | PASS |
| 2026-08-04 | `make lint` | PASS |
| 2026-08-04 | `make unit` | PASS (includes contract-test) |
| 2026-08-04 | `make coverage` | PASS (contract-test + all language gates) |
| 2026-08-04 | `make build` | PASS |
| 2026-08-04 | `make integration` | PASS (11/11 banners) |
| 2026-08-04 | `make e2e` | PASS |

### Milestone 1 limitations

- Contract files are committed and validated; client/server stub generation
  (`openapi-generator`, `protoc`, JAXB) is deferred until each consuming
  milestone needs generated code (Milestone 3 for REST, 4 for SOAP, 6 for
  gRPC).
- The runtime Kafka-event validator that rejects prohibited fields (section
  7.4) lands with the Kafka platform in Milestone 2; the static schema scan
  is active now.

### Next milestone

Milestone 3 — Thin vertical slice (CLI → REST → Kafka → SSE). Not started until
Milestone 2 acceptance passes.

---

## Milestone 2 — Local platform

### Scope

- k3d cluster creation script (`scripts/k3d-create.sh`) with a local registry
  (`infra/k3d/`), plus teardown (`scripts/k3d-delete.sh`).
- Terraform root module (`infra/terraform/`) managing namespace, Secrets,
  ConfigMaps, Helm releases, PV/PVCs, and network policies per section 22.
- PostgreSQL (one replica, 256 MiB request per section 21.5).
- Apache Kafka in KRaft mode (one broker, one replica, no ZooKeeper).
- Redis (one replica).
- MinIO artifact store with bucket `rube-goldberg-artifacts` (section 16).
- Readiness checks (`scripts/wait-ready.sh`) and platform smoke tests
  (`scripts/smoke-test.sh`): Kafka test message, MinIO artifact round trip,
  PostgreSQL and Redis checks.
- Makefile targets `cluster`, `infra`, `wait`, `down`, `destroy` wired to the
  scripts; acceptance runnable via `make demo`-style sequence.

### Tasks

- [x] Install local platform tools (Docker runtime via Colima, k3d, kubectl,
      helm, terraform) pinned in `versions.env`.
- [x] Create `infra/k3d/cluster.yaml` and registry configuration.
- [x] Implement `scripts/k3d-create.sh` and `scripts/k3d-delete.sh`.
- [x] Create Terraform root module with pinned Helm chart versions.
- [x] Deploy PostgreSQL, Kafka KRaft, Redis, MinIO via Terraform/Helm.
- [x] Add readiness checks to `scripts/wait-ready.sh`.
- [x] Add platform smoke tests to `scripts/smoke-test.sh`.
- [x] Wire Makefile targets `cluster`, `infra`, `wait`, `down`, `destroy`.
- [x] Update `docs/implementation-status.md` verification log.

### Acceptance conditions

- All infrastructure pods ready in namespace `rube-goldberg`.
- Test message passes through Kafka (produce + consume).
- MinIO artifact round trip works (put + get + hash verify).
- PostgreSQL and Redis checks pass.

### Verification log

| Date | Check | Result |
| --- | --- | --- |
| 2026-08-04 | Cluster creation (`make cluster`) | PASS (k3d cluster with local registry) |
| 2026-08-04 | Infrastructure deploy (`make infra`) | PASS (8 Terraform resources: namespace, 3 secrets, PostgreSQL, Kafka KRaft, Redis, MinIO) |
| 2026-08-04 | Readiness (`make wait`) | PASS (7 pods ready: kafka-controller-0/1/2, minio, minio-console, postgres, redis) |
| 2026-08-04 | Kafka smoke test | PASS (message round-tripped correctly) |
| 2026-08-04 | MinIO smoke test | PASS (artifact round-tripped, hash: 25dd2e8c1f464b6433a8c4aed702d153590f95c8b3182cad2e9a91f156768203) |
| 2026-08-04 | PostgreSQL smoke test | PASS (connection OK) |
| 2026-08-04 | Redis smoke test | PASS (PONG) |
| 2026-08-04 | Format/lint/unit/coverage/build | PASS (from Milestone 0) |
| 2026-08-04 | `make e2e` | PASS (all gates + platform smoke tests pass) |

### Milestone 2 limitations

- Platform services use single-replica Bitnami charts for local development;
  horizontal scaling and HA topologies arrive with the production hardening
  milestone (Milestone 12).
- Kafka uses KRaft mode with a fixed cluster ID (not persistent); a fresh
  cluster gets a new cluster ID each time. Production will need a stable
  cluster ID secret.
- MinIO runs in standalone (non-distributed) mode; distributed mode arrives
  with the hardening milestone.
- The local Docker registry (registries: 5001) is available for image pushing
  but services are not yet pushed; image builds land in Milestone 3.
- Network policies are not yet enforced; they arrive with the security
  hardening milestone.
- Credentials are pinned in Terraform as plain strings in `data` blocks for
  local development; production will use Vault or sealed secrets.

---

## Milestone 3 — Thin vertical slice

### Scope

- [x] Implement the orchestrator (Kotlin) as a Ktor web server with:
  - [x] REST endpoint `POST /api/v1/runs` accepting a `CreateRunRequest`
  - [x] Kafka producer that publishes a CloudEvents envelope to the planning topic
  - [x] SSE endpoint `GET /api/v1/runs/{runId}/stream` for live updates
  - [x] Redis cache for run state
  - [x] Kafka consumer that listens for the temp worker's response and publishes
    the final `run-events.v1` event
- [x] Implement a temporary worker (Node.js) that:
  - [x] Consumes the planning event from Kafka
  - [x] Echoes the requested message back as a "glyph blueprint" event
  - [x] Is clearly marked as temporary (removed in Milestone 4)
- [x] Update the CLI (Go) to:
  - [x] Submit a run via HTTP POST
  - [x] Stream SSE updates from the orchestrator
  - [x] Print the final assembled text to stdout
- [x] Add integration tests that verify the full control route
- [x] Update Makefile with `make run` target for local development
- [x] Deploy orchestrator and temp worker to Kubernetes

### Acceptance conditions

- CLI starts a run via `rghello run` (HTTP POST to orchestrator).
- SSE updates arrive during processing.
- Terminal result prints to stdout (the requested plaintext).
- Idempotency works (same idempotency key returns same run).
- `make e2e` passes with the new vertical slice.

### Verification log

| Date | Check | Result |
| --- | --- | --- |
| 2026-08-04 | Orchestrator unit tests (`./gradlew test`) | PASS (33 tests, jacoco line coverage >= 90%) |
| 2026-08-04 | Orchestrator ktlint | PASS |
| 2026-08-04 | Temp worker unit tests (`npm test`) | PASS (17 tests) |
| 2026-08-04 | Temp worker coverage (`npm run coverage`) | PASS (94.7% lines >= 90%) |
| 2026-08-04 | Temp worker lint (`npm run lint`) | PASS |
| 2026-08-04 | CLI tests (`go test ./...`) | PASS (coverage 90.8%) |
| 2026-08-04 | CLI vet + build | PASS |
| 2026-08-04 | Integration tests | PASS (0 failures) |
| 2026-08-04 | Image build + push (`localhost:5001`) | PASS (run-orchestrator:milestone3, temp-worker:milestone3) |
| 2026-08-04 | Deploy to k3d (`rube-goldberg` namespace) | PASS (both deployments ready) |
| 2026-08-04 | Vertical slice smoke test | PASS (`rghello run` printed `Hello World`, exit 0) |
| 2026-08-04 | `make e2e` | PASS (all gates + integration + platform smoke tests + vertical slice) |

---

## Milestone 4 — SOAP planning

### Scope

- [ ] Implement the Java glyph catalog (`services/glyph-catalog-java`) as a
      WSDL-first SOAP server (Spring Boot + Spring Web Services):
  - [ ] Serve the contract WSDL at `/ws/glyph-catalog`
  - [ ] `PlanPhrase` operation: decode the phrase, assign opaque
        `glyphInstanceId`s, map every character to a `RUBE_SIMPLEX_V1` glyph
        (H e l o W r d + SPACE), emit a gap blueprint for whitespace
  - [ ] `GetAlternateBlueprint` operation: return an alternate geometric
        representation for a glyph of a stored plan
  - [ ] Persist plans (embedded H2, file-backed) so alternates survive restarts
  - [ ] SOAP fault for unsupported characters
- [ ] Generate the Kotlin SOAP client from `contracts/soap/glyph-catalog.wsdl`
      (wsimport at build time) and wrap it in the orchestrator
- [ ] Orchestrator planning path:
  - [ ] Call `PlanPhrase` on run creation
  - [ ] Store the expected code points privately (never downstream)
  - [ ] Emit one `glyph-blueprint-produced.v1` event per phrase position to
        `rg.glyph-blueprints.v1` with partition key `runId:glyphInstanceId`
  - [ ] Remove the temp-worker echo path from the run state machine
- [ ] Remove the temporary worker (`services/temp-worker-node`), its
      deployment manifest, and Makefile references
- [ ] Deploy the glyph catalog to Kubernetes and update smoke tests:
  - [ ] Eleven ordered blueprint records for `"Hello World"` on
        `rg.glyph-blueprints.v1`
  - [ ] Gap position exists at index 5
  - [ ] Downstream blueprint events contain no plaintext or code points
- [ ] Add the section 7.4 static prohibited-field scan on event schemas

### Acceptance conditions

- `"Hello World"` produces eleven ordered blueprint records (positions 0..10).
- Gap position exists (position 5, kind `GAP`, advance width, no primitives).
- Downstream events (`rg.glyph-blueprints.v1`) exclude plaintext and code
  points; `rghello run` still prints `Hello World` via the orchestrator.
- Plans persist; `GetAlternateBlueprint` returns a different blueprint.
- `make e2e` passes (gates + integration + platform smoke + SOAP planning).

### Verification log

| Date | Check | Result |
| --- | --- | --- |
| 2026-08-04 | Java glyph catalog `mvn verify` | PASS (26 tests, JaCoCo line >= 90%, generated JAXB excluded) |
| 2026-08-04 | Java spotless:check | PASS |
| 2026-08-04 | Kotlin orchestrator `./gradlew check` | PASS (38 tests, JaCoCo line >= 90%, generated wsimport classes excluded) |
| 2026-08-04 | Kotlin ktlintCheck | PASS |
| 2026-08-04 | `make contracts` / `make contract-test` | PASS (XSD wrapper shape `glyphs/glyph`, `primitives/primitive`; prohibited-field scans green) |
| 2026-08-04 | `make format` / `make lint STRICT=1` | PASS |
| 2026-08-04 | `make coverage STRICT=1` / `make build` | PASS |
| 2026-08-04 | `make integration` | PASS (failures=0; SOAP round trip: 11 glyph records, positions 0..10, gap present) |
| 2026-08-05 | `make e2e` | PASS (gates + integration + smoke; `rghello run` printed `Hello World`; 11 blueprint records, gap at 5, no prohibited fields) |
| 2026-08-05 | Dependency upgrade sweep (ADR-0006) | PASS (Spring Boot 4.1.0 / Spring WS 5.0.2 / JDK 25 Temurin / Lettuce 7.6.0 / TypeScript 7.0.2 / Node 26 / Python 3.14 / Ruby 4.0 / Terraform providers helm 3.2.0, kubernetes 3.2.1, kubectl 1.19.0; CI actions SHA-pinned) |
| 2026-08-05 | `make format` / `make lint STRICT=1` | PASS (new pins; ktlint 1.8.0, tsc 7.0.2 clean) |
| 2026-08-05 | `make unit` / `make coverage` / `make build` | PASS (all language gates >= 90%; Java 26 tests on Boot 4.1.0, Kotlin 38, .NET 5/5, Python 4/4, Node 5+5, Ruby 5, Rust 5) |
| 2026-08-05 | `make integration` | PASS (failures=0; SOAP round trip 11 glyph records, gap present) |
| 2026-08-05 | Terraform helm provider v3 migration | PASS (`terraform plan`: 0 to add, 4 in-place changes, 0 to destroy; e2e apply: 0 added, 4 changed, 0 destroyed) |
| 2026-08-05 | `make e2e` (post-upgrade) | PASS (full gates + integration + smoke; smoke: eleven ordered blueprint records, no plaintext/code points) |

E2E debugging notes (2026-08-05): the deployed orchestrator initially failed
SOAP planning with "Cannot find 'wsdl/glyph-catalog.wsdl'". The wsimport
generated client resolves `wsdlLocation` via `Class.getResource`, which is
package-relative without a leading slash; the fix was the standard
`-wsdllocation /wsdl/glyph-catalog.wsdl` in
`services/run-orchestrator-kotlin/build.gradle.kts`. Images were rebuilt and
deployments rolled. The smoke test also had a `set -euo pipefail` trap: the
blueprint consumer timed out (fewer than 50 topic messages) and aborted the
script silently before printing FAIL diagnostics; fixed with
`--timeout-ms 5000` and a `|| true` guard on the consumption pipeline so
assertions surface real PASS/FAIL output.

### Milestone 4 limitations

- The orchestrator completes runs from its private expected-text store; the
  true OCR-derived assembly replaces this in Milestone 9 (the temporary
  Node.js echo worker was removed in this milestone).
- The orchestrator does not yet write the requested text to PostgreSQL
  (architecture stage 1 step 2); run text lives in memory plus the Redis
  result until a persistence milestone.
- The section 7.4 runtime Kafka-event validator is deferred to the milestone
  that adds downstream consumers; the static schema scan and orchestrator
  unit tests already enforce the prohibited-field boundary.

---

## Milestone 5 — Geometry and vector artifacts

### Scope

- Implement the C++ geometry engine (`services/geometry-engine-cpp`) as a
  librdkafka consumer of `rg.glyph-blueprints.v1` (section 29, Stage 2):
  - Convert abstract primitives (POLYLINE, POINT, ARC) into explicit line
    segments; approximate arcs with configurable subdivisions
  - Validate finite coordinates; remove zero-length segments; merge exactly
    collinear adjacent segments
  - Calculate bounding box, segment count, total path length, intersection
    count, and a deterministic geometry SHA-256
  - Emit `GAP_GEOMETRY` layout records for gap blueprints (advance width,
    left/right bearing — not skipped)
  - Write blueprint snapshot + JSON geometry artifact to MinIO with
    deterministic object keys (operation ID embedded per section 13.5)
  - Publish `GeometryExpanded` CloudEvents to `rg.geometry-expanded.v1`
    (partition key `runId:glyphInstanceId`, idempotent operation ID)
- Implement the Go vector-normalizer (`services/vector-normalizer-go`) as a
  franz-go consumer of `rg.geometry-expanded.v1` (Stage 3):
  - Translate into positive canvas space, scale into a standard em-square
    preserving aspect ratio, align to a common baseline, apply side bearings
  - Quantize to fixed precision; generate deterministic SVG (polyline only,
    no text elements) and its SHA-256
  - Normalize gap geometry into layout metadata (no rasterizer involvement)
  - Store normalized JSON geometry + SVG + layout metadata in MinIO
  - Publish `VectorNormalized` CloudEvents to `rg.glyph-normalized.v1`
    (partition key `runId:glyphInstanceId`, idempotent operation ID)
- Orchestrator (Kotlin) stage progression:
  - Runs move PLANNING → GENERATING_GEOMETRY → NORMALIZING → SUCCEEDED;
    `handleCreateRun` publishes blueprints and enters GENERATING_GEOMETRY
    instead of completing immediately
  - Kafka consumer on `rg.geometry-expanded.v1` + `rg.glyph-normalized.v1`
    with per-run fan-in counting (idempotent sets), maturity validation
    (10→20, 20→30; backward/equal-rank events fail the run, section 2.1),
    and the section 7.4 runtime prohibited-field validator (rejects
    `message`, `targetText`, `expectedCharacter`, `unicodeCodePoint`,
    `characterName`, `glyphLabel`)
  - Run completes from the private expected-text store only after all
    positions are normalized (fan-in), preserving `rghello run` output
- Deploy geometry-engine and vector-normalizer to Kubernetes
  (`infra/k8s/milestone5/`), extend `scripts/build-images.sh` (milestone5
  tag), and extend `scripts/smoke-test.sh` with milestone-5 acceptance
  checks
- Host-level integration tests: one-shot (`--once`) modes that transform a
  blueprint CloudEvent into geometry and normalized events without Kafka or
  MinIO, so `make integration` can verify the artifact pipeline, schema
  conformance, determinism, and maturity increases in CI
- Pin new dependencies in `versions.env` (librdkafka, franz-go, minio-go) and
  update CI to install `librdkafka-dev` for the C++ job

### Tasks

- [x] Implement C++ JSON parser/serializer (canonical key ordering) with tests
- [x] Implement C++ SHA-256 (FIPS 180-4) with NIST known-answer tests
- [x] Implement geometry expansion (POLYLINE/POINT/ARC, zero-length removal,
      collinear merge, finite validation, bbox/length/intersections/checksum)
- [x] Implement MinIO S3 client (AWS SigV4 + POSIX-socket HTTP PUT) with tests
- [x] Implement librdkafka consumer/producer wrapper and worker loop
- [x] Add `--once` one-shot mode and version banner; CMake library layout with
      90% coverage gate support
- [x] Implement Go normalization (em-square, baseline, bearings, quantization)
- [x] Implement deterministic SVG generation + SHA-256 (no text elements)
- [x] Implement Go MinIO store (minio-go), franz-go transport, worker loop
- [x] Add Go `--once` mode; pin franz-go and minio-go in go.mod/go.sum
- [x] Orchestrator: stage tracker + runtime validator + Kafka consumer with
      fan-in; update HttpApiTest to the new state flow
- [x] Add orchestrator tests: maturity violation fails run; prohibited-field
      event (e.g. `{"expectedCharacter":"H"}`) fails validation
- [x] Dockerfiles for both workers; `infra/k8s/milestone5/` manifests
- [x] Extend build-images.sh (milestone5 tag) and smoke-test.sh (geometry +
      normalized event counts, maturity, SVG no-text, MinIO artifacts)
- [x] Integration harness: blueprint fixture + `--once` pipeline validation
      against the event schemas
- [x] Pin librdkafka (and libcurl/OpenSSL equivalents) in versions.env and CI
- [x] Update docs: ADR-0007 (topics + artifact keys), service READMEs,
      verification log

### Acceptance conditions

- Every drawable glyph blueprint produces a deterministic SVG (identical
  input → byte-identical SVG; verified by unit, integration, and cluster
  smoke tests).
- Generated SVG contains no text elements (unit tests assert the generator
  emits only polyline; smoke test greps a stored SVG artifact).
- Every geometry artifact increases maturity: blueprint 10 → geometry 20 →
  normalized 30, with the orchestrator rejecting backward/equal-rank events.
- Eleven ordered `rg.geometry-expanded.v1` records (positions 0..10, gap at
  position 5) and eleven `rg.glyph-normalized.v1` records are produced for
  `"Hello World"` in the cluster; events contain no prohibited fields.
- `rghello run` still prints `Hello World` (run completes after the
  normalized fan-in, from the private expected-text store).
- `make format`, `make lint`, `make unit`, `make coverage`, `make build`
  (STRICT=1), `make integration`, and `make e2e` all pass.

### Verification log

| Date | Check | Result |
| --- | --- | --- |
| 2026-08-05 | C++ `make unit-cpp` | PASS (ctest 7/7: json, sha256, geometry, s3, service, version, banner) |
| 2026-08-05 | C++ `make format-cpp` / `make lint-cpp` | PASS (clang-format --dry-run --Werror clean) |
| 2026-08-05 | C++ Docker build (`geometry-engine:milestone5`) | PASS (gcc:13.2-bookworm builder + runtime; librdkafka-dev 2.0.2-1 arm64 pin; gcovr excludes src/kafka.cpp) |
| 2026-08-05 | Go `make unit-go` | PASS (all 7 packages; kfake + kadm + minio-go; kfake has no auto-create, explicit CreateTopics) |
| 2026-08-05 | Go `make coverage-go` | PASS (module total 90.9% >= 90%) |
| 2026-08-05 | Kotlin `make unit-kotlin` | PASS (stage tracker PLANNING -> GENERATING_GEOMETRY -> NORMALIZING -> SUCCEEDED; maturity violation fails run; prohibited-field validator) |
| 2026-08-05 | `make format` / `make lint STRICT=1` | PASS (all languages; `-Werror` clean) |
| 2026-08-05 | `make unit` / `make coverage` / `make build` (STRICT=1) | PASS (cmd/rghello 91.5%, vector-normalizer 90.9%; Java/Kotlin/dotnet/python/node/ruby gates >= 90%; C++ gcovr + Rust llvm-cov skipped locally, CI enforces) |
| 2026-08-05 | `make contracts` / `make contract-test` | PASS (schemas unchanged; prohibited-field scans green) |
| 2026-08-05 | `make integration` | PASS (geometry-engine --once deterministic; maturity 10 -> 20; vector-normalizer --once deterministic; maturity 20 -> 30; events validate against schemas; no prohibited fields; SVG has no text elements; SVG sha256 matches event svgSha256; 11 banners) |
| 2026-08-05 | `make e2e` (cluster rube-goldberg) | PASS (all gates + integration; smoke Tests 1-6: Kafka/MinIO/PostgreSQL/Redis round trips, `rghello run` printed Hello World with 11 ordered blueprints + gap, eleven geometry-expanded + gap records mature 10 -> 20, eleven glyph-normalized records mature 20 -> 30, 88 geometry + 88 normalized + 88 SVG artifacts in MinIO, SVG no text elements and sha256 match) |

E2E debugging notes (2026-08-05): the geometry-engine image initially pinned
`librdkafka-dev=2.2.0-1`, which Debian bookworm arm64 does not ship (candidate
2.0.2-1); the pin moved to versions.env as `LIBRDKAFKA_DEBIAN_VERSION`. A
second issue: the builder image was GCC 13 but the runtime stage was
`debian:bookworm-slim` (GCC 12 libstdc++), so the binary failed at startup
with `GLIBCXX_3.4.32 not found`; the runtime stage now reuses
`gcc:13.2-bookworm`. The smoke test's maturity checks originally used
adjacency greps (`"inputMaturity":10,"outputMaturity":20`) but live events are
compact single-line JSON with non-adjacent fields; both greps now use
`grep -qE '"inputMaturity":10,.*"outputMaturity":20'` (and 20 -> 30 for
normalized). The k3d node hit DiskPressure during image builds (Docker VM disk
94% full), evicting workloads; `docker image prune -af` plus
`docker restart k3d-rube-goldberg-server-0` recovered the cluster, and stale
evicted pods were force-deleted so `wait-ready.sh` sees only live pods.

### Milestone 5 limitations

- Runs still complete from the orchestrator's private expected-text store;
  OCR-derived assembly replaces this in Milestone 9.
- PostgreSQL-backed step rows and the outbox (sections 17.4/17.5) are not yet
  implemented; fan-in uses in-memory idempotent sets in the orchestrator.
- The orchestrator does not yet invoke the C# rasterizer;
  `rg.glyph-rasterized.v1` arrives in Milestone 6.
- Retry/timeout policy for stuck stages lands with the failure-policy
  milestone; a run whose worker events never arrive stays in stage.

---

## Milestone 6 — gRPC rasterization

### Scope

- Implement the C#/.NET rasterizer (`services/rasterizer-dotnet`) as a gRPC
  server implementing `rg.rasterizer.v1.Rasterizer.RenderGlyph` (Stage 4,
  section 12):
  - Validate requests at the trust boundary: reject non-finite coordinates,
    empty segment lists, more than the configured maximum segments, canvases
    outside the configured size limits, unknown line caps, unsupported
    supersampling factors, and missing/malformed `input_artifact_sha256`
  - Render normalized em-square segments onto a transparent canvas using the
    equivalent local rendering library ImageSharp (section 30 note: Stage 4
    permits "SkiaSharp or an equivalent local rendering library"; ADR-0008
    records the choice): rounded line caps, configurable antialiasing and
    stroke width, deterministic integer supersampling with box downsampling
  - Crop to the drawn content bounds plus an OCR margin; encode PNG bytes
    deterministically; compute SHA-256 and pixel density
  - Upload PNG to MinIO under a deterministic object key that embeds the
    section 13.5 operation ID (`SHA256(runId + "rasterize-glyph" +
    glyphInstanceId + attempt + inputArtifactSha256)`); duplicate requests
    therefore map to the same logical artifact (idempotent)
  - Never receive the phrase, expected character, or code point — the request
    carries only segments and opaque identifiers
- Extend the rasterizer proto contract (`contracts/proto/rasterizer/v1/`):
  add `input_artifact_sha256` to `RenderGlyphRequest` (the idempotency input
  hash) and point `go_package` at the consuming Go module; C# codegen stays
  build-time (Grpc.Tools); Go codegen becomes a pinned `make contracts`
  step (protoc + protoc-gen-go + protoc-gen-go-grpc) with generated code
  committed under `services/vector-normalizer-go/internal/rasterproto/`
- Extend the Go vector-normalizer (Stage 3 → 4, section 29):
  - gRPC client with a ten-second per-call deadline and retries for transient
    status codes only (Unavailable, ResourceExhausted, Aborted)
  - After normalizing a drawable glyph, call the rasterizer with the
    normalized segments (1024 em-square, baseline 800 → 512×512 canvas) and a
    named render profile, then publish `rg.glyph-rasterized.v1`
    (maturity 30 → 40, `transformation.name` = `rasterize-glyph`, event id
    derived from the same deterministic operation ID)
  - Gap geometry is normalized into layout metadata only — no rasterizer
    call, no rasterized event
  - `--once` gains `--rasterizer-url` so the host integration harness can run
    the real gRPC contract against a local rasterizer server
- Extend the Kotlin orchestrator (section 29):
  - Runs move PLANNING → GENERATING_GEOMETRY → NORMALIZING → RASTERIZING →
    SUCCEEDED; the run completes only after every drawable position has a
    rasterized event (drawable count excludes gap blueprints)
  - Kafka consumer on `rg.glyph-rasterized.v1` with maturity validation
    (30 → 40) and the section 7.4 prohibited-field validator
- Deploy the rasterizer to Kubernetes (`infra/k8s/milestone6/`), extend
  `scripts/build-images.sh` (milestone6 tag for rasterizer,
  vector-normalizer, run-orchestrator), and extend `scripts/smoke-test.sh`
  with milestone-6 acceptance checks
- Host-level integration tests: run the rasterizer locally in
  file-store mode, drive it through `vector-normalizer --once
  --rasterizer-url`, and verify PNG validity, determinism, object keys,
  schema conformance, maturity, and the gap skip in CI
- Pin new dependencies in `versions.env` (Grpc.AspNetCore, Grpc.Tools,
  ImageSharp, ImageSharp.Drawing, Minio .NET, grpc-go, protobuf-go, protoc
  toolchain) and NuGet lock files; pin the rasterizer base images
  (`sdk:10.0.302` builder, `aspnet:10.0.9` runtime)

### Tasks

- [x] Update `contracts/proto/rasterizer/v1/rasterizer.proto`
      (`input_artifact_sha256 = 10`, `go_package` → vector-normalizer module)
- [x] Add `scripts/gen-proto.sh` (pinned protoc 35.1 + protoc-gen-go
      v1.36.11 + protoc-gen-go-grpc v1.6.2) and wire proto codegen into
      `make contracts`
- [x] C# rasterizer library: request validation, ImageSharp rendering with
      crop, PNG encoding, SHA-256, pixel density
- [x] C# rasterizer stores: MinIO (Minio 7.0.0) and file-based local store
      (tests/integration); deterministic object keys with operation IDs
- [x] C# `RasterizerService` gRPC handler + CLI `serve`/`version` host;
      version 0.1.0-milestone6
- [x] C# unit tests (validation, determinism, crop, profiles, keys, stores,
      service) with coverlet 90% gate
- [x] C# Dockerfile (sdk:10.0.302 / aspnet:10.0.9) and NuGet lock files
- [x] Go generated proto package + rasterclient (deadline, transient-only
      retry) with bufconn tests
- [x] Go worker: rasterized event publication for drawables, gap skip,
      deterministic event id; `--once --rasterizer-url`; version
      0.2.0-milestone6; coverage >= 90%
- [x] Kotlin orchestrator: RASTERIZING stage, rasterized fan-in with
      drawable count, maturity 30 → 40; version 0.4.0-milestone6; tests
- [x] Integration harness: local rasterizer server + gRPC `--once` pipeline
      checks (determinism, PNG validity/sha256, keys, schema, prohibited
      fields, gap skip)
- [x] `infra/k8s/milestone6/` manifests (rasterizer + overlays for
      vector-normalizer and orchestrator), build-images.sh milestone6 tags
- [x] Smoke test Test 7: ten rasterized records for `"Hello World"` (gap
      excluded), maturity 30 → 40, no prohibited fields, PNG artifacts in
      MinIO with matching sha256 and PNG magic bytes
- [x] Docs: ADR-0008, service READMEs, versions.env pins, verification log

### Acceptance conditions

- Every drawable glyph blueprint produces a recognizable PNG: 512×512
  normalized canvas cropped to drawn bounds plus OCR margin, non-empty
  rendered content (verified by unit tests, integration, and cluster smoke).
- The rasterizer receives no expected character: the gRPC request contains
  only segments and opaque identifiers (contract + tests); rasterized events
  pass the section 7.4 prohibited-field scan.
- Duplicate requests are idempotent: identical `RenderGlyphRequest`s produce
  the same object key, the same event id, and byte-identical PNGs (unit +
  integration determinism checks).
- Ten ordered `rg.glyph-rasterized.v1` records (positions 0..10, gap at
  position 5 excluded) are produced for `"Hello World"` in the cluster,
  mature 30 → 40, and contain no prohibited fields.
- `rghello run` still prints `Hello World` (run completes only after the
  rasterized fan-in, from the private expected-text store).
- `make format`, `make lint`, `make unit`, `make coverage`, `make build`
  (STRICT=1), `make contracts`, `make integration`, and `make e2e` all pass.

### Verification log

| Date | Check | Result |
| --- | --- | --- |
| 2026-08-05 | Milestone 6 scope/tasks/acceptance recorded | PASS (written before implementation) |
| 2026-08-05 | Proto contract update + codegen (`make contracts`-wired scripts/gen-proto.sh; scripts/gen-csharp-proto.sh) | PASS (Go client generated in-repo; C# generated in pinned sdk:10.0.302 container on arm64 macOS, native on Linux x64; both committed, never hand-edited) |
| 2026-08-05 | C# `make unit-dotnet` | PASS (63/63: validator, renderer determinism/crop/profiles, operation keys, stores, service; TestServerCallContext) |
| 2026-08-05 | C# `make coverage-dotnet` | PASS (99.19% lines / 95.28% branches / 100% methods >= 90%; generated code excluded via ExcludeByFile) |
| 2026-08-05 | C# `make format-dotnet` / `make lint-dotnet` | PASS (dotnet format whitespace + --verify-no-changes on library, cli, tests; generated/ skipped via generated_code) |
| 2026-08-05 | Go `make coverage-go` | PASS (cmd/rghello 91.5%, vector-normalizer 90.5% >= 90%; generated rasterproto excluded in Makefile + CI) |
| 2026-08-05 | Go rasterclient bufconn tests | PASS (deadline 10s, retry only Unavailable/ResourceExhausted/Aborted, 3 attempts, backoff; no retry on InvalidArgument/DeadlineExceeded) |
| 2026-08-05 | Kotlin `./gradlew build` | PASS (ktlint + tests + JaCoCo 90%; RASTERIZING stage, drawable-count fan-in 10/11, maturity 30 -> 40, prohibited-field validator) |
| 2026-08-05 | `make integration` | PASS (banners incl. rasterizer 0.1.0-milestone6; M6 block: local rasterizer server, --once --rasterizer-url emits normalized+rasterized events, byte-determinism, PNG magic bytes + sha256 match, schema validation, prohibited-field scan, gap skip) |
| 2026-08-05 | `make contracts` / `make contract-test` | PASS (schemas unchanged; proto regenerated with no drift) |
| 2026-08-05 | `make format` / `make lint` / `make unit` / `make coverage` / `make build` (STRICT=1) | PASS (all languages; see row above for per-language gates) |
| 2026-08-05 | `make e2e` (cluster rube-goldberg) | PASS (smoke Test 7: ten glyph-rasterized records mature 30 -> 40 with no prohibited fields, gap position excluded, >= 10 raster PNG artifacts in MinIO with PNG magic bytes and sha256 matching each event) |

M6 debugging notes (2026-08-05): Kestrel in .NET 10 rejects h2c with
`Http1AndHttp2` — `SelectProtocol` always picks HTTP/1 without TLS (the
.NET 9 `EnableHttp2ClearText` AppContext switch no longer exists in the
assembly), so the rasterizer endpoint binds HTTP/2-only (ADR-0008). The
integration harness initially used a port above 65535 (Abort trap) and a
heredoc that shadowed the schema-check pipe; both fixed. Grpc.Tools ships no
macOS-arm64 protoc in any 2.8x version, which forced the committed C#
generated code + container-based codegen approach (ADR-0008).

