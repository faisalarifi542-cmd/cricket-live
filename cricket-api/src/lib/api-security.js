/**
 * Centralized API access security.
 *
 * Protects INCOMING requests to our public API. It does NOT touch outbound
 * provider calls (those use axios directly from the provider layer).
 *
 * Responsibilities:
 *   1. Resolve the endpoint group for a route.
 *   2. Load endpoint rule + allowed origins + blocklist + clients (cached).
 *   3. Enforce: endpoint enabled, blocklist, origin/CORS, API key, client type,
 *      rate limit.
 *   4. Record a request log (without secrets).
 *
 * Enforcement is gated by a mode setting (`apiSecurityMode`) so the rollout can
 * be staged from the Admin Panel:
 *   - 'enforce' (default): reject disallowed requests.
 *   - 'monitor': compute would-be block reason, log it, but allow the request.
 *   - 'off': skip all checks (still resolves group + logs).
 */
import crypto from 'node:crypto';
import { query } from './db.js';
import { getRedis } from './redis.js';
import config from '../config/index.js';
import logger from './logger.js';

const CACHE_TTL_MS = 30_000; // in-process cache for rules/origins/blocklist
// Default rollout-safe mode. 'monitor' logs would-be blocks but allows traffic
// so existing installed apps (without the key yet) keep working. Switch to
// 'enforce' from the Admin Panel once the keyed app version is rolled out.
// Override the initial default with API_SECURITY_MODE=enforce if desired.
const DEFAULT_MODE = (process.env.API_SECURITY_MODE || 'monitor').toLowerCase();
const ADMIN_PANEL_ORIGIN = process.env.ADMIN_PANEL_ORIGIN || 'https://admin.webcrichd.co';

const ALL_CLIENT_TYPES = ['android', 'ios', 'web', 'server', 'admin'];

// In-process caches (refreshed every CACHE_TTL_MS, or on explicit invalidate).
const cache = {
  rules: { data: null, at: 0 },
  origins: { data: null, at: 0 },
  blocklist: { data: null, at: 0 },
  mode: { data: null, at: 0 },
};

export function sha256(str) {
  return crypto.createHash('sha256').update(String(str)).digest('hex');
}

export function maskKey(key) {
  if (!key) return null;
  const s = String(key);
  if (s.length <= 12) return `${s.slice(0, 4)}…`;
  return `${s.slice(0, 8)}…${s.slice(-4)}`;
}

function nowMs() {
  return Date.now();
}

function stripQuery(url) {
  const idx = url.indexOf('?');
  return idx === -1 ? url : url.slice(0, idx);
}

function parseJson(value, fallback) {
  if (value == null) return fallback;
  if (typeof value === 'object') return value;
  try {
    return JSON.parse(value);
  } catch {
    return fallback;
  }
}

// ====================================================
// Cached loaders
// ====================================================
async function loadRules() {
  if (cache.rules.data && nowMs() - cache.rules.at < CACHE_TTL_MS) {
    return cache.rules.data;
  }
  const rows = await query(`SELECT * FROM api_endpoint_rules`).catch(() => []);
  const map = {};
  for (const r of rows) {
    map[r.group_name] = {
      group: r.group_name,
      enabled: !!r.enabled,
      authRequired: r.auth_required || 'api_key',
      allowedClientTypes: parseJson(r.allowed_client_types, ALL_CLIENT_TYPES),
      rateLimitPerMinute: Number(r.rate_limit_per_minute) || 120,
      rateLimitPerHour: Number(r.rate_limit_per_hour) || 0,
      cacheTtlSeconds: Number(r.cache_ttl_seconds) || 0,
      loggingEnabled: r.logging_enabled == null ? true : !!r.logging_enabled,
    };
  }
  cache.rules = { data: map, at: nowMs() };
  return map;
}

