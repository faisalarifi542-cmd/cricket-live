import { getRedis } from './redis.js';
import { query } from './db.js';
import logger from './logger.js';
import providerManager from '../providers/provider-manager.js';
import { ensureDefaultProvider } from '../admin/provider-seed.js';
// Phase 1a — cross-process single-flight lock + provider-fallback budget.
import {
  acquireCacheLock,
  releaseCacheLock,
  consumeProviderBudget,
  logProviderFallback,
} from './cache-lock.js';

export const DATA_SOURCES = [
  { dataType: 'homeData', label: 'Home Data', appScreen: 'Home', endpointPath: '/app/home', cacheKeyPrefix: 'app:home', providerMethod: null, ttl: 30, stale: true, strategy: 'aggregate' },
  { dataType: 'liveMatches', label: 'Live Matches', appScreen: 'Home / Matches', endpointPath: '/matches/live', cacheKeyPrefix: 'matches:live', providerMethod: 'getLiveMatches', ttl: 10, stale: false, strategy: 'polling' },
  { dataType: 'upcomingMatches', label: 'Upcoming Matches', appScreen: 'Home / Matches', endpointPath: '/matches/upcoming', cacheKeyPrefix: 'matches:upcoming', providerMethod: 'getUpcomingMatches', ttl: 300, stale: true, strategy: 'stale-while-revalidate' },
  { dataType: 'recentMatches', label: 'Recent / Finished Matches', appScreen: 'Home / Matches', endpointPath: '/matches/recent', cacheKeyPrefix: 'matches:recent', providerMethod: 'getRecentMatches', ttl: 300, stale: true, strategy: 'stale-while-revalidate' },
  { dataType: 'matchDetail', label: 'Match Detail', appScreen: 'Match Details', endpointPath: '/match/:id', cacheKeyPrefix: 'match:{id}:detail', providerMethod: 'getMatchInfo', ttl: 10, stale: true, strategy: 'adaptive' },
  { dataType: 'liveLine', label: 'Live Line', appScreen: 'Match Details / Live Player', endpointPath: '/match/:id/live-line', cacheKeyPrefix: 'match:{id}:live-line', providerMethod: 'getLiveLine', ttl: 5, stale: false, strategy: 'polling' },
  { dataType: 'scorecard', label: 'Scorecard', appScreen: 'Scorecard Tab', endpointPath: '/match/:id/scorecard', cacheKeyPrefix: 'match:{id}:scorecard', providerMethod: 'getScorecard', ttl: 30, stale: false, strategy: 'polling' },
  { dataType: 'commentary', label: 'Commentary', appScreen: 'Commentary Tab', endpointPath: '/match/:id/commentary', cacheKeyPrefix: 'match:{id}:commentary', providerMethod: 'getCommentary', ttl: 30, stale: false, strategy: 'polling' },
  { dataType: 'overs', label: 'Overs', appScreen: 'Overs Tab', endpointPath: '/match/:id/overs', cacheKeyPrefix: 'match:{id}:overs', providerMethod: 'getMatchOvers', ttl: 20, stale: false, strategy: 'polling' },
  { dataType: 'squads', label: 'Match Squads', appScreen: 'Squads Tab', endpointPath: '/match/:id/squads', cacheKeyPrefix: 'match:{id}:squads', providerMethod: 'getMatchSquads', ttl: 3600, stale: true, strategy: 'stale-while-revalidate' },
  { dataType: 'seriesList', label: 'Series List', appScreen: 'Series', endpointPath: '/series', cacheKeyPrefix: 'series:list', providerMethod: 'getSeriesList', ttl: 3600, stale: true, strategy: 'stale-while-revalidate' },
  { dataType: 'seriesDetail', label: 'Series Detail', appScreen: 'Series Detail', endpointPath: '/series/:id', cacheKeyPrefix: 'series:{id}:detail', providerMethod: 'getSeriesInfo', ttl: 3600, stale: true, strategy: 'stale-while-revalidate' },
  { dataType: 'seriesMatches', label: 'Series Matches', appScreen: 'Series Detail', endpointPath: '/series/:id/matches', cacheKeyPrefix: 'series:{id}:matches', providerMethod: 'getSeriesInfo', ttl: 900, stale: true, strategy: 'stale-while-revalidate' },
  { dataType: 'pointsTable', label: 'Points Table', appScreen: 'Series Detail', endpointPath: '/points-table/:seriesId', cacheKeyPrefix: 'points:{id}', providerMethod: 'getPointsTable', ttl: 300, stale: true, strategy: 'stale-while-revalidate' },
  { dataType: 'seriesStats', label: 'Series Stats', appScreen: 'Series Detail', endpointPath: '/series/:id/stats', cacheKeyPrefix: 'series:{id}:stats', providerMethod: 'getSeriesStatsTable', ttl: 300, stale: true, strategy: 'stale-while-revalidate' },
  { dataType: 'schedule', label: 'Schedule', appScreen: 'Schedule', endpointPath: '/schedule/upcoming', cacheKeyPrefix: 'schedule:all', providerMethod: 'getUpcomingSchedule', ttl: 300, stale: true, strategy: 'stale-while-revalidate' },
  { dataType: 'news', label: 'News', appScreen: 'News', endpointPath: '/news', cacheKeyPrefix: 'news:list', providerMethod: 'getNewsStories', ttl: 300, stale: true, strategy: 'stale-while-revalidate' },
  { dataType: 'playerProfile', label: 'Player Profile', appScreen: 'Player Profile', endpointPath: '/player/:id', cacheKeyPrefix: 'player:{id}', providerMethod: 'getPlayerInfo', ttl: 86400, stale: true, strategy: 'stale-while-revalidate' },
  { dataType: 'teamProfile', label: 'Team Profile', appScreen: 'Team Profile', endpointPath: '/team/:id', cacheKeyPrefix: 'team:{id}', providerMethod: 'getTeamInfo', ttl: 86400, stale: true, strategy: 'stale-while-revalidate' },
  { dataType: 'appConfig', label: 'App Config', appScreen: 'Startup', endpointPath: '/app-config', cacheKeyPrefix: 'app:config', providerMethod: null, ttl: 300, stale: true, strategy: 'admin' },
  { dataType: 'homeConfig', label: 'Home Config', appScreen: 'Home', endpointPath: '/home-config', cacheKeyPrefix: 'home:config', providerMethod: null, ttl: 300, stale: true, strategy: 'admin' },
  { dataType: 'matchStreams', label: 'Match Streams', appScreen: 'Live Player', endpointPath: '/match/:id/streams', cacheKeyPrefix: 'match:{id}:streams', providerMethod: null, ttl: 60, stale: false, strategy: 'admin' },
];

