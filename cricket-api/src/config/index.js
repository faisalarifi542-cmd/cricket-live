import 'dotenv/config';
import crypto from 'node:crypto';

const env = (key, fallback) => process.env[key] ?? fallback;
const int = (key, fallback) => parseInt(env(key, fallback), 10);
const bool = (key, fallback) => env(key, String(fallback)) === 'true';

/**
 * Resolve the Fastify `trustProxy` option (RL-1).
 *
 * Unset -> `true`, preserving today's behaviour for the documented
 * CloudPanel/nginx deployment. Explicit `false`/`0`/`no` disables it. Anything
 * else is passed through verbatim so operators can supply a hop count ("1") or
 * a CIDR/IP allowlist ("10.0.0.0/8,192.168.0.1"), which is what you actually
 * want when the app is directly internet-facing.
 */
export function trustProxySetting(raw = process.env.TRUST_PROXY) {
  if (raw === undefined || raw === null || String(raw).trim() === '') return true;
  const value = String(raw).trim();
  const lowered = value.toLowerCase();
  if (['false', '0', 'no', 'off'].includes(lowered)) return false;
  if (['true', '1', 'yes', 'on'].includes(lowered)) {
    // "1" is ambiguous: Fastify reads a number as a hop count. Honour the
    // boolean reading for the words, and the hop count for the digit.
    return lowered === '1' ? 1 : true;
  }
  // Numeric hop count.
  if (/^\d+$/.test(value)) return Number(value);
  // CIDR / comma-separated allowlist — hand straight to Fastify.
  return value;
}

