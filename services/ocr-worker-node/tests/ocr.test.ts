import assert from 'node:assert/strict';
import { test } from 'node:test';
import { writeFileSync, readFileSync, mkdirSync, rmSync } from 'node:fs';
import { resolve } from 'node:path';
import { tmpdir } from 'node:os';
import { spawnSync } from 'node:child_process';

import {
  computeSpacing,
  buildOcrEvent,
  buildOperationId,
  cryptoHash,
  checkProhibitedFields,
  PROHIBITED_FIELDS,
  parseTsvLines,
  symbolsToResult,
  performOcr,
  runOcrOnce,
  runTesseract,
  ALLOWED_ALPHABET,
  runCli,
} from '../src/index.js';

test('computeSpacing returns empty for single drawable', () => {
  const result = computeSpacing({
    layout: [{ position: 0, x: 0, y: 0, width: 100, height: 100, advanceWidth: 1.0, baseline: 80 }],
    totalWidth: 100,
    totalHeight: 100,
  });
  assert.equal(result.length, 0);
});

test('computeSpacing calculates pixel gaps between drawables', () => {
  const result = computeSpacing({
    layout: [
      { position: 0, x: 20, y: 0, width: 100, height: 100, advanceWidth: 1.0, baseline: 80 },
      { position: 1, x: 130, y: 0, width: 100, height: 100, advanceWidth: 1.0, baseline: 80 },
    ],
    totalWidth: 230,
    totalHeight: 100,
  });
  assert.equal(result.length, 1);
  assert.deepEqual(result[0]?.betweenPositions, [0, 1]);
  assert.equal(result[0]?.pixelGap, 10);
});

test('computeSpacing skips gap entries', () => {
  const result = computeSpacing({
    layout: [
      { position: 0, x: 20, y: 0, width: 100, height: 100, advanceWidth: 1.0, baseline: 80 },
      { position: 5, x: 120, y: 0, width: 0, height: 0, advanceWidth: 0.6, baseline: 0 },
      { position: 6, x: 180, y: 0, width: 100, height: 100, advanceWidth: 1.0, baseline: 80 },
    ],
    totalWidth: 280,
    totalHeight: 100,
  });
  assert.equal(result.length, 1);
  assert.deepEqual(result[0]?.betweenPositions, [0, 6]);
  assert.equal(result[0]?.pixelGap, 60);
});

test('buildOperationId is deterministic', () => {
  const id1 = buildOperationId('run-1', 'step-1', 1, ['hash1', 'hash2']);
  const id2 = buildOperationId('run-1', 'step-1', 1, ['hash2', 'hash1']);
  const id3 = buildOperationId('run-1', 'step-1', 1, ['hash1', 'hash3']);
  assert.equal(id1, id2, 'order of input hashes does not affect ID');
  assert.notEqual(id1, id3, 'different inputs produce different IDs');
});

test('cryptoHash produces consistent SHA-256', () => {
  const hash = cryptoHash('test');
  assert.equal(hash.length, 64);
  assert.equal(hash, cryptoHash('test'));
  assert.notEqual(hash, cryptoHash('different'));
});

test('ALLOWED_ALPHABET is a non-empty string', () => {
  assert.ok(typeof ALLOWED_ALPHABET === 'string');
  assert.ok(ALLOWED_ALPHABET.length > 0);
  assert.ok(ALLOWED_ALPHABET.includes('H'));
  assert.ok(ALLOWED_ALPHABET.includes('E'));
  assert.ok(ALLOWED_ALPHABET.includes('L'));
  assert.ok(ALLOWED_ALPHABET.includes('O'));
  assert.ok(ALLOWED_ALPHABET.includes('W'));
  assert.ok(ALLOWED_ALPHABET.includes('R'));
  assert.ok(ALLOWED_ALPHABET.includes('D'));
  assert.equal(/[a-z]/.test(ALLOWED_ALPHABET), false);
});

test('buildOcrEvent has correct maturity values', () => {
  const event = buildOcrEvent(
    'run-1',
    'step-1',
    1,
    'inputhash',
    {
      fullPhrase: { rawText: 'Hello', confidence: 95.2, symbols: [] },
      positionObservations: [],
      spacingObservations: [],
    },
    ['input'],
    ['output'],
  );
  const data = event.data as Record<string, unknown>;
  assert.equal(data.inputMaturity, 60);
  assert.equal(data.outputMaturity, 70);
  const transform = data.transformation as Record<string, unknown> | undefined;
  assert.equal(transform?.name, 'perform-ocr');
});

