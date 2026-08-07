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

export interface RunEvent {
  sequence: string;
  eventType: string;
  stepType: string | null;
  glyphPosition: number | null;
  status: string;
  artifactId: string | null;
  timestamp: number;
  summary: Record<string, unknown> | null;
}

export interface ArtifactMeta {
  artifactId: string;
  stage: string;
  glyphPosition: number | null;
  sha256: string;
  contentType: string | null;
  proxyUrl: string | null;
}

export interface RunArtifacts {
  runId: string;
  artifacts: ArtifactMeta[];
}
