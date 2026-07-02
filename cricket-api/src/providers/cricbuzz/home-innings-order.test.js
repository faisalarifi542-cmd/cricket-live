import test from 'node:test';
import assert from 'node:assert/strict';

import { extractHomeInnings } from './normalizer.js';

// extractHomeInnings powers /app/home AND /matches/live|upcoming|recent
// (via normalizeHomeMatchList). It must emit an explicit `innings_number`
// ordinal and order a team's innings CHRONOLOGICALLY regardless of the key
// insertion order — this is what stops the Home hero rendering a Test as
// `206/7 & 438/10*` (2nd innings first / wrong star).

test('emits innings_number from the keyed inngs ordinal', () => {
  const out = extractHomeInnings({
    inngs1: { runs: 438, wickets: 10, overs: 114.5 },
    inngs2: { runs: 209, wickets: 7, overs: 71.2 },
  });
  assert.equal(out.length, 2);
  assert.equal(out[0].innings_number, 1);
  assert.equal(out[1].innings_number, 2);
  assert.equal(out[0].runs, 438);
  assert.equal(out[1].runs, 209);
});

test('orders chronologically even when keys arrive reversed', () => {
  // Object key order is not guaranteed; the 2nd innings is listed first here.
  const out = extractHomeInnings({
    inngs2: { runs: 209, wickets: 7, overs: 71.2 },
    inngs1: { runs: 438, wickets: 10, overs: 114.5 },
  });
  assert.deepEqual(
    out.map((i) => i.runs),
    [438, 209],
  );
  assert.deepEqual(
    out.map((i) => i.innings_number),
    [1, 2],
  );
});

test('numeric sort survives double-digit innings ids (no inngs10 < inngs2 bug)', () => {
  const out = extractHomeInnings({
    inngs1: { runs: 10 },
    inngs10: { runs: 100 },
    inngs2: { runs: 20 },
  });
  assert.deepEqual(
    out.map((i) => i.innings_number),
    [1, 2, 10],
  );
});

test('prefers an explicit provider inningsId when present', () => {
  const out = extractHomeInnings({
    inngs1: { runs: 438, inningsId: 1 },
    inngs2: { runs: 209, inningsId: 3 },
  });
  assert.deepEqual(
    out.map((i) => i.innings_number),
    [1, 3],
  );
});

test('empty / missing score yields []', () => {
  assert.deepEqual(extractHomeInnings(null), []);
  assert.deepEqual(extractHomeInnings({}), []);
});
