import assert from 'node:assert/strict';
import { test } from 'node:test';

let moduleSequence = 0;

function telemetryModule(label: string): string {
  moduleSequence += 1;
  return `../src/telemetry.js?test=${label}-${moduleSequence}`;
}

function replaceGlobalProcess(value: unknown): () => void {
  const descriptor = Object.getOwnPropertyDescriptor(globalThis, 'process');
  Object.defineProperty(globalThis, 'process', {
    configurable: true,
    enumerable: descriptor?.enumerable ?? false,
    value,
    writable: true,
  });

  return () => {
    if (descriptor) {
      Object.defineProperty(globalThis, 'process', descriptor);
    } else {
      Reflect.deleteProperty(globalThis, 'process');
    }
  };
}

test('telemetry disables non-Node runtimes and remains idempotent', async () => {
  const restoreProcess = replaceGlobalProcess({ env: {} });

  try {
    const { initTelemetry } = await import(telemetryModule('non-node'));
    assert.equal(await initTelemetry('ocr-worker', 'test'), false);
    assert.equal(await initTelemetry('ocr-worker', 'test'), false);
  } finally {
    restoreProcess();
  }
});

test('telemetry initializes and shuts down through registered signals', async () => {
  const originalOn = process.on;
  const originalExit = process.exit;
  const originalEndpoint = process.env.OTEL_EXPORTER_OTLP_ENDPOINT;
  const handlers = new Map<string, (...args: unknown[]) => void | Promise<void>>();
  const exitCodes: number[] = [];

  process.env.OTEL_EXPORTER_OTLP_ENDPOINT = 'http://127.0.0.1:4317';
  process.on = ((event: string, listener: (...args: unknown[]) => void) => {
    handlers.set(event, listener);
    return process;
  }) as typeof process.on;
  process.exit = ((code?: number) => {
    exitCodes.push(code ?? 0);
  }) as typeof process.exit;

  try {
    const { initTelemetry } = await import(telemetryModule('node'));
    assert.equal(await initTelemetry('ocr-worker', 'test'), true);
    assert.ok(handlers.has('SIGTERM'));
    assert.ok(handlers.has('SIGINT'));

    await handlers.get('SIGTERM')?.();
    assert.deepEqual(exitCodes, [0]);
  } finally {
    process.on = originalOn;
    process.exit = originalExit;
    if (originalEndpoint === undefined) {
      delete process.env.OTEL_EXPORTER_OTLP_ENDPOINT;
    } else {
      process.env.OTEL_EXPORTER_OTLP_ENDPOINT = originalEndpoint;
    }
  }
});

test('telemetry reports initialization failures without throwing', async () => {
  const originalOn = process.on;
  const originalEndpoint = process.env.OTEL_EXPORTER_OTLP_ENDPOINT;
  process.env.OTEL_EXPORTER_OTLP_ENDPOINT = 'http://127.0.0.1:4317';
  process.on = (() => {
    throw new Error('signal registration failed');
  }) as typeof process.on;

  try {
    const { initTelemetry } = await import(telemetryModule('registration-failure'));
    assert.equal(await initTelemetry('ocr-worker'), false);
  } finally {
    process.on = originalOn;
    if (originalEndpoint === undefined) {
      delete process.env.OTEL_EXPORTER_OTLP_ENDPOINT;
    } else {
      process.env.OTEL_EXPORTER_OTLP_ENDPOINT = originalEndpoint;
    }
  }
});
