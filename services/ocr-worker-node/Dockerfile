# OCR worker: Node.js service that runs Tesseract locally.
# Base image is tag-pinned (never "latest").
# Pinned to NODE_VERSION=26.6.0 (see versions.env).
FROM node:26.6.0-bookworm-slim AS builder

WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci --include=dev

COPY tsconfig.build.json tsconfig.json tsconfig.test.json ./
COPY src ./src
COPY tests ./tests
RUN npm run build

# Pinned to NODE_VERSION=26.6.0 (see versions.env).
FROM node:26.6.0-bookworm-slim

RUN apt-get update && \
    apt-get install -y --no-install-recommends tesseract-ocr && \
    rm -rf /var/lib/apt/lists/*

RUN adduser --system --uid 1001 --group --home /nonexistent rghw

WORKDIR /app
COPY --from=builder /app/out/ ./out/
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

ENV NODE_ENV=production
ENV KAFKA_BOOTSTRAP=kafka.rube-goldberg.svc.cluster.local:9092
ENV KAFKA_GROUP_ID=ocr-worker
ENV OCR_INPUT_TOPIC=rg.ocr-images.v1
ENV OCR_OUTPUT_TOPIC=rg.ocr-observations.v1
ENV MINIO_ENDPOINT=minio.rube-goldberg.svc.cluster.local:9000
ENV MINIO_BUCKET=rube-goldberg-artifacts

ENTRYPOINT ["node", "out/index.js"]
CMD ["run"]
