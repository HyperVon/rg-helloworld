FROM eclipse-temurin:25-jdk AS builder

WORKDIR /app
COPY contracts/soap /app/contracts/soap
COPY services/run-orchestrator-kotlin /app/services/run-orchestrator-kotlin
WORKDIR /app/services/run-orchestrator-kotlin
RUN ./gradlew --no-daemon --console=plain installDist

# JAVA_VERSION=25 pins the Temurin major line (see versions.env).
FROM eclipse-temurin:25-jre

RUN adduser --system --uid 1001 --group --home /nonexistent rghw

WORKDIR /app
COPY --from=builder /app/services/run-orchestrator-kotlin/build/install/run-orchestrator ./

EXPOSE 8080
ENV KAFKA_BOOTSTRAP=localhost:9092
ENV REDIS_URL=redis://localhost:6379
ENV ORCHESTRATOR_PORT=8080
ENV GLYPH_CATALOG_URL=http://localhost:8082/ws/glyph-catalog

ENTRYPOINT ["/app/bin/run-orchestrator"]
