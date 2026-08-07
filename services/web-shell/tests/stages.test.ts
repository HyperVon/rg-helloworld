import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
  PROCESS_NODES,
  PROCESS_EDGES,
  getGraphNodes,
  nodeStatusForStage,
} from '../src/lib/stages.ts';

test('process nodes include all stages', () => {
  assert.ok(PROCESS_NODES.length >= 10);
  assert.ok(PROCESS_NODES.some((n) => n.stage === 'PLANNING'));
  assert.ok(PROCESS_NODES.some((n) => n.stage === 'SUCCEEDED'));
});

test('process edges connect all stages', () => {
  assert.ok(PROCESS_EDGES.length >= 10);
  const sources = new Set(PROCESS_EDGES.map((e) => e.source));
  const targets = new Set(PROCESS_EDGES.map((e) => e.target));
  const allNodes = new Set(PROCESS_NODES.map((n) => n.id));
  for (const s of sources) {
    assert.ok(allNodes.has(s), `edge source ${s} is a valid node`);
  }
  for (const t of targets) {
    assert.ok(allNodes.has(t), `edge target ${t} is a valid node`);
  }
});

test('getGraphNodes returns all nodes', () => {
  const nodes = getGraphNodes('PLANNING', false, 'CREATED', 11);
  assert.equal(nodes.length, PROCESS_NODES.length);
});

test('nodeStatusForStage returns running for current stage', () => {
  const status = nodeStatusForStage(
    'GEOMETRY_EXPANDING',
    'GEOMETRY_EXPANDING',
    false,
    'GEOMETRY_EXPANDING',
  );
  assert.equal(status, 'running');
});

test('nodeStatusForStage returns pending for non-terminal', () => {
  const status = nodeStatusForStage('PLANNING', 'PLANNING', false, 'CREATED');
  assert.equal(status, 'running');
});

test('nodeStatusForStage returns pending for future stage', () => {
  const status = nodeStatusForStage('RASTERIZING', 'PLANNING', false, 'CREATED');
  assert.equal(status, 'pending');
});

test('nodeStatusForStage returns completed for past stage', () => {
  const status = nodeStatusForStage('PLANNING', 'GEOMETRY_EXPANDING', false, 'GEOMETRY_EXPANDING');
  assert.equal(status, 'completed');
});

test('nodeStatusForStage returns completed for terminal success', () => {
  const status = nodeStatusForStage('VALIDATING', 'VALIDATING', true, 'SUCCEEDED');
  assert.equal(status, 'completed');
});

test('nodeStatusForStage returns failed for terminal failure', () => {
  const status = nodeStatusForStage('ASSEMBLING', 'ASSEMBLING', true, 'FAILED');
  assert.equal(status, 'failed');
});

test('getGraphNodes includes glyph count for geometry stage', () => {
  const nodes = getGraphNodes('GEOMETRY_EXPANDING', false, 'GEOMETRY_EXPANDING', 5);
  const geomNode = nodes.find((n) => n.stage === 'GEOMETRY_EXPANDING');
  assert.ok(geomNode);
  assert.deepEqual(geomNode.glyphPositions, [0, 1, 2, 3, 4]);
});
