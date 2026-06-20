import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  parseBallResultFromCommentary,
  normalizeLiveLineStatus,
  buildLiveLineData,
} from './client.js';

// --- parseBallResultFromCommentary -----------------------------------------

test('commentary "1 run" -> result 1', () => {
  const r = parseBallResultFromCommentary('1 run, to cover');
  assert.equal(r.result, '1');
  assert.equal(r.runs, 1);
  assert.equal(r.event, 'NONE');
});

test('commentary "no run" -> result 0', () => {
  const r = parseBallResultFromCommentary('no run, defended back to the bowler');
  assert.equal(r.result, '0');
  assert.equal(r.runs, 0);
});

test('commentary "FOUR" and "4 runs" -> result 4', () => {
  assert.equal(parseBallResultFromCommentary('FOUR, races away to the fence').result, '4');
  assert.equal(parseBallResultFromCommentary('4 runs, pierces the gap').result, '4');
  assert.equal(parseBallResultFromCommentary('4 runs, pierces the gap').event, 'FOUR');
});

test('commentary "SIX" -> result 6', () => {
  const r = parseBallResultFromCommentary('SIX, into the stands');
  assert.equal(r.result, '6');
  assert.equal(r.event, 'SIX');
});

test('commentary wide -> Wd', () => {
  const r = parseBallResultFromCommentary('wide down the leg side');
  assert.equal(r.result, 'Wd');
  assert.equal(r.event, 'WIDE');
});

test('commentary wicket -> W', () => {
  assert.equal(parseBallResultFromCommentary('OUT! caught at slip').result, 'W');
  assert.equal(parseBallResultFromCommentary('bowled him!').result, 'W');
  assert.equal(parseBallResultFromCommentary('lbw, struck on the pad').event, 'WICKET');
  // "not out" must NOT be parsed as a wicket
  assert.notEqual(parseBallResultFromCommentary('not out, 1 run')?.event, 'WICKET');
});

// --- normalizeLiveLineStatus -----------------------------------------------

test('status unknown becomes live when match context says live', () => {
  assert.equal(normalizeLiveLineStatus('unknown', { isLive: true }), 'live');
  assert.equal(normalizeLiveLineStatus('', { state: 'In Progress' }), 'live');
  assert.equal(normalizeLiveLineStatus('live', {}), 'live');
});

test('status normalizer preserves a real provider status', () => {
  assert.equal(normalizeLiveLineStatus('Complete', { isLive: false }), 'Complete');
  assert.equal(normalizeLiveLineStatus('unknown', {}), 'unknown');
});

// --- buildLiveLineData (integration: commentary -> latestBall + key) --------

function liveFixture(commText) {
  return [
    {
      matchHeader: {
        state: 'In Progress',
        team1: { id: 1, name: 'Alpha', shortName: 'ALP' },
        team2: { id: 2, name: 'Bravo', shortName: 'BRV' },
      },
      miniscore: {
        inningsId: 1,
        matchScoreDetails: {
          inningsScoreList: [
            { inningsId: 1, score: 104, wickets: 8, overs: '14.5', batTeamId: 1 },
          ],
          matchTeamInfo: [
            {
              battingTeamId: 1, battingTeamName: 'Alpha', battingTeamShortName: 'ALP',
              bowlingTeamId: 2, bowlingTeamName: 'Bravo', bowlingTeamShortName: 'BRV',
            },
          ],
        },
      },
    },
    { commentaryList: [{ commText, overNumber: '14.5', batsman: 'X', bowler: 'Y', timestamp: 1000 }] },
    {},
    '121774',
  ];
}

test('latestBallKey does not end with NONE when result can be parsed', () => {
  const out = buildLiveLineData(...liveFixture('1 run, to cover'));
  assert.equal(out.latestBall.result, '1');
  assert.ok(!out.latestBall.key.endsWith('NONE'), `key was ${out.latestBall.key}`);
  assert.ok(out.latestBall.key.endsWith('-1'), `key was ${out.latestBall.key}`);
});

test('buildLiveLineData normalizes status to live for an in-progress match', () => {
  const out = buildLiveLineData(...liveFixture('1 run, to cover'));
  assert.equal(out.status, 'live');
});
