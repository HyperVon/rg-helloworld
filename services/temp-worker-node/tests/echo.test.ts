import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
  configFromEnv,
  echoFromMessage,
  parseBlueprint,
  DEFAULT_KAFKA_BROKER,
  PLANNING_TOPIC,
  TEMP_ECHO_TOPIC,
} from '../src/index.js';

const blueprint = {
  specversion: '1.0',
  id: 'b1',
  source: 'run-orchestrator',
  type: PLANNING_TOPIC,
  subject: 'runs/run-123',
  correlationid: 'run-123',
  data: { runId: 'run-123', message: 'Hello World' },
};

test('configFromEnv uses defaults when env is empty', () => {
  const config = configFromEnv({});
  assert.deepEqual(config.brokers, [DEFAULT_KAFKA_BROKER]);
  assert.equal(config.planningTopic, PLANNING_TOPIC);
  assert.equal(config.echoTopic, TEMP_ECHO_TOPIC);
});

test('configFromEnv reads env overrides', () => {
  const config = configFromEnv({
    KAFKA_BOOTSTRAP_SERVERS: 'kafka:9092',
    PLANNING_TOPIC: 'custom.planning.v1',
    TEMP_ECHO_TOPIC: 'custom.echo.v1',
  });
  assert.deepEqual(config.brokers, ['kafka:9092']);
  assert.equal(config.planningTopic, 'custom.planning.v1');
  assert.equal(config.echoTopic, 'custom.echo.v1');
});

test('parseBlueprint parses a valid blueprint event', () => {
  const parsed = parseBlueprint(JSON.stringify(blueprint));
  assert.equal(parsed.type, PLANNING_TOPIC);
  assert.equal(parsed.data.message, 'Hello World');
});

test('echoFromMessage echoes assembledText from blueprint', () => {
  const echo = echoFromMessage(JSON.stringify(blueprint));
  assert.ok(echo !== null);
  assert.equal(echo.runId, 'run-123');
  const parsed = JSON.parse(echo.event) as Record<string, unknown>;
  assert.equal(parsed.type, TEMP_ECHO_TOPIC);
  assert.equal(parsed.source, 'temp-worker');
  assert.equal(parsed.correlationid, 'run-123');
  assert.equal((parsed.data as Record<string, string>).assembledText, 'Hello World');
});

test('echoFromMessage returns null for null input', () => {
  assert.equal(echoFromMessage(null), null);
});

test('echoFromMessage falls back to data.runId when correlationid missing', () => {
  const noCorrelation = { ...blueprint, correlationid: undefined };
  const echo = echoFromMessage(JSON.stringify(noCorrelation));
  assert.ok(echo !== null);
  assert.equal(echo.runId, 'run-123');
  const parsed = JSON.parse(echo.event) as Record<string, unknown>;
  assert.equal(parsed.correlationid, 'run-123');
});

test('echoFromMessage returns null when no runId is present', () => {
  const noRunId = { ...blueprint, correlationid: undefined, data: { message: 'Hello World' } };
  assert.equal(echoFromMessage(JSON.stringify(noRunId)), null);
});