const inflight = new Map();

export async function ensureDataControlSchema() {
  await query(`CREATE TABLE IF NOT EXISTS api_data_sources (
    id INT AUTO_INCREMENT PRIMARY KEY,
    data_type VARCHAR(80) UNIQUE NOT NULL,
    label VARCHAR(160) NOT NULL,
    provider_id INT NULL,
    app_screen VARCHAR(120) NULL,
    endpoint_path VARCHAR(220) NOT NULL,
    provider_method VARCHAR(120) NULL,
    cache_key_prefix VARCHAR(220) NOT NULL,
    enabled TINYINT(1) DEFAULT 1,
    cache_enabled TINYINT(1) DEFAULT 1,
    cache_ttl_seconds INT DEFAULT 300,
    stale_fallback_enabled TINYINT(1) DEFAULT 1,
    timeout_ms INT DEFAULT 8000,
    retry_count INT DEFAULT 1,
    refresh_strategy VARCHAR(80) DEFAULT 'stale-while-revalidate',
    refresh_frequency_seconds INT NULL,
    show_stale_in_app TINYINT(1) DEFAULT 1,
    show_last_updated_label TINYINT(1) DEFAULT 1,
    last_success_at DATETIME NULL,
    last_failure_at DATETIME NULL,
    last_fetched_at DATETIME NULL,
    last_error TEXT NULL,
    health_status VARCHAR(30) DEFAULT 'unknown',
    metadata JSON NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`);

  await query(`CREATE TABLE IF NOT EXISTS data_refresh_jobs (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    data_type VARCHAR(80) NOT NULL,
    target_id VARCHAR(120) NULL,
    status VARCHAR(40) DEFAULT 'idle',
    last_run_at DATETIME NULL,
    next_run_at DATETIME NULL,
    error_message TEXT NULL,
    enabled TINYINT(1) DEFAULT 1,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY data_job_target (data_type, target_id)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`);

  await query(`CREATE TABLE IF NOT EXISTS cache_events (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    event_type VARCHAR(80) NULL,
    cache_key VARCHAR(300),
    data_type VARCHAR(80),
    action VARCHAR(80) NOT NULL,
    status VARCHAR(40) DEFAULT 'ok',
    provider_id INT NULL,
    duration_ms INT NULL,
    error_message TEXT NULL,
    details JSON NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_cache_events_type (data_type, created_at),
    INDEX idx_cache_events_key (cache_key)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci`);

  const provider = await ensureDefaultProvider();
  await query(`ALTER TABLE api_data_sources ADD COLUMN app_screen VARCHAR(120) NULL AFTER label`).catch(() => null);
  await query(`ALTER TABLE cache_events ADD COLUMN event_type VARCHAR(80) NULL AFTER id`).catch(() => null);
  await query(`ALTER TABLE cache_events ADD COLUMN data_type VARCHAR(80) NULL AFTER cache_key`).catch(() => null);
  await query(`ALTER TABLE cache_events ADD COLUMN action VARCHAR(80) NULL AFTER data_type`).catch(() => null);
  await query(`ALTER TABLE cache_events ADD COLUMN status VARCHAR(40) DEFAULT 'ok' AFTER action`).catch(() => null);
  await query(`ALTER TABLE cache_events ADD COLUMN provider_id INT NULL AFTER status`).catch(() => null);
  await query(`ALTER TABLE cache_events ADD COLUMN duration_ms INT NULL AFTER provider_id`).catch(() => null);
  await query(`ALTER TABLE cache_events ADD COLUMN error_message TEXT NULL AFTER duration_ms`).catch(() => null);

  for (const item of DATA_SOURCES) {
    await query(
      `INSERT INTO api_data_sources
        (data_type, label, app_screen, provider_id, endpoint_path, provider_method, cache_key_prefix, cache_ttl_seconds,
         stale_fallback_enabled, refresh_strategy, refresh_frequency_seconds, timeout_ms, retry_count)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE
         label = VALUES(label),
         app_screen = VALUES(app_screen),
         provider_id = COALESCE(provider_id, VALUES(provider_id)),
         endpoint_path = VALUES(endpoint_path),
         provider_method = VALUES(provider_method),
         cache_key_prefix = VALUES(cache_key_prefix)`,
      [item.dataType, item.label, item.appScreen, provider?.id || null, item.endpointPath, item.providerMethod, item.cacheKeyPrefix, item.ttl, item.stale ? 1 : 0, item.strategy, item.ttl, item.ttl <= 30 ? 3000 : 8000, item.ttl <= 10 ? 1 : 2],
    );
  }
}

