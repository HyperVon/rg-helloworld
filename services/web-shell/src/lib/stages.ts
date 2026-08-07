import type { GraphEdge, GraphNode } from '../types';

export const STAGE_LABELS: Record<string, string> = {
  CREATED: 'Run Creation',
  PLANNING: 'Planning',
  GEOMETRY_EXPANDING: 'Geometric Expansion',
  NORMALIZING: 'Vector Normalization',
  RASTERIZING: 'Glyph Rasterization',
  COMPOSING: 'Phrase Composition',
  PREPROCESSING: 'OCR Preprocessing',
  OCR_RUNNING: 'OCR',
  ADJUDICATING: 'Adjudication',
  ASSEMBLING: 'Assembly',
  VALIDATING: 'Final Validation',
  SUCCEEDED: 'Succeed',
  FAILED: 'Failed',
  CANCELLED: 'Cancelled',
};

export const PROCESS_NODES: GraphNode[] = [
  { id: 'plan', stage: 'PLANNING', label: 'Run Planning', status: 'pending' },
  {
    id: 'geometry',
    stage: 'GEOMETRY_EXPANDING',
    label: 'Geometry Expansion',
    status: 'pending',
    glyphPositions: [],
  },
  {
    id: 'vector',
    stage: 'NORMALIZING',
    label: 'Vector Normalization',
    status: 'pending',
    glyphPositions: [],
  },
  {
    id: 'raster',
    stage: 'RASTERIZING',
    label: 'Glyph Rasterization',
    status: 'pending',
    glyphPositions: [],
  },
  { id: 'compose', stage: 'COMPOSING', label: 'Phrase Composition', status: 'pending' },
  { id: 'preprocess', stage: 'PREPROCESSING', label: 'OCR Preprocessing', status: 'pending' },
  { id: 'ocr', stage: 'OCR_RUNNING', label: 'OCR', status: 'pending' },
  { id: 'adjudicate', stage: 'ADJUDICATING', label: 'Adjudication', status: 'pending' },
  { id: 'assemble', stage: 'ASSEMBLING', label: 'Assembly', status: 'pending' },
  { id: 'validate', stage: 'VALIDATING', label: 'Final Validation', status: 'pending' },
  { id: 'terminal', stage: 'SUCCEEDED', label: 'Terminal', status: 'pending' },
];

export const PROCESS_EDGES: GraphEdge[] = [
  { source: 'plan', target: 'geometry' },
  { source: 'geometry', target: 'vector' },
  { source: 'vector', target: 'raster' },
  { source: 'raster', target: 'compose' },
  { source: 'compose', target: 'preprocess' },
  { source: 'preprocess', target: 'ocr' },
  { source: 'ocr', target: 'adjudicate' },
  { source: 'adjudicate', target: 'assemble' },
  { source: 'assemble', target: 'validate' },
  { source: 'validate', target: 'terminal' },
];

export const PROCESS_NODE_POSITIONS: Record<string, { x: number; y: number }> = {
  plan: { x: 0, y: 0 },
  geometry: { x: 0, y: 80 },
  vector: { x: 0, y: 160 },
  raster: { x: 0, y: 240 },
  compose: { x: 0, y: 320 },
  preprocess: { x: 0, y: 400 },
  ocr: { x: 0, y: 480 },
  adjudicate: { x: 0, y: 560 },
  assemble: { x: 0, y: 640 },
  validate: { x: 0, y: 720 },
  terminal: { x: 0, y: 800 },
};

export function nodeStatusForStage(
  targetStage: string,
  currentStage: string,
  terminal: boolean,
  status: string,
): GraphNode['status'] {
  if (terminal) {
    if (status === 'SUCCEEDED') return 'completed';
    return 'failed';
  }
  if (targetStage === currentStage) return 'running';

  const targetIdx = PROCESS_NODES.findIndex((n) => n.stage === targetStage);
  const currentIdx = PROCESS_NODES.findIndex((n) => n.stage === currentStage);
  if (targetIdx < 0 || currentIdx < 0) return 'pending';
  if (targetIdx < currentIdx) return 'completed';
  return 'pending';
}

export function getGraphNodes(
  currentStage: string,
  terminal: boolean,
  runStatus: string,
  glyphCount?: number,
): GraphNode[] {
  return PROCESS_NODES.map((n) => {
    const status = nodeStatusForStage(n.stage, currentStage, terminal, runStatus);
    const node: GraphNode = { ...n, status };
    if (n.stage === 'GEOMETRY_EXPANDING' && glyphCount !== undefined && glyphCount > 0) {
      node.glyphPositions = Array.from({ length: glyphCount }, (_, i) => i);
    }
    return node;
  });
}
