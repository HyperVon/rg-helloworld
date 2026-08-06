import { spawnSync } from 'node:child_process';
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { createHash } from 'node:crypto';

export const SERVICE_NAME = 'ocr-worker';
export const SERVICE_VERSION = '0.5.0-milestone8';
export const ALLOWED_ALPHABET =
  "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789.,!? '-:;";

export interface PositionObservation {
  position: number;
  candidate: string;
  confidence: number;
  alternatives: string[];
}

export interface SpacingObservation {
  betweenPositions: [number, number];
  pixelGap: number;
  medianGlyphGapRatio: number;
}

export interface Symbol {
  text: string;
  bbox: { x: number; y: number; width: number; height: number };
}

export interface FullPhraseResult {
  rawText: string;
  confidence: number;
  symbols: Symbol[];
}

export interface OcrObservations {
  fullPhrase: FullPhraseResult;
  positionObservations: PositionObservation[];
  spacingObservations: SpacingObservation[];
}

export interface LayoutEntry {
  position: number;
  x: number;
  y: number;
  width: number;
  height: number;
  advanceWidth: number;
  baseline: number;
}

export interface PreprocessReport {
  layout: LayoutEntry[];
  totalWidth: number;
  totalHeight: number;
}

export interface PreprocessData {
  ocrImageSha256: string;
  ocrImageWidth: number;
  ocrImageHeight: number;
  positionCrops: number;
}

export interface CropInfo {
  position: number;
  imagePath: string;
  bbox: { x: number; y: number; width: number; height: number };
}

export function banner(): string {
  return `${SERVICE_NAME} ${SERVICE_VERSION}`;
}

export function cryptoHash(data: string): string {
  return createHash('sha256').update(Buffer.from(data, 'utf-8')).digest('hex');
}

export const PROHIBITED_FIELDS = [
  'message',
  'targetText',
  'expectedCharacter',
  'unicodeCodePoint',
  'characterName',
  'glyphLabel',
] as const;

export function checkProhibitedFields(eventJson: string): string[] {
  const violations: string[] = [];
  for (const field of PROHIBITED_FIELDS) {
    if (eventJson.includes(`"${field}"`)) {
      violations.push(field);
    }
  }
  return violations;
}

export function buildOperationId(
  runId: string,
  stepId: string,
  attempt: number,
  inputHashes: string[],
): string {
  const payload = JSON.stringify({
    runId,
    stepId,
    attempt,
    inputs: [...inputHashes].sort(),
  });
  return cryptoHash(payload);
}

interface TesseractSymbol {
  text: string;
  confidence: number;
  bbox: { x: number; y: number; width: number; height: number };
}

export interface TesseractResult {
  text: string;
  confidence: number;
  symbols: TesseractSymbol[];
}

export function runTesseract(
  imagePath: string,
  psm: number,
  whitelist: string | null = null,
): TesseractResult {
  const args: string[] = ['--psm', String(psm)];
  if (whitelist) {
    args.push('-c', `tessedit_char_whitelist=${whitelist}`);
  }
  args.push(imagePath, 'stdout', 'tsv');
  const result = spawnSync('tesseract', args, { encoding: 'utf-8', timeout: 30000 });
  if (result.error) {
    throw new Error(`tesseract failed: ${result.error.message}`);
  }
  if (result.status !== 0) {
    throw new Error(`tesseract exited with code ${result.status}: ${result.stderr}`);
  }
  const lines = (result.stdout ?? '').trim().split('\n');
  const symbols = parseTsvLines(lines);
  return symbolsToResult(symbols);
}

export function symbolsToResult(symbols: TesseractSymbol[]): TesseractResult {
  const text = symbols
    .map((s) => s.text)
    .join('')
    .trim();
  const confidences = symbols.map((s) => s.confidence).filter((c) => c > 0);
  const avgConfidence =
    confidences.length > 0 ? confidences.reduce((a, b) => a + b, 0) / confidences.length : 0;
  return { text, confidence: avgConfidence, symbols };
}

export type OcrExecutor = (
  imagePath: string,
  psm: number,
  whitelist: string | null,
) => TesseractResult;

export function parseTsvLines(lines: string[]): TesseractSymbol[] {
  const symbols: TesseractSymbol[] = [];
  if (lines.length < 2) return symbols;

  const header = (lines[0] ?? '').split('\t');
  const idxLevel = header.indexOf('level');
  const idxText = header.indexOf('text');
  const idxConf = header.indexOf('conf');
  const idxLeft = header.indexOf('left');
  const idxTop = header.indexOf('top');
  const idxWidth = header.indexOf('width');
  const idxHeight = header.indexOf('height');

  for (let i = 1; i < lines.length; i++) {
    const fields = (lines[i] ?? '').split('\t');
    if (fields.length < header.length) continue;
    const level = fields[idxLevel] ?? '';
    if (level !== '10') continue;
    const text = fields[idxText] ?? '';
    if (!text || text.trim() === '') continue;
    const confStr = fields[idxConf] ?? '0';
    const conf = parseInt(confStr, 10);
    if (isNaN(conf) || conf < 0) continue;
    const leftStr = fields[idxLeft] ?? '0';
    const topStr = fields[idxTop] ?? '0';
    const widthStr = fields[idxWidth] ?? '0';
    const heightStr = fields[idxHeight] ?? '0';
    const left = parseInt(leftStr, 10) || 0;
    const top = parseInt(topStr, 10) || 0;
    const width = parseInt(widthStr, 10) || 0;
    const height = parseInt(heightStr, 10) || 0;
    symbols.push({
      text: text.trim(),
      confidence: conf / 100,
      bbox: { x: left, y: top, width, height },
    });
  }
  return symbols;
}

