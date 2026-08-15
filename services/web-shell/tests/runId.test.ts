import assert from 'node:assert/strict';
import { test } from 'node:test';

import { isValidRunId, sanitizeRunId } from '../src/lib/runId.ts';

test('accepts a canonical UUID runId', () => {
  assert.equal(isValidRunId('102b7eee-131c-5179-9436-a7cd1e5bbf61'), true);
  assert.equal(isValidRunId('01234567-89AB-CDEF-0123-456789ABCDEF'), true);
});

test('rejects non-UUID input that would break out of an href', () => {
  assert.equal(isValidRunId('" onmouseover="alert(1)'), false);
  assert.equal(isValidRunId('javascript:alert(1)'), false);
  assert.equal(isValidRunId('../../etc/passwd'), false);
  assert.equal(isValidRunId(''), false);
  assert.equal(isValidRunId(null), false);
  assert.equal(isValidRunId(undefined), false);
});

test('sanitizeRunId returns the value when valid and null otherwise', () => {
  const valid = '102b7eee-131c-5179-9436-a7cd1e5bbf61';
  assert.equal(sanitizeRunId(valid), valid);
  assert.equal(sanitizeRunId('"><script>'), null);
});
