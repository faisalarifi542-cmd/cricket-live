import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

import { resolveJwtSecret } from './index.js';

// SEC-2 regression suite.
//
// `config.auth.jwtSecret` previously fell back to the literal
// 'dev-secret-change-in-production' when JWT_SECRET was unset. That string is
// committed to this repository, so any deploy that forgot the env var signed
// admin tokens with a PUBLICLY KNOWN key. An attacker could then mint
// `{ typ: 'admin_access', sub: <id> }`, satisfy adminAuth (admin/auth.js:127)
// and inherit that user's full RBAC permission set — a complete admin bypass.
//
// The fix fails CLOSED in production and never uses a published constant in
// development either.

const CONFIG_PATH = fileURLToPath(new URL('./index.js', import.meta.url));
const ENV_EXAMPLE = fileURLToPath(new URL('../../.env.example', import.meta.url));
// Deliberately non-existent: dotenv silently no-ops on a missing path.
const NO_SUCH_ENV_FILE = fileURLToPath(new URL('./__sec2_no_such.env', import.meta.url));

const STRONG = 'x'.repeat(48);

// Runs resolveJwtSecret in a clean child so this test never mutates the
// process env that other suites (and dotenv) rely on.
function resolveInChild({ nodeEnv, secret }) {
  const script = `
    import(${JSON.stringify(new URL('./index.js', import.meta.url).href)})
      .then((m) => {
        const out = m.resolveJwtSecret(process.env.NODE_ENV === 'production');
        console.log(JSON.stringify({ ok: true, secret: out }));
      })
      .catch((e) => {
        console.log(JSON.stringify({ ok: false, message: e.message }));
      });
  `;
  // config/index.js runs `import 'dotenv/config'`, which would load the repo's
  // real .env and refill JWT_SECRET — masking every "unset/placeholder" case.
  // Point dotenv at a path that does not exist so the child env is authoritative.
  const env = { ...process.env, NODE_ENV: nodeEnv, DOTENV_CONFIG_PATH: NO_SUCH_ENV_FILE };
  if (secret === undefined) {
    delete env.JWT_SECRET;
  } else {
    env.JWT_SECRET = secret;
  }
  const res = spawnSync(process.execPath, ['--input-type=module', '-e', script], {
    encoding: 'utf8',
    env,
  });
  assert.equal(res.status, 0, `child failed: ${res.stderr}`);
  const line = res.stdout.trim().split('\n').filter(Boolean).pop();
  return JSON.parse(line);
}

// Sanity check on the harness itself: if dotenv ever starts bleeding the real
// .env into the child again, this fails loudly instead of silently making the
// "unset" assertions vacuous.
test('SEC-2 harness: the child does not inherit a JWT_SECRET from the repo .env', () => {
  const script = `console.log(JSON.stringify({ seen: process.env.JWT_SECRET ?? null }));`;
  const env = { ...process.env, NODE_ENV: 'development', DOTENV_CONFIG_PATH: NO_SUCH_ENV_FILE };
  delete env.JWT_SECRET;
  const res = spawnSync(process.execPath, ['-e', script], { encoding: 'utf8', env });
  assert.equal(JSON.parse(res.stdout.trim()).seen, null, 'JWT_SECRET leaked into the test child');
});

test('SEC-2: the hardcoded dev secret is gone from the shipped config', () => {
  const src = readFileSync(CONFIG_PATH, 'utf8');
  // It may only appear in the KNOWN_PLACEHOLDER_SECRETS reject-list, never as a
  // fallback passed to env()/?? .
  assert.equal(
    /env\(\s*'JWT_SECRET'\s*,\s*['"][^'"]+['"]\s*\)/.test(src),
    false,
    'JWT_SECRET still has a hardcoded string fallback',
  );
  assert.equal(
    /JWT_SECRET\s*(\|\||\?\?)\s*['"][^'"]+['"]/.test(src),
    false,
    'JWT_SECRET still falls back to a literal via ||/??',
  );
});

test('SEC-2: production REFUSES to boot when JWT_SECRET is unset', () => {
  const r = resolveInChild({ nodeEnv: 'production', secret: undefined });
  assert.equal(r.ok, false, 'production booted without a JWT_SECRET');
  assert.match(r.message, /JWT_SECRET/);
  assert.match(r.message, /not set/);
});

