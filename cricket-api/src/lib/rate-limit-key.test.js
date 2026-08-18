import { test } from 'node:test';
import assert from 'node:assert/strict';

import { rateLimitKey, apiKeyNamespace } from './rate-limit-key.js';
import { trustProxySetting } from '../config/index.js';

// RL-1 regression suite.
//
// The old keyGenerator was `req.headers['x-api-key'] || req.ip`, which had two
// verified defects:
//   1. Every CricPro install ships the SAME public key (api_config.dart compiles
//      in a default X-API-Key), so all app traffic shared ONE 100-req/60s bucket
//      — users 429 each other as traffic grows.
//   2. The key was attacker-chosen and unvalidated, so rotating the header gave
//      a fresh bucket per request, bypassing the limiter entirely.
//
// The contract these tests lock in: the IP is ALWAYS part of the bucket key (so
// header rotation cannot escape it), and different keys from the same IP still
// get separate buckets (so distinct legitimate clients do not collide).

const OPTS = { apiKeyHeader: 'x-api-key' };

const req = (ip, headers = {}) => ({ ip, headers });

test('two different app installs on different IPs get different buckets', () => {
  // Both send the identical shipped public key — the old code gave them ONE
  // bucket, which is the outage scenario.
  const shared = 'csk_live_cricpro_app_8f3a2b1c9d';
  const a = rateLimitKey(req('203.0.113.10', { 'x-api-key': shared }), OPTS);
  const b = rateLimitKey(req('203.0.113.11', { 'x-api-key': shared }), OPTS);
  assert.notEqual(a, b, 'same public key on two IPs must not share a bucket');
});

test('rotating the api key cannot escape the IP bucket', () => {
  const ip = '198.51.100.7';
  const keys = new Set();
  for (let i = 0; i < 50; i++) {
    keys.add(rateLimitKey(req(ip, { 'x-api-key': `csk_random_${i}` }), OPTS));
  }
  // Distinct namespaces are fine, but every one must remain scoped to this IP.
  for (const k of keys) {
    assert.ok(k.startsWith(`${ip}|`), `bucket ${k} lost its IP scope`);
  }
});

test('the same request shape always yields the same key (stable bucketing)', () => {
  const r = req('192.0.2.5', { 'x-api-key': 'csk_abc' });
  assert.equal(rateLimitKey(r, OPTS), rateLimitKey(r, OPTS));
});

test('same IP + different keys are separated so real clients do not collide', () => {
  const ip = '192.0.2.9';
  const one = rateLimitKey(req(ip, { 'x-api-key': 'csk_partner_one' }), OPTS);
  const two = rateLimitKey(req(ip, { 'x-api-key': 'csk_partner_two' }), OPTS);
  assert.notEqual(one, two);
});

test('a missing api key falls back to an anon namespace, still IP-scoped', () => {
  const key = rateLimitKey(req('192.0.2.20'), OPTS);
  assert.equal(key, '192.0.2.20|anon');
});

test('blank / whitespace-only keys are treated as anonymous', () => {
  assert.equal(rateLimitKey(req('10.0.0.1', { 'x-api-key': '' }), OPTS), '10.0.0.1|anon');
  assert.equal(rateLimitKey(req('10.0.0.1', { 'x-api-key': '   ' }), OPTS), '10.0.0.1|anon');
});

test('the raw api key never appears in the bucket key', () => {
  const secret = 'csk_super_secret_partner_key';
  const key = rateLimitKey(req('203.0.113.44', { 'x-api-key': secret }), OPTS);
  assert.equal(
    key.includes(secret),
    false,
    'the bucket key is used in logs/Redis — it must not embed the raw secret',
  );
  assert.equal(key.includes('secret'), false);
});

test('a duplicated header (array) is normalised instead of stringifying the array', () => {
  const key = rateLimitKey(req('203.0.113.50', { 'x-api-key': ['csk_a', 'csk_b'] }), OPTS);
  const single = rateLimitKey(req('203.0.113.50', { 'x-api-key': 'csk_a' }), OPTS);
  assert.equal(key, single, 'first value wins; no "csk_a,csk_b" bucket');
});

test('a missing ip does not collapse everyone into one undefined bucket key', () => {
  const key = rateLimitKey({ headers: {} }, OPTS);
  assert.equal(key, 'unknown-ip|anon');
  assert.equal(key.includes('undefined'), false);
});

test('a custom API_KEY_HEADER name is honoured', () => {
  const key = rateLimitKey(
    req('192.0.2.77', { 'x-custom-key': 'csk_z' }),
    { apiKeyHeader: 'x-custom-key' },
  );
  assert.equal(key, `192.0.2.77|${apiKeyNamespace('csk_z')}`);
});

test('apiKeyNamespace is a short, stable, non-reversible digest', () => {
  const ns = apiKeyNamespace('csk_value');
  assert.equal(ns, apiKeyNamespace('csk_value'), 'must be deterministic');
  assert.match(ns, /^[0-9a-f]{16}$/, 'hex digest, truncated');
  assert.notEqual(ns, apiKeyNamespace('csk_value2'));
  assert.equal(apiKeyNamespace(undefined), 'anon');
  assert.equal(apiKeyNamespace(null), 'anon');
  assert.equal(apiKeyNamespace(12345), 'anon', 'non-strings are not hashed');
});

test('a malformed request object does not throw (limiter must never 500)', () => {
  assert.doesNotThrow(() => rateLimitKey(undefined, OPTS));
  assert.doesNotThrow(() => rateLimitKey({}, OPTS));
  assert.doesNotThrow(() => rateLimitKey({ headers: null }, OPTS));
  // Also with no options at all — the default header name applies.
  assert.doesNotThrow(() => rateLimitKey({ ip: '1.2.3.4', headers: {} }));
});

// ---- TRUST_PROXY resolution (the second half of RL-1) ----

test('TRUST_PROXY defaults to true so the documented nginx deployment is unchanged', () => {
  assert.equal(trustProxySetting(undefined), true);
  assert.equal(trustProxySetting(''), true);
  assert.equal(trustProxySetting('   '), true);
});

test('TRUST_PROXY can be turned off for a directly internet-facing deploy', () => {
  for (const v of ['false', 'FALSE', '0', 'no', 'off']) {
    assert.equal(trustProxySetting(v), false, `${v} should disable trustProxy`);
  }
});

test('TRUST_PROXY accepts a numeric hop count', () => {
  assert.equal(trustProxySetting('1'), 1);
  assert.equal(trustProxySetting('2'), 2);
});

test('TRUST_PROXY passes a CIDR allowlist through verbatim', () => {
  assert.equal(trustProxySetting('10.0.0.0/8'), '10.0.0.0/8');
  assert.equal(trustProxySetting('10.0.0.0/8,192.168.0.1'), '10.0.0.0/8,192.168.0.1');
});

test('word-form true stays boolean', () => {
  assert.equal(trustProxySetting('true'), true);
  assert.equal(trustProxySetting('yes'), true);
  assert.equal(trustProxySetting('on'), true);
});
