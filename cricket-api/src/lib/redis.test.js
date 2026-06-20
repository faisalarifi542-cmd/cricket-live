import { test } from 'node:test';
import assert from 'node:assert/strict';

import { runDeduped, cacheGetOrFetchSWR, cacheSetSWR, unwrapSWR } from './redis.js';

// Build a fake cache backed by a plain Map plus injectable now, so SWR logic is
// tested without a live Redis. envelope shape matches the helper: {__swr__,v,f}.
function makeCache(initial = {}) {
  const store = new Map(Object.entries(initial));
  return {
    store,
    get: async (k) => (store.has(k) ? store.get(k) : null),
    set: async (k, val) => { store.set(k, val); },
  };
}
const wrap = (v, freshUntil) => ({ __swr__: true, v, f: freshUntil });

test('concurrent same-key calls trigger producer only once', async () => {
  let calls = 0;
  let resolveFetch;
  const gate = new Promise((res) => { resolveFetch = res; });
  const producer = async () => {
    calls += 1;
    await gate;
    return { score: 100 };
  };

  // Fire 100 concurrent callers for the same key while the fetch is in flight.
  const all = Promise.all(
    Array.from({ length: 100 }, () => runDeduped('match:1:live', producer)),
  );
  resolveFetch();
  const results = await all;

  assert.equal(calls, 1, 'producer must run exactly once for 100 concurrent callers');
  for (const r of results) assert.deepEqual(r, { score: 100 });
});

test('different keys run independently', async () => {
  let calls = 0;
  const producer = async () => { calls += 1; return calls; };
  await Promise.all([
    runDeduped('match:1:live', producer),
    runDeduped('match:2:live', producer),
  ]);
  assert.equal(calls, 2, 'distinct keys must not share a fetch');
});

test('failed fetch removes key from inflight map and propagates error', async () => {
  const boom = new Error('provider down');
  await assert.rejects(
    runDeduped('match:err:live', async () => { throw boom; }),
    /provider down/,
    'error must propagate to the caller',
  );

  // Key must have been cleared so a later call re-runs the producer.
  let secondCalls = 0;
  const data = await runDeduped('match:err:live', async () => {
    secondCalls += 1;
    return { ok: true };
  });
  assert.equal(secondCalls, 1, 'after a failure the next call must re-run the producer');
  assert.deepEqual(data, { ok: true });
});

test('after success the key is cleared so a later refresh re-fetches', async () => {
  let calls = 0;
  const producer = async () => { calls += 1; return calls; };

  const first = await runDeduped('match:2x:live', producer);
  // Sequential (not concurrent) call — previous fetch already settled, so the
  // key should be gone and the producer should run again.
  const second = await runDeduped('match:2x:live', producer);

  assert.equal(first, 1);
  assert.equal(second, 2, 'a fresh poll after the first settles must hit the producer again');
});

// ---- SWR (cacheGetOrFetchSWR) ----------------------------------------------
const TTL = 5;
const STALE = 3;

test('SWR: fresh cache returns cached and does NOT call fetch', async () => {
  const now = 1_000_000;
  const cache = makeCache({ 'm:1:live-line': wrap({ runs: 10 }, now + TTL * 1000) });
  let fetchCalls = 0;
  const res = await cacheGetOrFetchSWR('m:1:live-line', TTL, STALE,
    async () => { fetchCalls += 1; return { runs: 99 }; },
    { now, get: cache.get, set: cache.set });

  assert.deepEqual(res.data, { runs: 10 });
  assert.equal(res.stale, false);
  assert.equal(res.fromCache, true);
  assert.equal(fetchCalls, 0, 'fresh hit must not fetch');
});

test('SWR: stale-but-valid returns immediately and triggers ONE background refresh', async () => {
  const now = 1_000_000;
  // freshUntil already passed (1s ago) but within stale window.
  const cache = makeCache({ 'm:2:live-line': wrap({ runs: 20 }, now - 1000) });
  let refreshCalls = 0;
  let resolveRefresh;
  const refreshDone = new Promise((r) => { resolveRefresh = r; });
  const res = await cacheGetOrFetchSWR('m:2:live-line', TTL, STALE,
    async () => { refreshCalls += 1; return { runs: 21 }; },
    { now, get: cache.get, set: cache.set, refresh: () => { refreshCalls += 1; resolveRefresh(); return Promise.resolve(); } });

  assert.deepEqual(res.data, { runs: 20 }, 'must return stale data immediately');
  assert.equal(res.stale, true);
  await refreshDone;
  assert.equal(refreshCalls, 1, 'exactly one background refresh');
});

