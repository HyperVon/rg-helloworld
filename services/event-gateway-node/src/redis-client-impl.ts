import { createClient, type RedisClientType } from 'redis';
import type { RedisClient } from './redis-client.js';
import type { RunArtifacts, RunEvent, RunSummary } from './types.js';

function eventTypeForStatus(status: string | undefined): string {
  if (status === 'SUCCEEDED') return 'run-succeeded';
  if (status === 'FAILED') return 'run-failed';
  return 'step-status-changed';
}

export class RedisClientImpl implements RedisClient {
  private readonly redis: RedisClientType;

  constructor(redis: RedisClientType) {
    this.redis = redis;
  }

  async getSummary(runId: string): Promise<RunSummary | null> {
    const latest = await this.redis.hGet(`run-summary:${runId}`, 'latest');
    if (!latest) return null;
    let status = 'UNKNOWN';
    let percentage = 0;
    let attempt = 1;
    try {
      const obj = JSON.parse(latest) as Record<string, unknown>;
      if (typeof obj.status === 'string') status = obj.status;
      if (typeof obj.percentage === 'number') percentage = obj.percentage;
      if (typeof obj.attempt === 'number') attempt = obj.attempt;
    } catch {
      // ignore malformed summary entries
    }
    const terminal = status === 'SUCCEEDED' || status === 'FAILED' || status === 'CANCELLED';
    return {
      status: status as RunSummary['status'],
      currentStage: status,
      percentage,
      attempt,
      startedAt: 0,
      lastEventSequence: 0,
      terminal,
    };
  }

  async getEventsSince(runId: string, lastEventId: string | null): Promise<RunEvent[]> {
    const start = lastEventId && lastEventId !== '0' ? lastEventId : '-';
    const entries = await this.redis.xRange(`run-events:${runId}`, start, '+');
    return entries.map((entry) => {
      const status = entry.message['status'] ?? 'UNKNOWN';
      return {
        sequence: entry.id,
        eventType: eventTypeForStatus(status),
        stepType: null,
        glyphPosition: null,
        status,
        artifactId: null,
        timestamp: Date.now(),
        summary: null,
      } satisfies RunEvent;
    });
  }

  async getArtifacts(_runId: string): Promise<RunArtifacts> {
    return { runId: _runId, artifacts: [] };
  }

  async close(): Promise<void> {
    await this.redis.quit();
  }
}

export async function createRedisClient(url: string): Promise<RedisClientImpl> {
  const client = createClient({ url });
  await client.connect();
  return new RedisClientImpl(client as unknown as RedisClientType);
}
