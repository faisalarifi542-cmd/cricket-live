import { test } from 'node:test';
import assert from 'node:assert/strict';

import { CricinfoProvider } from './index.js';
import { cricinfoClient } from './client.js';
import providerManager from '../provider-manager.js';
import { BaseProvider } from '../base-provider.js';
import {
  ProviderIncompleteData,
  isProviderSentinel,
  isUsableResult,
} from '../provider-results.js';

// The provider calls methods on the shared `cricinfoClient` object, so we swap
// them per-test to simulate ESPN responses without touching the network. Each
// helper restores the originals so tests stay independent.
function withClientStub(overrides, fn) {
  const original = {};
  for (const key of Object.keys(overrides)) {
    original[key] = cricinfoClient[key];
    cricinfoClient[key] = overrides[key];
  }
  return (async () => {
    try {
      return await fn();
    } finally {
      Object.assign(cricinfoClient, original);
    }
  })();
}

const missingSeriesError = (matchId) =>
  new Error(`cricinfo getSummary: no seriesId known for match ${matchId}`);

// --- 1. Unknown Cricbuzz match id → typed sentinel, not a throw --------------

test('getMatchInfo with unknown Cricbuzz match id returns ProviderIncompleteData', async () => {
  const provider = new CricinfoProvider();
  await withClientStub(
    { getSummary: async () => { throw missingSeriesError('156691'); } },
    async () => {
      const result = await provider.getMatchInfo('156691');
      assert.ok(result instanceof ProviderIncompleteData, 'expected a sentinel, not a throw');
      assert.equal(result.reason, 'missing_series_mapping');
      assert.equal(result.provider, 'cricinfo');
      assert.equal(result.matchId, '156691');
      assert.match(result.message, /belongs to another provider ID space/i);
    },
  );
});

test('getScorecard and getCommentary also soft-fall-through on missing mapping', async () => {
  const provider = new CricinfoProvider();
  await withClientStub(
    {
      getSummary: async () => { throw missingSeriesError('161051'); },
      getPlayByPlay: async () => { throw missingSeriesError('161051'); },
    },
    async () => {
      const card = await provider.getScorecard('161051');
      const comm = await provider.getCommentary('161051');
      for (const [label, r] of [['getScorecard', card], ['getCommentary', comm]]) {
        assert.ok(r instanceof ProviderIncompleteData, `${label} should return a sentinel`);
        assert.equal(r.reason, 'missing_series_mapping', `${label} reason`);
        assert.equal(r.matchId, '161051', `${label} matchId`);
      }
    },
  );
});

// --- 2. Health is NOT decremented for a missing-mapping miss -----------------

test('Cricinfo health does not fail for repeated missing series mappings', async () => {
  const provider = new CricinfoProvider();
  await withClientStub(
    { getSummary: async () => { throw missingSeriesError('999999'); } },
    async () => {
      // Poll far past maxConsecutiveFailures (5) — a false "down" would trip here.
      for (let i = 0; i < 20; i++) {
        // eslint-disable-next-line no-await-in-loop
        const r = await provider.getMatchInfo('999999');
        assert.ok(isProviderSentinel(r));
      }
      assert.equal(provider.consecutiveFailures, 0, 'missing mapping must not accrue failures');
      assert.equal(provider.healthy, true, 'provider must stay healthy');
      assert.equal(provider.isAvailable(), true, 'provider must stay available');
    },
  );
});

// --- 3. provider-manager falls through to the next provider normally ---------

