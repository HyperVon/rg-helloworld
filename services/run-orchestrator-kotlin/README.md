# run-orchestrator-kotlin

Kotlin run orchestrator (Milestone 4). Owns the run state machine, SOAP
phrase planning, blueprint event emission, SSE, and Redis projection.

## Flow

`POST /api/v1/runs`:

1. Validates UTF-8 and registers the run (idempotency key → 409 on replay).
2. Calls `PlanPhrase` on the Java glyph catalog over SOAP (generated client
   from `contracts/soap/glyph-catalog.wsdl`, endpoint from
   `GLYPH_CATALOG_URL`).
3. Stores the expected text privately (never emitted downstream).
4. Emits one `glyph-blueprint-produced.v1` event per phrase position to
   `rg.glyph-blueprints.v1` with partition key `runId:glyphInstanceId`.
5. Completes the run: terminal `assembledText` over SSE, final
   `rg.run-events.v1` event, Redis result.

Downstream blueprint events contain no plaintext or code points (the
temporary echo worker was removed in this milestone; true OCR-derived
assembly arrives in Milestone 9).

## Commands

```bash
./gradlew ktlintFormat                # format
./gradlew ktlintCheck                 # lint
./gradlew test                        # unit tests
./gradlew check                       # tests + JaCoCo report + 90% coverage gate
./gradlew assemble                    # build
```

The Gradle wrapper is pinned to Gradle 9.6.1 (`gradle/wrapper/`).
Kotlin 2.4.10, JVM target 21, JUnit Jupiter 6.1.2, ktlint plugin 14.2.0,
JaCoCo 0.8.15, Ktor 3.2.0, Kafka clients 4.0.2, Lettuce 6.7.1.RELEASE,
JAX-WS 4.0.3.
