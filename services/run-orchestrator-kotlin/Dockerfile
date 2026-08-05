FROM eclipse-temurin:21-jdk AS builder

WORKDIR /app
COPY contracts/soap /app/contracts/soap
COPY services/run-orchestrator-kotlin /app/services/run-orchestrator-kotlin
WORKDIR /app/services/run-orchestrator-kotlin
RUN ./gradlew --no-daemon --console=plain installDist

FROM eclipse-temurin:21-jre

WORKDIR /app
COPY --from=builder /app/services/run-orchestrator-kotlin/build/install/run-orchestrator ./

EXPOSE 8080
ENV KAFKA_BOOTSTRAP=localhost:9092
ENV REDIS_URL=redis://localhost:6379
ENV ORCHESTRATOR_PORT=8080
ENV GLYPH_CATALOG_URL=http://localhost:8082/ws/glyph-catalog

ENTRYPOINT ["/app/bin/run-orchestrator"]