async function loadOrigins() {
  if (cache.origins.data && nowMs() - cache.origins.at < CACHE_TTL_MS) {
    return cache.origins.data;
  }
  const rows = await query(
    `SELECT origin, domain, status, allowed_endpoint_groups, rate_limit_per_minute
       FROM api_allowed_origins WHERE status = 'active'`,
  ).catch(() => []);
  const origins = new Map();
  const domains = new Map();
  for (const r of rows) {
    const entry = {
      origin: r.origin || null,
      domain: r.domain || null,
      groups: parseJson(r.allowed_endpoint_groups, null),
      rateLimitPerMinute: Number(r.rate_limit_per_minute) || 0,
    };
    if (r.origin) origins.set(r.origin.toLowerCase(), entry);
    if (r.domain) domains.set(r.domain.toLowerCase(), entry);
  }
  const data = { origins, domains };
  cache.origins = { data, at: nowMs() };
  return data;
}

async function loadBlocklist() {
  if (cache.blocklist.data && nowMs() - cache.blocklist.at < CACHE_TTL_MS) {
    return cache.blocklist.data;
  }
  const rows = await query(
    `SELECT type, value FROM api_blocklist
      WHERE enabled = 1 AND (expires_at IS NULL OR expires_at > NOW())`,
  ).catch(() => []);
  const data = { ip: new Set(), cidr: [], origin: new Set(), domain: new Set(), user_agent: [], client: new Set() };
  for (const r of rows) {
    const t = String(r.type || '').toLowerCase();
    const v = String(r.value || '').trim();
    if (!v) continue;
    if (t === 'ip') data.ip.add(v);
    else if (t === 'cidr') data.cidr.push(v);
    else if (t === 'origin') data.origin.add(v.toLowerCase());
    else if (t === 'domain') data.domain.add(v.toLowerCase());
    else if (t === 'user_agent') data.user_agent.push(v.toLowerCase());
    else if (t === 'client') data.client.add(v);
  }
  cache.blocklist = { data, at: nowMs() };
  return data;
}

export async function getSecurityMode() {
  if (cache.mode.data && nowMs() - cache.mode.at < CACHE_TTL_MS) {
    return cache.mode.data;
  }
  let mode = DEFAULT_MODE;
  try {
    const rows = await query(
      `SELECT setting_value FROM app_settings WHERE setting_key = 'apiSecurityMode' LIMIT 1`,
    );
    if (rows.length) {
      const v = parseJson(rows[0].setting_value, rows[0].setting_value);
      if (typeof v === 'string' && ['enforce', 'monitor', 'off'].includes(v)) mode = v;
    }
  } catch {
    /* ignore — use default */
  }
  cache.mode = { data: mode, at: nowMs() };
  return mode;
}

export function invalidateSecurityCaches() {
  cache.rules = { data: null, at: 0 };
  cache.origins = { data: null, at: 0 };
  cache.blocklist = { data: null, at: 0 };
  cache.mode = { data: null, at: 0 };
}

// ====================================================
// Endpoint group resolution
// ====================================================
export function resolveEndpointGroup(method, rawUrl) {
  const path = stripQuery(rawUrl || '');

  // System / never-block routes.
  if (path === '/health' || path.startsWith('/health/') || path === '/metrics'
    || path === '/providers' || path === '/docs' || path.startsWith('/docs/')
    || path === '/uploads' || path.startsWith('/uploads/')
    || path === '/app/assets') {
    return 'health';
  }
  if (path.startsWith('/admin')) return 'admin';

  // Public analytics ingest — no api-key required (anonymous app telemetry).
  // Auth 'none' + own group so it is rate-limited independently of data routes.
  if (path === '/analytics/events') return 'analytics_ingest';

  // Streams (check before generic /match details).
  if (/\/match\/[^/]+\/streams/.test(path)) return 'streams';
  if (/\/match\/[^/]+\/commentary/.test(path)) return 'commentary';
  if (/\/match\/[^/]+\/(scorecard|squads)/.test(path)) return 'scorecard';

  if (path === '/app/config' || path === '/app-config') return 'app_config';
  if (path.startsWith('/app/device')) return 'notifications_device_register';

  if (path.startsWith('/matches') || path === '/app/home') return 'matches';
  if (path.startsWith('/match') || path.startsWith('/app/match')) return 'match_details';

  if (path.startsWith('/series') || path.startsWith('/app/series')) return 'series';
  if (path.startsWith('/player')) return 'players';
  if (path.startsWith('/team')) return 'teams';
  if (path.startsWith('/news')) return 'news';
  if (path.startsWith('/rankings')) return 'rankings';
  if (path.startsWith('/schedule') || path === '/app/schedule') return 'schedule';

  return 'default';
}

