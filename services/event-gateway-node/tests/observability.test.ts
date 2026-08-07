import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
  getObservabilityConfig,
  injectTraceHeaders,
  formatTraceId,
  formatSpanId,
  logTraceContext,
  OTEL_ENDPOINT,
  OTEL_SERVICE_NAME,
  OTEL_SERVICE_VERSION,
} from '../src/observability.js';

test('getObservabilityConfig returns expected values', () => {
  const cfg = getObservabilityConfig();
  assert.equal(cfg.endpoint, OTEL_ENDPOINT);
  assert.equal(cfg.serviceName, OTEL_SERVICE_NAME);
  assert.equal(cfg.serviceVersion, OTEL_SERVICE_VERSION);
  assert.equal(typeof cfg.traceId, 'string');
});

test('formatTraceId pads to 32 hex chars', () => {
  const result = formatTraceId('abc');
  assert.equal(result.length, 32);
  assert.equal(result.slice(0, 3), 'abc');
  assert.equal(result.slice(3), '0'.repeat(29));
});

test('formatSpanId pads to 16 hex chars', () => {
  const result = formatSpanId('def');
  assert.equal(result.length, 16);
  assert.equal(result.slice(0, 3), 'def');
});

test('logTraceContext formats key=value pairs', () => {
  const output = logTraceContext({ traceId: 'abc', spanId: 'def', runId: 'r1' });
  assert.ok(output.includes('traceId=abc'));
  assert.ok(output.includes('spanId=def'));
  assert.ok(output.includes('runId=r1'));
});

test('logTraceContext handles empty fields', () => {
  const output = logTraceContext({});
  assert.equal(output, '');
});

test('injectTraceHeaders creates W3C traceparent', () => {
  const headers = injectTraceHeaders({}, 'abcdef1234567890abcdef1234567890', 'deadbeef', 1);
  assert.ok(headers.traceparent);
  const parts = headers.traceparent!.split('-');
  assert.equal(parts[0], '00');
  assert.equal(parts[1]!.length, 32);
  assert.equal(parts[2]!.length, 16);
  assert.equal(parts[3], '01');
});

test('injectTraceHeaders preserves existing headers', () => {
  const headers = injectTraceHeaders({ 'content-type': 'application/json' }, 'trace123', 'span456');
  assert.equal(headers['content-type'], 'application/json');
  assert.ok(headers.traceparent);
});

test('OTEL constants are set', () => {
  assert.equal(OTEL_ENDPOINT, 'http://otel-collector.rube-goldberg:4318');
  assert.equal(OTEL_SERVICE_NAME, 'event-gateway');
  assert.equal(OTEL_SERVICE_VERSION, '0.5.0-milestone11');
});
