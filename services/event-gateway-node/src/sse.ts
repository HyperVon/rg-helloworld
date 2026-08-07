import type { RunEvent, RunSummary } from './types.js';

export interface SseEvent {
  event: string;
  data: unknown;
  id?: string;
}

export interface SseFrame {
  event: string;
  data: string;
  id: string;
}

export function formatSseEvent(ev: SseEvent): string {
  const parts: string[] = [];
  if (ev.id !== undefined) {
    parts.push(`id:${ev.id}`);
  }
  parts.push(`event:${ev.event}`);
  const dataStr = typeof ev.data === 'string' ? ev.data : JSON.stringify(ev.data);
  for (const line of dataStr.split('\n')) {
    parts.push(`data: ${line}`);
  }
  parts.push('');
  return parts.join('\n');
}

export function buildSseFrame(ev: SseEvent, eventId: string): SseFrame {
  return {
    event: ev.event,
    data: JSON.stringify(ev.data),
    id: eventId,
  };
}

export function formatSseFrame(frame: SseFrame): string {
  const parts: string[] = [];
  parts.push(`id:${frame.id}`);
  parts.push(`event:${frame.event}`);
  for (const line of frame.data.split('\n')) {
    parts.push(`data: ${line}`);
  }
  parts.push('');
  return parts.join('\n');
}

export function snapshotEvent(summary: RunSummary): SseEvent {
  return {
    event: 'snapshot',
    data: summary,
  };
}

export function heartbeatEvent(): SseEvent {
  return {
    event: 'heartbeat',
    data: { ts: Date.now() },
  };
}

export function runEventToSse(ev: RunEvent): SseEvent {
  return {
    event: ev.eventType,
    data: ev,
    id: ev.sequence,
  };
}