export async function getDataSources() {
  await ensureDataControlSchema();
  const rows = await query(`SELECT ds.*, p.slug provider_slug, p.name provider_name, p.health_status provider_health
      FROM api_data_sources ds
      LEFT JOIN api_providers p ON p.id = ds.provider_id
      ORDER BY ds.id ASC`);
  return rows.map((r) => ({
    id: r.id,
    dataType: r.data_type,
    label: r.label,
    appScreen: r.app_screen,
    endpointPath: r.endpoint_path,
    providerMethod: r.provider_method,
    cacheKeyPrefix: r.cache_key_prefix,
    providerId: r.provider_id,
    providerName: r.provider_name || r.provider_slug || 'auto',
    enabled: !!r.enabled,
    cacheEnabled: !!r.cache_enabled,
    cacheTtlSeconds: Number(r.cache_ttl_seconds || 0),
    staleFallbackEnabled: !!r.stale_fallback_enabled,
    timeoutMs: Number(r.timeout_ms || 0),
    retryCount: Number(r.retry_count || 0),
    refreshStrategy: r.refresh_strategy,
    refreshFrequencySeconds: r.refresh_frequency_seconds,
    showStaleInApp: !!r.show_stale_in_app,
    showLastUpdatedLabel: !!r.show_last_updated_label,
    lastSuccessAt: r.last_success_at,
    lastFailureAt: r.last_failure_at,
    lastFetchedAt: r.last_fetched_at,
    lastError: r.last_error,
    healthStatus: r.health_status || 'unknown',
    providerHealth: r.provider_health || 'unknown',
  }));
}

