import Redis from 'ioredis';
import config from '../config/index.js';
import logger from './logger.js';
// Phase 1a — cross-process single-flight + provider budget for cache-miss
// rebuilds. Imported lazily-safe: cache-lock.js only calls getRedis() at
// runtime, so the import cycle is hoisting-safe.
import { singleFlightRebuild } from './cache-lock.js';

/** @type {Redis} */
let client;
/** @type {Redis} */
let subscriber;

class MemoryRedis {
  constructor() {
    this.status = 'memory';
    this.store = new Map();
  }

  _read(key) {
    const item = this.store.get(key);
    if (!item) return null;
    if (item.expiresAt && item.expiresAt <= Date.now()) {
      this.store.delete(key);
      return null;
    }
    return item.value;
  }

  async get(key) { return this._read(key); }
  async set(key, value) { this.store.set(key, { value, expiresAt: null }); return 'OK'; }
  async setex(key, ttl, value) { this.store.set(key, { value, expiresAt: Date.now() + ttl * 1000 }); return 'OK'; }
  async del(...keys) { let count = 0; for (const key of keys.flat()) if (this.store.delete(key)) count += 1; return count; }
  async incr(key) { const next = Number(this._read(key) || 0) + 1; await this.set(key, String(next)); return next; }
  async expire(key, ttl) { const value = this._read(key); if (value == null) return 0; this.store.set(key, { value, expiresAt: Date.now() + ttl * 1000 }); return 1; }
  async dbsize() { return this.store.size; }
  async info() { return 'used_memory_human:memory-fallback'; }
  async flushdb() { this.store.clear(); return 'OK'; }
  async keys(pattern = '*') {
    const regex = new RegExp(`^${pattern.replace(/[.+^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '.*')}$`);
    return [...this.store.keys()].filter((key) => regex.test(key));
  }
  async scan(cursor, _match, pattern = '*') { return ['0', await this.keys(pattern)]; }
  async publish() { return 0; }
  subscribe() {}
  on() { return this; }
  async quit() {}
}

function createClient(name = 'default') {
  const c = new Redis(config.redis.url, {
    password: config.redis.password,
    maxRetriesPerRequest: null,
    enableReadyCheck: true,
    retryStrategy(times) {
      const delay = Math.min(times * 200, 5000);
      logger.warn(`Redis ${name} reconnecting in ${delay}ms (attempt ${times})`);
      return delay;
    },
    lazyConnect: false,
  });

  c.on('connect', () => logger.info(`Redis ${name} connected`));
  c.on('error', (err) => logger.error(`Redis ${name} error: ${err.message}`));

  return c;
}

export function getRedis() {
  if (!client) {
    client = createClient('main');
    client.on('error', () => {
      if (client?.status !== 'ready' && client?.status !== 'memory') {
        logger.warn('Redis unavailable; using in-memory cache fallback for this local process');
        client = new MemoryRedis();
      }
    });
  }
  return client;
}

export function getSubscriber() {
  if (!subscriber) {
    subscriber = createClient('subscriber');
    subscriber.on('error', () => {
      if (subscriber?.status !== 'ready' && subscriber?.status !== 'memory') {
        subscriber = new MemoryRedis();
      }
    });
  }
  return subscriber;
}

