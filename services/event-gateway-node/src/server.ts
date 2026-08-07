import { createServer } from 'node:http';
import { banner, SERVICE_NAME, SERVICE_VERSION } from './index.js';
import { formatSseFrame, buildSseFrame, heartbeatEvent } from './sse.js';

const PORT = Number(process.env.PORT ?? 3001);

const server = createServer((req, res) => {
  const url = new URL(req.url ?? '/', `http://${req.headers.host ?? 'localhost'}`);
  if (url.pathname === '/health') {
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok', service: SERVICE_NAME, version: SERVICE_VERSION }));
    return;
  }
  if (url.pathname.startsWith('/events/')) {
    res.writeHead(200, {
      'content-type': 'text/event-stream',
      'cache-control': 'no-cache',
      connection: 'keep-alive',
    });
    res.write(formatSseFrame(buildSseFrame(heartbeatEvent(), '0')));
    const timer = setInterval(() => {
      res.write(formatSseFrame(buildSseFrame(heartbeatEvent(), String(Date.now()))));
    }, 15_000);
    req.on('close', () => clearInterval(timer));
    return;
  }
  res.writeHead(404, { 'content-type': 'application/json' });
  res.end(JSON.stringify({ error: 'not_found' }));
});

server.listen(PORT, '0.0.0.0', () => {
  console.log(`${banner()} listening on :${PORT}`);
});
