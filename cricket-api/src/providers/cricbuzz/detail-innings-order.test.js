import test from 'node:test';
import assert from 'node:assert/strict';

import { normalizeMatchDetail } from './normalizer.js';

// normalizeMatchDetail feeds /match/:id AND /app/live-scores (via projectLiveScore).
// Cricbuzz `inningsScoreList` often lists the CURRENT innings FIRST for a live
// Test. The normalizer must emit each team's innings CHRONOLOGICALLY with the
// REAL `inningsId` ordinal — not a positional index that would reverse the
// score and mis-place the live innings (the Home-hero `222/7 & 438/10*` poll bug).

function buildRaw() {
  return {
    matchHeader: {
      matchId: 129574,
      seriesId: 1,
      seriesName: 'New Zealand tour of England, 2026',
      matchDescription: '3rd Test',
      state: 'In Progress',
      team1: { id: 13, teamId: 13, name: 'New Zealand', shortName: 'NZ' },
      team2: { id: 9, teamId: 9, name: 'England', shortName: 'ENG' },
    },
    miniscore: {
      // current innings is NZ's 2nd (inningsId 3)
      inningsId: 3,
      matchScoreDetails: {
        inningsScoreList: [
          // CURRENT innings listed FIRST (Cricbuzz live ordering)
          { inningsId: 3, batTeamId: 13, batTeamName: 'NZ', score: 222, wickets: 7, overs: 79.4 },
          { inningsId: 1, batTeamId: 13, batTeamName: 'NZ', score: 438, wickets: 10, overs: 114.5 },
          { inningsId: 2, batTeamId: 9, batTeamName: 'ENG', score: 354, wickets: 10, overs: 88.2 },
        ],
      },
    },
  };
}

test('NZ innings come out chronological (438 then 222) with real inningsId', () => {
  const d = normalizeMatchDetail(buildRaw());
  const nz = d.team1.innings;
  assert.equal(nz.length, 2);
  assert.deepEqual(nz.map((i) => i.runs), [438, 222]);
  assert.deepEqual(nz.map((i) => i.innings_number), [1, 3]);
});

test('the live innings (#3) is NOT numbered #1 by position', () => {
  const d = normalizeMatchDetail(buildRaw());
  const live = d.team1.innings.find((i) => i.runs === 222);
  assert.equal(live.innings_number, 3); // real ordinal, not positional 1
});

test('ENG single innings is intact', () => {
  const d = normalizeMatchDetail(buildRaw());
  assert.equal(d.team2.innings.length, 1);
  assert.equal(d.team2.innings[0].runs, 354);
  assert.equal(d.team2.innings[0].innings_number, 2);
});