test('buildOcrEvent includes observations', () => {
  const observations = {
    fullPhrase: {
      rawText: 'Hello World',
      confidence: 93.2,
      symbols: [{ text: 'H', bbox: { x: 0, y: 0, width: 10, height: 20 } }],
    },
    positionObservations: [
      { position: 0, candidate: 'H', confidence: 0.96, alternatives: ['H', 'N'] },
    ],
    spacingObservations: [
      { betweenPositions: [0, 1] as [number, number], pixelGap: 5, medianGlyphGapRatio: 1.2 },
    ],
  };
  const event = buildOcrEvent('run-1', 'step-1', 1, 'inputhash', observations, [], []);
  const data = event.data as Record<string, unknown>;
  const obs = data.observations as Record<string, unknown>;
  assert.deepEqual(obs.fullPhrase, observations.fullPhrase);
  const posObs = obs.positionObservations as Array<Record<string, unknown>>;
  assert.equal(posObs.length, 1);
  const spacingObs = obs.spacingObservations as Array<Record<string, unknown>>;
  assert.equal(spacingObs.length, 1);
});

test('checkProhibitedFields returns empty for clean event', () => {
  const cleanEvent = JSON.stringify({
    specversion: '1.0',
    type: 'rg.ocr-observations.v1',
    data: { runId: 'run-1', observations: { fullPhrase: { rawText: 'Hello' } } },
  });
  assert.deepEqual(checkProhibitedFields(cleanEvent), []);
});

test('checkProhibitedFields detects prohibited fields', () => {
  for (const field of PROHIBITED_FIELDS) {
    const poisoned = JSON.stringify({
      specversion: '1.0',
      data: { [field]: 'H' },
    });
    const violations = checkProhibitedFields(poisoned);
    assert.ok(violations.includes(field), `should detect ${field}`);
  }
});

test('checkProhibitedFields is case-sensitive', () => {
  const event = JSON.stringify({ data: { targettext: 'H' } });
  assert.deepEqual(checkProhibitedFields(event), []);
});

test('buildOcrEvent event has correct structure', () => {
  const event = buildOcrEvent(
    'run-1',
    'step-1',
    1,
    'inputhash',
    {
      fullPhrase: { rawText: 'Hello', confidence: 95.2, symbols: [] },
      positionObservations: [],
      spacingObservations: [],
    },
    ['input'],
    ['output'],
  );
  assert.equal(event.specversion, '1.0');
  assert.equal(event.source, 'ocr-worker');
  assert.equal(event.type, 'rg.ocr-observations.v1');
  assert.equal(event.correlationid, 'run-1');
});

test('buildOcrEvent operation ID is deterministic', () => {
  const event1 = buildOcrEvent(
    'run-1',
    'step-1',
    1,
    'hash',
    {
      fullPhrase: { rawText: '', confidence: 0, symbols: [] },
      positionObservations: [],
      spacingObservations: [],
    },
    [],
    [],
  );
  const event2 = buildOcrEvent(
    'run-1',
    'step-1',
    1,
    'hash',
    {
      fullPhrase: { rawText: '', confidence: 0, symbols: [] },
      positionObservations: [],
      spacingObservations: [],
    },
    [],
    [],
  );
  assert.equal(event1.id, event2.id);
});

test('parseTsvLines extracts level-10 symbol rows', () => {
  const tsv = [
    'level\tpage_num\tblock_num\tpar_num\tline_num\tword_num\tleft\ttop\twidth\theight\ttext\tconf',
    '5\t1\t1\t1\t1\t1\t10\t20\t100\t30\tHello\t95',
    '7\t1\t1\t1\t1\t1\t10\t20\t100\t30\tHello\t-1',
    '10\t1\t1\t1\t1\t1\t10\t20\t5\t10\tH\t98',
    '10\t1\t1\t1\t1\t2\t15\t20\t5\t10\te\t92',
    '10\t1\t1\t1\t1\t3\t20\t20\t5\t10\tl\t-5',
  ];
  const result = parseTsvLines(tsv);
  assert.equal(result.length, 2);
  assert.equal(result[0]?.text, 'H');
  assert.equal(result[0]?.confidence, 0.98);
  assert.deepEqual(result[0]?.bbox, { x: 10, y: 20, width: 5, height: 10 });
});

test('parseTsvLines splits a multi-character level-10 row', () => {
  const tsv = ['level\ttext\tconf\tleft\ttop\twidth\theight', '10\teC\t90\t10\t20\t20\t30'];
  const result = parseTsvLines(tsv);
  assert.deepEqual(
    result.map((symbol) => symbol.text),
    ['e', 'C'],
  );
  assert.deepEqual(result[0]?.bbox, { x: 10, y: 20, width: 10, height: 30 });
  assert.deepEqual(result[1]?.bbox, { x: 20, y: 20, width: 10, height: 30 });
});