// TTL constants (seconds)
export const TTL = Object.freeze({
  LIVE_SCORE: 15,
  LIVE_LIST: 8, // live match LIST cache, aligned with Flutter Home 8s poll. Separate from LIVE_SCORE so match-detail TTL is unaffected.
  COMMENTARY: 5,
  SCORECARD: 5,
  MATCH_INFO: 10,
  MATCH_LIST: 20,
  MATCH_STATS: 20,
  MATCH_OVERS: 5,
  SERIES: 300,
  PLAYER: 3600,
  TEAM: 3600,
  POINTS_TABLE: 300,
  UPCOMING: 300,
  RECENT: 120,
  HOME_MATCHES: 20,
  NEWS_LIST: 300,
  NEWS_DETAIL: 3600,
  SERIES_STATS_TYPES: 21600,
  SERIES_STATS_TABLE: 3600,
  SERIES_NEWS: 900,
  MATCH_NEWS: 900,
  FULL_COMMENTARY_LIVE: 15,
  FULL_COMMENTARY_DONE: 21600,
  HIGHLIGHTS_LIVE: 20,
  HIGHLIGHTS_DONE: 21600,
  BALLS_MAP_LIVE: 30,
  BALLS_MAP_DONE: 21600,
  OVER_BY_OVER_LIVE: 15,
  OVER_BY_OVER_DONE: 21600,
  SCHEDULE: 1200,
  MATCH_SUMMARY: 3600,
  SQUADS: 1800, // 30 minutes
  LIVE_LINE: 5, // 5 seconds - very short for live data
  MATCH_INFO_DETAILED: 300, // 5 minutes for detailed match info
  LIVE_CENTER_LIVE: 4, // merged live-center while the match is in progress
  LIVE_CENTER_DONE: 600, // merged live-center for finished matches
});

// Key builders
export const KEYS = Object.freeze({
  matchLive: (id) => `match:${id}:live`,
  matchCommentary: (id) => `match:${id}:commentary`,
  matchScorecard: (id) => `match:${id}:scorecard`,
  matchInfo: (id) => `match:${id}:info`,
  matchStats: (id) => `match:${id}:stats`,
  matchOvers: (id) => `match:${id}:overs`,
  matchesList: (type) => `matches:${type}`,
  homeMatches: () => 'home:matches',
  series: (id) => `series:${id}`,
  seriesList: () => 'series:list',
  player: (id) => `player:${id}`,
  team: (id) => `team:${id}`,
  pointsTable: (seriesId) => `points:${seriesId}`,
  newsList: (cursor) => `news:list:${cursor || 'default'}`,
  newsDetail: (id) => `news:detail:${id}`,
  seriesStatsTypes: (seriesId) => `series:${seriesId}:stats:types`,
  seriesStatsTable: (seriesId, type) => `series:${seriesId}:stats:${type}`,
  seriesNews: (seriesId, cursor) => `series:${seriesId}:news:${cursor || 'default'}`,
  matchNews: (matchId, cursor) => `match:${matchId}:news:${cursor || 'default'}`,
  fullCommentary: (matchId, inningsId) => `match:${matchId}:full-comm:${inningsId}`,
  highlights: (matchId, inningsId) => `match:${matchId}:highlights:${inningsId}`,
  ballsMap: (matchId, inningsId) => `match:${matchId}:balls-map:${inningsId}`,
  overByOver: (matchId, inningsId) => `match:${matchId}:over-by-over:${inningsId}`,
  schedule: (type, ts) => `schedule:${type}:${ts || 'default'}`,
  providerHealth: (name) => `provider:${name}:health`,
  wsRooms: () => 'ws:rooms',
  matchSummary: (id) => `match:${id}:summary`,
  matchSquads: (id) => `match:${id}:squads`,
  matchLiveLine: (id) => `match:${id}:live-line`,
  matchInfoDetailed: (id) => `match:${id}:info-detailed`,
  matchLiveCenter: (id) => `match:${id}:live-center`,
  seriesTeams: (id) => `series:${id}:teams`,
  seriesSquads: (id) => `series:${id}:squads:v2`,
  activeMatches: () => 'active:matches',
});

export async function cacheGet(key) {
  const data = await getRedis().get(key);
  return data ? JSON.parse(data) : null;
}

export async function cacheSet(key, value, ttl) {
  const serialized = JSON.stringify(value);
  if (ttl) {
    await getRedis().setex(key, ttl, serialized);
  } else {
    await getRedis().set(key, serialized);
  }
}

