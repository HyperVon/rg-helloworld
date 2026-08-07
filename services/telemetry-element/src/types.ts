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

export interface StepLedgerEntry {
  stepType: string;
  glyphPosition: number | null;
  status: string;
  durationMs: number;
  timestamp: number;
}

export interface AttemptEntry {
  attempt: number;
  startedAt: number;
  durationMs: number;
  result: string;
}

export interface OcrConfidenceEntry {
  glyphPosition: number;
  symbol: string;
  confidence: number;
  timestamp: number;
}

export interface RunSummary {
  status: RunStatus;
  currentStage: string;
  percentage: number;
  attempt: number;
  startedAt: number;
  lastEventSequence: number;
  terminal: boolean;
}

export interface TelemetryData {
  runId: string;
  status: RunStatus;
  stepLedger: StepLedgerEntry[];
  attempts: AttemptEntry[];
  ocrConfidences: OcrConfidenceEntry[];
  kafkaEventCount: number;
  resourceUsage: {
    cpu: number;
    memory: number;
  };
}