test('parseTsvLines falls back to a word-level row', () => {
  const tsv = ['level\ttext\tconf\tleft\ttop\twidth\theight', '5\tHi\t80\t10\t20\t20\t30'];
  const result = parseTsvLines(tsv);
  assert.deepEqual(
    result.map((symbol) => symbol.text),
    ['H', 'i'],
  );
  assert.equal(result[0]?.confidence, 0.8);
});

test('parseTsvLines handles empty input', () => {
  assert.deepEqual(parseTsvLines([]), []);
  assert.deepEqual(parseTsvLines(['level\ttext\tconf']), []);
});

test('parseTsvLines skips rows with negative confidence', () => {
  const tsv = [
    'level\ttext\tconf\tleft\ttop\twidth\theight',
    '10\tX\t-1\t0\t0\t10\t10',
    '10\tY\t50\t0\t0\t10\t10',
  ];
  const result = parseTsvLines(tsv);
  assert.equal(result.length, 1);
  assert.equal(result[0]?.text, 'Y');
});

test('parseTsvLines handles missing fields gracefully', () => {
  const tsv = ['level\ttext\tconf\tleft\ttop\twidth\theight', '10'];
  const result = parseTsvLines(tsv);
  assert.equal(result.length, 0);
});

test('parseTsvLines uses defaults for missing columns', () => {
  const tsv = ['level\ttext\tconf', '10\tT\t50'];
  const result = parseTsvLines(tsv);
  assert.equal(result.length, 1);
  assert.equal(result[0]?.text, 'T');
  assert.equal(result[0]?.confidence, 0.5);
  assert.deepEqual(result[0]?.bbox, { x: 0, y: 0, width: 0, height: 0 });
});

test('symbolsToResult joins text and computes average confidence', () => {
  const result = symbolsToResult([
    { text: 'H', confidence: 0.98, bbox: { x: 0, y: 0, width: 5, height: 10 } },
    { text: 'i', confidence: 0.92, bbox: { x: 5, y: 0, width: 3, height: 10 } },
    { text: '', confidence: 0, bbox: { x: 8, y: 0, width: 2, height: 10 } },
  ]);
  assert.equal(result.text, 'Hi');
  assert.equal(result.symbols.length, 3);
  assert.equal(result.confidence, 0.95);
});

test('symbolsToResult handles empty symbols', () => {
  const result = symbolsToResult([]);
  assert.equal(result.text, '');
  assert.equal(result.confidence, 0);
});

test('symbolsToResult computes confidence with single symbol', () => {
  const result = symbolsToResult([
    { text: 'A', confidence: 0.8, bbox: { x: 0, y: 0, width: 5, height: 10 } },
  ]);
  assert.equal(result.text, 'A');
  assert.equal(result.confidence, 0.8);
});

test('symbolsToResult averages confidence excluding zero-confidence', () => {
  const result = symbolsToResult([
    { text: 'A', confidence: 0.9, bbox: { x: 0, y: 0, width: 5, height: 10 } },
    { text: 'B', confidence: 0.7, bbox: { x: 5, y: 0, width: 5, height: 10 } },
    { text: '', confidence: 0, bbox: { x: 8, y: 0, width: 5, height: 10 } },
  ]);
  assert.equal(result.text, 'AB');
  assert.equal(result.confidence, 0.8);
});

test('performOcr with mock executor produces observations', () => {
  const manifest = {
    layout: [
      { position: 0, x: 20, y: 0, width: 100, height: 100, advanceWidth: 1.0, baseline: 80 },
      { position: 6, x: 180, y: 0, width: 100, height: 100, advanceWidth: 1.0, baseline: 80 },
    ],
    totalWidth: 280,
    totalHeight: 100,
  };
  const mockExecutor = (_path: string, psm: number) => {
    if (psm === 7) {
      return symbolsToResult([
        { text: 'H', confidence: 0.98, bbox: { x: 0, y: 0, width: 10, height: 20 } },
        { text: 'W', confidence: 0.96, bbox: { x: 15, y: 0, width: 10, height: 20 } },
      ]);
    }
    return symbolsToResult([
      { text: 'H', confidence: 0.97, bbox: { x: 0, y: 0, width: 10, height: 20 } },
    ]);
  };
  const observations = performOcr('/fake/full.png', manifest, '/fake/crops', mockExecutor);
  assert.equal(observations.fullPhrase.rawText, 'HW');
  assert.equal(
    observations.positionObservations.length,
    0,
    'no crop files exist so no position observations',
  );
  assert.equal(observations.spacingObservations.length, 1);
  assert.deepEqual(observations.spacingObservations[0]?.betweenPositions, [0, 6]);
});

