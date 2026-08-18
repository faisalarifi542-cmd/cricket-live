import { test, after } from 'node:test';
import assert from 'node:assert/strict';
import Fastify from 'fastify';
import cors from '@fastify/cors';

import { resolveCorsCredentials } from './api-security.js';
import { shutdownDb } from './db.js';
import { shutdownRedis } from './redis.js';

// api-security.js reads the security mode / origin allowlist from MySQL and
// Redis, so importing it opens those pools lazily. Release them or the test
// runner keeps the event loop alive and the file times out. The queries
// themselves fail closed when the services are absent, which is exactly the
// behaviour the "hostile origin" assertions rely on.
after(async () => {
  await Promise.allSettled([shutdownDb(), shutdownRedis()]);
});

// CORS-1 regression suite.
//
// server.js used to register @fastify/cors with a hardcoded `credentials: true`
// alongside an origin delegate that reflects ANY origin whenever the security
// mode is not 'enforce' — and the shipped default mode is 'monitor'. Reflected
// origin + Access-Control-Allow-Credentials is the classic dangerous CORS
// combination: it authorises any website to read authenticated responses.
//
// These tests exercise the REAL @fastify/cors delegate wiring (not a mock), so
// they also prove the delegate form is applied globally and that the admin panel
// origin keeps working — a CORS regression would break the panel silently.

const ADMIN_ORIGIN = process.env.ADMIN_PANEL_ORIGIN || 'https://admin.webcrichd.co';
const HOSTILE_ORIGIN = 'https://evil.example.com';

// Mirrors the registration in server.js.
function buildApp() {
  const app = Fastify();
  const baseCorsOptions = {
    // Monitor mode reflects any origin; that behaviour is deliberately preserved.
    origin: (origin, cb) => cb(null, true),
    methods: ['GET', 'POST', 'PUT', 'DELETE'],
    allowedHeaders: ['Content-Type', 'Authorization', 'x-api-key'],
  };
  app.register(cors, () => (req, callback) => {
    resolveCorsCredentials(req.headers.origin || null)
      .catch(() => false)
      .then((credentials) => callback(null, { ...baseCorsOptions, credentials }));
  });
  app.get('/ping', async () => ({ ok: true }));
  return app;
}

async function getCors(app, origin) {
  const res = await app.inject({
    method: 'GET',
    url: '/ping',
    headers: origin ? { origin } : {},
  });
  return {
    status: res.statusCode,
    allowOrigin: res.headers['access-control-allow-origin'],
    allowCredentials: res.headers['access-control-allow-credentials'],
  };
}

test('a hostile origin is NOT granted credentials', async (t) => {
  const app = buildApp();
  t.after(() => app.close());
  await app.ready();

  const res = await getCors(app, HOSTILE_ORIGIN);
  assert.equal(res.status, 200, 'public reads stay open — behaviour preserved');
  assert.notEqual(
    res.allowCredentials,
    'true',
    'reflected origin + credentials would let any site read authenticated responses',
  );
});

test('the admin panel origin still gets credentials (no panel regression)', async (t) => {
  const app = buildApp();
  t.after(() => app.close());
  await app.ready();

  const res = await getCors(app, ADMIN_ORIGIN);
  assert.equal(res.status, 200);
  assert.equal(
    res.allowCredentials,
    'true',
    `${ADMIN_ORIGIN} is the admin panel and must keep credentialed access`,
  );
});

test('a request with no Origin is unaffected (mobile app / server-to-server)', async (t) => {
  const app = buildApp();
  t.after(() => app.close());
  await app.ready();

  const res = await getCors(app, null);
  assert.equal(res.status, 200, 'non-browser clients must never be blocked');
});

test('CORS still applies globally with the delegate form', async (t) => {
  const app = buildApp();
  t.after(() => app.close());
  await app.ready();

  // If the delegate had been registered inside an encapsulated plugin, no
  // Access-Control-Allow-Origin header would be emitted here at all.
  const res = await getCors(app, HOSTILE_ORIGIN);
  assert.ok(
    res.allowOrigin !== undefined,
    'Access-Control-Allow-Origin missing — CORS is no longer applied globally',
  );
});

test('a preflight (OPTIONS) request is answered and not credentialed for strangers', async (t) => {
  const app = buildApp();
  t.after(() => app.close());
  await app.ready();

  const res = await app.inject({
    method: 'OPTIONS',
    url: '/ping',
    headers: {
      origin: HOSTILE_ORIGIN,
      'access-control-request-method': 'GET',
    },
  });
  assert.ok(res.statusCode < 400, `preflight should succeed, got ${res.statusCode}`);
  assert.notEqual(res.headers['access-control-allow-credentials'], 'true');
});

// ---- resolveCorsCredentials unit behaviour ----

test('resolveCorsCredentials allows the admin panel and denies strangers', async () => {
  assert.equal(await resolveCorsCredentials(ADMIN_ORIGIN), true);
  assert.equal(await resolveCorsCredentials(HOSTILE_ORIGIN), false);
});

test('resolveCorsCredentials is case-insensitive on the admin origin', async () => {
  assert.equal(await resolveCorsCredentials(ADMIN_ORIGIN.toUpperCase()), true);
});

test('resolveCorsCredentials returns true when there is no Origin header', async () => {
  assert.equal(await resolveCorsCredentials(null), true);
  assert.equal(await resolveCorsCredentials(undefined), true);
  assert.equal(await resolveCorsCredentials(''), true);
});
