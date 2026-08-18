import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

import { validateProviderBaseUrl, isSafeRedirectTarget } from './url-guard.js';

/**
 * SEC-3 regression suite — SSRF via the admin-configurable provider base_url.
 *
 * The admin provider probe does `axios.get(base_url + path)`
 * (admin/routes/providers.routes.js:348), turning a stored admin value into a
 * server-side request. Severity is bounded — it needs `providers.write` and the
 * probe returns only status/latency/x-cache, never the body — but a status-code
 * plus timing oracle is still enough to port-scan an internal network, so the
 * guard blocks loopback/private/link-local/metadata targets and non-http schemes.
 */

const ALLOWED = [
  'https://api.cricapi.com/v1',
  'http://api.example.com',
  'https://hs-consumer-api.espncricinfo.com/v1',
  'https://www.cricbuzz.com',
  'https://provider.example.co.uk:8443/base/path',
  'https://8.8.8.8/v1', // a public literal IP is legitimate
  'https://[2606:4700:4700::1111]/v1', // public IPv6
];

const BLOCKED = [
  // loopback / this machine
  ['http://localhost:5000', 'localhost'],
  ['http://localhost.localdomain', 'localhost variant'],
  ['http://api.localhost', '.localhost suffix'],
  ['http://127.0.0.1:6379', 'loopback IPv4 (redis)'],
  ['http://127.1.2.3', 'anything in 127/8'],
  ['http://0.0.0.0:8080', '"this network"'],
  ['http://[::1]:5000', 'loopback IPv6'],
  ['http://[::]:5000', 'unspecified IPv6'],
  // cloud metadata — the highest-value SSRF target
  ['http://169.254.169.254/latest/meta-data/', 'AWS/Azure IMDS'],
  ['http://metadata.google.internal/computeMetadata/v1/', 'GCP metadata'],
  ['http://metadata/computeMetadata/v1/', 'GCP metadata short name'],
  ['http://[fe80::1]/x', 'IPv6 link-local'],
  // private ranges
  ['http://10.0.0.5:3306', 'private 10/8 (mysql)'],
  ['http://172.16.31.9', 'private 172.16/12'],
  ['http://172.31.255.254', 'top of 172.16/12'],
  ['http://192.168.1.1', 'private 192.168/16'],
  ['http://100.64.0.1', 'CGNAT 100.64/10'],
  ['http://[fd00::1]/x', 'IPv6 unique-local'],
  ['http://[::ffff:127.0.0.1]/x', 'IPv4-mapped loopback'],
  // multicast / reserved
  ['http://224.0.0.1', 'multicast'],
  ['http://255.255.255.255', 'broadcast'],
  // encodings that decode to loopback
  ['http://2130706433', 'decimal-encoded 127.0.0.1'],
  ['http://0x7f000001', 'hex-encoded 127.0.0.1'],
  // non-http schemes
  ['file:///etc/passwd', 'file scheme'],
  ['gopher://127.0.0.1:6379/_INFO', 'gopher (redis protocol smuggling)'],
  ['ftp://internal.example.com', 'ftp scheme'],
  ['data:text/plain,hi', 'data scheme'],
  // parser confusion
  ['http://user:pass@169.254.169.254/', 'embedded credentials'],
  // malformed / relative
  ['not-a-url', 'not absolute'],
  ['/relative/path', 'relative path'],
  ['', 'empty'],
  ['   ', 'whitespace only'],
];

test('SEC-3: legitimate public provider URLs are allowed', () => {
  for (const url of ALLOWED) {
    const r = validateProviderBaseUrl(url);
    assert.equal(r.ok, true, `${url} should be allowed but was rejected: ${r.error}`);
  }
});

test('SEC-3: SSRF targets are rejected', () => {
  for (const [url, why] of BLOCKED) {
    const r = validateProviderBaseUrl(url);
    assert.equal(r.ok, false, `${url} (${why}) should have been rejected`);
    assert.equal(typeof r.error, 'string');
    assert.ok(r.error.length > 0, 'a rejection must explain itself to the admin');
  }
});

test('SEC-3: non-string / nullish input is rejected, not crashed on', () => {
  for (const v of [undefined, null, 0, {}, [], true, NaN]) {
    const r = validateProviderBaseUrl(v);
    assert.equal(r.ok, false, `${JSON.stringify(v)} should be rejected`);
  }
});

test('SEC-3: surrounding whitespace does not smuggle a blocked host through', () => {
  assert.equal(validateProviderBaseUrl('  http://169.254.169.254/  ').ok, false);
  assert.equal(validateProviderBaseUrl('\thttp://127.0.0.1\n').ok, false);
  // ...and does not break a legitimate URL either.
  assert.equal(validateProviderBaseUrl('  https://api.cricapi.com/v1  ').ok, true);
});

test('SEC-3: case and trailing-dot variants of localhost are rejected', () => {
  for (const h of ['http://LOCALHOST:5000', 'http://LocalHost', 'http://127.0.0.1.']) {
    assert.equal(validateProviderBaseUrl(h).ok, false, `${h} should be rejected`);
  }
});

test('SEC-3: redirect hops are validated with the same rules', () => {
  // axios follows up to 5 redirects, so an allowed public host could bounce the
  // probe into the metadata service. Same predicate must apply per hop.
  assert.equal(isSafeRedirectTarget('https://api.cricapi.com/v2'), true);
  assert.equal(isSafeRedirectTarget('http://169.254.169.254/latest/meta-data/'), false);
  assert.equal(isSafeRedirectTarget('http://127.0.0.1:6379'), false);
  assert.equal(isSafeRedirectTarget('file:///etc/passwd'), false);
});

test('SEC-3: the probe route enforces the guard at fetch time and on redirects', () => {
  // Validating only on write would leave rows created before this change
  // exploitable, and validating only the first URL would leave the redirect
  // bypass open. Assert both call sites still exist.
  const src = readFileSync(new URL('../admin/routes/providers.routes.js', import.meta.url), 'utf8');
  assert.match(src, /validateProviderBaseUrl\(provider\.base_url\)/, 'probe must validate at fetch time');
  assert.match(src, /beforeRedirect/, 'probe must re-validate redirect hops');
  assert.match(src, /isSafeRedirectTarget\(options\.href\)/, 'redirect hook must use the guard');
  // And the write paths (POST + PUT) must validate too.
  const writeChecks = src.match(/validateProviderBaseUrl\(/g) || [];
  assert.ok(writeChecks.length >= 3, `expected >=3 guard call sites, found ${writeChecks.length}`);
});

test('SEC-3: a private-range host is refused with a 400-style error, not silently allowed', () => {
  const r = validateProviderBaseUrl('http://10.1.2.3:9200');
  assert.equal(r.ok, false);
  assert.match(r.error, /private, loopback, or link-local/);
});
