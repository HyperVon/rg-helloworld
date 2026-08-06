# OCR worker: Node.js service that runs Tesseract locally.
# Base image is tag-pinned (never "latest").
FROM node:24.6.0-bookworm AS builder

WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci --include=dev

COPY tsconfig.build.json tsconfig.json tsconfig.test.json ./
COPY src ./src
COPY tests ./tests
RUN npm run build

FROM node:24.6.0-bookworm

RUN apt-get update && \
    apt-get install -y --no-install-recommends tesseract-ocr libtesseract-dev && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=builder /app/out/ ./out/
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/package.json ./package.json

ENV NODE_ENV=production
ENV KAFKA_BOOTSTRAP=kafka.rube-goldberg.svc.cluster.local:9092
ENV KAFKA_GROUP_ID=ocr-worker
ENV OCR_INPUT_TOPIC=rg.ocr-images.v1
ENV OCR_OUTPUT_TOPIC=rg.ocr-observations.v1
ENV MINIO_ENDPOINT=minio.rube-goldberg.svc.cluster.local:9000
ENV MINIO_BUCKET=rube-goldberg-artifacts

ENTRYPOINT ["node", "out/index.js"]
CMD ["run"]
