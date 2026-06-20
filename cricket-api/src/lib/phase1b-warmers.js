/**
 * Phase 1b — in-process cache warmers.
 * ----------------------------------------------------------------------------
 * Keeps the heaviest Flutter-facing Redis keys hot so public routes almost never
 * trigger a user-facing provider fallback:
 *
 *   appdata:app:home      ← runHomeFetch(force)            (controlledFetch envelope)
 *   appdata:app:config    ← controlledFetch(appConfig)     (controlledFetch envelope)
 *   livefast:{id}         ← fetchLiveScoreFast(caller=warmer)   (setex {s,t,p})
 *   livecomm:{id}         ← fetchLiveCommentaryFast(caller=warmer) (setex {c,t,...})
 *
 * Design notes (see Phase 1b brief):
 *  - These run IN the API process and reuse the EXACT route fetch closures via
 *    `phase1bWarmEntrypoints`, so cache key formats are guaranteed identical and
 *    no live-commentary logic is duplicated/extracted.
 *  - Single-instance under PM2 cluster `-i max`: every warmer tick first takes a
 *    Redis leader lock (`lock:cache:warmer:{name}`); only the holder warms that
 *    tick. Defense-in-depth: the fetch closures themselves hold the Phase 1a
 *    per-key lock, so even a double tick hits the provider once cluster-wide.
 *  - Worker/warmer provider calls are EXEMPT from the public fallback budget.
 *  - Active live matches are discovered ONLY from the worker-fed `matches:live`
 *    cache (no fresh provider call); a per-warmer cap bounds fan-out; matches
 *    that leave live status simply stop being selected next tick.
 */
import config from '../config/index.js';
import logger from './logger.js';
import { cacheGet, unwrapSWR, KEYS } from './redis.js';
import { controlledFetch } from './data-control.js';
import { buildPublicAppConfig } from './public-app-state.js';
import { acquireCacheLock, releaseCacheLock } from './cache-lock.js';
import { phase1bWarmEntrypoints } from '../routes/app.js';

const timers = [];
const disabledLogged = new Set();

function warmerEnabled(name) {
  if (!config.phase1b.enabled) {
    if (!disabledLogged.has('__master__')) {
      logger.warn({ msg: 'phase1b-warmer disabled', warmer: 'ALL', reason: 'ENABLE_PHASE1B_WARMING=false' });
      disabledLogged.add('__master__');
    }
    return false;
  }
  if (!config.phase1b.warmers[name]) {
    if (!disabledLogged.has(name)) {
      logger.warn({ msg: 'phase1b-warmer disabled', warmer: name, reason: `ENABLE_${name} flag is false` });
      disabledLogged.add(name);
    }
    return false;
  }
  return true;
}

// Single-leader gate for a tick. Only the process that takes the lock warms;
// the lock TTL is ~ the interval so the next tick can re-elect any process.
async function asLeader(name, intervalMs, fn) {
  const lockTtlMs = Math.max(1000, intervalMs - config.phase1b.leaderLockGraceMs);
  const token = await acquireCacheLock(`warmer:${name}`, lockTtlMs);
  if (!token) return; // another API process is the leader for this tick
  try {
    await fn();
  } finally {
    await releaseCacheLock(`warmer:${name}`, token);
  }
}

export function capFor(specific) {
  const v = Number(specific || 0);
  return v > 0 ? v : config.phase1b.caps.liveMatches;
}

function liveMatchId(m) {
  return String(m?.match_id ?? m?.matchId ?? m?.id ?? '').trim();
}

/**
 * Deterministic priority order for which live matches to warm when there are
 * more live than the cap allows. No provider/MySQL calls — reads only caches:
 *   1. ids appearing in the cached home top-featured/live sections (high interest)
 *   2. status === 'live' before 'innings_break'
 *   3. original matches:live provider order (stable)
 */
export async function selectLiveMatchIds(cap) {
  const raw = unwrapSWR(await cacheGet(KEYS.matchesList('live')).catch(() => null));
  const list = Array.isArray(raw) ? raw : [];
  const liveItems = list.filter((m) => {
    const s = String(m?.status || '').toLowerCase();
    return s === 'live' || s === 'innings_break';
  });

  // Best-effort high-interest set from the cached home payload.
  const highInterest = new Set();
  try {
    const homeEnv = await cacheGet('appdata:app:home');
    const home = homeEnv?.data || null;
    const pools = [home?.topFeaturedMatches, home?.liveMatches, home?.matches];
    for (const pool of pools) {
      for (const m of pool || []) {
        const id = liveMatchId(m);
        if (id) highInterest.add(id);
      }
    }
  } catch { /* home cache optional */ }

  const score = (m) => {
    const id = liveMatchId(m);
    const s = String(m?.status || '').toLowerCase();
    let v = 0;
    if (highInterest.has(id)) v += 100;
    if (s === 'live') v += 10; // live before innings_break
    return v;
  };

  const ordered = liveItems
    .map((m, idx) => ({ id: liveMatchId(m), idx, score: score(m) }))
    .filter((x) => x.id)
    // Stable: higher score first, then original provider order.
    .sort((a, b) => (b.score - a.score) || (a.idx - b.idx));

  const seen = new Set();
  const ids = [];
  for (const x of ordered) {
    if (seen.has(x.id)) continue;
    seen.add(x.id);
    ids.push(x.id);
    if (ids.length >= cap) break;
  }
  return { selected: ids, discovered: liveItems.length };
}

