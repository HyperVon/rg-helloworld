import type { RunArtifacts, RunEvent, RunSummary } from './types.js';

export interface RedisClient {
  getSummary(runId: string): Promise<RunSummary | null>;
  getEventsSince(runId: string, lastEventId: string | null): Promise<RunEvent[]>;
  getArtifacts(runId: string): Promise<RunArtifacts>;
  close(): Promise<void>;
}

export function isTerminalStatus(status: string): boolean {
  return status === 'SUCCEEDED' || status === 'FAILED' || status === 'CANCELLED';
}