test('provider-manager falls through Cricinfo sentinel to Cricbuzz', async () => {
  // Stubbed Cricbuzz (priority 1) that serves the real data.
  class FakeCricbuzz extends BaseProvider {
    constructor() { super('cricbuzz', 1); }
    async getMatchInfo() { return { matchId: '156691', score: 'SLA 273/5' }; }
  }
  const cricbuzz = new FakeCricbuzz();
  const cricinfo = new CricinfoProvider();

  // Pin the manager to our two providers (cricbuzz first) for this call, then
  // restore. resolveProviders() returns whatever order we inject here.
  const originalResolve = providerManager.resolveProviders;
  providerManager.resolveProviders = () => [cricbuzz, cricinfo];
  providerManager._cfg = { at: Date.now(), dbOk: true, order: [cricbuzz, cricinfo] };

  try {
    await withClientStub(
      { getSummary: async () => { throw missingSeriesError('156691'); } },
      async () => {
        const out = await providerManager.execute('getMatchInfo', '156691');
        assert.equal(out.provider, 'cricbuzz');
        assert.deepEqual(out.data, { matchId: '156691', score: 'SLA 273/5' });
        assert.equal(cricinfo.healthy, true, 'Cricinfo stays healthy after fall-through');
        assert.equal(cricinfo.consecutiveFailures, 0, 'no failure recorded on fall-through');
      },
    );
  } finally {
    providerManager.resolveProviders = originalResolve;
    providerManager.invalidateConfig();
  }
});

test('sentinel is recognised as non-usable by isUsableResult', () => {
  const sentinel = new ProviderIncompleteData('getMatchInfo', 'missing_series_mapping');
  assert.equal(isUsableResult(sentinel), false);
  assert.equal(isUsableResult({ real: 'data' }), true);
});

// --- 4. Real ESPN errors STILL count as failures -----------------------------

test('real ESPN error still throws and records a health failure', async () => {
  const provider = new CricinfoProvider();
  await withClientStub(
    { getSummary: async () => { throw new Error('timeout of 10000ms exceeded'); } },
    async () => {
      await assert.rejects(() => provider.getMatchInfo('156691'), /timeout of 10000ms/);
      assert.equal(provider.consecutiveFailures, 1, 'genuine error must accrue a failure');
    },
  );
});

test('five real ESPN errors mark the provider unhealthy (unchanged behavior)', async () => {
  const provider = new CricinfoProvider();
  await withClientStub(
    { getSummary: async () => { throw new Error('ECONNRESET'); } },
    async () => {
      for (let i = 0; i < 5; i++) {
        // eslint-disable-next-line no-await-in-loop
        await assert.rejects(() => provider.getMatchInfo('156691'));
      }
      assert.equal(provider.healthy, false, 'genuine errors must still trip the cooldown');
    },
  );
});

// --- 5. Remaining detail paths also soft-skip missing mapping ----------------

test('getMatchHeader returns null without recording failure on missing mapping', async () => {
  const provider = new CricinfoProvider();
  await withClientStub(
    { getSummary: async () => { throw missingSeriesError('156691'); } },
    async () => {
      const header = await provider.getMatchHeader('156691');
      assert.equal(header, null, 'header is best-effort → null');
      assert.equal(provider.consecutiveFailures, 0, 'missing mapping must not accrue a failure');
      assert.equal(provider.healthy, true);
    },
  );
});

test('getFullCommentary returns sentinel without recording failure on missing mapping', async () => {
  const provider = new CricinfoProvider();
  await withClientStub(
    { getPlayByPlay: async () => { throw missingSeriesError('161051'); } },
    async () => {
      const r = await provider.getFullCommentary('161051', 1);
      assert.ok(r instanceof ProviderIncompleteData);
      assert.equal(r.reason, 'missing_series_mapping');
      assert.equal(provider.consecutiveFailures, 0);
      assert.equal(provider.healthy, true);
    },
  );
});

test('getMatchHeader still records a failure on a genuine error', async () => {
  const provider = new CricinfoProvider();
  await withClientStub(
    { getSummary: async () => { throw new Error('ETIMEDOUT'); } },
    async () => {
      const header = await provider.getMatchHeader('156691');
      assert.equal(header, null);
      assert.equal(provider.consecutiveFailures, 1, 'genuine error must still accrue a failure');
    },
  );
});

// --- 6. Health-state derivation ---------------------------------------------

test('healthState reflects up / down transitions for cricinfo', () => {
  const provider = new CricinfoProvider();
  assert.equal(provider.healthState(), 'up');
  assert.equal(provider.isConfigured(), true, 'cricinfo needs no API key');
  provider.healthy = false;
  assert.equal(provider.healthState(), 'down');
});