test('SWR: expired beyond stale window blocks and fetches fresh', async () => {
  const now = 1_000_000;
  // Physical TTL would have evicted it; simulate by empty cache (hard miss).
  const cache = makeCache({});
  let fetchCalls = 0;
  const res = await cacheGetOrFetchSWR('m:3:live-line', TTL, STALE,
    async () => { fetchCalls += 1; return { runs: 30 }; },
    { now, get: cache.get, set: cache.set });

  assert.deepEqual(res.data, { runs: 30 });
  assert.equal(res.fromCache, false);
  assert.equal(fetchCalls, 1, 'hard miss must block + fetch');
  // fresh value written back as an envelope
  const stored = cache.store.get('m:3:live-line');
  assert.equal(stored.__swr__, true);
  assert.deepEqual(stored.v, { runs: 30 });
});

test('SWR: concurrent stale hits trigger only ONE background refresh', async () => {
  const now = 1_000_000;
  const cache = makeCache({ 'm:4:live-line': wrap({ runs: 40 }, now - 1000) });
  let fetchCalls = 0;
  let release;
  const gate = new Promise((r) => { release = r; });
  // Use the real runDeduped path (no refresh override) so dedupe is exercised.
  const calls = Array.from({ length: 100 }, () =>
    cacheGetOrFetchSWR('m:4:live-line', TTL, STALE,
      async () => { fetchCalls += 1; await gate; return { runs: 41 }; },
      { now, get: cache.get, set: cache.set }));
  const results = await Promise.all(calls);
  release();
  // let background refresh settle
  await new Promise((r) => setImmediate(r));

  for (const r of results) assert.deepEqual(r.data, { runs: 40 });
  assert.equal(fetchCalls, 1, '100 concurrent stale hits → one provider refresh');
});

test('SWR: background refresh error does NOT throw to user', async () => {
  const now = 1_000_000;
  const cache = makeCache({ 'm:5:live-line': wrap({ runs: 50 }, now - 1000) });
  // refresh rejects; helper must still return stale data without throwing.
  const res = await cacheGetOrFetchSWR('m:5:live-line', TTL, STALE,
    async () => { throw new Error('provider down'); },
    { now, get: cache.get, set: cache.set });
  assert.deepEqual(res.data, { runs: 50 });
  assert.equal(res.stale, true);
  // give the rejected background promise a tick to settle (must be swallowed)
  await new Promise((r) => setImmediate(r));
});

test('SWR: response always contains { data }', async () => {
  const now = 1_000_000;
  const cache = makeCache({});
  const res = await cacheGetOrFetchSWR('m:6:live-line', TTL, STALE,
    async () => ({ runs: 60 }), { now, get: cache.get, set: cache.set });
  assert.ok('data' in res);
  assert.deepEqual(res.data, { runs: 60 });
});

// Scorecard validation contract: the scorecard route's fetchFn returns null for
// empty/broken scorecard data (no innings). SWR must NOT cache a null result, so
// invalid scorecard data never gets served from cache on a later request.
test('SWR: fetchFn returning null (invalid scorecard) is NOT cached', async () => {
  const now = 1_000_000;
  const cache = makeCache({}); // hard miss
  const res = await cacheGetOrFetchSWR('m:7:scorecard', TTL, STALE,
    async () => null, // mirrors empty-innings scorecard guard
    { now, get: cache.get, set: cache.set });

  assert.equal(res.data, null, 'invalid scorecard returns null data');
  assert.equal(res.fromCache, false);
  assert.equal(cache.store.has('m:7:scorecard'), false, 'null result must not be written to cache');
});

test('SWR: hard-miss write uses physical TTL = ttl + staleWindow', async () => {
  const now = 1_000_000;
  const store = new Map();
  let writtenTtl = null;
  const get = async (k) => (store.has(k) ? store.get(k) : null);
  const set = async (k, val, ttl) => { writtenTtl = ttl; store.set(k, val); };
  const res = await cacheGetOrFetchSWR('m:8:scorecard', TTL, STALE,
    async () => ({ innings: [{}] }), { now, get, set });

  assert.equal(res.fromCache, false);
  assert.equal(writtenTtl, TTL + STALE, 'physical Redis TTL must be ttl + staleWindow (8)');
  const stored = store.get('m:8:scorecard');
  assert.equal(stored.__swr__, true, 'value stored as SWR envelope');
});

