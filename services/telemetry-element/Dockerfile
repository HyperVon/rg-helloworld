# Pinned to NODE_VERSION=26.6.0 (see versions.env); never "latest".
FROM node:26.6.0-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build && npm prune --omit=dev

FROM node:26.6.0-alpine AS runtime
RUN addgroup -S -g 1001 rghw \
    && adduser -S -u 1001 -G rghw rghw
WORKDIR /app
COPY --from=builder /app/out/ ./out/
COPY --from=builder /app/node_modules/ ./node_modules/
COPY --from=builder /app/package*.json ./
EXPOSE 3002
ENTRYPOINT ["node", "out/server.js"]
