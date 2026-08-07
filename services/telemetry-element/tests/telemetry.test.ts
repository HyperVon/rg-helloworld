import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
  SERVICE_NAME,
  SERVICE_VERSION,
  banner,
  formatStepType,
  isRunning,
  formatDuration,
  averageConfidence,
  minConfidence,
  renderTemplate,
  renderStepRow,
  renderAttemptRow,
} from '../src/index.js';
import { applySnapshot, applyStepEvent, applyRunResult, buildEmptyData } from '../src/handlers.js';
import { TelemetryPanel } from '../src/index.js';
import type {
  OcrConfidenceEntry,
  StepLedgerEntry,
  AttemptEntry,
  TelemetryData,
} from '../src/types.js';

test('formatStepType converts underscores to spaces and capitalizes', () => {
  assert.equal(formatStepType('GEOMETRY_EXPANDING'), 'Geometry Expanding');
  assert.equal(formatStepType('OCR_RUNNING'), 'Ocr Running');
});

test('isRunning returns false for terminal states', () => {
  assert.equal(isRunning('SUCCEEDED'), false);
  assert.equal(isRunning('FAILED'), false);
  assert.equal(isRunning('CANCELLED'), false);
});

test('isRunning returns true for active states', () => {
  assert.equal(isRunning('PLANNING'), true);
  assert.equal(isRunning('ASSEMBLING'), true);
});

test('formatDuration handles milliseconds', () => {
  assert.equal(formatDuration(500), '500ms');
});

test('formatDuration handles seconds', () => {
  assert.equal(formatDuration(1500), '1.5s');
});

test('formatDuration handles minutes', () => {
  assert.equal(formatDuration(120000), '2.0m');
});

test('averageConfidence returns 0 for empty', () => {
  assert.equal(averageConfidence([]), 0);
});

test('averageConfidence computes mean', () => {
  const entries: OcrConfidenceEntry[] = [
    { glyphPosition: 0, symbol: 'H', confidence: 0.8, timestamp: 0 },
    { glyphPosition: 1, symbol: 'i', confidence: 0.9, timestamp: 0 },
  ];
  assert.ok(Math.abs(averageConfidence(entries) - 0.85) < 0.001);
});

test('minConfidence returns 0 for empty', () => {
  assert.equal(minConfidence([]), 0);
});

test('minConfidence finds minimum', () => {
  const entries: OcrConfidenceEntry[] = [
    { glyphPosition: 0, symbol: 'H', confidence: 0.8, timestamp: 0 },
    { glyphPosition: 1, symbol: 'i', confidence: 0.5, timestamp: 0 },
  ];
  assert.equal(minConfidence(entries), 0.5);
});

test('TelemetryPanel is constructable and attribute-based', () => {
  const panel = new TelemetryPanel();
  assert.ok(panel instanceof Object);
  assert.doesNotThrow(() => panel.setAttribute('run-id', 'test-run-1'));
  assert.doesNotThrow(() => panel.disconnectedCallback());
  assert.doesNotThrow(() => panel.connectedCallback());
});

test('renderTemplate shows loading when no data', () => {
  const html = renderTemplate(null);
  assert.ok(html.includes('Loading run'));
  assert.ok(html.includes('telemetry-panel'));
});

test('renderTemplate renders full telemetry', () => {
  const data: TelemetryData = {
    runId: 'run-1',
    status: 'SUCCEEDED',
    stepLedger: [
      {
        stepType: 'GEOMETRY_EXPANDING',
        glyphPosition: 0,
        status: 'completed',
        durationMs: 50,
        timestamp: 100,
      },
    ],
    attempts: [{ attempt: 1, startedAt: 1000, durationMs: 5000, result: 'success' }],
    ocrConfidences: [{ glyphPosition: 0, symbol: 'H', confidence: 0.8, timestamp: 0 }],
    kafkaEventCount: 12,
    resourceUsage: { cpu: 15, memory: 30 },
  };
  const html = renderTemplate(data);
  assert.ok(html.includes('Run run-1'));
  assert.ok(html.includes('SUCCEEDED'));
  assert.ok(html.includes('Kafka events: 12'));
  assert.ok(html.includes('Geometry Expanding'));
  assert.ok(html.includes('OCR Confidence'));
  assert.ok(html.includes('CPU: 15%'));
  assert.ok(html.includes('Memory: 30%'));
  assert.ok(html.includes('Min: 0.80'));
  assert.ok(html.includes('Avg: 0.80'));
});

test('renderTemplate shows em dash for null glyphPosition', () => {
  const data: TelemetryData = {
    runId: 'r1',
    status: 'CREATED',
    stepLedger: [
      { stepType: 'PLANNING', glyphPosition: null, status: 'pending', durationMs: 0, timestamp: 0 },
    ],
    attempts: [],
    ocrConfidences: [],
    kafkaEventCount: 0,
    resourceUsage: { cpu: 0, memory: 0 },
  };
  const html = renderTemplate(data);
  assert.ok(html.includes('—'));
});

