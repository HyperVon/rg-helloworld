# AGENTS.md

Guidance for AI coding agents working in this repository. Read this file before
making changes.

## Project

Rube Goldberg Hello World: a deliberately excessive, fully local distributed
system whose only purpose is to derive and print `Hello World` through
vector glyphs -> geometry -> SVG -> raster images -> phrase image -> OCR ->
adjudication -> assembly.

- Authoritative architecture: `docs/architecture.md` (read the relevant
  sections before any milestone work).
- Authoritative status: `docs/implementation-status.md` (update it with every
  milestone; work must be resumable after context compression).
- Acceptance: `rghello run` prints exactly `Hello World` and exits 0, with the
  phrase derived from OCR-derived artifacts — never printed from the request.

## Non-negotiable integrity rules

1. Only the CLI, orchestrator, and glyph catalog may see the requested
   plaintext before final validation.
2. No downstream event may contain `targetText`, `expectedCharacter`,
   `unicodeCodePoint`, `characterName`, or equivalent fields.
3. OCR and adjudication must never receive the expected output.
4. The Rust assembler assembles only accepted OCR-derived symbols.
5. The CLI prints only the orchestrator's terminal `assembledText`.
6. Every primary transformation must increase the artifact maturity rank
   (0 -> 10 -> 20 -> ... -> 100).
7. Every output artifact records input artifact IDs and SHA-256 hashes.
8. Kafka consumers must be idempotent (deterministic operation IDs).
9. No paid service or external runtime API, ever.
10. The whole acceptance environment runs on one laptop.

## Milestone workflow

Implement one milestone at a time, in the order in
`docs/architecture.md` section 29. Never start the next milestone while the
current one's acceptance conditions fail.

For each milestone:

1. Read the relevant architecture sections.
2. Update `docs/implementation-status.md`: scope, tasks, acceptance
   conditions.
3. Implement the smallest complete milestone.
4. Add tests before proceeding. Coverage must be >= 90% per language where
   tooling allows (enforced by `make coverage`, CI-gated).
5. Run targeted checks during iteration; run the milestone's full checks
   before completion.
6. Update documentation.
7. Commit the milestone as one coherent change **only when explicitly
   authorized** to commit.

## Required commands

From the repository root:

```bash
make prerequisites   # toolchain check + language deps (venv, npm ci, bundle)
make format          # format all languages
make lint            # lint all languages (STRICT=1 fails on missing tools)
make unit            # unit tests for all skeleton services
make coverage        # unit tests + 90% coverage gates
make build           # compile everything
make integration     # cross-language artifact integration tests
make e2e             # full milestone acceptance (gates + integration)
```

Missing toolchains are skipped with a warning unless `STRICT=1` is set.
CI always runs strict. Run `make format` before `make lint`; the two must both
pass before a milestone is complete.

## Documentation freshness

`docs/implementation-status.md` is the authoritative status and must be
updated with every milestone (scope, tasks, acceptance, verification log).
Any change that alters behavior, commands, or structure must update the
relevant documentation (README, service READMEs, runbook, ADRs) **in the
same change** — never leave docs behind.

## Language ownership

Do not combine service implementations into one language, and do not bypass a
protocol the architecture requires:

| Language | Owns |
|---|---|
| Go | `cmd/rghello` (CLI), `services/vector-normalizer-go` |
| Kotlin | `services/run-orchestrator-kotlin` (orchestrator) |
| Java | `services/glyph-catalog-java` (SOAP glyph catalog) |
| C++ | `services/geometry-engine-cpp` |
| C#/.NET | `services/rasterizer-dotnet` (gRPC rasterizer) |
| Python | `services/image-pipeline-python` |
| TypeScript/Node.js | `services/ocr-worker-node`, `services/event-gateway-node` |
| Ruby | `services/adjudicator-ruby` |
| Rust | `services/phrase-assembler-rust` |

Kafka and Redis are both required and are not interchangeable. Kubernetes
(k3d/k3s) is the acceptance environment; Docker Compose may only be an
optional focused-development aid.

## Engineering rules

- Work contract-first: `contracts/` is the single source of truth for all
  inter-service boundaries (`make contracts` regenerates clients and models;
  generated code is never hand-edited).
- Pin every dependency and container version. Never use floating `latest`
  tags. Update `versions.env` and the per-language lockfiles.
- Prefer deterministic outputs (fixed seeds, quantized floats, sorted output).
- Use structured JSON logs in services (later milestones); never log the
  requested plaintext, credentials, image bytes, or huge payloads.
- Propagate OpenTelemetry trace context through HTTP, SOAP, gRPC, and Kafka.
- Keep large payloads in MinIO, not in Kafka, logs, Redis, or command output.
- No unapproved architecture changes; record changes as ADRs under
  `docs/adr/`.

## Context and output discipline

- Use quiet test modes; capture complete logs in files under
  `.local/diagnostics/`.
- Show only relevant failure excerpts; never dump entire dependency trees or
  full Kubernetes manifests.
- Use `kubectl logs --tail`, bounded `grep`/`head`.
- Summarize command results instead of repeating thousands of lines.

## Code style

- Write readable, idiomatic code for each language; follow the per-language
  linters and formatters configured in this repo (gofmt/go vet, Spotless,
  ktlint, clang-format, dotnet format, ruff, prettier/tsc, rubocop,
  rustfmt/clippy).
- Do not add explanatory comments; let the code speak. Keep comments only
  where language conventions require them (e.g., exported Go identifiers).

## Testing

- Every service has unit tests; keep coverage at 90% or higher where the
  tooling supports measurement.
- Golden artifacts, contract tests, integration tests, and e2e tests arrive
  with their milestones; never delete a test that guards an integrity rule.
- The anti-cheating suite (`tests/anti-cheating/`) must keep passing once it
  exists (Milestone 1+).