// ---- Individual warmers -----------------------------------------------------

async function warmAppHome() {
  if (!warmerEnabled('appHome')) return;
  // The home payload embeds ABSOLUTE image URLs derived from the request host.
  // Without PUBLIC_BASE_URL the warmer would rebuild them as relative paths and
  // clobber the good absolute URLs a real request cached → broken Image.network.
  // So require a base URL; otherwise skip and let real requests own the home key
  // (still Phase 1a protected).
  if (!String(config.phase1b.baseUrl || '').trim()) {
    if (!disabledLogged.has('appHome:no-base-url')) {
      logger.warn({ msg: 'phase1b-warmer disabled', warmer: 'appHome', reason: 'PUBLIC_BASE_URL not set (avoids clobbering absolute image URLs)' });
      disabledLogged.add('appHome:no-base-url');
    }
    return;
  }
  await asLeader('app-home', config.phase1b.intervals.appHomeMs, async () => {
    const fn = phase1bWarmEntrypoints.warmHome;
    if (typeof fn !== 'function') return;
    try {
      const res = await fn();
      logger.info({ msg: 'phase1b-warmer', warmer: 'app-home', key: 'appdata:app:home', cache: res?.meta?.cache || null });
    } catch (err) {
      logger.warn({ msg: 'phase1b-warmer error', warmer: 'app-home', error: err.message });
    }
  });
}

async function warmAppConfig() {
  if (!warmerEnabled('appConfig')) return;
  await asLeader('app-config', config.phase1b.intervals.appConfigMs, async () => {
    try {
      const res = await controlledFetch({
        dataType: 'appConfig',
        targetId: 'default',
        force: true,
        budgetExempt: true,
        fetcher: async () => ({ data: await buildPublicAppConfig(), provider: 'admin' }),
      });
      logger.info({ msg: 'phase1b-warmer', warmer: 'app-config', key: 'appdata:app:config', cache: res?.meta?.cache || null });
    } catch (err) {
      logger.warn({ msg: 'phase1b-warmer error', warmer: 'app-config', error: err.message });
    }
  });
}

async function warmLivefast() {
  if (!warmerEnabled('livefast')) return;
  await asLeader('livefast', config.phase1b.intervals.livefastMs, async () => {
    const fn = phase1bWarmEntrypoints.warmLiveScore;
    if (typeof fn !== 'function') return;
    const cap = capFor(config.phase1b.caps.livefast);
    const { selected, discovered } = await selectLiveMatchIds(cap);
    if (!selected.length) return;
    await Promise.allSettled(selected.map((id) => fn(id)));
    logger.info({ msg: 'phase1b-warmer', warmer: 'livefast', discovered, warmed: selected.length, skipped: Math.max(discovered - selected.length, 0), cap });
  });
}

async function warmLivecomm() {
  if (!warmerEnabled('livecomm')) return;
  await asLeader('livecomm', config.phase1b.intervals.livecommMs, async () => {
    const fn = phase1bWarmEntrypoints.warmLiveCommentary;
    if (typeof fn !== 'function') return;
    const cap = capFor(config.phase1b.caps.livecomm);
    const { selected, discovered } = await selectLiveMatchIds(cap);
    if (!selected.length) return;
    await Promise.allSettled(selected.map((id) => fn(id)));
    logger.info({ msg: 'phase1b-warmer', warmer: 'livecomm', discovered, warmed: selected.length, skipped: Math.max(discovered - selected.length, 0), cap });
  });
}

// ---- Scheduler --------------------------------------------------------------

function schedule(name, intervalMs, tick) {
  // Guard each tick so a throw never kills the interval.
  const safeTick = async () => {
    try { await tick(); } catch (err) {
      logger.warn({ msg: 'phase1b-warmer tick failed', warmer: name, error: err.message });
    }
  };
  const t = setInterval(safeTick, intervalMs);
  if (typeof t.unref === 'function') t.unref(); // never keep the process alive on its own
  timers.push(t);
}

/**
 * Start all Phase 1b warmers. Safe to call once after the server is listening.
 * If the master kill switch is off, logs and starts nothing.
 */
export function startPhase1bWarmers() {
  if (!config.phase1b.enabled) {
    logger.warn({ msg: 'phase1b-warmers not started', reason: 'ENABLE_PHASE1B_WARMING=false' });
    return;
  }
  const i = config.phase1b.intervals;
  schedule('app-home', i.appHomeMs, warmAppHome);
  schedule('app-config', i.appConfigMs, warmAppConfig);
  schedule('livefast', i.livefastMs, warmLivefast);
  schedule('livecomm', i.livecommMs, warmLivecomm);
  logger.info({
    msg: 'phase1b-warmers started',
    enabled: config.phase1b.warmers,
    intervals: i,
    caps: config.phase1b.caps,
  });
}

/** Stop all Phase 1b warmers (graceful shutdown). */
export function stopPhase1bWarmers() {
  for (const t of timers.splice(0)) clearInterval(t);
}
