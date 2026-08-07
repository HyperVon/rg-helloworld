import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
  buildSseFrame,
  formatSseEvent,
  formatSseFrame,
  heartbeatEvent,
  runEventToSse,
  snapshotEvent,
} from '../src/sse.js';

test('formatSseEvent includes event name and data', () => {
  const output = formatSseEvent({ event: 'heartbeat', data: { ts: 123 } });
  assert.ok(output.includes('event:heartbeat'));
  assert.ok(output.includes('data: {"ts":123'));
  assert.ok(output.includes('data: }') || output.includes('data:'));
  assert.ok(output.endsWith('\n'));
});

test('formatSseEvent supports data on multiple lines', () => {
  const output = formatSseEvent({ event: 'test', data: 'line1\nline2' });
  assert.ok(output.includes('data: line1'));
  assert.ok(output.includes('data: line2'));
});

test('formatSseEvent includes id when present', () => {
  const output = formatSseEvent({ event: 'msg', data: {}, id: '5' });
  assert.ok(output.includes('id:5'));
  assert.ok(output.includes('event:msg'));
});

test('buildSseFrame produces correct structure', () => {
  const frame = buildSseFrame({ event: 'test', data: { ok: true } }, '7');
  assert.equal(frame.event, 'test');
  assert.equal(frame.id, '7');
  assert.equal(frame.data, '{"ok":true}');
});

test('formatSseFrame outputs standard SSE format', () => {
  const frame = buildSseFrame({ event: 'snapshot', data: { status: 'ok' } }, '0');
  const output = formatSseFrame(frame);
  assert.ok(output.includes('id:0'));
  assert.ok(output.includes('event:snapshot'));
  assert.ok(output.includes('data: {"status":"ok"}'));
  assert.ok(output.trimEnd().endsWith(''));
});

test('heartbeatEvent returns heartbeat event type', () => {
  const ev = heartbeatEvent();
  assert.equal(ev.event, 'heartbeat');
  assert.ok(typeof ev.data === 'object');
});

test('snapshotEvent wraps summary in snapshot event', () => {
  const summary = {
    status: 'SUCCEEDED' as const,
    currentStage: 'done',
    percentage: 100,
    attempt: 1,
    startedAt: 0,
    lastEventSequence: 5,
    terminal: true,
  };
  const ev = snapshotEvent(summary);
  assert.equal(ev.event, 'snapshot');
  assert.deepEqual(ev.data, summary);
});

test('runEventToSse maps run event to SSE', () => {
  const runEvent = {
    sequence: '1',
    eventType: 'step-status-changed',
    stepType: 'GEOMETRY',
    glyphPosition: null,
    status: 'started',
    artifactId: null,
    timestamp: 100,
    summary: null,
  };
  const ev = runEventToSse(runEvent);
  assert.equal(ev.event, 'step-status-changed');
  assert.equal(ev.id, '1');
  assert.deepEqual(ev.data, runEvent);
});
