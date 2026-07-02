import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

import {
  parseScore,
  mapState,
  mapFormat,
  normalizeMatchList,
  normalizeEvent,
  normalizeMatchDetail,
  normalizeScorecard,
  normalizeCommentary,
  normalizeSeriesList,
} from './normalizer.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const fixDir = path.resolve(__dirname, '../../../test/fixtures');
const loadFixture = (name) =>
  JSON.parse(readFileSync(path.join(fixDir, name), 'utf8'));

// --- score-string parsing (the highest-risk normalizer piece) --------------

test('parseScore handles runs/wickets', () => {
  assert.deepEqual(parseScore('298/5'), { runs: 298, wickets: 5, overs: 0 });
});

test('parseScore handles chase string with overs and target', () => {
  assert.deepEqual(parseScore('173 (42.3/50 ov, target 299)'), {
    runs: 173,
    wickets: 0,
    overs: 42.3,
  });
});

test('parseScore handles runs/wickets with overs in parens', () => {
  assert.deepEqual(parseScore('120/3 (18.2 ov)'), {
    runs: 120,
    wickets: 3,
    overs: 18.2,
  });
});

test('parseScore handles all-out plain runs', () => {
  assert.deepEqual(parseScore('350'), { runs: 350, wickets: 0, overs: 0 });
});

test('parseScore handles empty/null', () => {
  assert.deepEqual(parseScore(''), { runs: 0, wickets: 0, overs: 0 });
  assert.deepEqual(parseScore(null), { runs: 0, wickets: 0, overs: 0 });
});

// --- state / format mapping ------------------------------------------------

test('mapState maps ESPN states', () => {
  assert.equal(mapState('in'), 'live');
  assert.equal(mapState('pre'), 'upcoming');
  assert.equal(mapState('post'), 'completed');
  assert.equal(mapState('post', 'Match abandoned'), 'abandoned');
  assert.equal(mapState('post', 'No result'), 'no_result');
});

test('mapFormat maps ESPN event types', () => {
  assert.equal(mapFormat('T20'), 't20');
  assert.equal(mapFormat('ODI'), 'odi');
  assert.equal(mapFormat('TEST'), 'test');
});

// --- match list from the real scoreboard/header fixture --------------------

test('normalizeMatchList produces internal match summaries', () => {
  const raw = loadFixture('espn_header.json');
  const all = normalizeMatchList(raw, null);
  assert.ok(all.length > 0, 'expected at least one match');
  const m = all[0];
  // required internal-schema keys
  for (const k of ['match_id', 'series_id', 'status', 'team1', 'team2', 'score', 'last_updated']) {
    assert.ok(k in m, `missing key ${k}`);
  }
  assert.ok(['live', 'upcoming', 'completed', 'abandoned', 'no_result'].includes(m.status));
  assert.equal(typeof m.team1.name, 'string');
  assert.ok(Array.isArray(m.score.team1));
});

test('normalizeEvent links seriesId/seriesName and parses innings score', () => {
  const raw = loadFixture('espn_header.json');
  const league = raw.sports[0].leagues.find((l) => (l.events || []).some((e) => e.competitors));
  const ev = league.events.find((e) => e.competitors);
  const m = normalizeEvent(ev, league.id, league.name);
  assert.equal(m.series_id, String(league.id));
  assert.equal(m.series_name, league.name);
  assert.equal(m.match_id, String(ev.id));
  // score innings entries carry {runs,wickets,overs}
  const anyInnings = [...m.score.team1, ...m.score.team2];
  if (anyInnings.length) {
    for (const inn of anyInnings) {
      assert.equal(typeof inn.runs, 'number');
      assert.equal(typeof inn.wickets, 'number');
      assert.equal(typeof inn.overs, 'number');
    }
  }
});

// --- match detail + scorecard from the real summary fixture ----------------

