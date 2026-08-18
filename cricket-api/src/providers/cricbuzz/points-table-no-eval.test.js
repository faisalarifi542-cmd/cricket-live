import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync, existsSync, rmSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import {
  POINTS_TABLE_CHILD_HELPERS,
  buildPointsTableCleanProcessScript,
} from './client.js';

// SEC-1 regression suite.
//
// `fetchPointsTableInCleanProcess` builds a script that is run with
// `spawnSync(process.execPath, ['-e', script])` and fed HTML scraped from
// cricbuzz.com. That HTML is remote input CricPro does not control, and the
// points-table route is reachable UNAUTHENTICATED
// (routes/series.js -> providerManager.execute('getPointsTable') ->
// client.js getPointsTable -> fetchPointsTableInCleanProcess), plus from
// workers/handlers/series.handler.js.
//
// Historically a `JSON.parse` failure fell through to
// `new Function('return (' + objectText + ');')()`, i.e. the scraped slice was
// EXECUTED AS CODE inside an unsandboxed child process. These tests pin the
// behaviour that replaced it: non-JSON is DISCARDED, never evaluated.

const FALLBACK = JSON.stringify({
  seriesId: '1234',
  pointsTable: [{ groupName: 'Points Table', pointsTableInfo: [] }],
  source: 'cricbuzz',
});

// Runs the REAL child helper source (imported, not copied) against a fixture,
// exactly as the production child does on `res.on('end')`. The fixture arrives
// on stdin so it stays a runtime STRING — same as the streamed response body —
// rather than being baked into the script text.
function renderInChild(html) {
  const script = `${POINTS_TABLE_CHILD_HELPERS}
const html = require('node:fs').readFileSync(0, 'utf8');
console.log(renderPointsTableFromHtml(html, ${JSON.stringify(FALLBACK)}));
`;
  return spawnSync(process.execPath, ['-e', script], {
    input: html,
    encoding: 'utf8',
    maxBuffer: 10 * 1024 * 1024,
  });
}

