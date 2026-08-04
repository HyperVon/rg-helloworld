import assert from 'node:assert/strict';
import { test } from 'node:test';

import { SERVICE_NAME, SERVICE_VERSION, banner } from '../src/index.js';

test('version matches skeleton', () => {
  assert.equal(SERVICE_VERSION, '0.0.0-skeleton');
});

test('version is not empty', () => {
  assert.ok(SERVICE_VERSION.length > 0);
});

test('service name is set', () => {
  assert.equal(SERVICE_NAME, 'event-gateway');
});

test('banner includes service and version', () => {
  assert.match(banner(), /^event-gateway 0\.0\.0-skeleton/);
});

test('banner is deterministic', () => {
  assert.equal(banner(), banner());
});