const DEFAULT_RULE = {
  group: 'default',
  enabled: true,
  authRequired: 'api_key',
  allowedClientTypes: ALL_CLIENT_TYPES,
  rateLimitPerMinute: 120,
  rateLimitPerHour: 0,
  cacheTtlSeconds: 0,
  loggingEnabled: true,
};

// ====================================================
// Origin / domain helpers
// ====================================================
function originHost(origin) {
  try {
    return new URL(origin).hostname.toLowerCase();
  } catch {
    return null;
  }
}

function isDevOrigin(origin) {
  if (!config.isDev || !origin) return false;
  const host = originHost(origin);
  return host === 'localhost' || host === '127.0.0.1' || host === '0.0.0.0';
}

export async function isOriginAllowed(origin) {
  if (!origin) return true; // non-browser (mobile/server) — validated via API key
  const lower = origin.toLowerCase();
  if (lower === ADMIN_PANEL_ORIGIN.toLowerCase()) return true;
  if (isDevOrigin(origin)) return true;
  const { origins, domains } = await loadOrigins();
  if (origins.has(lower)) return true;
  const host = originHost(origin);
  if (host && domains.has(host)) return true;
  return false;
}

/** CORS delegate for @fastify/cors. Never throws.
 *  In non-enforce mode it allows all origins (preserves the previous allow-all
 *  behavior so the rollout doesn't break browser clients). In enforce mode it
 *  only allows approved origins (admin panel, dev localhost, api_allowed_origins).
 *
 *  CORS-1: allowing the origin is NOT the same as allowing credentials. See
 *  resolveCorsCredentials below — `credentials: true` is now granted only to
 *  allowlisted origins, so a hostile page can still read public data (unchanged
 *  monitor-mode behaviour) but can no longer make *credentialed* cross-origin
 *  calls that ride a victim's cookies. */
export function corsOriginDelegate(origin, cb) {
  getSecurityMode()
    .then((mode) => {
      if (mode !== 'enforce') return cb(null, true);
      return isOriginAllowed(origin).then((ok) => cb(null, ok));
    })
    .catch(() => cb(null, false));
}

/**
 * Decide whether `Access-Control-Allow-Credentials: true` may be sent (CORS-1).
 *
 * The registration pairs `credentials: true` with an origin delegate that
 * reflects ANY origin whenever the security mode is not 'enforce' — and the
 * default mode is 'monitor'. Reflected-origin + credentials is the classic
 * dangerous CORS combination: it tells the browser that any site may read
 * authenticated responses.
 *
 * Why this was P2 and not P1 here: the admin panel sends a `Bearer` token
 * (admin-panel/lib/api.ts) rather than relying on ambient cookies, and the only
 * cookie is the refresh token, which is httpOnly + sameSite=lax (admin/auth.js)
 * — so `lax` already blocks it on cross-site subrequests. This closes the hole
 * properly instead of depending on those two mitigations staying true.
 *
 * Requests with no Origin (mobile apps, server-to-server) are unaffected: the
 * browser CORS model does not apply to them, and they are validated by API key.
 */
export async function resolveCorsCredentials(origin) {
  if (!origin) return true; // non-browser caller; nothing to protect against here
  try {
    return await isOriginAllowed(origin);
  } catch {
    return false; // fail closed
  }
}

