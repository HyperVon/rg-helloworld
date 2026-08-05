import assert from 'node:assert/strict';
import { test } from 'node:test';

import { SERVICE_NAME, SERVICE_VERSION, banner } from '../src/index.js';

test('version matches milestone', () => {
  assert.equal(SERVICE_VERSION, '0.1.0-milestone3');
});

test('version is not empty', () => {
  assert.ok(SERVICE_VERSION.length > 0);
});

test('service name is set', () => {
  assert.equal(SERVICE_NAME, 'temp-worker');
});

test('banner includes service and version', () => {
  assert.match(banner(), /^temp-worker 0\.1\.0-milestone3/);
});

test('banner is deterministic', () => {
  assert.equal(banner(), banner());
});
