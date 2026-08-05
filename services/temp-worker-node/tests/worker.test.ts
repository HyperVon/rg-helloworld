import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
  configFromEnv,
  main,
  runWorker,
  startWorker,
  PLANNING_TOPIC,
  TEMP_ECHO_TOPIC,
} from '../src/index.js';

interface FakeMessage {
  value: Buffer | null;
}

interface FakeSendRequest {
  topic: string;
  messages: Array<{ key?: string; value: string }>;
}

type EachMessageHandler = (payload: { message: FakeMessage }) => Promise<void>;

function fakeKafka() {
  const sent: Array<{ topic: string; key?: string; value: string }> = [];
  const runHandlers: Array<EachMessageHandler> = [];
  let producerConnected = false;
  let consumerConnected = false;
  let subscribedTopic: string | undefined;

  return {
    producer() {
      return {
        connect: async () => {
          producerConnected = true;
        },
        send: async (request: FakeSendRequest) => {
          for (const message of request.messages) {
            sent.push({ topic: request.topic, key: message.key, value: message.value });
          }
        },
      };
    },
    consumer() {
      return {
        connect: async () => {
          consumerConnected = true;
        },
        subscribe: async (request: { topic: string }) => {
          subscribedTopic = request.topic;
        },
        run: async (request: { eachMessage: EachMessageHandler }) => {
          runHandlers.push(request.eachMessage);
        },
      };
    },
    state: () => ({ producerConnected, consumerConnected, subscribedTopic, sent }),
    handlers: () => runHandlers,
  };
}

test('startWorker connects, subscribes, and runs the consumer', async () => {
  const kafka = fakeKafka();
  const config = configFromEnv({});

  await startWorker(config, kafka as never);

  const state = kafka.state();
  assert.equal(state.producerConnected, true);
  assert.equal(state.consumerConnected, true);
  assert.equal(state.subscribedTopic, PLANNING_TOPIC);
  assert.equal(kafka.handlers().length, 1);
});

test('startWorker echoes a blueprint message back to the echo topic', async () => {
  const kafka = fakeKafka();
  const config = configFromEnv({});

  await startWorker(config, kafka as never);
  const handler = kafka.handlers()[0]!;
  await handler({
    message: {
      value: Buffer.from(
        JSON.stringify({
          specversion: '1.0',
          id: 'b1',
          source: 'run-orchestrator',
          type: PLANNING_TOPIC,
          subject: 'runs/run-123',
          correlationid: 'run-123',
          data: { runId: 'run-123', message: 'Hello World' },
        }),
      ),
    },
  });

  const sent = kafka.state().sent;
  assert.equal(sent.length, 1);
  assert.equal(sent[0]!.topic, TEMP_ECHO_TOPIC);
  assert.equal(sent[0]!.key, 'run-123');
  const parsed = JSON.parse(sent[0]!.value) as Record<string, unknown>;
  assert.equal(parsed.type, TEMP_ECHO_TOPIC);
  assert.equal((parsed.data as Record<string, string>).assembledText, 'Hello World');
});

test('startWorker skips messages that cannot be echoed', async () => {
  const kafka = fakeKafka();
  const config = configFromEnv({});

  await startWorker(config, kafka as never);
  const handler = kafka.handlers()[0]!;
  await handler({ message: { value: null } });

  assert.equal(kafka.state().sent.length, 0);
});

test('runWorker starts the worker without settling', async () => {
  const kafka = fakeKafka();
  const config = configFromEnv({});

  const runPromise = runWorker(config, kafka as never);
  await new Promise((resolve) => setImmediate(resolve));

  assert.equal(kafka.state().producerConnected, true);
  assert.equal(kafka.state().consumerConnected, true);
  assert.equal(kafka.handlers().length, 1);
  assert.equal(typeof runPromise.then, 'function');
});

test('main wires config and starts the worker via the factory', async () => {
  const kafka = fakeKafka();

  main(() => kafka as never);
  await new Promise((resolve) => setImmediate(resolve));

  assert.equal(kafka.state().subscribedTopic, PLANNING_TOPIC);
  assert.equal(kafka.handlers().length, 1);
});
