# Geometry engine: C++20 + librdkafka consumer of glyph blueprints.
# Base images are tag-pinned (never "latest").
# librdkafka version is the Debian bookworm arm64/amd64 apt package (see versions.env).
ARG LIBRDKAFKA_DEBIAN_VERSION=2.0.2-1
FROM gcc:13.2-bookworm AS builder

ARG LIBRDKAFKA_DEBIAN_VERSION=2.0.2-1
WORKDIR /app
COPY contracts/soap /app/contracts/soap
COPY services/geometry-engine-cpp /app/services/geometry-engine-cpp
WORKDIR /app/services/geometry-engine-cpp
RUN apt-get update && apt-get install -y --no-install-recommends cmake librdkafka-dev=${LIBRDKAFKA_DEBIAN_VERSION} \
    && rm -rf /var/lib/apt/lists/* \
    && cmake -S . -B build -DCMAKE_BUILD_TYPE=Release \
    && cmake --build build

FROM gcc:13.2-bookworm

ARG LIBRDKAFKA_DEBIAN_VERSION=2.0.2-1
RUN apt-get update && apt-get install -y --no-install-recommends librdkafka1=${LIBRDKAFKA_DEBIAN_VERSION} ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN adduser --system --uid 1001 --group --home /nonexistent rghw

WORKDIR /app
COPY --from=builder /app/services/geometry-engine-cpp/build/geometry_engine ./

ENV KAFKA_BOOTSTRAP=kafka.rube-goldberg.svc.cluster.local:9092
ENV KAFKA_GROUP_ID=geometry-engine
ENV GEOMETRY_INPUT_TOPIC=rg.glyph-blueprints.v1
ENV GEOMETRY_OUTPUT_TOPIC=rg.geometry-expanded.v1
ENV MINIO_ENDPOINT=http://minio.rube-goldberg.svc.cluster.local:9000
ENV MINIO_BUCKET=rube-goldberg-artifacts

ENTRYPOINT ["/app/geometry_engine"]
