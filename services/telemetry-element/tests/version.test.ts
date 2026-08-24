import assert from 'node:assert/strict';
import { test } from 'node:test';

import { SERVICE_NAME, SERVICE_VERSION, banner } from '../src/index.js';

test('version matches milestone 11', () => {
  assert.equal(SERVICE_VERSION, '0.5.0-milestone11');
});

test('service name is set', () => {
  assert.equal(SERVICE_NAME, 'telemetry-element');
});

test('banner includes service and version', () => {
  assert.match(banner(), /^telemetry-element 0\.5\.0-milestone11/);
});