test('unwrapSWR returns inner value for envelopes and passes plain values through', () => {
  // The scorecard key is shared: non-SWR readers (live-center, commentary-feed)
  // must see the real payload, never the { __swr__, v, f } wrapper.
  const envelope = { __swr__: true, v: { innings: [{ a: 1 }] }, f: 123 };
  assert.deepEqual(unwrapSWR(envelope), { innings: [{ a: 1 }] }, 'envelope -> inner value');
  assert.deepEqual(unwrapSWR({ innings: [] }), { innings: [] }, 'plain value passes through');
  assert.equal(unwrapSWR(null), null, 'null passes through');
});

test('cacheSetSWR is exported for non-route writers (worker) of the SWR key', () => {
  assert.equal(typeof cacheSetSWR, 'function');
});

// ---- Commentary SWR (third wired route) ------------------------------------
// The /commentary route's fetchFn returns null for empty/non-array commentary so
// SWR never caches broken data. A valid non-empty array is cached as an envelope
// and served as a HIT on the next call.

test('SWR commentary: empty/invalid commentary (null fetchFn) is NOT cached', async () => {
  const now = 1_000_000;
  const cache = makeCache({}); // hard miss
  const res = await cacheGetOrFetchSWR('m:c1:commentary', TTL, STALE,
    async () => null, // mirrors `Array.isArray && length>0 ? list : null`
    { now, get: cache.get, set: cache.set });

  assert.equal(res.data, null, 'invalid commentary returns null data');
  assert.equal(res.fromCache, false);
  assert.equal(cache.store.has('m:c1:commentary'), false, 'null result must not be cached');
});

test('SWR commentary: valid array cached as envelope, served HIT next call', async () => {
  const now = 1_000_000;
  const store = new Map();
  const get = async (k) => (store.has(k) ? store.get(k) : null);
  const set = async (k, val) => { store.set(k, val); };
  const list = [{ id: 'b1', text: '1 run' }, { id: 'b2', text: 'FOUR' }];

  // Call 1: hard miss → fetch + write envelope → fromCache false (X-Cache MISS).
  const r1 = await cacheGetOrFetchSWR('m:c2:commentary', TTL, STALE,
    async () => list, { now, get, set });
  assert.equal(r1.fromCache, false);
  assert.deepEqual(r1.data, list);
  const stored = store.get('m:c2:commentary');
  assert.equal(stored.__swr__, true, 'commentary stored as SWR envelope');

  // Call 2 (still fresh): no fetch → fromCache true (X-Cache HIT).
  let fetchCalls = 0;
  const r2 = await cacheGetOrFetchSWR('m:c2:commentary', TTL, STALE,
    async () => { fetchCalls += 1; return list; },
    { now: now + 1000, get, set });
  assert.equal(r2.fromCache, true, 'second call within ttl is a cache HIT');
  assert.equal(fetchCalls, 0, 'fresh hit must not fetch');
  assert.deepEqual(r2.data, list);
});

test('SWR commentary: worker envelope (cacheSetSWR) is read back unwrapped', () => {
  // Worker writes via cacheSetSWR; the route reads an envelope, the worker reads
  // via unwrapSWR. Round-trip the envelope shape the worker produces.
  const list = [{ id: 'b1' }];
  const envelope = { __swr__: true, v: list, f: 9_999 };
  assert.deepEqual(unwrapSWR(envelope), list, 'worker reader unwraps its own envelope');
});

// ---- Matches Live SWR (fourth wired route) ---------------------------------
// The /matches/live route's fetchFn returns the provider array (empty array is
// VALID = no live matches now, and is cached to avoid hammering the provider);
// only a non-array/broken payload returns null so SWR skips caching.
const LIVE_TTL = 8;
const LIVE_STALE = 4;

test('SWR matches:live: broken (non-array) payload is NOT cached', async () => {
  const now = 1_000_000;
  const cache = makeCache({}); // hard miss
  const res = await cacheGetOrFetchSWR('matches:live', LIVE_TTL, LIVE_STALE,
    async () => null, // mirrors `Array.isArray(list) ? list : null` on a broken payload
    { now, get: cache.get, set: cache.set });

  assert.equal(res.data, null, 'broken live list returns null data');
  assert.equal(res.fromCache, false);
  assert.equal(cache.store.has('matches:live'), false, 'null result must not be cached');
});

