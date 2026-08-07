import type { RunSummary, TelemetryData } from './types.js';
import type { RunStatus } from './types.js';

export function buildEmptyData(runId: string): TelemetryData {
  return {
    runId,
    status: 'CREATED' as RunStatus,
    stepLedger: [],
    attempts: [],
    ocrConfidences: [],
    kafkaEventCount: 0,
    resourceUsage: { cpu: 0, memory: 0 },
  };
}

export function applySnapshot(
  prev: TelemetryData | null,
  summary: RunSummary,
  runId: string,
): TelemetryData {
  const base = prev ?? buildEmptyData(runId);
  return {
    ...base,
    status: summary.status,
    stepLedger: prev ? prev.stepLedger : [],
    attempts: prev ? prev.attempts : [],
    ocrConfidences: prev ? prev.ocrConfidences : [],
    kafkaEventCount: summary.lastEventSequence || 0,
  };
}

export function applyStepEvent(
  prev: TelemetryData | null,
  msg: Record<string, unknown>,
): TelemetryData | null {
  if (!prev) return null;
  const entry = {
    stepType: (msg.stepType as string) || 'unknown',
    glyphPosition: (msg.glyphPosition as number) ?? null,
    status: (msg.status as string) || 'unknown',
    durationMs: (msg.durationMs as number) ?? 0,
    timestamp: (msg.timestamp as number) ?? Date.now(),
  };
  return {
    ...prev,
    stepLedger: [...prev.stepLedger, entry],
    kafkaEventCount: prev.kafkaEventCount + 1,
  };
}

export function applyRunResult(
  prev: TelemetryData | null,
  status: RunStatus,
): TelemetryData | null {
  if (!prev) return null;
  return { ...prev, status };
}
