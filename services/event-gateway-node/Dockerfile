FROM node:24-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM node:24-alpine AS runtime
WORKDIR /app
COPY --from=builder /app/out/src/ ./out/
COPY --from=builder /app/package*.json ./
EXPOSE 3001
ENTRYPOINT ["node", "out/src/index.js"]