// ====================================================
// API client validation
// ====================================================
async function findClientByKey(apiKey) {
  if (!apiKey) return null;
  const keyHash = sha256(apiKey);
  const redis = getRedis();
  const cacheKey = `apiclient:${keyHash}`;
  try {
    const cached = await redis.get(cacheKey);
    if (cached) return JSON.parse(cached);
  } catch { /* ignore */ }

  const rows = await query(
    `SELECT id, name, client_type, api_key_prefix, allowed_origins, allowed_domains,
            allowed_package_names, allowed_bundle_ids, scopes, status, expires_at,
            rate_limit_per_minute, rate_limit_per_hour, rate_limit_per_day
       FROM api_clients WHERE api_key_hash = ? LIMIT 1`,
    [keyHash],
  ).catch(() => []);
  if (!rows.length) return null;
  const r = rows[0];
  const client = {
    id: r.id,
    name: r.name,
    clientType: r.client_type,
    keyPrefix: r.api_key_prefix,
    allowedOrigins: parseJson(r.allowed_origins, null),
    allowedDomains: parseJson(r.allowed_domains, null),
    allowedPackageNames: parseJson(r.allowed_package_names, null),
    allowedBundleIds: parseJson(r.allowed_bundle_ids, null),
    scopes: parseJson(r.scopes, null),
    status: r.status,
    expiresAt: r.expires_at,
    rateLimitPerMinute: Number(r.rate_limit_per_minute) || 0,
    rateLimitPerHour: Number(r.rate_limit_per_hour) || 0,
    rateLimitPerDay: Number(r.rate_limit_per_day) || 0,
  };
  try {
    await redis.setex(cacheKey, 120, JSON.stringify(client));
  } catch { /* ignore */ }
  return client;
}

export async function invalidateClientKeyCache(apiKey) {
  if (!apiKey) return;
  try {
    await getRedis().del(`apiclient:${sha256(apiKey)}`);
  } catch { /* ignore */ }
}

// ====================================================
// Rate limiting (Redis sliding window per minute + per hour)
// ====================================================
async function checkRateLimit(bucket, limitPerMinute, limitPerHour) {
  if (!bucket) return { ok: true, remaining: null };
  const redis = getRedis();
  let remaining = null;

  if (limitPerMinute > 0) {
    const key = `arl:m:${bucket}`;
    const current = await redis.incr(key).catch(() => 0);
    if (current === 1) await redis.expire(key, 60).catch(() => {});
    remaining = Math.max(0, limitPerMinute - current);
    if (current > limitPerMinute) return { ok: false, remaining: 0, scope: 'minute' };
  }
  if (limitPerHour > 0) {
    const key = `arl:h:${bucket}`;
    const current = await redis.incr(key).catch(() => 0);
    if (current === 1) await redis.expire(key, 3600).catch(() => {});
    if (current > limitPerHour) return { ok: false, remaining: 0, scope: 'hour' };
  }
  return { ok: true, remaining };
}

// ====================================================
// Error responses (intentionally generic — no internal detail)
// ====================================================
const ERRORS = {
  ENDPOINT_DISABLED: { code: 'ENDPOINT_DISABLED', status: 403, message: 'This endpoint is currently unavailable.' },
  BLOCKED: { code: 'API_ACCESS_DENIED', status: 403, message: 'Access denied.' },
  ORIGIN_NOT_ALLOWED: { code: 'ORIGIN_NOT_ALLOWED', status: 403, message: 'This origin is not allowed to access this API.' },
  API_KEY_REQUIRED: { code: 'API_KEY_REQUIRED', status: 401, message: 'A valid API key is required to access this API.' },
  API_KEY_INVALID: { code: 'API_KEY_INVALID', status: 403, message: 'This client is not allowed to access this API.' },
  CLIENT_NOT_ALLOWED: { code: 'API_ACCESS_DENIED', status: 403, message: 'This client is not allowed to access this API.' },
  RATE_LIMITED: { code: 'RATE_LIMIT_EXCEEDED', status: 429, message: 'Rate limit exceeded. Please slow down.' },
};

function sendError(reply, errKey, extra = {}) {
  const e = ERRORS[errKey] || ERRORS.BLOCKED;
  return reply.code(e.status).send({
    success: false,
    error: { code: e.code, message: e.message, ...extra },
  });
}

