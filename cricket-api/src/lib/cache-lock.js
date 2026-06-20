/**
 * Phase 1a — Cross-process cache-miss hardening.
 * ----------------------------------------------------------------------------
 * ADDITIVE layer on top of the existing in-memory dedupe (runDeduped /
 * controlledFetch inflight maps). Those maps only protect ONE Node process; once
 * the API runs under PM2 cluster mode each worker has its own map, so N processes
 * can still fan out N concurrent provider calls on a cold start / Redis flush.
 *
 * This module adds:
 *   1. `lock:cache:{key}` — a single-flight Redis lock so only ONE process across
 *      the whole cluster rebuilds a missing key; everyone else waits briefly then
 *      serves stale/last-good (or a placeholder).
 *   2. A global provider call-rate budget (`budget:provider:fallback:{minute}`)
 *      shared across all API processes + workers, so a bug or traffic spike can
 *      never turn into a provider call storm.
 *   3. Dedicated logging of PUBLIC-ROUTE provider fallbacks, tagged so the Step 7
 *      dashboards can separate "expected worker traffic" from "cache-miss
 *      fallback".
 *
 * It does NOT replace any existing cache system. Worker (BullMQ) calls do not go
 * through here — they are already distributed-single-flight via job schedulers.
 */
import { getRedis } from './redis.js';
import config from '../config/index.js';
import logger from './logger.js';

const LOCK_PREFIX = 'lock:cache:';
const BUDGET_PREFIX = 'budget:provider:fallback:';

// Unique-ish per-process token so a lock is only released by its holder. No
// Math.random()/Date.now() restriction here (this is runtime infra, not a
// workflow script), but keep it cheap.
let tokenSeq = 0;
function lockToken() {
  tokenSeq += 1;
  return `${process.pid}-${tokenSeq}-${Date.now()}`;
}

function lockKey(key) {
  return `${LOCK_PREFIX}${key}`;
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/**
 * Try to acquire lock:cache:{key}. Returns the token on success, null if someone
 * else already holds it. Best-effort: a Redis error means "could not lock" so the
 * caller falls back to stale/placeholder rather than crashing.
 */
export async function acquireCacheLock(key, ttlMs = config.cacheLock.ttlMs) {
  const redis = getRedis();
  const token = lockToken();
  try {
    // SET NX PX — atomic acquire with auto-expiry so a crashed holder can't
    // deadlock the key. ioredis signature: set(key, val, 'PX', ms, 'NX').
    const res = await redis.set(lockKey(key), token, 'PX', ttlMs, 'NX');
    return res === 'OK' ? token : null;
  } catch (err) {
    // MemoryRedis fallback (local dev) ignores extra args — emulate NX manually.
    try {
      const existing = await redis.get(lockKey(key));
      if (existing) return null;
      await redis.setex(lockKey(key), Math.ceil(ttlMs / 1000), token);
      return token;
    } catch {
      logger.warn(`cache-lock: acquire failed for ${key}: ${err.message}`);
      return null;
    }
  }
}

/** Release lock:cache:{key} only if we still hold it (compare token). */
export async function releaseCacheLock(key, token) {
  if (!token) return;
  const redis = getRedis();
  try {
    const current = await redis.get(lockKey(key));
    if (current === token) await redis.del(lockKey(key));
  } catch {
    // Lock will auto-expire via PX; nothing to do.
  }
}

/**
 * Global provider-fallback budget. Increments a per-minute counter shared across
 * all processes via Redis and returns true if the call is within budget. Worker
 * calls must NOT call this — it is only for public-route cache-miss fallbacks.
 *
 * Fail-open: if Redis errors we allow the call (better to risk one extra provider
 * hit than to blank the app because the budget counter is unreachable).
 */
export async function consumeProviderBudget(reason = 'fallback') {
  if (!config.providerBudget.enabled) return { allowed: true, count: 0, max: Infinity };
  const redis = getRedis();
  const minute = Math.floor(Date.now() / 60000);
  const key = `${BUDGET_PREFIX}${minute}`;
  try {
    const count = await redis.incr(key);
    if (count === 1) await redis.expire(key, 120); // keep two windows for observability
    const max = config.providerBudget.maxPerMinute;
    const allowed = count <= max;
    if (!allowed) {
      logger.warn({ msg: 'provider-budget exceeded', source: 'public-fallback', reason, count, max, minute });
    }
    return { allowed, count, max };
  } catch (err) {
    logger.warn(`provider-budget check failed (fail-open): ${err.message}`);
    return { allowed: true, count: 0, max: config.providerBudget.maxPerMinute };
  }
}

/** Current fallback budget usage for the live minute (for /admin dashboards). */
export async function getProviderBudgetStatus() {
  const redis = getRedis();
  const minute = Math.floor(Date.now() / 60000);
  try {
    const raw = await redis.get(`${BUDGET_PREFIX}${minute}`);
    const count = Number(raw || 0);
    return {
      enabled: config.providerBudget.enabled,
      windowMinute: minute,
      used: count,
      max: config.providerBudget.maxPerMinute,
      remaining: Math.max(config.providerBudget.maxPerMinute - count, 0),
    };
  } catch {
    return { enabled: config.providerBudget.enabled, windowMinute: minute, used: null, max: config.providerBudget.maxPerMinute, remaining: null };
  }
}

/** Structured log for every public-route provider fallback (separate from worker calls). */
export function logProviderFallback(fields) {
  logger.info({ msg: 'provider-fallback', source: 'public-route', ...fields });
}

/**
 * Wrap a value in a timeout. On timeout the underlying promise is NOT cancelled
 * (it keeps running to backfill the cache) — we just stop WAITING on it so the
 * request can serve stale/placeholder instead of hanging.
 */
export function withTimeout(promise, ms, label = 'provider') {
  let timer;
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new Error(`${label} timeout after ${ms}ms`)), ms);
  });
  return Promise.race([promise, timeout]).finally(() => clearTimeout(timer));
}

