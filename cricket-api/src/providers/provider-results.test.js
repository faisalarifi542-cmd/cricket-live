import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  ProviderFeatureNotSupported,
  ProviderIncompleteData,
  isProviderSentinel,
  isUsableResult,
} from './provider-results.js';

test('isProviderSentinel recognizes both sentinel types', () => {
  assert.equal(isProviderSentinel(new ProviderFeatureNotSupported('m')), true);
  assert.equal(isProviderSentinel(new ProviderIncompleteData('m')), true);
  assert.equal(isProviderSentinel({}), false);
  assert.equal(isProviderSentinel([]), false);
  assert.equal(isProviderSentinel(null), false);
});

test('isUsableResult rejects sentinels and nullish, accepts real data', () => {
  assert.equal(isUsableResult(new ProviderFeatureNotSupported('m')), false);
  assert.equal(isUsableResult(new ProviderIncompleteData('m')), false);
  assert.equal(isUsableResult(null), false);
  assert.equal(isUsableResult(undefined), false);
  // real data — including an empty array — is usable
  assert.equal(isUsableResult([]), true);
  assert.equal(isUsableResult([{ match_id: '1' }]), true);
  assert.equal(isUsableResult({ innings: [] }), true);
  assert.equal(isUsableResult(0), true);
});

test('sentinels carry method + reason for diagnostics', () => {
  const s = new ProviderFeatureNotSupported('getBallsMap', 'no endpoint');
  assert.equal(s.method, 'getBallsMap');
  assert.equal(s.reason, 'no endpoint');
  const d = new ProviderIncompleteData('getScorecard');
  assert.equal(d.method, 'getScorecard');
  assert.ok(d.reason.includes('getScorecard'));
});
