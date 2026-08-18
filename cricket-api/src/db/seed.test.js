import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import { resolveSeedCredentials, blockedReason } from './seed.js';

// SEED-1 regression suite.
//
// `src/db/seed.js` used to hardcode `admin` / `admin123` (bcrypt cost 10) plus the
// published API key `csk_demo_key_for_development_only`, with NO environment gate.
// `npm run seed` (package.json) against a production database therefore created a
// role='admin' row in `users` whose password is committed to this repository.
//
// Scope note, so severity is not misremembered: the modern admin panel
// authenticates against the SEPARATE `admin_users` table via adminAuth, which
// also demands `typ === 'admin_access'`, so this never granted panel access. The
// surface it did unlock is the legacy router mounted at /admin/legacy
// (server.js), whose routes are all [jwtAuth, adminOnly]. That is why this is P1
// and not P0 — but a known-password admin account is still unacceptable.
//
// These tests assert the two properties that matter:
//   1. No credential is a hardcoded constant — absent env vars produce randomness.
//   2. The script refuses to run against NODE_ENV=production unless forced.

const SEED_PATH = fileURLToPath(new URL('./seed.js', import.meta.url));
const SEED_SOURCE = readFileSync(SEED_PATH, 'utf8');

test('the literal admin123 is gone from the seed source', () => {
  assert.equal(
    /admin123/.test(SEED_SOURCE),
    false,
    'seed.js must not contain the hardcoded admin123 password',
  );
  assert.equal(
    /csk_demo_key_for_development_only/.test(SEED_SOURCE),
    false,
    'seed.js must not contain the published demo API key',
  );
});

test('bcrypt cost was raised from 10 to 12 (matches admin-seed.js)', () => {
  assert.match(SEED_SOURCE, /BCRYPT_COST\s*=\s*12/);
  assert.equal(
    /bcrypt\.hash\([^,]+,\s*10\s*\)/.test(SEED_SOURCE),
    false,
    'no bcrypt.hash call should still use cost 10',
  );
});

test('with no env vars, the password and api key are random each call', () => {
  const a = resolveSeedCredentials({});
  const b = resolveSeedCredentials({});

  assert.notEqual(a.password, b.password, 'password must not be deterministic');
  assert.notEqual(a.apiKey, b.apiKey, 'api key must not be deterministic');
  assert.equal(a.generatedPassword, true);
  assert.equal(a.generatedApiKey, true);
  // 16 random bytes in base64url.
  assert.ok(a.password.length >= 20, `password too short: ${a.password.length}`);
  assert.match(a.apiKey, /^csk_/, 'api key keeps the csk_ prefix the middleware expects');
  // apiKeyAuth (middleware/auth.js) rejects keys shorter than 20 chars.
  assert.ok(a.apiKey.length >= 20, 'generated key must satisfy the apiKeyAuth format check');
});

test('explicit env values are honoured and reported as not-generated', () => {
  const creds = resolveSeedCredentials({
    SEED_ADMIN_USERNAME: 'ops',
    SEED_ADMIN_EMAIL: 'OPS@Example.COM',
    SEED_ADMIN_PASSWORD: 'a-deliberately-chosen-password',
    SEED_API_KEY: 'csk_pinned_value_for_ci_runs',
  });

  assert.equal(creds.username, 'ops');
  assert.equal(creds.email, 'ops@example.com', 'email is normalised to lower case');
  assert.equal(creds.password, 'a-deliberately-chosen-password');
  assert.equal(creds.apiKey, 'csk_pinned_value_for_ci_runs');
  assert.equal(creds.generatedPassword, false);
  assert.equal(creds.generatedApiKey, false);
});

test('seeding is blocked when NODE_ENV=production', () => {
  const reason = blockedReason({ NODE_ENV: 'production' });
  assert.ok(reason, 'production must be blocked');
  assert.match(reason, /SEED_FORCE=1/, 'the message must state the override');
});

test('production block is case-insensitive', () => {
  assert.ok(blockedReason({ NODE_ENV: 'PRODUCTION' }));
  assert.ok(blockedReason({ NODE_ENV: 'Production' }));
});

test('SEED_FORCE=1 allows a deliberate production override', () => {
  assert.equal(blockedReason({ NODE_ENV: 'production', SEED_FORCE: '1' }), null);
});

test('a non-1 SEED_FORCE does not unlock production', () => {
  for (const value of ['0', 'true', 'yes', '']) {
    assert.ok(
      blockedReason({ NODE_ENV: 'production', SEED_FORCE: value }),
      `SEED_FORCE=${JSON.stringify(value)} must not unlock production`,
    );
  }
});

test('development and unset NODE_ENV still seed normally', () => {
  assert.equal(blockedReason({}), null);
  assert.equal(blockedReason({ NODE_ENV: 'development' }), null);
  assert.equal(blockedReason({ NODE_ENV: 'test' }), null);
});

test('importing seed.js does not execute the seed', () => {
  // The import at the top of this file already happened. If seed() had run on
  // import it would have called getPool() and tried to reach MySQL. Assert the
  // direct-execution guard is present in source so this stays true.
  assert.match(SEED_SOURCE, /process\.argv\[1\]/);
  assert.match(SEED_SOURCE, /fileURLToPath\(import\.meta\.url\)/);
});

test('credentials are not written to the app logger', () => {
  // logger output can be shipped to files/aggregators; secrets belong on stdout
  // for a one-time read only.
  assert.equal(
    /logger\.info\(`?[^)]*\$\{creds\.password\}/.test(SEED_SOURCE),
    false,
    'the generated password must never go through logger.info',
  );
  assert.equal(
    /logger\.info\(`Demo API key/.test(SEED_SOURCE),
    false,
    'the api key must never go through logger.info',
  );
});
