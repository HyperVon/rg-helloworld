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
| 4 | SOAP planning (Java glyph catalog, `RUBE_SIMPLEX_V1`) | **IN PROGRESS** |
| 5 | Geometry and vector artifacts (C++, Go) | not started |
| 6 | gRPC rasterization (C#, SkiaSharp) | not started |
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