// ====================================================
// Request logging (no secrets, no full keys)
// ====================================================
export async function logApiRequest(entry) {
  try {
    await query(
      `INSERT INTO api_request_logs
        (method, path, endpoint_group, status_code, ip, origin, referer, user_agent,
         api_client_id, api_key_prefix, allowed, blocked_reason, response_time_ms)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        entry.method || null,
        (entry.path || '').slice(0, 400),
        entry.group || null,
        entry.statusCode || null,
        entry.ip || null,
        (entry.origin || '').slice(0, 255) || null,
        (entry.referer || '').slice(0, 400) || null,
        (entry.userAgent || '').slice(0, 400) || null,
        entry.clientId || null,
        entry.keyPrefix || null,
        entry.allowed ? 1 : 0,
        entry.blockedReason || null,
        entry.responseTimeMs ?? null,
      ],
    );
  } catch (err) {
    logger.debug({ msg: 'api_request_log_failed', error: err.message });
  }
}

// ====================================================
// Main middleware (Fastify preHandler)
// ====================================================
export async function apiSecurityMiddleware(request, reply) {
  const path = stripQuery(request.url || '');

  // WebSocket upgrade + favicon — never gate.
  if (path === '/ws' || path.startsWith('/ws/') || path === '/favicon.ico') return;

  const method = request.method;
  const group = resolveEndpointGroup(method, request.url);
  const origin = request.headers.origin || null;
  const apiKey = request.headers[config.auth.apiKeyHeader] || null;
  const userAgent = request.headers['user-agent'] || '';
  const ip = request.ip;

  const mode = await getSecurityMode();

  // Stash for the onResponse logger.
  request.security = {
    group,
    clientId: null,
    keyPrefix: apiKey ? String(apiKey).slice(0, 12) : null,
    allowed: true,
    blockedReason: null,
    loggingEnabled: true,
  };

  if (mode === 'off') return;

  const enforce = mode === 'enforce';
  // Health is always allowed and never reveals detail.
  const rules = await loadRules();
  const rule = rules[group] || (group === 'admin'
    ? { ...DEFAULT_RULE, authRequired: 'admin_jwt', enabled: true }
    : group === 'health'
      ? { ...DEFAULT_RULE, authRequired: 'none', enabled: true }
      : group === 'analytics_ingest'
        ? { ...DEFAULT_RULE, authRequired: 'none', enabled: true, rateLimitPerMinute: 100 }
        : DEFAULT_RULE);

  request.security.loggingEnabled = rule.loggingEnabled;

  const deny = (errKey, reason, extra) => {
    request.security.allowed = false;
    request.security.blockedReason = reason;
    if (enforce) return sendError(reply, errKey, extra);
    return null; // monitor mode: allow through
  };

  // ---- Blocklist (applies to every group, including admin) ----
  const blocklist = await loadBlocklist();
  if (blocklist.ip.has(ip)) return deny('BLOCKED', 'blocked_ip');
  if (origin && blocklist.origin.has(origin.toLowerCase())) return deny('BLOCKED', 'blocked_origin');
  const host = originHost(origin);
  if (host && blocklist.domain.has(host)) return deny('BLOCKED', 'blocked_domain');
  if (userAgent && blocklist.user_agent.some((ua) => userAgent.toLowerCase().includes(ua))) {
    return deny('BLOCKED', 'blocked_user_agent');
  }

  // ---- Admin routes self-enforce JWT/RBAC; we only applied blocklist. ----
  if (group === 'admin') return;

  // ---- Endpoint enabled? ----
  if (!rule.enabled && group !== 'health') {
    return deny('ENDPOINT_DISABLED', 'endpoint_disabled');
  }

  // ---- Origin / CORS validation for browser requests ----
  if (origin && !(await isOriginAllowed(origin))) {
    return deny('ORIGIN_NOT_ALLOWED', 'origin_not_allowed');
  }

  // ---- Auth ----
  let client = null;
  if (rule.authRequired === 'api_key') {
    if (!apiKey) return deny('API_KEY_REQUIRED', 'missing_api_key');
    client = await findClientByKey(apiKey);
    if (!client) return deny('API_KEY_INVALID', 'invalid_api_key');
    if (client.status !== 'active') return deny('API_KEY_INVALID', `key_${client.status}`);
    if (client.expiresAt && new Date(client.expiresAt) < new Date()) {
      return deny('API_KEY_INVALID', 'key_expired');
    }
    if (blocklist.client.has(String(client.id))) return deny('BLOCKED', 'blocked_client');

    // Client type allowed for this endpoint group?
    const allowedTypes = rule.allowedClientTypes || ALL_CLIENT_TYPES;
    if (allowedTypes.length && !allowedTypes.includes(client.clientType)) {
      return deny('CLIENT_NOT_ALLOWED', 'client_type_not_allowed');
    }
    // Scope (endpoint group) allowed for this client?
    if (Array.isArray(client.scopes) && client.scopes.length && !client.scopes.includes(group)) {
      return deny('CLIENT_NOT_ALLOWED', 'scope_not_allowed');
    }
    // Package name / bundle id (mobile) — only checked when provided + restricted.
    const pkg = request.headers['x-package-name'];
    if (pkg && Array.isArray(client.allowedPackageNames) && client.allowedPackageNames.length
      && !client.allowedPackageNames.includes(pkg)) {
      return deny('CLIENT_NOT_ALLOWED', 'package_not_allowed');
    }
    const bundle = request.headers['x-bundle-id'];
    if (bundle && Array.isArray(client.allowedBundleIds) && client.allowedBundleIds.length
      && !client.allowedBundleIds.includes(bundle)) {
      return deny('CLIENT_NOT_ALLOWED', 'bundle_not_allowed');
    }
    // Origin restriction per client (web clients).
    if (origin && Array.isArray(client.allowedOrigins) && client.allowedOrigins.length
      && !client.allowedOrigins.map((o) => o.toLowerCase()).includes(origin.toLowerCase())) {
      return deny('CLIENT_NOT_ALLOWED', 'client_origin_not_allowed');
    }

    request.security.clientId = client.id;
    request.security.keyPrefix = client.keyPrefix;
    request.apiClient = client;
    // Touch last_used_at (best-effort, throttled by Redis).
    touchClientLastUsed(client.id);
  }

  // ---- Rate limiting ----
  const limitMin = client?.rateLimitPerMinute || rule.rateLimitPerMinute || 0;
  const limitHour = client?.rateLimitPerHour || rule.rateLimitPerHour || 0;
  const bucket = client ? `c:${client.id}:${group}` : `ip:${ip}:${group}`;
  const rl = await checkRateLimit(bucket, limitMin, limitHour);
  if (limitMin > 0) {
    reply.header('X-RateLimit-Limit', limitMin);
    reply.header('X-RateLimit-Remaining', rl.remaining ?? 0);
  }
  if (!rl.ok) return deny('RATE_LIMITED', 'rate_limited');
}

const lastUsedThrottle = new Map();
function touchClientLastUsed(clientId) {
  const now = nowMs();
  const last = lastUsedThrottle.get(clientId) || 0;
  if (now - last < 60_000) return; // at most once a minute per client
  lastUsedThrottle.set(clientId, now);
  query(`UPDATE api_clients SET last_used_at = NOW() WHERE id = ?`, [clientId]).catch(() => {});
}

/**
 * onResponse hook companion — writes the request log using stashed security
 * context. Skips system noise and respects per-rule logging toggle.
 */
export async function apiSecurityResponseLog(request, reply) {
  const sec = request.security;
  if (!sec) return;
  if (sec.loggingEnabled === false) return;
  const path = stripQuery(request.url || '');
  if (path === '/ws' || path === '/favicon.ico' || path === '/metrics') return;

  let responseTimeMs = null;
  if (request.startTime) {
    responseTimeMs = Math.round(Number(process.hrtime.bigint() - request.startTime) / 1e6);
  }

  await logApiRequest({
    method: request.method,
    path,
    group: sec.group,
    statusCode: reply.statusCode,
    ip: request.ip,
    origin: request.headers.origin || null,
    referer: request.headers.referer || request.headers.referrer || null,
    userAgent: request.headers['user-agent'] || null,
    clientId: sec.clientId,
    keyPrefix: sec.keyPrefix,
    allowed: sec.allowed,
    blockedReason: sec.blockedReason,
    responseTimeMs,
  });
}

/** Delete request logs older than `days`. Returns affected rows. */
export async function trimRequestLogs(days = 14) {
  const result = await query(
    `DELETE FROM api_request_logs WHERE created_at < (NOW() - INTERVAL ? DAY)`,
    [Math.max(1, Number(days) || 14)],
  ).catch(() => ({ affectedRows: 0 }));
  return result?.affectedRows || 0;
}
