import Redis from 'ioredis';
import config from '../config/index.js';
import logger from './logger.js';

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
  COMMENTARY: 15,
  SCORECARD: 30,
  MATCH_INFO: 60,
  MATCH_LIST: 20,
  MATCH_STATS: 20,
  MATCH_OVERS: 15,
  SERIES: 300,
  PLAYER: 3600,
  TEAM: 3600,
  POINTS_TABLE: 300,
  UPCOMING: 300,
  RECENT: 120,
  HOME_MATCHES: 20,
  NEWS_LIST: 600,
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
  seriesTeams: (id) => `series:${id}:teams`,
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

export async function cacheGetOrFetch(key, ttl, fetchFn) {
  const cached = await cacheGet(key);
  if (cached) return { data: cached, fromCache: true };

  const fresh = await fetchFn();
  if (fresh) await cacheSet(key, fresh, ttl);
  return { data: fresh, fromCache: false };
}

export async function shutdownRedis() {
  if (client) await client.quit();
  if (subscriber) await subscriber.quit();
  logger.info('Redis connections closed');
}
