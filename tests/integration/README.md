# Integration tests

Cross-language integration harness for the skeleton services. Builds every
service with its real toolchain and executes each artifact's `version` path,
asserting the exact expected output. This proves the polyglot build pipeline
produces runnable binaries whose output matches the version contract.

```bash
make integration
```

## Current scope (Milestone 0)

- Builds: Go (2), Java jar, Kotlin distribution, C++ binary, .NET binary,
  TypeScript (2), Rust binary.
- Asserts: every binary's version/banner output exactly.
- Missing toolchains are skipped with a warning; any failed assertion fails
  the run.

## Later milestones

- Milestone 2+: PostgreSQL migrations, Kafka produce/consume, Redis
  projection, MinIO round trips against the local cluster.
- Milestone 3+: SOAP client/server, gRPC client/server, SSE reconnection
  and replay.
- The harness in this directory stays the entry point; per-service suites
  are added under `tests/integration/<service>/`.
