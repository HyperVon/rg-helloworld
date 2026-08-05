FROM eclipse-temurin:21-jdk AS builder

WORKDIR /app
COPY . .
RUN ./gradlew --no-daemon --console=plain installDist

FROM eclipse-temurin:21-jre

WORKDIR /app
COPY --from=builder /app/build/install/run-orchestrator ./

EXPOSE 8080
ENV KAFKA_BOOTSTRAP=localhost:9092
ENV REDIS_URL=redis://localhost:6379
ENV ORCHESTRATOR_PORT=8080

ENTRYPOINT ["/app/bin/run-orchestrator"]
