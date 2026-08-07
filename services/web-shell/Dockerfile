FROM node:24-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM node:24-alpine AS runtime
WORKDIR /app
COPY --from=builder /app/dist/ ./dist/
COPY --from=builder /app/node_modules ./node_modules/
COPY --from=builder /app/package*.json ./
COPY --from=builder /app/index.html ./
EXPOSE 3000
ENTRYPOINT ["npx", "vite", "preview", "--host", "0.0.0.0", "--port", "3000"]
