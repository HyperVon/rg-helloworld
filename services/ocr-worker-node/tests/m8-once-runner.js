import { runOcrOnce } from '../out/index.js';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const fixtures = process.argv[2];
const output = process.argv[3];
const eventOutput = process.argv[4];

const mockExecutor = (_path, psm) => {
  if (psm === 7) {
    return {
      rawText: 'HHH',
      confidence: 0.97,
      symbols: [
        { text: 'H', confidence: 0.98, bbox: { x: 0, y: 0, width: 10, height: 20 } },
        { text: 'H', confidence: 0.98, bbox: { x: 60, y: 0, width: 10, height: 20 } },
        { text: 'H', confidence: 0.98, bbox: { x: 120, y: 0, width: 10, height: 20 } },
      ],
    };
  }
  return {
    rawText: 'H',
    confidence: 0.95,
    symbols: [{ text: 'H', confidence: 0.95, bbox: { x: 0, y: 0, width: 10, height: 20 } }],
  };
};

const observations = runOcrOnce(
  join(fixtures, 'ocr-image.png'),
  join(fixtures, 'manifest.json'),
  join(fixtures, 'crops'),
  output,
  eventOutput,
  mockExecutor,
);

console.log(JSON.stringify({ maturity: '60->70', fullPhrase: observations.fullPhrase.rawText }));