/**
 * Single-flight cross-process rebuild of a missing cache key.
 *
 * Order (matches the brief's cache-miss protection contract):
 *   1. Acquire lock:cache:{key}. Only the holder may call the provider.
 *   2. Non-holders wait briefly for the holder, then re-read cache (served by
 *      `readCached`); if still nothing, they get whatever `readStale` returns
 *      (last-good) or `onPlaceholder()` (cold start) — they never call provider.
 *   3. The holder checks the provider budget; if exhausted it serves
 *      stale/placeholder instead of calling the provider.
 *   4. The holder calls `rebuild()` under a short timeout. Success → returns
 *      fresh. Failure/timeout → stale → placeholder.
 *
 * Every provider fallback is logged via logProviderFallback({ ... }).
 *
 * @param {object} o
 * @param {string} o.key               cache key being rebuilt (for lock + logs)
 * @param {() => Promise<any>} o.rebuild   calls provider + writes cache, returns data
 * @param {() => Promise<any>} [o.readCached] re-read fresh cache (after waiting on lock)
 * @param {() => Promise<any>} [o.readStale]  read last-good/stale value
 * @param {() => any} [o.onPlaceholder]       safe lightweight value on true cold start
 * @param {string} [o.route]            route label for logs
 * @param {string} [o.reason]           'miss' | 'cold-start' | 'stale-refresh'
 * @returns {Promise<{ data:any, source:string }>}
 */
/**
 * Lighter cross-process single-flight for keys WITHOUT a stale/last-good concept
 * (the layer-B `cacheGetOrFetch` / `cacheGetOrFetchSWR` hard-miss path).
 *
 * Designed to be the producer INSIDE the existing in-memory `runDeduped`, so:
 *   - In a single process (current, non-cluster) the runDeduped collapse means
 *     one producer runs, acquires the lock uncontended, and its resolve/REJECT is
 *     shared with every concurrent caller — error propagation is preserved
 *     exactly as before this change.
 *   - Across PM2 cluster processes, only the lock holder calls the provider; the
 *     others wait briefly and re-read cache (or get null), so the provider is hit
 *     once cluster-wide instead of once-per-process.
 *
 * Unlike rebuildWithLock, the holder's provider error is RE-THROWN (not turned
 * into a placeholder), so callers that depend on cacheGetOrFetch throwing keep
 * working. Waiters never call the provider and never throw.
 *
 * @returns {Promise<any>} the rebuilt data (or null if a waiter found nothing)
 */
