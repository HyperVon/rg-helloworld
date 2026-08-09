FROM node:24-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build && npm prune --omit=dev

FROM node:24-alpine AS runtime
WORKDIR /app
COPY --from=builder /app/out/ ./out/
COPY --from=builder /app/node_modules/ ./node_modules/
COPY --from=builder /app/package*.json ./
EXPOSE 3002
ENTRYPOINT ["node", "out/server.js"]