test('SEC-2: production REFUSES the placeholder that used to be the fallback', () => {
  const r = resolveInChild({ nodeEnv: 'production', secret: 'dev-secret-change-in-production' });
  assert.equal(r.ok, false, 'production accepted the old hardcoded secret');
  assert.match(r.message, /publicly-known placeholder/);
});

test('SEC-2: production REFUSES the .env.example placeholder', () => {
  const r = resolveInChild({ nodeEnv: 'production', secret: 'change-this-to-a-long-random-secret' });
  assert.equal(r.ok, false, 'production accepted the .env.example placeholder');
  assert.match(r.message, /publicly-known placeholder/);
});

test('SEC-2: production REFUSES a too-short secret', () => {
  const r = resolveInChild({ nodeEnv: 'production', secret: 'short-key-123' });
  assert.equal(r.ok, false, 'production accepted a 13-char secret');
  assert.match(r.message, /shorter than the 32-character minimum/);
});

test('SEC-2: production REFUSES a long-but-unexpanded $(date) secret (the real .env value)', () => {
  // This exact 66-char string was live in cricket-api/.env. It passes the length
  // gate, but dotenv performs no command substitution, so the literal text —
  // fully guessable from the repo — was the admin token signing key.
  const r = resolveInChild({
    nodeEnv: 'production',
    secret: 'change-this-to-a-very-long-random-string-in-production-$(date +%s)',
  });
  assert.equal(r.ok, false, 'production accepted the unexpanded $(date +%s) secret');
  assert.match(r.message, /change-this|UNEXPANDED/i);
});

test('SEC-2: production REFUSES a long secret containing ${VAR} or %VAR%', () => {
  for (const s of ['prod-secret-${JWT_ROTATION_TOKEN}-abcdefghijklmnop', 'prod-secret-%USERPROFILE%-abcdefghijklmnopqrst']) {
    const r = resolveInChild({ nodeEnv: 'production', secret: s });
    assert.equal(r.ok, false, `production accepted an unexpanded template: ${s}`);
  }
});

test('SEC-2: production ACCEPTS a strong secret (no false positive)', () => {
  const r = resolveInChild({ nodeEnv: 'production', secret: STRONG });
  assert.equal(r.ok, true, `strong secret was rejected: ${r.message}`);
  assert.equal(r.secret, STRONG);
});

test('SEC-2: whitespace padding does not smuggle a placeholder past the check', () => {
  const r = resolveInChild({ nodeEnv: 'production', secret: '  dev-secret-change-in-production  ' });
  assert.equal(r.ok, false, 'padded placeholder was accepted');
});

test('SEC-2: a whitespace-only secret counts as unset, not as a valid long secret', () => {
  const r = resolveInChild({ nodeEnv: 'production', secret: ' '.repeat(40) });
  assert.equal(r.ok, false, 'a 40-space string was accepted as a secret');
  assert.match(r.message, /not set/);
});

test('SEC-2: development still boots with no secret, but NOT with a published constant', () => {
  const r = resolveInChild({ nodeEnv: 'development', secret: undefined });
  assert.equal(r.ok, true, 'development failed to boot without JWT_SECRET');
  assert.notEqual(r.secret, 'dev-secret-change-in-production');
  assert.equal(r.secret.length >= 32, true, 'generated dev secret is too short');
});

test('SEC-2: two dev boots without a secret do not share a key', () => {
  const a = resolveInChild({ nodeEnv: 'development', secret: undefined });
  const b = resolveInChild({ nodeEnv: 'development', secret: undefined });
  assert.notEqual(a.secret, b.secret, 'dev fallback is deterministic — that is a shared static key');
});

test('SEC-2: development honours an explicitly set secret (DX unchanged)', () => {
  const r = resolveInChild({ nodeEnv: 'development', secret: STRONG });
  assert.equal(r.ok, true);
  assert.equal(r.secret, STRONG);
});

test('SEC-2: .env.example documents JWT_SECRET as required', () => {
  const example = readFileSync(ENV_EXAMPLE, 'utf8');
  assert.match(example, /JWT_SECRET=/, '.env.example no longer documents JWT_SECRET');
  assert.match(
    example,
    /REQUIRED/i,
    '.env.example does not flag JWT_SECRET as required — operators need this to deploy safely',
  );
});
