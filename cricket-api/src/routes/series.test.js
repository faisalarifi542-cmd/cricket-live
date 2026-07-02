import { test } from 'node:test';
import assert from 'node:assert/strict';

import { computeSeriesStatus, summarizeSeriesFormat, buildFormatLabel } from './series.js';

// Date-first series status (mirrors the Flutter classifier's date rules).
// `now` is fixed so the assertions are deterministic.
const now = Date.parse('2026-06-23T12:00:00.000Z');
const day = 24 * 60 * 60 * 1000;

test('end date in the past -> completed', () => {
  assert.equal(
    computeSeriesStatus({ isLive: false, startMs: now - 10 * day, endMs: now - 2 * day, now }),
    'completed',
  );
});

test('start date in the future -> upcoming', () => {
  assert.equal(
    computeSeriesStatus({ isLive: false, startMs: now + 2 * day, endMs: now + 5 * day, now }),
    'upcoming',
  );
});

test('today inside the date window -> ongoing', () => {
  assert.equal(
    computeSeriesStatus({ isLive: false, startMs: now - 1 * day, endMs: now + 3 * day, now }),
    'ongoing',
  );
});

test('a live match wins even with a past end date (stale dates)', () => {
  assert.equal(
    computeSeriesStatus({ isLive: true, startMs: now - 10 * day, endMs: now - 2 * day, now }),
    'ongoing',
  );
});

test('a past end date beats a future match in the same series', () => {
  // endMs already past -> completed, regardless of any later startMs.
  assert.equal(
    computeSeriesStatus({ isLive: false, startMs: now + 5 * day, endMs: now - 1 * day, now }),
    'completed',
  );
});

test('no dates -> unknown ("") so the client does not default it to upcoming', () => {
  assert.equal(
    computeSeriesStatus({ isLive: false, startMs: null, endMs: null, now }),
    '',
  );
});

// --- Real series ranges from the Cricbuzz schedule list, evaluated on Jun 23 ---
// These pin the exact expectations from the bug report so a regression in the
// classifier is caught directly against the named series' true date ranges.
const D = (s) => Date.parse(`${s}T00:00:00.000Z`);

test('Afghanistan tour of India 2026 (Jun 06 - Jun 20) on Jun 23 -> completed', () => {
  assert.equal(
    computeSeriesStatus({ isLive: false, startMs: D('2026-06-06'), endMs: D('2026-06-20'), now }),
    'completed',
  );
});

test('Australia tour of Bangladesh 2026 (Jun 09 - Jun 21) on Jun 23 -> completed', () => {
  assert.equal(
    computeSeriesStatus({ isLive: false, startMs: D('2026-06-09'), endMs: D('2026-06-21'), now }),
    'completed',
  );
});

test('ICC Women’s T20 World Cup 2026 (Jun 12 - Jul 05) on Jun 23 -> ongoing', () => {
  assert.equal(
    computeSeriesStatus({ isLive: false, startMs: D('2026-06-12'), endMs: D('2026-07-05'), now }),
    'ongoing',
  );
});

test('Major League Cricket 2026 (Jun 18 - Jul 18) on Jun 23 -> ongoing', () => {
  assert.equal(
    computeSeriesStatus({ isLive: false, startMs: D('2026-06-18'), endMs: D('2026-07-18'), now }),
    'ongoing',
  );
});

test('India A tour of Sri Lanka 2026 (Jun 25 - Jul 05) on Jun 23 -> upcoming', () => {
  assert.equal(
    computeSeriesStatus({ isLive: false, startMs: D('2026-06-25'), endMs: D('2026-07-05'), now }),
    'upcoming',
  );
});

// --- Authoritative full-series format/count (fixes the match-window undercount) ---
// The series' OWN match list carries every match; the upcoming-window feeds only
// a slice. summarizeSeriesFormat is what turns the real list into the chip label.

test('ICC Women’s T20 World Cup full list -> "33 T20s" (never the 8-match window)', () => {
  // 33 T20 matches, women's event (non-international category -> "T20s").
  const matches = Array.from({ length: 33 }, () => ({ match_format: 't20' }));
  const summary = summarizeSeriesFormat(matches, 'women');
  assert.equal(summary.matchCount, 33);
  assert.equal(summary.format, '33 T20s');
  assert.notEqual(summary.format, '8 T20s');
});

test('mixed bilateral tour -> "1 Test • 3 ODIs • 3 T20Is"', () => {
  const matches = [
    { match_format: 'test' },
    ...Array.from({ length: 3 }, () => ({ match_format: 'odi' })),
    ...Array.from({ length: 3 }, () => ({ match_format: 't20' })),
  ];
  const summary = summarizeSeriesFormat(matches, 'international');
  assert.equal(summary.matchCount, 7);
  assert.equal(summary.format, '1 Test • 3 ODIs • 3 T20Is');
});

test('camelCase matchFormat is also bucketed', () => {
  const summary = summarizeSeriesFormat(
    [{ matchFormat: 'T20' }, { matchFormat: 'T20' }],
    'league',
  );
  assert.equal(summary.format, '2 T20s');
});

test('empty match list -> empty label, null count', () => {
  const summary = summarizeSeriesFormat([], 'international');
  assert.equal(summary.format, '');
  assert.equal(summary.matchCount, null);
});

test('buildFormatLabel: leagues use plain T20, internationals use T20I', () => {
  assert.equal(buildFormatLabel({ T20: 13 }, 'league'), '13 T20s');
  assert.equal(buildFormatLabel({ T20: 2 }, 'international'), '2 T20Is');
});