test('performOcr skips gap entries in layout', () => {
  const manifest = {
    layout: [{ position: 0, x: 0, y: 0, width: 0, height: 0, advanceWidth: 0.3, baseline: 0 }],
    totalWidth: 100,
    totalHeight: 100,
  };
  const mockExecutor = () => symbolsToResult([]);
  const observations = performOcr('/fake/image.png', manifest, '/fake/crops', mockExecutor);
  assert.equal(observations.positionObservations.length, 0);
});

test('performOcr default executor throws on non-existent image', () => {
  const manifest = {
    layout: [],
    totalWidth: 100,
    totalHeight: 100,
  };
  assert.throws(() => performOcr('/nonexistent.png', manifest, '/fake/crops'));
});

test('runTesseract error path throws on non-existent image', () => {
  assert.throws(() => runTesseract('/nonexistent.png', 7), /tesseract/);
});

function createTestImage(text: string): string {
  const tempPng = resolve(tmpdir(), `tesseract-test-${Date.now()}-${Math.random()}.png`);
  const result = spawnSync('python3', [
    '-c',
    `from PIL import Image, ImageDraw; img = Image.new('RGB', (200, 50), 'white'); d = ImageDraw.Draw(img); d.text((10, 10), '${text}', fill='black'); img.save('${tempPng}')`,
  ]);
  if (result.status !== 0) {
    throw new Error(`Failed to create test image: ${result.stderr}`);
  }
  return tempPng;
}

test('runTesseract success with generated PNG', () => {
  let tempPng: string | null = null;
  try {
    tempPng = createTestImage('Hi');
    const ocrResult = runTesseract(tempPng, 7);
    assert.ok(typeof ocrResult.text === 'string');
    assert.ok(ocrResult.confidence >= 0);
    assert.ok(Array.isArray(ocrResult.symbols));
  } finally {
    if (tempPng) rmSync(tempPng, { force: true });
  }
});

test('runTesseract with whitelist applies character filter', () => {
  let tempPng: string | null = null;
  try {
    tempPng = createTestImage('ABC');
    const ocrResult = runTesseract(tempPng, 7, 'ABC');
    assert.ok(typeof ocrResult.text === 'string');
    assert.ok(ocrResult.confidence >= 0);
  } finally {
    if (tempPng) rmSync(tempPng, { force: true });
  }
});

test('performOcr processes existing crop files', () => {
  const tempDir = resolve(tmpdir(), `ocr-test-${Date.now()}`);
  mkdirSync(tempDir, { recursive: true });
  writeFileSync(resolve(tempDir, 'crop-position-0.png'), 'dummy-image-data');

  const manifest = {
    layout: [
      { position: 0, x: 20, y: 0, width: 100, height: 100, advanceWidth: 1.0, baseline: 80 },
      { position: 6, x: 180, y: 0, width: 100, height: 100, advanceWidth: 1.0, baseline: 80 },
    ],
    totalWidth: 280,
    totalHeight: 100,
  };

  let fullCalls = 0;
  let cropCalls = 0;
  const mockExecutor = (_path: string, psm: number) => {
    if (psm === 7) {
      fullCalls++;
      return symbolsToResult([
        { text: 'H', confidence: 0.98, bbox: { x: 0, y: 0, width: 10, height: 20 } },
      ]);
    }
    cropCalls++;
    return symbolsToResult([
      { text: 'H', confidence: 0.97, bbox: { x: 0, y: 0, width: 10, height: 20 } },
    ]);
  };

  try {
    const observations = performOcr('/fake/full.png', manifest, tempDir, mockExecutor);
    assert.equal(fullCalls, 1);
    assert.equal(cropCalls, 2);
    assert.equal(observations.positionObservations.length, 1);
    assert.equal(observations.positionObservations[0]?.candidate, 'H');
    assert.equal(observations.positionObservations[0]?.confidence, 0.97);
    assert.deepEqual(observations.positionObservations[0]?.alternatives, ['H']);
  } finally {
    rmSync(tempDir, { recursive: true, force: true });
  }
});

