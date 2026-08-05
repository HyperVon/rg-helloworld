# glyph-catalog-java

Java WSDL-first SOAP glyph-catalog service (Milestone 4). Provides phrase
planning (`PlanPhrase`), alternate blueprints (`GetAlternateBlueprint`), and
the `RUBE_SIMPLEX_V1` vector alphabet (H e l o W r d + SPACE).

## Endpoints

- `POST /ws/glyph-catalog` — SOAP 1.1, document/literal.
- `GET /ws/glyph-catalog.wsdl` — contract WSDL (served from
  `contracts/soap/glyph-catalog.wsdl`).
- `GET /healthz` — readiness probe.

## Behavior

- `PlanPhrase` decodes the message into Unicode code points and returns one
  blueprint per position: opaque `glyphInstanceId`, `position`, `kind`
  (`DRAWABLE`/`GAP`), `advanceWidth`, and polylines in a unit box.
- Unsupported characters, alphabets, and variants return SOAP client faults.
- Plans persist in an embedded H2 database (`GLYPH_CATALOG_DB_URL`, default
  `jdbc:h2:file:./data/glyph-catalog`), so `GetAlternateBlueprint` works
  across restarts. Alternates are deterministic transforms (mirror/rotate).

## Commands

```bash
mvn -B spotless:apply          # format (google-java-format)
mvn -B spotless:check          # format check
mvn -B test                    # unit tests + JaCoCo coverage
mvn -B verify                  # coverage gate (90% line coverage)
mvn -B -DskipTests package     # build
```

## Dependencies

- Spring Boot 3.5.3, Spring WS 4.0.13, wsdl4j 1.6.3, H2 2.3.232, JAXB 4
  (generated from `contracts/soap/glyph-catalog.xsd`) — all pinned in
  `pom.xml` and `versions.env`.
- JUnit Jupiter 6.1.2, JaCoCo 0.8.15, Spotless 3.9.0.
- Java release 21 (toolchain-agnostic; builds on JDK 21+).