test('SWR matches:live: empty array IS valid and cached (no live matches)', async () => {
  const now = 1_000_000;
  const store = new Map();
  const get = async (k) => (store.has(k) ? store.get(k) : null);
  const set = async (k, val) => { store.set(k, val); };

  // Call 1: hard miss → fetch returns [] (no live games) → cached as envelope.
  const r1 = await cacheGetOrFetchSWR('matches:live', LIVE_TTL, LIVE_STALE,
    async () => [], { now, get, set });
  assert.equal(r1.fromCache, false);
  assert.deepEqual(r1.data, []);
  const stored = store.get('matches:live');
  assert.equal(stored.__swr__, true, 'empty live list stored as SWR envelope');
  assert.deepEqual(stored.v, [], 'empty array is cached, not skipped');

  // Call 2 (still fresh): served from cache, no provider call.
  let fetchCalls = 0;
  const r2 = await cacheGetOrFetchSWR('matches:live', LIVE_TTL, LIVE_STALE,
    async () => { fetchCalls += 1; return []; },
    { now: now + 1000, get, set });
  assert.equal(r2.fromCache, true, 'empty list served as HIT, not re-fetched');
  assert.equal(fetchCalls, 0);
});

test('SWR matches:live: valid list cached as envelope, served HIT next call', async () => {
  const now = 1_000_000;
  const store = new Map();
  const get = async (k) => (store.has(k) ? store.get(k) : null);
  const set = async (k, val) => { store.set(k, val); };
  const list = [{ match_id: 'm1', status: 'live' }, { match_id: 'm2', status: 'live' }];

  const r1 = await cacheGetOrFetchSWR('matches:live', LIVE_TTL, LIVE_STALE,
    async () => list, { now, get, set });
  assert.equal(r1.fromCache, false, 'first call is X-Cache MISS');
  assert.deepEqual(r1.data, list);

  let fetchCalls = 0;
  const r2 = await cacheGetOrFetchSWR('matches:live', LIVE_TTL, LIVE_STALE,
    async () => { fetchCalls += 1; return list; },
    { now: now + 2000, get, set });
  assert.equal(r2.fromCache, true, 'second call is X-Cache HIT');
  assert.equal(fetchCalls, 0);
  assert.deepEqual(r2.data, list);
});

test('SWR matches:live: physical TTL = ttl + staleWindow (12)', async () => {
  const now = 1_000_000;
  const store = new Map();
  let writtenTtl = null;
  const get = async (k) => (store.has(k) ? store.get(k) : null);
  const set = async (k, val, ttl) => { writtenTtl = ttl; store.set(k, val); };
  await cacheGetOrFetchSWR('matches:live', LIVE_TTL, LIVE_STALE,
    async () => [{ match_id: 'm1' }], { now, get, set });
  assert.equal(writtenTtl, LIVE_TTL + LIVE_STALE, 'physical Redis TTL must be 12 (8 + 4)');
});

test('SWR matches:live: fromCache is a strict boolean (never null) on both paths', async () => {
  // Regression: the route exposed fromCache:null because the response schema
  // stripped the field AND the body omitted it. The helper itself must always
  // hand the route a real boolean to forward.
  const now = 1_000_000;
  const store = new Map();
  const get = async (k) => (store.has(k) ? store.get(k) : null);
  const set = async (k, val) => { store.set(k, val); };

  const miss = await cacheGetOrFetchSWR('matches:live', LIVE_TTL, LIVE_STALE,
    async () => [{ match_id: 'm1' }], { now, get, set });
  assert.equal(typeof miss.fromCache, 'boolean', 'fromCache must be boolean on miss');
  assert.equal(miss.fromCache, false);

  const hit = await cacheGetOrFetchSWR('matches:live', LIVE_TTL, LIVE_STALE,
    async () => [{ match_id: 'm1' }], { now: now + 1000, get, set });
  assert.equal(typeof hit.fromCache, 'boolean', 'fromCache must be boolean on hit');
  assert.equal(hit.fromCache, true);
});

test('SWR matches:live: worker envelope (cacheSetSWR shape) is read back unwrapped', () => {
  // match-list worker writes the live list via cacheSetSWR; route + any direct
  // reader must see the real array, never the wrapper.
  const list = [{ match_id: 'm1', status: 'live' }];
  const envelope = { __swr__: true, v: list, f: 9_999 };
  assert.deepEqual(unwrapSWR(envelope), list, 'live-list worker envelope unwraps to the array');
});

// ---- Match Detail SWR (fifth / final wired route) --------------------------
// /match/:id (key match:{id}:live). ttl 15 + window 5 = max age 20s. fetchFn
// returns null for clearly-empty match detail so SWR never caches broken data.
// The key is shared by /live-center + the live-score worker, all unified on the
// SWR envelope (route/live-center via cacheGetOrFetchSWR, worker via cacheSetSWR
// write + unwrapSWR read).
const MD_TTL = 15;
const MD_STALE = 5;

