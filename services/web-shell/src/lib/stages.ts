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

/**
 * Feeder (boustrophedon / theater-row) layout.
 *
 * Instead of one node per row zig-zag (wasted 60%+ whitespace), fill rows
 * left-to-right, then right-to-left, like a theater queue feeder line.
 * COLS nodes per row, then serpentine to the next row.
 *
 *  Row 0 L→R:  plan | geometry | vector | raster
 *  Row 1 R→L:  adjudicate | ocr | preprocess | compose   (visually reversed,
 *              logical order preserved via edges)
 *  Row 2 L→R:  assemble | validate | terminal
 *
 * Coordinates are centered around x=0 so React Flow fitView stays centered.
 * DX/DY chosen to keep node minWidth 120px + 16px padding with no overlap.
 */
const FEEDER_COLS = 4;
const FEEDER_DX = 180;
const FEEDER_DY = 110;
const FEEDER_X0 = -((FEEDER_COLS - 1) * FEEDER_DX) / 2; // -270

function feederPos(index: number): { x: number; y: number } {
  const row = Math.floor(index / FEEDER_COLS);
  const colInRow = index % FEEDER_COLS;
  const reversed = row % 2 === 1;
  const col = reversed ? FEEDER_COLS - 1 - colInRow : colInRow;
  return { x: FEEDER_X0 + col * FEEDER_DX, y: row * FEEDER_DY };
}

// Order must match PROCESS_NODES logical order.
const _ORDERED_IDS = [
  'plan',
  'geometry',
  'vector',
  'raster',
  'compose',
  'preprocess',
  'ocr',
  'adjudicate',
  'assemble',
  'validate',
  'terminal',
] as const;

export const PROCESS_NODE_POSITIONS: Record<string, { x: number; y: number }> = Object.fromEntries(
  _ORDERED_IDS.map((id, i) => [id, feederPos(i)]),
) as Record<string, { x: number; y: number }>;

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
