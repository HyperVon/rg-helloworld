import { createServer } from 'node:http';
import { banner, HEARTBEAT_INTERVAL_MS, SERVICE_NAME, SERVICE_VERSION } from './index.js';
import { initTelemetry } from './telemetry.js';
import { buildSseFrame, formatSseFrame, heartbeatEvent } from './sse.js';
import { EventGateway } from './gateway.js';
import { createRedisClient } from './redis-client-impl.js';
import type { RedisClient } from './redis-client.js';

const PORT = Number(process.env.PORT ?? 3001);
const REDIS_URL = process.env.REDIS_URL ?? 'redis://localhost:6379';

async function main(): Promise<void> {
  let client: RedisClient;
  try {
    client = await createRedisClient(REDIS_URL);
  } catch (err) {
    console.error(`${banner()} failed to connect to Redis at ${REDIS_URL}:`, err);
    process.exit(1);
    return;
  }
  const gateway = new EventGateway(client);

  const server = createServer(async (req, res) => {
    const url = new URL(req.url ?? '/', `http://${req.headers.host ?? 'localhost'}`);
    if (url.pathname === '/health') {
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ status: 'ok', service: SERVICE_NAME, version: SERVICE_VERSION }));
      return;
    }
    if (url.pathname.startsWith('/events/')) {
      const runId = decodeURIComponent(url.pathname.slice('/events/'.length));
      if (!runId) {
        res.writeHead(400, { 'content-type': 'application/json' });
        res.end(JSON.stringify({ error: 'missing_run_id' }));
        return;
      }
      res.writeHead(200, {
        'content-type': 'text/event-stream',
        'cache-control': 'no-cache',
        connection: 'keep-alive',
      });
      const lastEventId = url.searchParams.get('lastEventId');
      try {
        const summary = await gateway.getSummary(runId);
        const events = await gateway.getEventsSince(runId, lastEventId);
        res.write(gateway.formatStream(summary, events, lastEventId));
      } catch (err) {
        console.error(`${banner()} failed to read run ${runId}:`, err);
        res.end();
        return;
      }
      const timer = setInterval(async () => {
        try {
          const current = await gateway.getSummary(runId);
          if (current && current.terminal) {
            const name = current.status === 'SUCCEEDED' ? 'run-succeeded' : 'run-failed';
            res.write(
              formatSseFrame(
                buildSseFrame(
                  { event: name, data: { status: current.status }, id: 'terminal' },
                  'terminal',
                ),
              ),
            );
            clearInterval(timer);
            res.end();
            return;
          }
          res.write(formatSseFrame(buildSseFrame(heartbeatEvent(), String(Date.now()))));
        } catch {
          clearInterval(timer);
          res.end();
        }
      }, HEARTBEAT_INTERVAL_MS);
      req.on('close', () => clearInterval(timer));
      return;
    }
    res.writeHead(404, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ error: 'not_found' }));
  });

  server.listen(PORT, '0.0.0.0', () => {
    console.log(`${banner()} listening on :${PORT}`);
  });
}

void (async () => {
  try {
    await initTelemetry(SERVICE_NAME, SERVICE_VERSION);
  } catch {
    // telemetry init must never block serving
  }
  await main();
})();
