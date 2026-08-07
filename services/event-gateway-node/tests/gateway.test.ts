import assert from 'node:assert/strict';
import { test } from 'node:test';

import { EventGateway } from '../src/gateway.js';
import type { RunArtifacts, RunEvent, RunSummary } from '../src/types.js';

class MockRedisClient {
  summary: RunSummary | null = null;
  events: RunEvent[] = [];
  artifacts: RunArtifacts = { runId: '', artifacts: [] };

  async getSummary(): Promise<RunSummary | null> {
    return this.summary;
  }

  async getEventsSince(): Promise<RunEvent[]> {
    return this.events;
  }

  async getArtifacts(runId: string): Promise<RunArtifacts> {
    this.artifacts.runId = runId;
    return this.artifacts;
  }

  async close(): Promise<void> {}
}

test('formatStream sends snapshot first', () => {
  const mock = new MockRedisClient();
  const gw = new EventGateway(mock);
  const summary: RunSummary = {
    status: 'PLANNING',
    currentStage: 'Planning',
    percentage: 0,
    attempt: 1,
    startedAt: 100,
    lastEventSequence: 0,
    terminal: false,
  };

  const output = gw.formatStream(summary, [], null);
  assert.ok(output.includes('event:snapshot'));
});

test('formatStream includes event frames', () => {
  const mock = new MockRedisClient();
  const gw = new EventGateway(mock);
  const summary: RunSummary = {
    status: 'PLANNING',
    currentStage: 'Planning',
    percentage: 0,
    attempt: 1,
    startedAt: 100,
    lastEventSequence: 0,
    terminal: false,
  };
  const events: RunEvent[] = [
    {
      sequence: '1',
      eventType: 'step-status-changed',
      stepType: 'GEOMETRY',
      glyphPosition: null,
      status: 'started',
      artifactId: null,
      timestamp: 100,
      summary: null,
    },
    {
      sequence: '2',
      eventType: 'run-succeeded',
      stepType: null,
      glyphPosition: null,
      status: 'ok',
      artifactId: 'art-1',
      timestamp: 200,
      summary: null,
    },
  ];

  const output = gw.formatStream(summary, events, null);
  assert.ok(output.includes('event:step-status-changed'));
  assert.ok(output.includes('event:run-succeeded'));
  assert.ok(output.includes('event:heartbeat'));
});

test('formatStream includes replay-point when lastEventId present', () => {
  const mock = new MockRedisClient();
  const gw = new EventGateway(mock);
  const output = gw.formatStream(null, [], '5');
  assert.ok(output.includes('event:replay-point'));
});

test('formatStream skips replay-point when no lastEventId', () => {
  const mock = new MockRedisClient();
  const gw = new EventGateway(mock);
  const output = gw.formatStream(null, [], null);
  assert.ok(!output.includes('replay-point'));
});

test('shouldSendHeartbeat returns true after interval', () => {
  const mock = new MockRedisClient();
  const gw = new EventGateway(mock);
  assert.ok(gw.shouldSendHeartbeat(Date.now() - 16_000, Date.now()));
});

test('shouldSendHeartbeat returns false before interval', () => {
  const mock = new MockRedisClient();
  const gw = new EventGateway(mock);
  assert.ok(!gw.shouldSendHeartbeat(Date.now() - 5_000, Date.now()));
});

test('isTerminal detects SUCCEEDED', () => {
  const mock = new MockRedisClient();
  const gw = new EventGateway(mock);
  assert.ok(gw.isTerminal('SUCCEEDED'));
});

test('isTerminal detects FAILED', () => {
  const mock = new MockRedisClient();
  const gw = new EventGateway(mock);
  assert.ok(gw.isTerminal('FAILED'));
});

test('isTerminal detects CANCELLED', () => {
  const mock = new MockRedisClient();
  const gw = new EventGateway(mock);
  assert.ok(gw.isTerminal('CANCELLED'));
});

test('isTerminal rejects in progress', () => {
  const mock = new MockRedisClient();
  const gw = new EventGateway(mock);
  assert.ok(!gw.isTerminal('PLANNING'));
  assert.ok(!gw.isTerminal('ASSEMBLING'));
});

test('getSummary returns mock summaries', async () => {
  const mock = new MockRedisClient();
  const gw = new EventGateway(mock);
  mock.summary = {
    status: 'SUCCEEDED',
    currentStage: 'Done',
    percentage: 100,
    attempt: 1,
    startedAt: 0,
    lastEventSequence: 10,
    terminal: true,
  };
  const result = await gw.getSummary('run-1');
  assert.deepEqual(result, mock.summary);
});

test('getArtifacts returns mock artifacts', async () => {
  const mock = new MockRedisClient();
  const gw = new EventGateway(mock);
  mock.artifacts = {
    runId: 'run-1',
    artifacts: [
      {
        artifactId: 'a1',
        stage: 'assembly',
        glyphPosition: null,
        sha256: 'abc',
        contentType: 'text/plain',
        proxyUrl: '/proxy/a1',
      },
    ],
  };
  const result = await gw.getArtifacts('run-1');
  assert.equal(result.artifacts.length, 1);
  assert.equal(result.artifacts[0]?.artifactId, 'a1');
});
