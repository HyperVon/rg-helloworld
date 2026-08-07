export type RunStatus =
  | 'CREATED'
  | 'PLANNING'
  | 'GEOMETRY_EXPANDING'
  | 'NORMALIZING'
  | 'RASTERIZING'
  | 'COMPOSING'
  | 'PREPROCESSING'
  | 'OCR_RUNNING'
  | 'ADJUDICATING'
  | 'ASSEMBLING'
  | 'VALIDATING'
  | 'SUCCEEDED'
  | 'FAILED'
  | 'CANCELLED';

export interface RunSummary {
  status: RunStatus;
  currentStage: string;
  percentage: number;
  attempt: number;
  startedAt: number;
  lastEventSequence: number;
  terminal: boolean;
}

export interface GraphNode {
  id: string;
  stage: string;
  label: string;
  status: 'pending' | 'running' | 'completed' | 'failed';
  glyphPositions?: number[];
}

export interface GraphEdge {
  source: string;
  target: string;
}

export interface ArtifactNode {
  id: string;
  stage: string;
  sha256: string;
  contentType: string | null;
  proxyUrl: string | null;
}

export interface SseMessage {
  event: string;
  data: unknown;
  lastEventId: string;
}
