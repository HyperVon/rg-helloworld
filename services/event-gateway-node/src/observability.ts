import type {
  Span,
  SpanStatusCode,
  TraceFlags,
  TraceState,
  TraceContext,
} from './observability-types.js';

export const OTEL_ENDPOINT =
  process.env.OTEL_EXPORTER_OTLP_ENDPOINT || 'http://otel-collector.rube-goldberg:4318';
export const OTEL_SERVICE_NAME = 'event-gateway';
export const OTEL_SERVICE_VERSION = '0.5.0-milestone11';

export interface ObservabilityConfig {
  endpoint: string;
  serviceName: string;
  serviceVersion: string;
  traceId: string;
}

export function getObservabilityConfig(): ObservabilityConfig {
  return {
    endpoint: OTEL_ENDPOINT,
    serviceName: OTEL_SERVICE_NAME,
    serviceVersion: OTEL_SERVICE_VERSION,
    traceId: process.env.RG_RUN_ID || '',
  };
}

export function formatTraceId(id: string): string {
  return id.padEnd(32, '0');
}

export function formatSpanId(id: string): string {
  return id.padEnd(16, '0');
}

export function logTraceContext(fields: Record<string, unknown>): string {
  const parts: string[] = [];
  if (fields.traceId) parts.push(`traceId=${fields.traceId}`);
  if (fields.spanId) parts.push(`spanId=${fields.spanId}`);
  if (fields.runId) parts.push(`runId=${fields.runId}`);
  return parts.join(' ');
}

export function injectTraceHeaders(
  headers: Record<string, string>,
  traceId: string,
  spanId: string,
  traceFlags: number = 1,
): Record<string, string> {
  const context = `${traceFlags.toString(16).padStart(2, '0')}-${traceId.slice(0, 32).padEnd(32, '0')}-${spanId.slice(0, 16).padEnd(16, '0')}-00`;
  return {
    ...headers,
    traceparent: `00-${formatTraceId(traceId)}-${formatSpanId(spanId)}-${traceFlags.toString(16).padStart(2, '0')}`,
  };
}

export type { Span, SpanStatusCode, TraceFlags, TraceState, TraceContext };
