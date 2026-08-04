# run-orchestrator-kotlin

Kotlin run orchestrator (Milestone 0 skeleton). Owns the run state machine,
scheduling, validation, persistence, SSE, and Redis projection in later
milestones.

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
JaCoCo 0.8.15.
