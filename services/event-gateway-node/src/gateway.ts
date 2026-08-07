import type { RedisClient } from './redis-client.js';
import type { RunArtifacts, RunEvent, RunSummary } from './types.js';
import {
  buildSseFrame,
  formatSseFrame,
  heartbeatEvent,
  runEventToSse,
  snapshotEvent,
} from './sse.js';
import { HEARTBEAT_INTERVAL_MS } from './index.js';

export class EventGateway {
  constructor(private redis: RedisClient) {}

  async getSummary(runId: string): Promise<RunSummary | null> {
    return this.redis.getSummary(runId);
  }

  async getEventsSince(runId: string, lastEventId: string | null): Promise<RunEvent[]> {
    return this.redis.getEventsSince(runId, lastEventId);
  }

  async getArtifacts(runId: string): Promise<RunArtifacts> {
    return this.redis.getArtifacts(runId);
  }

  formatStream(summary: RunSummary | null, events: RunEvent[], lastEventId: string | null): string {
    const frames: string[] = [];

    if (summary !== null) {
      frames.push(formatSseFrame(buildSseFrame(snapshotEvent(summary), '0')));
    }

    let nextId = 1;
    for (const ev of events) {
      const id = ev.sequence || String(nextId);
      frames.push(formatSseFrame(buildSseFrame(runEventToSse(ev), id)));
      nextId++;
    }

    if (lastEventId !== null) {
      frames.push(
        formatSseFrame({
          event: 'replay-point',
          data: JSON.stringify({ lastEventId }),
          id: String(nextId),
        }),
      );
    }

    frames.push(formatSseFrame(buildSseFrame(heartbeatEvent(), String(nextId))));

    return frames.join('\n');
  }

  shouldSendHeartbeat(lastActivity: number, now: number): boolean {
    return now - lastActivity >= HEARTBEAT_INTERVAL_MS;
  }

  isTerminal(status: string): boolean {
    return status === 'SUCCEEDED' || status === 'FAILED' || status === 'CANCELLED';
  }
}
