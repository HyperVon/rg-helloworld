import { useEffect, useRef, useState } from 'react';
import type { SseMessage, RunSummary } from '../types';

export interface SseState {
  summary: RunSummary | null;
  eventId: string | null;
  connected: boolean;
  error: string | null;
  eventTypeCount: Record<string, number>;
}

export function useSseStream(streamUrl: string, reconnectMs = 5000): SseState {
  const [state, setState] = useState<SseState>({
    summary: null,
    eventId: null,
    connected: false,
    error: null,
    eventTypeCount: {},
  });
  const reconnectRef = useRef<number | null>(null);
  const sourceRef = useRef<EventSource | null>(null);

  useEffect(() => {
    let cancelled = false;

    function connect(lastId?: string) {
      const url = new URL(streamUrl, window.location.origin);
      if (lastId) {
        url.searchParams.set('lastEventId', lastId);
      }
      const source = new EventSource(url.toString());
      sourceRef.current = source;

      source.onopen = () => {
        if (cancelled) return;
        setState((prev) => ({ ...prev, connected: true, error: null }));
        if (reconnectRef.current !== null) {
          clearTimeout(reconnectRef.current);
          reconnectRef.current = null;
        }
      };

      source.addEventListener('snapshot', (ev) => {
        if (cancelled) return;
        const data = JSON.parse((ev as MessageEvent).data) as RunSummary;
        setState((prev) => ({ ...prev, summary: data }));
      });

      source.addEventListener('heartbeat', () => {
        if (cancelled) return;
        setState((prev) => ({
          ...prev,
          eventTypeCount: {
            ...prev.eventTypeCount,
            heartbeat: (prev.eventTypeCount.heartbeat ?? 0) + 1,
          },
        }));
      });

      source.addEventListener('run-succeeded', (ev) => {
        if (cancelled) return;
        const data = JSON.parse((ev as MessageEvent).data) as {
          runId: string;
          assembledText?: string;
        };
        setState((prev) => ({
          ...prev,
          summary: prev.summary ? { ...prev.summary, status: 'SUCCEEDED', terminal: true } : null,
          eventTypeCount: {
            ...prev.eventTypeCount,
            'run-succeeded': (prev.eventTypeCount['run-succeeded'] ?? 0) + 1,
          },
        }));
        void data;
      });

      source.addEventListener('run-failed', () => {
        if (cancelled) return;
        setState((prev) => ({
          ...prev,
          summary: prev.summary ? { ...prev.summary, status: 'FAILED', terminal: true } : null,
          eventTypeCount: {
            ...prev.eventTypeCount,
            'run-failed': (prev.eventTypeCount['run-failed'] ?? 0) + 1,
          },
        }));
        source.close();
      });

      for (const evt of [
        'step-status-changed',
        'artifact-created',
        'retry-scheduled',
        'replay-point',
      ]) {
        source.addEventListener(evt, (ev) => {
          if (cancelled) return;
          const msg = JSON.parse((ev as MessageEvent).data) as any;
          setState((prev) => ({
            ...prev,
            eventTypeCount: {
              ...prev.eventTypeCount,
              [evt]: (prev.eventTypeCount[evt] ?? 0) + 1,
            },
            eventId: (ev as MessageEvent).lastEventId || prev.eventId,
            ...(msg?.summary
              ? {
                  summary: {
                    ...prev.summary!,
                    ...(msg.summary as Partial<RunSummary>),
                  } as RunSummary,
                }
              : {}),
          }));
        });
      }

      source.onerror = (err) => {
        void err;
        if (cancelled) return;
        setState((prev) => ({ ...prev, connected: false, error: 'SSE connection error' }));
        const id = state.eventId;
        reconnectRef.current = window.setTimeout(
          () => connect(id ?? undefined),
          reconnectMs,
        ) as unknown as number;
      };
    }

    connect();

    return () => {
      cancelled = true;
      sourceRef.current?.close();
      if (reconnectRef.current !== null) {
        clearTimeout(reconnectRef.current);
      }
    };
  }, [streamUrl, reconnectMs]);

  return state;
}

export function parseSseFrame(raw: string): SseMessage | null {
  const lines = raw.split('\n');
  let event = '';
  let data = '';
  let id = '';
  for (const line of lines) {
    if (line.startsWith('id:')) {
      id = line.slice(3).trim();
    } else if (line.startsWith('event:')) {
      event = line.slice(6).trim();
    } else if (line.startsWith('data: ')) {
      const d = line.slice(6);
      data += (data ? '\n' : '') + d;
    }
  }
  if (!event && !data) return null;
  return { event, data: data || null, lastEventId: id };
}