export async function cacheDel(key) {
  await getRedis().del(key);
}

// In-flight fetch dedupe. When a cache key is expired/missing and many requests
// arrive at once (e.g. 100 users polling the same live match), only the FIRST
// runs the producer; the rest await the same promise. Prevents a cache-miss
// "thundering herd" from fanning out into N concurrent provider calls. The map
// only ever holds keys for the duration of an active fetch, and the finally()
// always deletes the key, so it cannot leak.
const inflight = new Map();

/**
 * Run `producer` for `key`, sharing one in-flight promise across concurrent
 * callers. Exported for unit testing the dedupe/cleanup invariants without a
 * live Redis. Errors propagate to every awaiting caller; the key is always
 * removed in finally so a failed run lets the next caller retry.
 */
export function runDeduped(key, producer) {
  const pending = inflight.get(key);
  if (pending) return pending;

  const promise = (async () => {
    try {
      return await producer();
    } finally {
      // Always clear — on resolve OR throw — so a failed run lets the next
      // caller retry and the map never grows unbounded. Guard against clobbering
      // a newer entry for the same key.
      if (inflight.get(key) === promise) inflight.delete(key);
    }
  })();
  inflight.set(key, promise);
  return promise;
}

export async function cacheGetOrFetch(key, ttl, fetchFn) {
  const cached = await cacheGet(key);
  if (cached) return { data: cached, fromCache: true };

  // Cache miss: in-memory dedupe (runDeduped) collapses concurrent callers in
  // THIS process; the Redis lock inside singleFlightRebuild collapses across PM2
  // cluster processes so the provider is hit once cluster-wide. Provider errors
  // propagate exactly as before (holder re-throws, shared by all in-proc callers).
  // Response shape stays identical to the non-deduped path.
  const data = await runDeduped(key, async () =>
    singleFlightRebuild({
      key,
      route: 'cacheGetOrFetch',
      reason: 'miss',
      readCached: () => cacheGet(key),
      rebuild: async () => {
        const fresh = await fetchFn();
        if (fresh) await cacheSet(key, fresh, ttl);
        return fresh;
      },
    }),
  );
  return { data, fromCache: false };
}

// Stale-while-revalidate windows (seconds). Each is how long an EXPIRED live
// value may still be served while a background refresh runs. Kept tight (<= ttl)
// so live scores are never served very old. Max served age = ttl + window.
export const SWR_WINDOW = Object.freeze({
  LIVE_LINE: 3, // ttl 5 + 3 = max age 8s
  SCORECARD: 3, // ttl 5 + 3 = max age 8s
  COMMENTARY: 3, // ttl 5 + 3 = max age 8s
  LIVE_LIST: 4, // ttl 8 + 4 = max age 12s (live match list)
  MATCH_DETAIL: 5, // ttl 15 + 5 = max age 20s (match detail / match:{id}:live)
});

// SWR envelope marker so we can distinguish a wrapped value from a legacy plain
// cached value written by cacheGetOrFetch for the same key.
const SWR_TAG = '__swr__';

/**
 * Stale-while-revalidate variant of cacheGetOrFetch. ADDITIVE — does not change
 * cacheGetOrFetch. Behavior by cached age:
 *   age < ttl                  → fresh hit, return cached (no fetch).
 *   ttl <= age < ttl+stale     → return stale immediately + ONE background
 *                                 refresh (deduped); never awaited.
 *   age >= ttl+stale / no value → block + fetch fresh (same as cacheGetOrFetch).
 *
 * Value is stored as { __swr__:true, v:<data>, f:<freshUntilMs> } with a PHYSICAL
 * Redis TTL of ttl+staleWindow, so data older than the stale window auto-evicts
 * and can never be served. Response shape is unchanged: { data, fromCache } plus
 * an optional `stale` flag that callers may ignore.
 *
 * @param {object} [opts] test seams: opts.now (ms), opts.refresh (override
 *   background scheduler, must return a promise), opts.get/opts.set (override
 *   cache read/write so the logic can be unit-tested without a live Redis).
 */
