# Phrase assembler: Rust service for final UTF-8 phrase assembly.
# Base image is tag-pinned (never "latest").
FROM rust:1.97.1-bookworm AS builder

WORKDIR /app
COPY Cargo.toml Cargo.lock ./
COPY src ./src/

RUN cargo build --release

# Pinned to DEBIAN_IMAGE_VERSION=12.11 (see versions.env).
FROM debian:12.11-slim

RUN adduser --system --uid 1001 --group --home /nonexistent rghw

WORKDIR /app
COPY --from=builder /app/target/release/phrase-assembler ./

ENV KAFKA_BOOTSTRAP=kafka.rube-goldberg.svc.cluster.local:9092
ENV KAFKA_GROUP_ID=phrase-assembler
ENV ASSEMBLER_INPUT_TOPIC=rg.symbols-adjudicated.v1
ENV ASSEMBLER_OUTPUT_TOPIC=rg.phrase-assembled.v1
ENV MINIO_ENDPOINT=http://minio.rube-goldberg.svc.cluster.local:9000
ENV MINIO_BUCKET=rube-goldberg-artifacts

ENTRYPOINT ["/app/phrase-assembler"]
CMD ["run"]
