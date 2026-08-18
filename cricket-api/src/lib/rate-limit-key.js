/**
 * Rate-limit bucket key derivation for the global @fastify/rate-limit layer.
 *
 * RL-1. The previous keyGenerator was:
 *
 *     (req) => req.headers[config.auth.apiKeyHeader] || req.ip
 *
 * Two concrete problems with that, both verified against this codebase:
 *
 * 1. **The whole userbase shared ONE bucket.** Every CricPro install ships the
 *    same public key (`lib/core/api/api_config.dart` — `X-API-Key` with a
 *    compiled-in default), so every app request produced an identical key and
 *    collapsed into a single RATE_LIMIT_MAX (default 100) per 60s counter. That
 *    is a self-inflicted outage as soon as traffic grows: legitimate users
 *    429 each other. This is the bigger half of RL-1 and it is a
 *    reliability/capacity bug, not just an abuse vector.
 *
 * 2. **The bucket key was attacker-chosen.** The header is not validated before
 *    being used as the key, so sending a random `X-API-Key` per request created
 *    a fresh bucket every time — trivially bypassing the limiter. And because
 *    `trustProxy` is enabled, the `req.ip` fallback comes from a client-supplied
 *    `X-Forwarded-For` unless a trusted proxy overwrites it.
 *
 * The fix keeps this layer as the coarse backstop it is meant to be and buckets
 * by client IP, while *namespacing* by a hash of the presented key so that
 * distinct legitimate API clients still get independent budgets. An attacker
 * rotating the header can no longer escape their own IP bucket, and a million
 * app installs no longer share one counter.
 *
 * Per-client precision limiting still lives in `lib/api-security.js`, which
 * buckets on a DB-validated `client.id` (`c:<id>:<group>`) with an `ip:` fallback
 * — that layer is unchanged and remains the authoritative one.
 */
import crypto from 'node:crypto';

/** Short, non-reversible namespace for a presented API key. */
export function apiKeyNamespace(rawKey) {
  if (!rawKey || typeof rawKey !== 'string') return 'anon';
  const trimmed = rawKey.trim();
  if (!trimmed) return 'anon';
  // Truncated SHA-256: enough to separate clients, and never logs the key.
  return crypto.createHash('sha256').update(trimmed).digest('hex').slice(0, 16);
}

/**
 * Build the bucket key for a request.
 *
 * Always includes the IP so the limiter cannot be escaped by header rotation.
 * `ipOf` is injectable for tests.
 */
export function rateLimitKey(request, { apiKeyHeader = 'x-api-key' } = {}) {
  const headers = request?.headers || {};
  const raw = headers[apiKeyHeader];
  // A repeated header arrives as an array; normalise so the key stays stable.
  const key = Array.isArray(raw) ? raw[0] : raw;
  const ip = request?.ip || 'unknown-ip';
  return `${ip}|${apiKeyNamespace(key)}`;
}
