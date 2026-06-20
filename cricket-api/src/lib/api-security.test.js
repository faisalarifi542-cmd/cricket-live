import { test } from 'node:test';
import assert from 'node:assert/strict';

import { resolveEndpointGroup, maskKey, sha256 } from './api-security.js';

test('resolveEndpointGroup maps system routes to health (public)', () => {
  assert.equal(resolveEndpointGroup('GET', '/health'), 'health');
  assert.equal(resolveEndpointGroup('GET', '/health/ready'), 'health');
  assert.equal(resolveEndpointGroup('GET', '/metrics'), 'health');
});

test('resolveEndpointGroup maps admin routes to admin', () => {
  assert.equal(resolveEndpointGroup('POST', '/admin/auth/login'), 'admin');
  assert.equal(resolveEndpointGroup('GET', '/admin/api-security/clients'), 'admin');
});

test('resolveEndpointGroup maps analytics ingest to its own public group', () => {
  assert.equal(resolveEndpointGroup('POST', '/analytics/events'), 'analytics_ingest');
});

test('resolveEndpointGroup separates streams/commentary/scorecard from match details', () => {
  assert.equal(resolveEndpointGroup('GET', '/match/123/streams'), 'streams');
  assert.equal(resolveEndpointGroup('GET', '/app/match/123/streams'), 'streams');
  assert.equal(resolveEndpointGroup('GET', '/match/123/commentary'), 'commentary');
  assert.equal(resolveEndpointGroup('GET', '/match/123/scorecard'), 'scorecard');
  assert.equal(resolveEndpointGroup('GET', '/match/123/squads'), 'scorecard');
  assert.equal(resolveEndpointGroup('GET', '/match/123'), 'match_details');
});

test('resolveEndpointGroup maps list + config + device routes', () => {
  assert.equal(resolveEndpointGroup('GET', '/matches/live'), 'matches');
  assert.equal(resolveEndpointGroup('GET', '/app/home'), 'matches');
  assert.equal(resolveEndpointGroup('GET', '/app/config'), 'app_config');
  assert.equal(resolveEndpointGroup('GET', '/app-config'), 'app_config');
  assert.equal(resolveEndpointGroup('POST', '/app/device/register'), 'notifications_device_register');
});

test('resolveEndpointGroup maps content routes', () => {
  assert.equal(resolveEndpointGroup('GET', '/series/9'), 'series');
  assert.equal(resolveEndpointGroup('GET', '/player/9'), 'players');
  assert.equal(resolveEndpointGroup('GET', '/team/9'), 'teams');
  assert.equal(resolveEndpointGroup('GET', '/news'), 'news');
  assert.equal(resolveEndpointGroup('GET', '/rankings/odi'), 'rankings');
  assert.equal(resolveEndpointGroup('GET', '/schedule/live'), 'schedule');
});

test('resolveEndpointGroup ignores query string', () => {
  assert.equal(resolveEndpointGroup('GET', '/matches/live?foo=bar'), 'matches');
});

test('resolveEndpointGroup falls back to default for unknown routes', () => {
  assert.equal(resolveEndpointGroup('GET', '/something/unknown'), 'default');
});

test('maskKey never exposes the full key', () => {
  const key = 'csk_abcdefghijklmnopqrstuvwxyz0123456789';
  const masked = maskKey(key);
  assert.ok(!masked.includes('mnopqrstuv'));
  assert.ok(masked.startsWith('csk_'));
  assert.equal(maskKey(null), null);
});

test('sha256 is stable and hex-encoded', () => {
  assert.equal(sha256('hello'), sha256('hello'));
  assert.match(sha256('hello'), /^[0-9a-f]{64}$/);
  assert.notEqual(sha256('a'), sha256('b'));
});
