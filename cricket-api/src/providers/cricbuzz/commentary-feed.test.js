import { test } from 'node:test';
import assert from 'node:assert/strict';

import { buildCommentaryFeed } from './normalizer.js';

// Shapes mirror what normalizeFullCommentary() emits (which maps the raw
// Cricbuzz full-commentary fields verified against the real API).
function ball({ over, ballNbr, event = 'NONE', text, total = 0, batTeamScore = 0, isWicket = false, isFour = false, isSix = false, team = 'Netherlands', ts = ballNbr * 1000 }) {
  return {
    inningsId: 1,
    overNumber: over,
    ballNumber: ballNbr,
    event,
    text,
    rawText: text,
    batTeamName: team,
    batTeamScore,
    runs: { legal: total, total },
    isWicket,
    isFour,
    isSix,
    isOverBreak: event.includes('over-break'),
    timestamp: ts,
  };
}

function note(text, ts = 1) {
  return {
    inningsId: 1, overNumber: 0, ballNumber: 0, event: 'NONE',
    text, rawText: text, batTeamName: 'Netherlands', batTeamScore: 0,
    runs: { legal: 0, total: 0 }, isWicket: false, isFour: false, isSix: false,
    isOverBreak: false, timestamp: ts,
  };
}

test('over-break deliveries are real balls, NOT "END OF OVER" notes', () => {
  const feed = buildCommentaryFeed('159921', [
    { inningsId: 1, teamName: 'Netherlands', commentary: [
      ball({ over: 49.6, ballNbr: 300, event: 'over-break,SIX,HIGHSCORING_OVER', total: 6, isSix: true, batTeamScore: 196, text: 'to deep mid-wicket' }),
      ball({ over: 49.5, ballNbr: 299, event: 'NONE', total: 0, batTeamScore: 190, text: 'no run' }),
    ] },
  ]);
  assert.equal(feed.items.every((i) => i.label !== 'END OF OVER'), true);
  const six = feed.items.find((i) => i.over === '49.6');
  assert.equal(six.type, 'six');
  assert.equal(six.isBall, true);
  assert.equal(six.label, 'SIX');
});

test('normal end-of-over delivery is classified by its real outcome', () => {
  const feed = buildCommentaryFeed('159921', [
    { inningsId: 1, teamName: 'Netherlands', commentary: [
      ball({ over: 47.6, ballNbr: 288, event: 'over-break', total: 1, batTeamScore: 163, text: 'Netravalkar to Roy, 1 run, to cover' }),
    ] },
  ]);
  assert.equal(feed.items[0].type, 'run');
  assert.equal(feed.items[0].label, '1 RUN');
  assert.equal(feed.items[0].isBall, true);
});

test('"THATS OUT!!" echo fragment is dropped (no duplicate wicket)', () => {
  const feed = buildCommentaryFeed('159921', [
    { inningsId: 1, teamName: 'Netherlands', commentary: [
      ball({ over: 40.2, ballNbr: 242, event: 'WICKET', isWicket: true, batTeamScore: 137, text: "Harmeet Singh to Roelof van der Merwe, out, b Harmeet 5(7)" }),
      note('Harmeet Singh to Roelof van der Merwe, THATS OUT!! Bowled!!', 9999),
    ] },
  ]);
  const wickets = feed.items.filter((i) => i.type === 'wicket');
  assert.equal(wickets.length, 1);
  assert.equal(feed.items.some((i) => /THATS OUT/i.test(i.text)), false);
});

test('cumulative score with wickets is correct on each ball', () => {
  const feed = buildCommentaryFeed('159921', [
    { inningsId: 1, teamName: 'Netherlands', commentary: [
      ball({ over: 21.3, ballNbr: 129, event: 'WICKET', isWicket: true, batTeamScore: 75, text: 'run out' }),
      ball({ over: 20.6, ballNbr: 126, event: 'over-break,WICKET', isWicket: true, batTeamScore: 75, text: 'bowled' }),
      ball({ over: 0.1, ballNbr: 1, event: 'NONE', total: 0, batTeamScore: 0, text: 'no run' }),
    ] },
  ]);
  // Two wickets total; the later (21.3) shows 75/2, the earlier (20.6) 75/1.
  const w213 = feed.items.find((i) => i.over === '21.3');
  const w206 = feed.items.find((i) => i.over === '20.6');
  assert.equal(w213.score, '75/2');
  assert.equal(w206.score, '75/1');
});

test('key events exclude normal dot/run balls', () => {
  const feed = buildCommentaryFeed('159921', [
    { inningsId: 1, teamName: 'Netherlands', commentary: [
      ball({ over: 1.1, ballNbr: 1, total: 0, text: 'no run' }),
      ball({ over: 1.2, ballNbr: 2, total: 1, text: '1 run' }),
      ball({ over: 1.3, ballNbr: 3, event: 'FOUR', isFour: true, total: 4, text: 'FOUR' }),
      ball({ over: 1.4, ballNbr: 4, event: 'WICKET', isWicket: true, text: 'out' }),
      note('Drinks are on the field now', 5),
      note('Alexander Roy comes to the crease', 6),
    ] },
  ]);
  const keyEvents = feed.items.filter((i) => i.isKeyEvent);
  // dot + 1-run balls are NOT key events; four, wicket, and drinks ARE.
  assert.equal(keyEvents.some((i) => i.label === 'DOT BALL'), false);
  assert.equal(keyEvents.some((i) => i.label === '1 RUN'), false);
  assert.equal(keyEvents.some((i) => i.type === 'four'), true);
  assert.equal(keyEvents.some((i) => i.type === 'wicket'), true);
  assert.equal(keyEvents.some((i) => i.label === 'DRINKS'), true);
  // "comes to the crease" is INFO, not a key event.
  assert.equal(keyEvents.some((i) => i.label === 'INFO'), false);
});

test('over numbers are clean (never 12.5.7) and notes carry no over', () => {
  const feed = buildCommentaryFeed('159921', [
    { inningsId: 1, teamName: 'Netherlands', commentary: [
      ball({ over: 12.5, ballNbr: 77, total: 0, text: 'no run' }),
      note('Cedric de Lange comes to the crease', 7),
    ] },
  ]);
  const b = feed.items.find((i) => i.isBall);
  const n = feed.items.find((i) => !i.isBall);
  assert.equal(b.over, '12.5');
  assert.equal(n.over, null);
  assert.equal(n.team, null);
  assert.notEqual(n.type, 'dot');
});

test('post-match note is a note, never a dot ball', () => {
  const feed = buildCommentaryFeed('159921', [
    { inningsId: 2, teamName: 'USA', commentary: [
      note('Gill collects the trophy and gives it to his teammates.', 100),
    ] },
  ]);
  assert.equal(feed.items[0].isBall, false);
  assert.notEqual(feed.items[0].type, 'dot');
  assert.equal(feed.items[0].label, 'PRESENTATION');
});

test('merges all innings newest-first (innings 2 before innings 1)', () => {
  const feed = buildCommentaryFeed('159921', [
    { inningsId: 1, teamName: 'Netherlands', commentary: [ball({ over: 1.1, ballNbr: 1, total: 0, text: 'ned ball' })] },
    { inningsId: 2, teamName: 'USA', commentary: [ball({ over: 0.1, ballNbr: 1, total: 1, text: 'usa ball', team: 'USA' })] },
  ]);
  assert.equal(feed.items[0].innings, 2);
  assert.equal(feed.items[feed.items.length - 1].innings, 1);
  assert.equal(feed.innings.length, 2);
});
