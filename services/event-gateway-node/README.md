# event-gateway-node

TypeScript/Node.js browser event gateway (Milestone 0 skeleton). Converts
Redis run streams into browser SSE with `Last-Event-ID` replay in later
milestones.

## Commands

```bash
npm ci                       # install pinned dependencies
npm run format               # prettier --write
npm run lint                 # prettier --check + tsc --noEmit
npm test                     # compile + node --test
npm run coverage             # c8 with 90% line-coverage gate
npm run build                # tsc build
```

Pinned in `package.json`/`package-lock.json`: TypeScript 5.9.3, prettier 3.9.6,
c8 12.0.0, @types/node 26.1.2. Node 24 LTS (see `.nvmrc`).
