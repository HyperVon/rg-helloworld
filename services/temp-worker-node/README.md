# temp-worker-node

Temporary Milestone 3 echo worker (Node.js + KafkaJS).

Consumes `rg.glyph-blueprints.v1`, echoes the message back as a CloudEvents
envelope on `rg.temp-echo.v1` so the orchestrator's SSE stream can complete the
vertical slice. **Temporary**: removed in Milestone 4 when the real pipeline
workers land.

## Commands

```bash
npm ci
npm test          # unit tests
npm run coverage  # tests + 90% line gate
npm run lint      # prettier check + typecheck
npm run build     # tsc build
```

## Environment

| Variable                  | Default                  |
| ------------------------- | ------------------------ |
| `KAFKA_BOOTSTRAP_SERVERS` | `localhost:9092`         |
| `PLANNING_TOPIC`          | `rg.glyph-blueprints.v1` |
| `TEMP_ECHO_TOPIC`         | `rg.temp-echo.v1`        |