export async function getDataSource(dataType) {
  const rows = await getDataSources();
  return rows.find((r) => r.dataType === dataType) || null;
}

export function cacheKeyFor(dataType, targetId = 'default') {
  const def = DATA_SOURCES.find((d) => d.dataType === dataType);
  const prefix = def?.cacheKeyPrefix || `data:${dataType}`;
  return `appdata:${prefix.replace(/\{id\}/g, targetId || 'default')}`;
}

function isValidPayload(data, { allowEmpty = false, requiredId } = {}) {
  if (data == null) return false;
  if (typeof data === 'string') {
    const t = data.trim().toLowerCase();
    if (t.startsWith('<!doctype') || t.startsWith('<html')) return false;
  }
  if (data?.success === false) return false;
  if (requiredId && !(data.matchId || data.match_id || data.id || data.playerId || data.teamId || data.seriesId)) return false;
  if (Array.isArray(data) && data.length === 0) return allowEmpty;
  return true;
}

async function recordEvent(event) {
  try {
    await query(
      `INSERT INTO cache_events (event_type, cache_key, data_type, action, status, provider_id, duration_ms, error_message, details)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [event.action || 'cache.event', event.cacheKey || null, event.dataType || null, event.action, event.status || 'ok', event.providerId || null, event.durationMs || null, event.errorMessage || null, event.details ? JSON.stringify(event.details) : null],
    );
  } catch {
    // Cache telemetry must never break public API traffic.
  }
}

// Data types whose payload reflects an in-progress (live) match. For these the
// stale window must be TINY so a live score is never served minutes old. All
// other (upcoming/recent/series/player/team/news/schedule) keep the long stale
// fallback that protects against provider blips.
const LIVE_DATA_TYPES = new Set([
  'homeData', 'liveMatches', 'matchDetail', 'liveLine',
  'scorecard', 'commentary', 'overs',
]);

// Seconds an EXPIRED envelope may still be served while a background refresh
// runs. Live types: short, capped at 15s. Others: previous max(ttl*4,60).
function staleWindowSeconds(dataType, ttl) {
  if (LIVE_DATA_TYPES.has(dataType)) {
    return Math.min(Math.max(ttl, 5), 15);
  }
  return Math.max(ttl * 4, 60);
}

async function writeEnvelope(key, data, ttl, meta) {
  const now = new Date().toISOString();
  const staleWindow = staleWindowSeconds(meta.dataType, ttl);
  const isLiveType = LIVE_DATA_TYPES.has(meta.dataType);
  const envelope = {
    data,
    meta: {
      provider: meta.provider || 'local',
      providerId: meta.providerId || null,
      createdAt: now,
      lastUpdated: now,
      ttl,
      // Absolute ceiling from creation: fresh while age<=ttl, stale until here.
      staleUntil: Date.now() + (ttl + staleWindow) * 1000,
    },
  };
  // Physical Redis TTL: for live types keep it tight (ttl+window+small grace) so
  // a dead live key cannot linger and be served via the error-fallback path for
  // minutes. Non-live keeps the generous retention for blip protection.
  const physicalTtl = isLiveType
    ? ttl + staleWindow + 5
    : Math.max(ttl * 6, ttl + 60);
  await getRedis().setex(key, physicalTtl, JSON.stringify(envelope));
  return envelope;
}

async function readEnvelope(key) {
  const raw = await getRedis().get(key);
  if (!raw) return null;
  try { return JSON.parse(raw); } catch { return null; }
}

export function sendAppResponse(reply, payload) {
  const meta = payload.meta || {};
  reply.header('X-Cache', meta.cache || 'MISS');
  reply.header('X-Cache-TTL', String(meta.ttl ?? 0));
  if (meta.lastUpdated) {
    reply.header('X-Last-Updated', meta.lastUpdated);
    const ageMs = Date.now() - Date.parse(meta.lastUpdated);
    if (Number.isFinite(ageMs)) reply.header('X-Cache-Age-Ms', String(Math.max(ageMs, 0)));
  }
  if (meta.provider) reply.header('X-Provider', meta.provider);
  if (meta.isStale) reply.header('X-Stale', '1');
  return payload;
}

export async function controlledFetch({
  dataType,
  targetId = 'default',
  fetcher,
  allowEmpty = false,
  requiredId = false,
  force = false,
  // Phase 1b: background warmers set this so their provider refreshes do NOT
  // consume the public-route fallback budget (same exemption BullMQ workers get).
  budgetExempt = false,
}) {
  const source = await getDataSource(dataType).catch(() => null);
  const key = cacheKeyFor(dataType, targetId);
  const ttl = Number(source?.cacheTtlSeconds || DATA_SOURCES.find((d) => d.dataType === dataType)?.ttl || 300);
  const cacheEnabled = source?.cacheEnabled !== false;
  const staleEnabled = source?.staleFallbackEnabled !== false;
  const now = Date.now();

  if (cacheEnabled && !force) {
    const cached = await readEnvelope(key);
    if (cached?.meta?.createdAt) {
      const age = Math.floor((now - Date.parse(cached.meta.createdAt)) / 1000);
      if (age <= ttl) {
        await recordEvent({ cacheKey: key, dataType, action: 'cache.hit', status: 'ok' });
        return { data: cached.data, meta: { cache: 'HIT', provider: cached.meta.provider, lastUpdated: cached.meta.lastUpdated, ttl: Math.max(ttl - age, 0), isStale: false } };
      }
      if (staleEnabled && cached.meta.staleUntil > now) {
        const inflightKey = `${dataType}:${targetId}`;
        if (!inflight.has(inflightKey)) {
          // Fire-and-forget background revalidation: the caller returns STALE
          // below and never awaits this promise. A rejection here (provider
          // failure, or Redis "Connection is closed" during a restart) would
          // otherwise surface as a process-killing unhandledRejection.
          const refresh = controlledFetch({ dataType, targetId, fetcher, allowEmpty, requiredId, force: true })
            .finally(() => inflight.delete(inflightKey));
          // Keep the raw promise in `inflight` so a concurrent hard-miss caller
          // (line below) still awaits the real result/error. Attach a separate
          // no-op rejection handler so the un-awaited fire-and-forget path can
          // never raise unhandledRejection; serving stale is the intended outcome.
          refresh.catch((err) => logger.warn({ msg: 'background stale refresh failed', dataType, targetId, error: err.message }));
          inflight.set(inflightKey, refresh);
        }
        await recordEvent({ cacheKey: key, dataType, action: 'cache.stale', status: 'ok' });
        return { data: cached.data, meta: { cache: 'STALE', provider: cached.meta.provider, lastUpdated: cached.meta.lastUpdated, ttl: 0, isStale: true } };
      }
    }
  }

  const inflightKey = `${dataType}:${targetId}`;
  if (!force && inflight.has(inflightKey)) return inflight.get(inflightKey);

  // Phase 1a — wrap the provider rebuild in a cross-process Redis lock
  // (lock:cache:{key}) so that under PM2 cluster mode only ONE process calls the
  // provider for a missing key; the others wait briefly, re-read cache, and serve
  // stale/last-good. In the current single-process runtime the lock is acquired
  // uncontended, so behavior is identical to before. Worker calls do not pass
  // through here. `force` (stale background refresh / admin warm) skips the
  // waiter path — it must always attempt a real provider refresh.
  const promise = (async () => {
    const started = Date.now();

    const lockToken = await acquireCacheLock(key);

    // Not the holder (only possible across cluster processes) and this is a
    // normal user-facing miss: wait for the holder, then serve fresh/stale.
    if (!lockToken && !force) {
      const deadline = Date.now() + 1500;
      while (Date.now() < deadline) {
        await new Promise((r) => setTimeout(r, 100));
        const fresh = await readEnvelope(key);
        if (fresh?.meta?.createdAt) {
          const age = Math.floor((Date.now() - Date.parse(fresh.meta.createdAt)) / 1000);
          if (age <= ttl) {
            return { data: fresh.data, meta: { cache: 'HIT', provider: fresh.meta.provider, lastUpdated: fresh.meta.lastUpdated, ttl: Math.max(ttl - age, 0), isStale: false } };
          }
        }
      }
      const stale = await readEnvelope(key);
      if (stale?.data) {
        logProviderFallback({ route: 'controlledFetch', key, dataType, reason: 'miss', outcome: 'served-stale-waiter' });
        return { data: stale.data, meta: { cache: 'STALE', provider: stale.meta.provider, lastUpdated: stale.meta.lastUpdated, ttl: 0, isStale: true } };
      }
      // No data at all and we are not allowed to call the provider — surface a
      // clear miss so the caller's own fallbacks (route-level) can handle it.
      logProviderFallback({ route: 'controlledFetch', key, dataType, reason: 'cold-start', outcome: 'waiter-empty' });
      throw new Error('cache miss: rebuild in progress by another process');
    }

    try {
      // Budget gate for the actual provider call (public-route fallback only).
      // Warmers are exempt — they are scheduled background refreshes, not
      // user-triggered fallbacks.
      const budget = budgetExempt
        ? { allowed: true, count: 0, max: Infinity }
        : await consumeProviderBudget(`controlledFetch:${dataType}`);
      if (!budget.allowed) {
        if (staleEnabled) {
          const cached = await readEnvelope(key);
          if (cached?.data) {
            logProviderFallback({ route: 'controlledFetch', key, dataType, reason: 'miss', outcome: 'budget-exhausted-stale', budgetCount: budget.count, budgetMax: budget.max });
            return { data: cached.data, meta: { cache: 'STALE', provider: cached.meta.provider, lastUpdated: cached.meta.lastUpdated, ttl: 0, isStale: true } };
          }
        }
        // No stale to fall back to: let the provider call proceed rather than
        // blank the app (budget is a soft shed, not a hard wall on cold start).
        logProviderFallback({ route: 'controlledFetch', key, dataType, reason: 'cold-start', outcome: 'budget-exhausted-no-stale-proceeding', budgetCount: budget.count, budgetMax: budget.max });
      }

      const result = await fetcher(source);
      const data = result?.data ?? result;
      const provider = result?.provider || source?.providerName || 'local';
      if (!isValidPayload(data, { allowEmpty, requiredId })) {
        // Diagnostic: explain WHY the payload was rejected instead of only the
        // generic message. requiredId rejection on a COMPOSITE payload (id nested
        // under a child like `.match`) is the common cause — surface the shape.
        const idField = requiredId
          ? (data?.matchId || data?.match_id || data?.id || data?.playerId || data?.teamId || data?.seriesId || null)
          : 'n/a';
        logProviderFallback({
          route: 'controlledFetch',
          key,
          dataType,
          reason: 'invalid-payload',
          outcome: 'rejected',
          source: 'provider',
          provider,
          dataNull: data == null,
          dataType_js: Array.isArray(data) ? 'array' : typeof data,
          topLevelKeys: data && typeof data === 'object' && !Array.isArray(data) ? Object.keys(data).slice(0, 20) : null,
          requiredId: !!requiredId,
          topLevelIdPresent: requiredId ? !!idField : null,
          allowEmpty: !!allowEmpty,
          successFalse: data?.success === false,
        });
        throw new Error('Provider returned invalid or unsafe data');
      }
      if (cacheEnabled) await writeEnvelope(key, data, ttl, { provider, providerId: source?.providerId, dataType });
      await query(`UPDATE api_data_sources SET last_success_at = NOW(), last_fetched_at = NOW(), health_status = 'healthy', last_error = NULL WHERE data_type = ?`, [dataType]).catch(() => null);
      await recordEvent({ cacheKey: key, dataType, action: force ? 'cache.refresh' : 'cache.miss', status: 'ok', providerId: source?.providerId, durationMs: Date.now() - started });
      return { data, meta: { cache: force ? 'BYPASS' : 'MISS', provider, lastUpdated: new Date().toISOString(), ttl, isStale: false } };
    } catch (err) {
      await query(`UPDATE api_data_sources SET last_failure_at = NOW(), last_fetched_at = NOW(), health_status = 'down', last_error = ? WHERE data_type = ?`, [err.message, dataType]).catch(() => null);
      await recordEvent({ cacheKey: key, dataType, action: 'provider.fetch', status: 'error', providerId: source?.providerId, durationMs: Date.now() - started, errorMessage: err.message });
      if (staleEnabled) {
        const cached = await readEnvelope(key);
        if (cached?.data) {
          return { data: cached.data, meta: { cache: 'STALE', provider: cached.meta.provider, lastUpdated: cached.meta.lastUpdated, ttl: 0, isStale: true, error: err.message } };
        }
      }
      throw err;
    } finally {
      await releaseCacheLock(key, lockToken);
    }
  })();

  inflight.set(inflightKey, promise.finally(() => inflight.delete(inflightKey)));
  return promise;
}

export async function providerFetch(dataType, method, ...args) {
  return controlledFetch({
    dataType,
    targetId: args[0] || 'default',
    fetcher: async () => {
      const result = await providerManager.execute(method, ...args);
      return { data: result.data, provider: result.provider };
    },
    allowEmpty: ['liveMatches', 'upcomingMatches', 'recentMatches', 'news', 'schedule'].includes(dataType),
    requiredId: ['matchDetail', 'liveLine', 'playerProfile', 'teamProfile'].includes(dataType),
  });
}

export async function clearDataCache(dataType, targetId = '*') {
  const redis = getRedis();
  const pattern = targetId === '*' ? `${cacheKeyFor(dataType, '*').replace(/\*/g, '*')}*` : cacheKeyFor(dataType, targetId);
  const keys = await redis.keys(pattern);
  const deleted = keys.length ? await redis.del(...keys) : 0;
  await recordEvent({ cacheKey: pattern, dataType, action: 'cache.clear', status: 'ok', details: { deleted } });
  return deleted;
}

export async function getCacheStats() {
  const redis = getRedis();
  const keys = await redis.keys('*');
  const appKeys = keys.filter((k) => k.startsWith('appdata:'));
  const events = await query(
    `SELECT
       SUM(action = 'cache.hit') hits,
       SUM(action = 'cache.miss') misses,
       SUM(action = 'cache.stale') staleServed,
       SUM(action = 'provider.fetch') providerFetches,
       SUM(status = 'error') failedProviderFetches,
       AVG(duration_ms) avgProviderLatency
     FROM cache_events
     WHERE created_at > DATE_SUB(NOW(), INTERVAL 24 HOUR)`,
  ).catch(() => [{}]);
  return {
    status: redis.status,
    totalKeys: keys.length,
    appCacheKeys: appKeys.length,
    liveCacheKeys: keys.filter((k) => k.includes('live')).length,
    matchCacheKeys: keys.filter((k) => k.includes('match:')).length,
    seriesCacheKeys: keys.filter((k) => k.includes('series:')).length,
    scheduleCacheKeys: keys.filter((k) => k.includes('schedule')).length,
    newsCacheKeys: keys.filter((k) => k.includes('news')).length,
    streamCacheKeys: keys.filter((k) => k.includes('streams')).length,
    events: events[0] || {},
  };
}

export async function warmDataSource(dataType, targetId, fetcher) {
  return controlledFetch({ dataType, targetId: targetId || 'default', fetcher, force: true, allowEmpty: true });
}
