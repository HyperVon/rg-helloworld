export const SERVICE_NAME = 'event-gateway';
export const SERVICE_VERSION = '0.5.0-milestone11';

export const HEARTBEAT_INTERVAL_MS = 15_000;

export function banner(): string {
  return `${SERVICE_NAME} ${SERVICE_VERSION} (Milestone 11)`;
}

export { buildSseFrame, formatSseEvent, type SseEvent, type SseFrame } from './sse.js';
export { EventGateway } from './gateway.js';
export type { RunEvent, RunSummary, ArtifactMeta } from './types.js';
export {
  getObservabilityConfig,
  injectTraceHeaders,
  formatTraceId,
  formatSpanId,
  logTraceContext,
} from './observability.js';
export type { ObservabilityConfig } from './observability.js';