// SEC-2: JWT_SECRET must never fall back to a value that is committed to this
// repository. A hardcoded default is a full admin-authentication bypass: the
// signing key is public, so anyone can forge a `typ: 'admin_access'` token and
// clear adminAuth (src/admin/auth.js:127) with every RBAC permission.
//
// Rules:
//   production  — a missing / known-placeholder / too-short secret is FATAL.
//                 We refuse to boot rather than serve requests that accept
//                 forged tokens (fail closed).
//   development — an explicitly set secret is honoured (weak ones only warn, so
//                 local DX is unchanged). If none is set we generate a random
//                 per-process secret: tokens then stop surviving a restart, but
//                 no published constant is ever a valid signing key.
const MIN_JWT_SECRET_LENGTH = 32;
// Values that have shipped in this repo or its docs, so they must be treated as
// publicly known. Keep in sync with .env.example.
const KNOWN_PLACEHOLDER_SECRETS = new Set([
  'dev-secret-change-in-production',
  'change-this-to-a-long-random-secret',
  'changeme',
  'secret',
]);
// Length alone does not make a secret strong. These patterns catch long-but-
// worthless values, including the real one this repo's own .env shipped with:
// `change-this-to-a-very-long-random-string-in-production-$(date +%s)` — 66
// chars, so it passes the length gate, but dotenv does NOT perform command
// substitution, so `$(date +%s)` stayed literal and the value is fully guessable.
const PLACEHOLDER_SECRET_PATTERNS = [
  { re: /change[-_ ]?(this|me)/i, why: 'still contains a "change-this/change-me" placeholder marker' },
  { re: /\$\(|\$\{|%[A-Z_]+%/, why: 'contains an UNEXPANDED shell/template substitution (e.g. $(date +%s)) — dotenv does not evaluate these, so the literal text is the secret' },
  { re: /^(your|example|sample|dummy|test|placeholder)[-_]/i, why: 'looks like an example value' },
];

export function resolveJwtSecret(isProd) {
  const raw = process.env.JWT_SECRET;
  const secret = typeof raw === 'string' ? raw.trim() : '';
  const patternHit = PLACEHOLDER_SECRET_PATTERNS.find((p) => p.re.test(secret));
  const problem = !secret
    ? 'is not set'
    : KNOWN_PLACEHOLDER_SECRETS.has(secret.toLowerCase())
      ? 'is a publicly-known placeholder value'
      : patternHit
        ? patternHit.why
        : secret.length < MIN_JWT_SECRET_LENGTH
          ? `is shorter than the ${MIN_JWT_SECRET_LENGTH}-character minimum`
          : null;

  if (!problem) return secret;

  if (isProd) {
    throw new Error(
      `FATAL: JWT_SECRET ${problem}. Refusing to start in production — admin ` +
        'tokens would be forgeable. Generate one with:\n' +
        "  node -e \"console.log(require('crypto').randomBytes(48).toString('base64url'))\"\n" +
        'then set JWT_SECRET in the environment (see cricket-api/.env.example).',
    );
  }

  if (!secret) {
    // Dev with nothing configured: ephemeral key, never a published constant.
    console.warn(
      '[config] JWT_SECRET is not set — generated a random secret for this ' +
        'process. Admin sessions will not survive a restart. Set JWT_SECRET in ' +
        'cricket-api/.env to make them persist.',
    );
    return crypto.randomBytes(48).toString('base64url');
  }

  console.warn(
    `[config] JWT_SECRET ${problem}. This is tolerated in development but is a ` +
      'fatal error when NODE_ENV=production.',
  );
  return secret;
}

const isProdEnv = env('NODE_ENV', 'development') === 'production';

const config = Object.freeze({
  env: env('NODE_ENV', 'development'),
  isDev: env('NODE_ENV', 'development') === 'development',
  isProd: isProdEnv,

  server: {
    port: int('PORT', 5000),
    host: env('HOST', '0.0.0.0'),
  },

  db: {
    host: env('DB_HOST', '127.0.0.1'),
    port: int('DB_PORT', 3306),
    user: env('DB_USER', 'webcrichdapi'),
    password: env('DB_PASSWORD', ''),
    database: env('DB_NAME', 'webcrichdapi'),
    pool: {
      min: int('DB_POOL_MIN', 2),
      max: int('DB_POOL_MAX', 20),
    },
  },

  redis: {
    url: env('REDIS_URL', 'redis://localhost:6379'),
    password: env('REDIS_PASSWORD', '') || undefined,
  },

  auth: {
    jwtSecret: resolveJwtSecret(isProdEnv),
    jwtExpiresIn: env('JWT_EXPIRES_IN', '7d'),
    apiKeyHeader: env('API_KEY_HEADER', 'x-api-key'),
  },

  rateLimit: {
    max: int('RATE_LIMIT_MAX', 100),
    timeWindow: int('RATE_LIMIT_WINDOW_MS', 60000),
  },

  // RL-1: `trustProxy` was hardcoded `true`, so `req.ip` came from a
  // client-supplied X-Forwarded-For on any deployment not fronted by a proxy
  // that overwrites it — which lets a caller forge the IP used for rate-limit
  // buckets, blocklist checks and audit logs. Default stays `true` because the
  // documented deployment IS behind CloudPanel/nginx (and flipping it would
  // silently make every client look like 127.0.0.1), but it is now tunable:
  // set TRUST_PROXY to `false`, or to the proxy hop count / CIDR list that
  // Fastify accepts, e.g. TRUST_PROXY=1 or TRUST_PROXY=10.0.0.0/8.
  trustProxy: trustProxySetting(),

  providers: {
    cricbuzz: {
      baseUrl: env('CRICBUZZ_BASE_URL', 'https://www.cricbuzz.com'),
    },
    cricketdata: {
      apiKey: env('CRICKETDATA_API_KEY', ''),
      baseUrl: env('CRICKETDATA_BASE_URL', 'https://api.cricapi.com/v1'),
    },
    cricinfo: {
      baseUrl: env('CRICINFO_BASE_URL', 'https://hs-consumer-api.espncricinfo.com/v1'),
    },
  },

  polling: {
    liveInterval: int('POLL_LIVE_INTERVAL', 3000),
    inningsBreakInterval: int('POLL_INNINGS_BREAK_INTERVAL', 15000),
    upcomingInterval: int('POLL_UPCOMING_INTERVAL', 300000),
    commentaryInterval: int('POLL_COMMENTARY_INTERVAL', 5000),
    scorecardInterval: int('POLL_SCORECARD_INTERVAL', 10000),
  },

  workers: {
    concurrency: int('WORKER_CONCURRENCY', 5),
    limiter: {
      max: int('WORKER_LIMITER_MAX', 10),
      duration: int('WORKER_LIMITER_DURATION', 1000),
    },
  },

  // Phase 1a hardening — cross-process cache-miss protection + provider budget.
  // All additive and safe to leave at defaults. The budget is a CEILING for
  // public-route provider FALLBACK calls (cache misses / cold starts), NOT for
  // scheduled BullMQ worker calls, so normal worker traffic is never throttled.
  cacheLock: {
    // How long a single rebuild may hold lock:cache:{key} before it auto-expires.
    ttlMs: int('CACHE_LOCK_TTL_MS', 5000),
    // How long a non-lock-holder waits for the holder to publish before serving
    // stale/last-good (bounded so requests never hang).
    waitMs: int('CACHE_LOCK_WAIT_MS', 1500),
    pollMs: int('CACHE_LOCK_POLL_MS', 100),
    // Short timeout on the provider call made by the lock holder. On timeout the
    // underlying fetch keeps running to backfill cache; the request serves
    // stale/placeholder instead of hanging.
    fallbackTimeoutMs: int('PROVIDER_FALLBACK_TIMEOUT_MS', 9000),
  },
  providerBudget: {
    enabled: bool('PROVIDER_BUDGET_ENABLED', true),
    // Max public-route provider FALLBACK calls per rolling minute, shared across
    // all PM2 API processes via Redis. Generous by default: steady-state reads
    // are cache hits, so fallbacks should be rare. A storm beyond this is shed
    // to stale/placeholder instead of hammering the provider.
    maxPerMinute: int('PROVIDER_CALL_BUDGET_PER_MIN', 600),
  },

  // Phase 1b — background warmers that keep the heaviest Flutter-facing keys hot
  // so public routes almost never trigger a user-facing provider fallback. These
  // run IN the API process (they reuse the route fetch closures) and are made
  // single-instance under PM2 cluster by a Redis leader lock per warmer plus the
  // Phase 1a per-key lock. Worker/warmer provider calls are EXEMPT from the
  // public-fallback budget (consistent with existing BullMQ workers).
  phase1b: {
    // Master kill switch — false disables ALL Phase 1b warmers instantly.
    enabled: bool('ENABLE_PHASE1B_WARMING', true),
    warmers: {
      appHome: bool('ENABLE_APP_HOME_WARMER', true),
      appConfig: bool('ENABLE_APP_CONFIG_WARMER', true),
      livefast: bool('ENABLE_LIVEFAST_WARMER', true),
      livecomm: bool('ENABLE_LIVECOMM_WARMER', true),
      // Match-detail warming is deferred this phase — off by default.
      matchDetail: bool('ENABLE_MATCH_DETAIL_WARMER', false),
    },
    intervals: {
      appHomeMs: int('WARM_APP_HOME_INTERVAL_MS', 12000),     // home live data 10–15s
      appConfigMs: int('WARM_APP_CONFIG_INTERVAL_MS', 60000), // app config 30–120s
      livefastMs: int('WARM_LIVEFAST_INTERVAL_MS', 4000),     // live score 3–5s
      livecommMs: int('WARM_LIVECOMM_INTERVAL_MS', 8000),     // commentary 5–10s
      matchDetailMs: int('WARM_MATCH_DETAIL_INTERVAL_MS', 12000),
    },
    caps: {
      // Global cap on how many live matches any per-match warmer touches.
      liveMatches: int('MAX_WARM_LIVE_MATCHES', 12),
      // Optional per-warmer overrides (0 = inherit liveMatches).
      livefast: int('MAX_WARM_LIVEFAST_MATCHES', 0),
      livecomm: int('MAX_WARM_LIVECOMM_MATCHES', 0),
      matchDetail: int('MAX_WARM_MATCH_DETAIL_MATCHES', 0),
    },
    // Absolute base URL the home warmer uses to build Image.network URLs when
    // there is no inbound request (e.g. https://api.example.com). Empty = the
    // home warmer leaves relative URLs (route requests still build their own).
    baseUrl: env('PUBLIC_BASE_URL', ''),
    // How long the per-warmer leader lock is held (defaults to ~ the interval).
    leaderLockGraceMs: int('WARM_LEADER_LOCK_GRACE_MS', 500),
  },

  ws: {
    heartbeatInterval: int('WS_HEARTBEAT_INTERVAL', 30000),
    maxConnections: int('WS_MAX_CONNECTIONS', 50000),
  },

  monitoring: {
    logLevel: env('LOG_LEVEL', 'info'),
    metricsEnabled: bool('METRICS_ENABLED', true),
    metricsPort: int('METRICS_PORT', 9090),
  },

  cors: {
    origin: env('CORS_ORIGIN', '*'),
  },
});

export default config;
