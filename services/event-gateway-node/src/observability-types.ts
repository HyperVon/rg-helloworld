export interface Span {
  spanId: string;
  traceId: string;
  name: string;
  startTime: number;
  endTime?: number;
  attributes: Record<string, unknown>;
  status: SpanStatusCode;
  statusCode: SpanStatusCode;
}

export type SpanStatusCode = 'OK' | 'ERROR' | 'UNSET';

export interface TraceFlags {
  sampled: boolean;
}

export interface TraceState {
  toString(): string;
}

export interface TraceContext {
  traceId: string;
  spanId: string;
  traceFlags: TraceFlags;
  traceState: TraceState;
}
