# Pinned to NODE_VERSION=26.6.0 (see versions.env); never "latest".
FROM node:26.6.0-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM node:26.6.0-alpine AS runtime
RUN addgroup -S -g 1001 rghw \
    && adduser -S -u 1001 -G rghw rghw
WORKDIR /app
COPY --from=builder /app/dist/ ./dist/
COPY --from=builder /app/node_modules ./node_modules/
COPY --from=builder /app/package*.json ./
COPY --from=builder /app/index.html ./
COPY --from=builder /app/vite.config.ts ./
ENV HOME=/app
RUN chown -R rghw:rghw /app
EXPOSE 3000
ENTRYPOINT ["npx", "vite", "preview", "--host", "0.0.0.0", "--port", "3000"]