test('performOcr selects the higher-confidence crop mode', () => {
  const tempDir = resolve(tmpdir(), `ocr-mode-test-${Date.now()}`);
  mkdirSync(tempDir, { recursive: true });
  writeFileSync(resolve(tempDir, 'crop-position-0.png'), 'dummy-image-data');

  const manifest = {
    layout: [
      { position: 0, x: 20, y: 0, width: 100, height: 100, advanceWidth: 1.0, baseline: 80 },
    ],
    totalWidth: 140,
    totalHeight: 100,
  };
  const mockExecutor = (_path: string, psm: number) =>
    symbolsToResult([
      {
        text: psm === 8 ? 'L' : 'l',
        confidence: psm === 8 ? 0.74 : 0.89,
        bbox: { x: 0, y: 0, width: 10, height: 20 },
      },
    ]);

  try {
    const observations = performOcr('/fake/full.png', manifest, tempDir, mockExecutor);
    assert.equal(observations.positionObservations[0]?.candidate, 'l');
    assert.equal(observations.positionObservations[0]?.confidence, 0.89);
    assert.deepEqual(observations.positionObservations[0]?.alternatives, ['l', 'L']);
  } finally {
    rmSync(tempDir, { recursive: true, force: true });
  }
});

test('runOcrOnce writes output and event files', () => {
  const tempDir = resolve(tmpdir(), `ocr-once-${Date.now()}`);
  mkdirSync(tempDir, { recursive: true });
  const manifestPath = resolve(tempDir, 'manifest.json');
  const outputPath = resolve(tempDir, 'observations.json');
  const eventPath = resolve(tempDir, 'event.json');
  writeFileSync(
    manifestPath,
    JSON.stringify({
      layout: [
        { position: 0, x: 0, y: 0, width: 100, height: 100, advanceWidth: 1.0, baseline: 80 },
        { position: 6, x: 120, y: 0, width: 100, height: 100, advanceWidth: 1.0, baseline: 80 },
      ],
      totalWidth: 220,
      totalHeight: 100,
    }),
  );

  const mockExecutor = (_path: string, psm: number) => {
    if (psm === 7) {
      return symbolsToResult([
        { text: 'H', confidence: 0.98, bbox: { x: 0, y: 0, width: 10, height: 20 } },
      ]);
    }
    return symbolsToResult([
      { text: 'H', confidence: 0.97, bbox: { x: 0, y: 0, width: 10, height: 20 } },
    ]);
  };

  try {
    const observations = runOcrOnce(
      '/fake/full.png',
      manifestPath,
      tempDir,
      outputPath,
      eventPath,
      mockExecutor,
    );
    assert.equal(observations.fullPhrase.rawText, 'H');

    const savedOutput = JSON.parse(readFileSync(outputPath, 'utf-8'));
    assert.deepEqual(savedOutput, observations);

    const savedEvent = JSON.parse(readFileSync(eventPath, 'utf-8'));
    assert.equal(savedEvent.type, 'rg.ocr-observations.v1');
    assert.equal(savedEvent.data.outputMaturity, 70);
  } finally {
    rmSync(tempDir, { recursive: true, force: true });
  }
});

test('runTesseract throws when tesseract binary is missing', () => {
  const originalPath = process.env.PATH;
  process.env.PATH = '/nonexistent';
  try {
    assert.throws(() => runTesseract('/fake.png', 7), /tesseract failed/);
  } finally {
    process.env.PATH = originalPath;
  }
});

test('CLI prints banner with no args', async () => {
  const code = await runCli(['node', 'index.js']);
  assert.equal(code, 0);
});

test('CLI once mode with missing args prints usage', async () => {
  const code = await runCli(['node', 'index.js', 'once']);
  assert.equal(code, 1);
});

test('CLI once mode with valid args runs successfully', async () => {
  const tempDir = resolve(tmpdir(), `ocr-cli-test-${Date.now()}`);
  mkdirSync(tempDir, { recursive: true });
  const imagePath = resolve(tempDir, 'test.png');
  const manifestPath = resolve(tempDir, 'manifest.json');
  const cropsDir = resolve(tempDir, 'crops');
  mkdirSync(cropsDir, { recursive: true });
  writeFileSync(
    imagePath,
    Buffer.from(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
      'base64',
    ),
  );
  writeFileSync(
    manifestPath,
    JSON.stringify({
      layout: [{ position: 0, x: 0, y: 0, width: 10, height: 10, advanceWidth: 1.0, baseline: 8 }],
      totalWidth: 10,
      totalHeight: 10,
    }),
  );

  try {
    const code = await runCli(['node', 'index.js', 'once', imagePath, manifestPath, cropsDir]);
    assert.equal(code, 0);
  } finally {
    rmSync(tempDir, { recursive: true, force: true });
  }
});