test('SEC-1: the shipped source contains no code-evaluation sink', () => {
  const source = readFileSync(new URL('./client.js', import.meta.url), 'utf8');
  assert.equal(
    /new Function\s*\(/.test(source),
    false,
    'new Function() reintroduced in cricbuzz client.js — scraped HTML must never be evaluated as code',
  );
  assert.equal(/(^|[^.\w])eval\s*\(/m.test(source), false, 'eval() reintroduced in cricbuzz client.js');
  assert.equal(
    /require\(\s*['"]node:vm['"]\s*\)|from\s+['"]node:vm['"]/.test(source),
    false,
    'node:vm is not an acceptable substitute for removing the eval fallback',
  );
});

test('SEC-1: generated child script is syntactically valid (guards the String.raw escaping)', () => {
  const script = buildPointsTableCleanProcessScript('1234', 'some-series-2026');
  const res = spawnSync(process.execPath, ['--check', '-'], { input: script, encoding: 'utf8' });
  assert.equal(res.status, 0, `child script failed node --check:\n${res.stderr}`);
});

test('SEC-1: an IIFE in pointsTableData is NOT executed and yields the empty-table shape', () => {
  // Braces balance so extractJsonObjectAt returns the slice, but it is not JSON.
  // Under the old `new Function` fallback this ran and returned {pwned:true}.
  const html = '<script>{"pointsTableData":{"x":(function(){return {pwned:true};})()}}</script>';
  const res = renderInChild(html);
  assert.equal(res.status, 0);
  assert.equal(res.stdout.includes('pwned'), false, 'injected IIFE was evaluated');
  assert.deepEqual(JSON.parse(res.stdout.trim()), JSON.parse(FALLBACK));
});

test('SEC-1: process.exit() in the payload cannot kill the child', () => {
  // The old fallback would have executed this, making the child exit non-zero,
  // which fetchPointsTableInCleanProcess turns into a thrown 5xx-producing error.
  const html = '<script>{"pointsTableData":{"a":process.exit(7)}}</script>';
  const res = renderInChild(html);
  assert.equal(res.status, 0, 'payload caused a non-zero child exit — code ran');
  assert.deepEqual(JSON.parse(res.stdout.trim()), JSON.parse(FALLBACK));
});

test('SEC-1: side-effecting payload cannot touch the filesystem', () => {
  const marker = fileURLToPath(new URL('./__sec1_should_not_exist.tmp', import.meta.url));
  rmSync(marker, { force: true });
  const html =
    '<script>{"pointsTableData":{"a":require("node:fs").writeFileSync(' +
    JSON.stringify(marker) +
    ',"pwned")}}</script>';
  const res = renderInChild(html);
  assert.equal(res.status, 0);
  assert.deepEqual(JSON.parse(res.stdout.trim()), JSON.parse(FALLBACK));
  assert.equal(
    existsSync(marker),
    false,
    'payload executed and wrote a file — eval sink still live',
  );
});

test('SEC-1: lenient JS-object syntax is rejected, not evaluated (documents the tradeoff)', () => {
  // Unquoted keys / trailing commas were the original excuse for `new Function`.
  // They are now DISCARDED. If cricbuzz ever genuinely ships this, the fix is a
  // tolerant PARSER (JSON5), never code evaluation.
  const html = "<script>{\"pointsTableData\":{teamName:'IND',points:10,}}</script>";
  const res = renderInChild(html);
  assert.equal(res.status, 0);
  assert.deepEqual(JSON.parse(res.stdout.trim()), JSON.parse(FALLBACK));
});

test('valid JSON still parses through unchanged (API response shape preserved)', () => {
  const payload = {
    seriesId: '1234',
    pointsTable: [
      {
        groupName: 'Group A',
        pointsTableInfo: [
          { teamName: 'India', teamShortName: 'IND', matchesPlayed: 3, matchesWon: 2, points: 4, nrr: '+0.512' },
          { teamName: 'Australia', teamShortName: 'AUS', matchesPlayed: 3, matchesWon: 1, points: 2, nrr: '-0.212' },
        ],
      },
    ],
  };
  const html = `<script>{"pointsTableData":${JSON.stringify(payload)}}</script>`;
  const res = renderInChild(html);
  assert.equal(res.status, 0);
  assert.deepEqual(JSON.parse(res.stdout.trim()), payload);
});

test('escaped Next.js payload (\\" encoded) still decodes and parses', () => {
  // decodeNextPayloadText un-escapes the embedded JSON before extraction; this
  // pins that the SEC-1 refactor did not break the String.raw regex escaping.
  const payload = { seriesId: '99', pointsTable: [{ groupName: 'Points Table', pointsTableInfo: [] }] };
  const escaped = JSON.stringify(payload).replace(/"/g, '\\"');
  const html = `<script>{\\"pointsTableData\\":${escaped}}</script>`;
  const res = renderInChild(html);
  assert.equal(res.status, 0);
  assert.deepEqual(JSON.parse(res.stdout.trim()), payload);
});

test('missing pointsTableData key returns the empty-table fallback shape', () => {
  const res = renderInChild('<html><body>no payload here</body></html>');
  assert.equal(res.status, 0);
  const out = JSON.parse(res.stdout.trim());
  assert.deepEqual(out, JSON.parse(FALLBACK));
  // Shape contract relied on by getPointsTable's `.some(...)` check.
  assert.equal(Array.isArray(out.pointsTable), true);
  assert.deepEqual(out.pointsTable[0].pointsTableInfo, []);
  assert.equal(out.source, 'cricbuzz');
});

test('unterminated object (no closing brace) returns the fallback shape', () => {
  const res = renderInChild('<script>{"pointsTableData":{"a":1');
  assert.equal(res.status, 0);
  assert.deepEqual(JSON.parse(res.stdout.trim()), JSON.parse(FALLBACK));
});
