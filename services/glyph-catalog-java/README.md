# glyph-catalog-java

Java SOAP glyph-catalog service (Milestone 0 skeleton). Provides phrase
planning and the `RUBE_SIMPLEX_V1` vector alphabet in later milestones.

## Commands

```bash
mvn -B spotless:apply          # format (google-java-format)
mvn -B spotless:check          # format check
mvn -B test                    # unit tests + JaCoCo coverage
mvn -B verify                  # coverage gate (90% line coverage)
mvn -B -DskipTests package     # build
```

## Dependencies

- JUnit Jupiter 6.1.2, JaCoCo 0.8.15, Spotless 3.9.0 — all pinned in `pom.xml`.
- Java release 21 (toolchain-agnostic; builds on JDK 21+).
