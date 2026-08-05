# Vector normalizer: Go consumer of geometry events -> normalized SVG.
# Base images are tag-pinned (never "latest").
FROM golang:1.26-bookworm AS builder

WORKDIR /app
COPY services/vector-normalizer-go /app/services/vector-normalizer-go
WORKDIR /app/services/vector-normalizer-go
RUN CGO_ENABLED=0 go build -trimpath -o /app/vector-normalizer .

FROM debian:bookworm-slim

WORKDIR /app
COPY --from=builder /app/vector-normalizer ./

ENV KAFKA_BOOTSTRAP=kafka.rube-goldberg.svc.cluster.local:9092
ENV KAFKA_GROUP_ID=vector-normalizer
ENV NORMALIZER_INPUT_TOPIC=rg.geometry-expanded.v1
ENV NORMALIZER_OUTPUT_TOPIC=rg.glyph-normalized.v1
ENV MINIO_ENDPOINT=minio.rube-goldberg.svc.cluster.local:9000
ENV MINIO_BUCKET=rube-goldberg-artifacts

ENTRYPOINT ["/app/vector-normalizer", "run"]
