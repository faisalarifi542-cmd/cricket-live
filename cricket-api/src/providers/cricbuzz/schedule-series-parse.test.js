import { test } from 'node:test';
import assert from 'node:assert/strict';

import { parseScheduleSeriesPage } from './normalizer.js';

// The /cricket-schedule/series/all page renders the real series LIST (section B)
// as one anchor per series: `/cricket-series/<id>/<slug>/matches` whose `title`
// carries the AUTHORITATIVE series-level date range. This fixture reproduces
// those anchors exactly as they appear in the live page source (HTML-encoded
// apostrophes, the "Matches <range>" title), so the parser is exercised against
// the real shape.
const SECTION_B =
  '<a class="flex" href="/cricket-series/10119/icc-womens-t20-world-cup-2026/matches" ' +
  'title="ICC Women&#x27;s T20 World Cup 2026 Matches 12 Jun 2026 - 5 Jul 2026">' +
  '<div>ICC Women&#x27;s T20 World Cup 2026</div></a>' +
  '<a href="/cricket-series/11641/afghanistan-tour-of-india-2026/matches" ' +
  'title="Afghanistan tour of India 2026 Matches 6 Jun 2026 - 20 Jun 2026">x</a>' +
  '<a href="/cricket-series/12063/australia-tour-of-bangladesh-2026/matches" ' +
  'title="Australia tour of Bangladesh, 2026 Matches 9 Jun 2026 - 21 Jun 2026">x</a>' +
  '<a href="/cricket-series/11793/major-league-cricket-2026/matches" ' +
  'title="Major League Cricket 2026 Matches 18 Jun 2026 - 18 Jul 2026">x</a>';

// Section A: the top current/upcoming match blocks. Their series links have NO
// `/matches` suffix and NO date range — the parser must IGNORE these so it never
// picks up a narrow match-window date instead of the real series span.
const SECTION_A =
  '<div class="WOMEN"><a href="/cricket-series/10119/icc-womens-t20-world-cup" ' +
  'class="block">ICC Women&#x27;s T20 World Cup</a>' +
  '<a href="/live-cricket-scores/121928/scow-vs-nzw-19th-match" title="Scotland Women vs New Zealand Women">live</a></div>';

const FIXTURE = SECTION_A + SECTION_B;

const iso = (s) => s.slice(0, 10);

test('parses the real series schedule list (section B), not the top match blocks', () => {
  const list = parseScheduleSeriesPage(FIXTURE);
  // One entry per series in section B; section A's dateless link is excluded.
  assert.equal(list.length, 4);
  for (const s of list) {
    assert.equal(s.source, 'cricbuzz_series_schedule_page');
  }
});

test('extracts ICC Women’s T20 World Cup 2026 as Jun 12 - Jul 05', () => {
  const s = parseScheduleSeriesPage(FIXTURE).find((x) => x.series_id === '10119');
  assert.ok(s);
  assert.equal(s.name, "ICC Women's T20 World Cup 2026");
  assert.equal(iso(s.start_date), '2026-06-12');
  assert.equal(iso(s.end_date), '2026-07-05');
});

test('extracts Afghanistan tour of India 2026 as Jun 06 - Jun 20', () => {
  const s = parseScheduleSeriesPage(FIXTURE).find((x) => x.series_id === '11641');
  assert.ok(s);
  assert.equal(iso(s.start_date), '2026-06-06');
  assert.equal(iso(s.end_date), '2026-06-20');
});

test('extracts Australia tour of Bangladesh, 2026 as Jun 09 - Jun 21', () => {
  const s = parseScheduleSeriesPage(FIXTURE).find((x) => x.series_id === '12063');
  assert.ok(s);
  assert.equal(iso(s.start_date), '2026-06-09');
  assert.equal(iso(s.end_date), '2026-06-21');
});

test('extracts Major League Cricket 2026 as Jun 18 - Jul 18', () => {
  const s = parseScheduleSeriesPage(FIXTURE).find((x) => x.series_id === '11793');
  assert.ok(s);
  assert.equal(iso(s.start_date), '2026-06-18');
  assert.equal(iso(s.end_date), '2026-07-18');
});

test('ignores section-A match blocks (dateless series links are not emitted)', () => {
  // Section A alone (no /matches anchor, no title range) yields nothing.
  assert.deepEqual(parseScheduleSeriesPage(SECTION_A), []);
});

test('returns an empty list for junk input (never throws)', () => {
  assert.deepEqual(parseScheduleSeriesPage(''), []);
  assert.deepEqual(parseScheduleSeriesPage(null), []);
  assert.deepEqual(parseScheduleSeriesPage('<html>no series here</html>'), []);
});