export function performOcr(
  ocrImagePath: string,
  manifest: PreprocessReport,
  cropsDir: string,
  ocrExecutor: OcrExecutor = runTesseract,
): OcrObservations {
  const fullPhraseResult = ocrExecutor(ocrImagePath, 7, null);
  const positionObservations: PositionObservation[] = [];

  for (const entry of manifest.layout) {
    if (entry.width === 0 && entry.height === 0) continue;
    const cropPath = resolve(cropsDir, `crop-position-${entry.position}.png`);
    if (!existsSync(cropPath)) continue;
    const cropResult = ocrExecutor(cropPath, 10, ALLOWED_ALPHABET);
    const candidates = cropResult.symbols
      .map((s) => s.text)
      .filter((c) => c.length > 0)
      .slice(0, 5);
    const bestCandidate = candidates[0] ?? '?';
    positionObservations.push({
      position: entry.position,
      candidate: bestCandidate,
      confidence: cropResult.confidence,
      alternatives: candidates,
    });
  }

  const spacingObservations = computeSpacing(manifest);

  return {
    fullPhrase: {
      rawText: fullPhraseResult.text,
      confidence: fullPhraseResult.confidence,
      symbols: fullPhraseResult.symbols,
    },
    positionObservations,
    spacingObservations,
  };
}

export function computeSpacing(manifest: PreprocessReport): SpacingObservation[] {
  const drawables = manifest.layout.filter((e) => e.width > 0 || e.height > 0);
  if (drawables.length < 2) return [];

  const observations: SpacingObservation[] = [];
  for (let i = 1; i < drawables.length; i++) {
    const prev = drawables[i - 1]!;
    const curr = drawables[i]!;
    const prevEnd = prev.x + prev.width;
    const pixelGap = curr.x - prevEnd;
    const avgWidth = (prev.width + curr.width) / 2;
    const ratio = avgWidth > 0 ? pixelGap / avgWidth : 0;
    observations.push({
      betweenPositions: [prev.position, curr.position],
      pixelGap,
      medianGlyphGapRatio: ratio,
    });
  }
  return observations;
}

export function buildOcrEvent(
  runId: string,
  stepId: string,
  attempt: number,
  inputHash: string,
  observations: OcrObservations,
  inputArtifacts: string[],
  outputArtifacts: string[],
): Record<string, unknown> {
  const operationId = buildOperationId(runId, stepId, attempt, [inputHash]);
  return {
    specversion: '1.0',
    id: operationId,
    source: 'ocr-worker',
    type: 'rg.ocr-observations.v1',
    subject: `runs/${runId}`,
    time: new Date().toISOString(),
    correlationid: runId,
    datacontenttype: 'application/json',
    data: {
      runId,
      stepId,
      attempt,
      inputMaturity: 60,
      outputMaturity: 70,
      inputArtifacts,
      outputArtifacts,
      transformation: { name: 'perform-ocr', version: '1.0.0' },
      observations,
    },
  };
}

export function runOcrOnce(
  ocrImagePath: string,
  compositionManifestPath: string,
  cropsDir: string,
  outputPath?: string,
  eventOutputPath?: string,
  ocrExecutor: OcrExecutor = runTesseract,
): OcrObservations {
  const manifestRaw = JSON.parse(readFileSync(compositionManifestPath, 'utf-8'));
  const manifest: PreprocessReport = {
    layout: manifestRaw.layout as LayoutEntry[],
    totalWidth: manifestRaw.totalWidth,
    totalHeight: manifestRaw.totalHeight,
  };

  const observations = performOcr(ocrImagePath, manifest, cropsDir, ocrExecutor);

  if (eventOutputPath) {
    const event = buildOcrEvent(
      'test-run',
      'test-step',
      1,
      cryptoHash(JSON.stringify(manifest)),
      observations,
      [ocrImagePath],
      [eventOutputPath],
    );
    writeFileSync(eventOutputPath, JSON.stringify(event, null, 2));
  }

  if (outputPath) {
    writeFileSync(outputPath, JSON.stringify(observations, null, 2));
  }

  return observations;
}

export async function runCli(argv: string[]): Promise<number> {
  const cmd = argv[2];
  if (cmd === 'run') {
    console.log(banner());
    try {
      const { runConsumer } = await import('./consumer.js');
      await runConsumer();
      return 0;
    } catch (err) {
      console.error('ocr-worker consumer error:', err);
      return 1;
    }
  } else if (cmd === 'once') {
    const ocrImage = argv[3];
    const manifest = argv[4];
    const cropsDir = argv[5];
    const output = argv[6];
    const eventOutput = argv[7];
    if (!ocrImage || !manifest || !cropsDir) {
      console.error(
        'Usage: ocr-worker once <ocr-image> <manifest> <crops-dir> [output] [event-output]',
      );
      return 1;
    }
    runOcrOnce(ocrImage, manifest, cropsDir, output, eventOutput);
    return 0;
  } else {
    console.log(banner());
    return 0;
  }
}

if (process.argv[1] && process.argv[1].endsWith('index.js')) {
  runCli(process.argv).then((code) => process.exit(code));
}