export async function cacheGetOrFetchSWR(key, ttl, staleWindow, fetchFn, opts = {}) {
  const now = opts.now ?? Date.now();
  const physicalTtl = ttl + staleWindow;
  const getFn = opts.get ?? cacheGet;
  const setFn = opts.set ?? cacheSet;

  const raw = await getFn(key);
  const envelope = raw && typeof raw === 'object' && raw[SWR_TAG] ? raw : null;

  if (envelope) {
    const freshUntil = envelope.f;
    if (now < freshUntil) {
      return { data: envelope.v, fromCache: true, stale: false };
    }
    // Expired but within stale window (physical TTL guarantees we never see
    // anything older). Serve stale now, refresh in background exactly once
    // across concurrent callers. Background errors are logged, never thrown.
    const scheduleRefresh = opts.refresh
      ? () => opts.refresh()
      : () =>
          runDeduped(`swr:${key}`, async () => {
            const fresh = await fetchFn();
            if (fresh) {
              await setFn(key, { [SWR_TAG]: true, v: fresh, f: Date.now() + ttl * 1000 }, physicalTtl);
            }
            return fresh;
          });
    Promise.resolve()
      .then(scheduleRefresh)
      .catch((err) => logger.warn(`SWR background refresh failed for ${key}: ${err.message}`));
    return { data: envelope.v, fromCache: true, stale: true };
  }

  // Hard miss (no value, or a legacy non-envelope value): block + fetch, deduped.
  // Errors propagate exactly like cacheGetOrFetch.
  const produce = async () => {
    const fresh = await fetchFn();
    if (fresh) {
      await setFn(key, { [SWR_TAG]: true, v: fresh, f: Date.now() + ttl * 1000 }, physicalTtl);
    }
    return fresh;
  };

  // Phase 1a: when running for real (no test seams), add a cross-process Redis
  // lock around the rebuild so PM2 cluster processes don't each call the
  // provider on a cold start. With injected opts (unit tests) we keep the exact
  // prior in-memory-only behavior, so all existing SWR tests are unaffected.
  const usingTestSeams = !!(opts.get || opts.set || opts.refresh || opts.now != null);
  const data = await runDeduped(key, async () =>
    usingTestSeams
      ? produce()
      : singleFlightRebuild({
          key,
          route: 'cacheGetOrFetchSWR',
          reason: 'cold-start',
          readCached: async () => unwrapSWR(await cacheGet(key)),
          rebuild: produce,
        }),
  );
  return { data, fromCache: false, stale: false };
}

// Unwrap a value that MAY be an SWR envelope written by cacheGetOrFetchSWR /
// cacheSetSWR. Plain (legacy) values pass through untouched. Lets non-SWR
// readers of a shared SWR key (e.g. the scorecard key) read the real payload
// instead of the { __swr__, v, f } wrapper.
export function unwrapSWR(raw) {
  return raw && typeof raw === 'object' && raw[SWR_TAG] ? raw.v : raw;
}

// Write an SWR envelope directly (for non-route writers of a shared SWR key,
// e.g. the scorecard worker). Mirrors cacheGetOrFetchSWR's storage exactly:
// physical Redis TTL = ttl + staleWindow, freshUntil = now + ttl. Keeps the key
// readable by the SWR route (which would treat a plain write as a hard miss).
export async function cacheSetSWR(key, value, ttl, staleWindow) {
  const physicalTtl = ttl + staleWindow;
  await cacheSet(key, { [SWR_TAG]: true, v: value, f: Date.now() + ttl * 1000 }, physicalTtl);
}

export async function shutdownRedis() {
  if (client) await client.quit();
  if (subscriber) await subscriber.quit();
  logger.info('Redis connections closed');
}