export async function singleFlightRebuild({
  key,
  rebuild,
  readCached = async () => null,
  readStale = null,
  route = '',
  reason = 'miss',
}) {
  const token = await acquireCacheLock(key);

  if (!token) {
    const deadline = Date.now() + config.cacheLock.waitMs;
    while (Date.now() < deadline) {
      await sleep(config.cacheLock.pollMs);
      const fresh = await readCached().catch(() => null);
      if (fresh != null) return fresh;
    }
    if (readStale) {
      const stale = await readStale().catch(() => null);
      if (stale != null) {
        logProviderFallback({ route, key, reason, outcome: 'served-stale-waiter' });
        return stale;
      }
    }
    logProviderFallback({ route, key, reason, outcome: 'waiter-empty' });
    return null;
  }

  try {
    const budget = await consumeProviderBudget(reason);
    if (!budget.allowed) {
      if (readStale) {
        const stale = await readStale().catch(() => null);
        if (stale != null) {
          logProviderFallback({ route, key, reason, outcome: 'budget-exhausted-stale', budgetCount: budget.count, budgetMax: budget.max });
          return stale;
        }
      }
      logProviderFallback({ route, key, reason, outcome: 'budget-exhausted-empty', budgetCount: budget.count, budgetMax: budget.max });
      return null;
    }
    const started = Date.now();
    // Provider error/timeout PROPAGATES (caller's runDeduped shares the rejection
    // with all in-process callers — same contract as before).
    const data = await withTimeout(rebuild(), config.cacheLock.fallbackTimeoutMs, `provider:${key}`);
    logProviderFallback({ route, key, reason, outcome: 'provider-ok', providerMs: Date.now() - started, budgetCount: budget.count });
    return data;
  } finally {
    await releaseCacheLock(key, token);
  }
}

export async function rebuildWithLock({
  key,
  rebuild,
  readCached = async () => null,
  readStale = async () => null,
  onPlaceholder = () => null,
  route = '',
  reason = 'miss',
}) {
  const token = await acquireCacheLock(key);

  // --- Not the lock holder: wait briefly, then serve cache/stale/placeholder.
  if (!token) {
    const deadline = Date.now() + config.cacheLock.waitMs;
    while (Date.now() < deadline) {
      await sleep(config.cacheLock.pollMs);
      const fresh = await readCached().catch(() => null);
      if (fresh != null) {
        return { data: fresh, source: 'lock-wait-hit' };
      }
    }
    const stale = await readStale().catch(() => null);
    if (stale != null) {
      logProviderFallback({ route, key, reason, outcome: 'served-stale-waiter' });
      return { data: stale, source: 'stale' };
    }
    logProviderFallback({ route, key, reason, outcome: 'served-placeholder-waiter' });
    return { data: onPlaceholder(), source: 'placeholder' };
  }

  // --- Lock holder: budget check, then provider call under timeout.
  try {
    const budget = await consumeProviderBudget(reason);
    if (!budget.allowed) {
      const stale = await readStale().catch(() => null);
      if (stale != null) {
        logProviderFallback({ route, key, reason, outcome: 'budget-exhausted-stale', budgetCount: budget.count, budgetMax: budget.max });
        return { data: stale, source: 'stale' };
      }
      logProviderFallback({ route, key, reason, outcome: 'budget-exhausted-placeholder', budgetCount: budget.count, budgetMax: budget.max });
      return { data: onPlaceholder(), source: 'placeholder' };
    }

    const started = Date.now();
    try {
      const data = await withTimeout(rebuild(), config.cacheLock.fallbackTimeoutMs, `provider:${key}`);
      logProviderFallback({ route, key, reason, outcome: 'provider-ok', providerMs: Date.now() - started, budgetCount: budget.count });
      return { data, source: 'provider' };
    } catch (err) {
      const stale = await readStale().catch(() => null);
      if (stale != null) {
        logProviderFallback({ route, key, reason, outcome: 'provider-failed-stale', error: err.message, providerMs: Date.now() - started });
        return { data: stale, source: 'stale' };
      }
      logProviderFallback({ route, key, reason, outcome: 'provider-failed-placeholder', error: err.message, providerMs: Date.now() - started });
      return { data: onPlaceholder(), source: 'placeholder' };
    }
  } finally {
    await releaseCacheLock(key, token);
  }
}