test('SWR match-detail: invalid/empty match detail (null fetchFn) is NOT cached', async () => {
  const now = 1_000_000;
  const cache = makeCache({}); // hard miss
  const res = await cacheGetOrFetchSWR('match:m1:live', MD_TTL, MD_STALE,
    async () => null, // mirrors isInvalidMatchDetailPayload guard returning null
    { now, get: cache.get, set: cache.set });

  assert.equal(res.data, null, 'invalid match detail returns null data');
  assert.equal(res.fromCache, false);
  assert.equal(cache.store.has('match:m1:live'), false, 'null result must not be cached');
});

test('SWR match-detail: valid detail cached as envelope, served HIT next call', async () => {
  const now = 1_000_000;
  const store = new Map();
  const get = async (k) => (store.has(k) ? store.get(k) : null);
  const set = async (k, val) => { store.set(k, val); };
  const detail = { match_id: 'm2', status: 'live', team1: { name: 'IND' }, team2: { name: 'AUS' } };

  // Call 1: hard miss → fetch + write envelope → fromCache false (X-Cache MISS).
  const r1 = await cacheGetOrFetchSWR('match:m2:live', MD_TTL, MD_STALE,
    async () => detail, { now, get, set });
  assert.equal(r1.fromCache, false, 'first call is X-Cache MISS');
  assert.deepEqual(r1.data, detail);
  const stored = store.get('match:m2:live');
  assert.equal(stored.__swr__, true, 'match detail stored as SWR envelope');

  // Call 2 (still fresh): no fetch → fromCache true (X-Cache HIT).
  let fetchCalls = 0;
  const r2 = await cacheGetOrFetchSWR('match:m2:live', MD_TTL, MD_STALE,
    async () => { fetchCalls += 1; return detail; },
    { now: now + 2000, get, set });
  assert.equal(r2.fromCache, true, 'second call within ttl is a cache HIT');
  assert.equal(fetchCalls, 0, 'fresh hit must not fetch');
  assert.deepEqual(r2.data, detail);
});

test('SWR match-detail: physical TTL = ttl + staleWindow (20)', async () => {
  const now = 1_000_000;
  const store = new Map();
  let writtenTtl = null;
  const get = async (k) => (store.has(k) ? store.get(k) : null);
  const set = async (k, val, ttl) => { writtenTtl = ttl; store.set(k, val); };
  await cacheGetOrFetchSWR('match:m3:live', MD_TTL, MD_STALE,
    async () => ({ match_id: 'm3', status: 'live' }), { now, get, set });
  assert.equal(writtenTtl, MD_TTL + MD_STALE, 'physical Redis TTL must be 20 (15 + 5)');
});

test('SWR match-detail: worker envelope (cacheSetSWR shape) is read back unwrapped', () => {
  // live-score worker writes match:{id}:live via cacheSetSWR; /innings + the
  // worker itself read via unwrapSWR and must see the real detail object.
  const detail = { match_id: 'm4', innings: [{ a: 1 }] };
  const envelope = { __swr__: true, v: detail, f: 9_999 };
  assert.deepEqual(unwrapSWR(envelope), detail, 'match-detail worker envelope unwraps to the object');
});

test('SWR match-detail: fromCache is a strict boolean (never null) on both paths', async () => {
  // Regression: the /match/:id route returned fromCache:null because the handler
  // used the boolean only for the X-Cache header and omitted it from the body.
  // The helper must always hand the route a real boolean to forward; the route
  // now spreads it into { success, data, fromCache }.
  const now = 1_000_000;
  const store = new Map();
  const get = async (k) => (store.has(k) ? store.get(k) : null);
  const set = async (k, val) => { store.set(k, val); };
  const detail = { match_id: 'm5', status: 'live', team1: { name: 'IND' } };

  const miss = await cacheGetOrFetchSWR('match:m5:live', MD_TTL, MD_STALE,
    async () => detail, { now, get, set });
  assert.equal(typeof miss.fromCache, 'boolean', 'fromCache must be boolean on miss');
  assert.equal(miss.fromCache, false);

  const hit = await cacheGetOrFetchSWR('match:m5:live', MD_TTL, MD_STALE,
    async () => detail, { now: now + 1000, get, set });
  assert.equal(typeof hit.fromCache, 'boolean', 'fromCache must be boolean on hit');
  assert.equal(hit.fromCache, true);
});