test('normalizeMatchDetail returns internal match-detail shape', () => {
  const raw = loadFixture('espn_summary.json');
  const d = normalizeMatchDetail(raw);
  assert.ok(d.match_id);
  assert.ok(d.series_id);
  assert.ok('team1' in d && 'innings' in d.team1);
  assert.ok(Array.isArray(d.team1.innings));
});

test('normalizeScorecard extracts per-player batting and bowling', () => {
  const raw = loadFixture('espn_summary.json');
  const card = normalizeScorecard(raw);
  assert.ok(card, 'expected a scorecard');
  assert.ok(card.innings.length >= 1);
  const inn = card.innings[0];
  for (const k of ['innings_number', 'batting_team', 'total', 'batting', 'bowling']) {
    assert.ok(k in inn, `missing innings key ${k}`);
  }
  assert.equal(typeof inn.total.runs, 'number');
  assert.ok(inn.batting.length > 0, 'expected batsmen');
  const bat = inn.batting[0];
  for (const k of ['player_id', 'name', 'runs', 'balls', 'fours', 'sixes']) {
    assert.ok(k in bat, `missing batting key ${k}`);
  }
  // at least one innings should carry bowlers
  const withBowling = card.innings.find((i) => i.bowling.length > 0);
  assert.ok(withBowling, 'expected at least one innings with bowlers');
  const bowl = withBowling.bowling[0];
  for (const k of ['player_id', 'name', 'overs', 'wickets', 'runs', 'economy']) {
    assert.ok(k in bowl, `missing bowling key ${k}`);
  }
});

test('normalizeScorecard drops phantom (placeholder) innings', () => {
  // ESPN lists a linescore period for BOTH competitors even when only one batted
  // in it; the idle side is runs:0/wickets:0 with overs pre-filled to the format
  // max. Those must NOT become empty innings. This synthetic payload has 2 real
  // innings (211/2, 177/8) each paired with a 0/0-but-overs:20 placeholder.
  const raw = {
    header: {
      competitions: [
        {
          competitors: [
            {
              id: 'A',
              team: { id: 'A', displayName: 'Team A' },
              linescores: [
                { period: 1, runs: 211, wickets: 2, overs: 20 },
                { period: 2, runs: 0, wickets: 0, overs: 20 },
              ],
            },
            {
              id: 'B',
              team: { id: 'B', displayName: 'Team B' },
              linescores: [
                { period: 1, runs: 0, wickets: 0, overs: 20 },
                { period: 2, runs: 177, wickets: 8, overs: 20 },
              ],
            },
          ],
        },
      ],
    },
    rosters: [
      { team: { id: 'A' }, roster: [] },
      { team: { id: 'B' }, roster: [] },
    ],
  };
  const card = normalizeScorecard(raw);
  assert.equal(card.innings.length, 2, 'expected exactly 2 real innings');
  assert.deepEqual(
    card.innings.map((i) => `${i.total.runs}/${i.total.wickets}`),
    ['211/2', '177/8'],
  );
});

// --- commentary from the real playbyplay fixture ---------------------------

test('normalizeCommentary maps ESPN playbyplay items', () => {
  const raw = loadFixture('espn_playbyplay.json');
  const items = normalizeCommentary(raw);
  assert.ok(items.length > 0);
  const c = items[0];
  for (const k of ['id', 'innings_number', 'over', 'event', 'text', 'runs', 'is_wicket', 'is_boundary']) {
    assert.ok(k in c, `missing commentary key ${k}`);
  }
  assert.equal(typeof c.is_wicket, 'boolean');
});

// --- series list -----------------------------------------------------------

test('normalizeSeriesList de-duplicates leagues into series', () => {
  const raw = loadFixture('espn_header.json');
  const list = normalizeSeriesList(raw);
  assert.ok(list.length > 0);
  const ids = list.map((s) => s.series_id);
  assert.equal(ids.length, new Set(ids).size, 'series ids must be unique');
  for (const s of list) {
    assert.ok('series_id' in s && 'name' in s);
  }
});