test('renderTemplate handles empty step ledger', () => {
  const data: TelemetryData = {
    runId: 'r1',
    status: 'CREATED',
    stepLedger: [],
    attempts: [],
    ocrConfidences: [],
    kafkaEventCount: 0,
    resourceUsage: { cpu: 0, memory: 0 },
  };
  const html = renderTemplate(data);
  assert.ok(html.includes('telemetry-panel'));
  assert.ok(html.includes('Kafka events: 0'));
});

test('renderStepRow renders glyph position', () => {
  const entry: StepLedgerEntry = {
    stepType: 'GEOMETRY_EXPANDING',
    glyphPosition: 5,
    status: 'completed',
    durationMs: 500,
    timestamp: 100,
  };
  const html = renderStepRow(entry);
  assert.ok(html.includes('Geometry Expanding'));
  assert.ok(html.includes('5'));
  assert.ok(html.includes('completed'));
  assert.ok(html.includes('500ms'));
});

test('renderStepRow shows em dash for null position', () => {
  const entry: StepLedgerEntry = {
    stepType: 'PLANNING',
    glyphPosition: null,
    status: 'running',
    durationMs: 1000,
    timestamp: 0,
  };
  const html = renderStepRow(entry);
  assert.ok(html.includes('—'));
  assert.ok(html.includes('1.0s'));
});

test('renderAttemptRow renders attempt info', () => {
  const attempt: AttemptEntry = {
    attempt: 2,
    startedAt: 1000000000000,
    durationMs: 60000,
    result: 'retry',
  };
  const html = renderAttemptRow(attempt);
  assert.ok(html.includes('2'));
  assert.ok(html.includes('retry'));
  assert.ok(html.includes('1.0m'));
});

test('applySnapshot creates new data from snapshot', () => {
  const result = applySnapshot(
    null,
    {
      status: 'SUCCEEDED',
      currentStage: 'Done',
      percentage: 100,
      attempt: 1,
      startedAt: 0,
      lastEventSequence: 10,
      terminal: true,
    },
    'run-1',
  );
  assert.equal(result.status, 'SUCCEEDED');
  assert.equal(result.kafkaEventCount, 10);
  assert.equal(result.runId, 'run-1');
});

test('applySnapshot preserves existing data', () => {
  const existing: TelemetryData = {
    runId: 'run-1',
    status: 'PLANNING',
    stepLedger: [
      { stepType: 'GEOMETRY', glyphPosition: 0, status: 'running', durationMs: 0, timestamp: 0 },
    ],
    attempts: [],
    ocrConfidences: [],
    kafkaEventCount: 1,
    resourceUsage: { cpu: 10, memory: 20 },
  };
  const result = applySnapshot(
    existing,
    {
      status: 'ASSEMBLING',
      currentStage: 'Assembly',
      percentage: 80,
      attempt: 1,
      startedAt: 0,
      lastEventSequence: 5,
      terminal: false,
    },
    'run-1',
  );
  assert.equal(result.status, 'ASSEMBLING');
  assert.equal(result.kafkaEventCount, 5);
  assert.equal(result.stepLedger.length, 1);
  assert.equal(result.resourceUsage.cpu, 10);
});

test('applyStepEvent adds entry to step ledger', () => {
  const existing: TelemetryData = {
    runId: 'run-1',
    status: 'ASSEMBLING',
    stepLedger: [],
    attempts: [],
    ocrConfidences: [],
    kafkaEventCount: 3,
    resourceUsage: { cpu: 0, memory: 0 },
  };
  const result = applyStepEvent(existing, {
    stepType: 'GEOMETRY',
    glyphPosition: 3,
    status: 'completed',
    durationMs: 100,
  });
  assert.ok(result !== null);
  assert.equal(result!.stepLedger.length, 1);
  assert.equal(result!.stepLedger[0]?.stepType, 'GEOMETRY');
  assert.equal(result!.kafkaEventCount, 4);
});

test('applyStepEvent returns null for empty state', () => {
  const result = applyStepEvent(null, { stepType: 'x' });
  assert.equal(result, null);
});

test('applyRunResult updates status', () => {
  const existing: TelemetryData = {
    runId: 'run-1',
    status: 'ASSEMBLING',
    stepLedger: [],
    attempts: [],
    ocrConfidences: [],
    kafkaEventCount: 1,
    resourceUsage: { cpu: 0, memory: 0 },
  };
  const result = applyRunResult(existing, 'SUCCEEDED');
  assert.ok(result !== null);
  assert.equal(result!.status, 'SUCCEEDED');
});

test('applyRunResult returns null for empty state', () => {
  const result = applyRunResult(null, 'SUCCEEDED');
  assert.equal(result, null);
});

test('buildEmptyData creates valid initial state', () => {
  const data = buildEmptyData('test-run');
  assert.equal(data.runId, 'test-run');
  assert.equal(data.status, 'CREATED');
  assert.equal(data.stepLedger.length, 0);
  assert.equal(data.kafkaEventCount, 0);
  assert.deepEqual(data.resourceUsage, { cpu: 0, memory: 0 });
});

test('SERVICE_NAME and VERSION exported', () => {
  assert.equal(SERVICE_NAME, 'telemetry-element');
  assert.equal(SERVICE_VERSION, '0.5.0-milestone11');
});

test('banner includes milestone 11', () => {
  assert.ok(banner().includes('Milestone 11'));
});
