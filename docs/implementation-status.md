# Implementation Status

> Status of the Rube Goldberg Hello World project, milestone by milestone.
> Update this document whenever a milestone's scope, tasks, or acceptance
> conditions change, and mark tasks complete only after their checks pass.

## Milestone overview

| # | Milestone | Status |
|---:|---|---|
| 0 | Repository skeleton | **COMPLETE** |
| 1 | Contracts (OpenAPI, AsyncAPI, JSON Schema, WSDL/XSD, protobuf) | **COMPLETE** |
| 2 | Local platform (k3d, Terraform, PostgreSQL, Kafka KRaft, Redis, MinIO) | not started |
| 3 | Thin vertical slice (CLI → REST → Kafka → SSE) | not started |
| 4 | SOAP planning (Java glyph catalog, `RUBE_SIMPLEX_V1`) | not started |
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
|---|---|---|---|
| `cmd/rghello` | Go | `go build` | `go test` |
| `services/vector-normalizer-go` | Go | `go build` | `go test` |
| `services/glyph-catalog-java` | Java 21 | Maven `package` | JUnit Jupiter |
| `services/run-orchestrator-kotlin` | Kotlin 2.4 / JVM 21 | Gradle `assemble` | JUnit Jupiter |
| `services/geometry-engine-cpp` | C++20 | CMake | CTest |
| `services/rasterizer-dotnet` | .NET 10 | `dotnet build` | xUnit |
| `services/image-pipeline-python` | Python 3.13+ | `compileall` | unittest |
| `services/ocr-worker-node` | TypeScript 5.9 / Node 24 | `tsc` | `node --test` |
| `services/event-gateway-node` | TypeScript 5.9 / Node 24 | `tsc` | `node --test` |
| `services/adjudicator-ruby` | Ruby 3.4+ | `ruby -c` | minitest |
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
|---|---|---|
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
|---|---|---|
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

Milestone 2 — Local platform: k3d cluster script, local registry, Terraform
root module, PostgreSQL, Kafka KRaft, Redis, MinIO, readiness checks.
Acceptance: all infrastructure pods ready; test message passes through Kafka;
artifact round trip works; PostgreSQL and Redis checks pass.
