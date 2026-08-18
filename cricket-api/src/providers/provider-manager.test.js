import { test } from 'node:test';
import assert from 'node:assert/strict';

import providerManager, { NoActiveProviderError } from './provider-manager.js';
import { ProviderFeatureNotSupported, ProviderIncompleteData } from './provider-results.js';

// A minimal fake provider with the health surface execute() relies on.
function fakeProvider(name, methods = {}) {
  return {
    name,
    priority: 1,
    healthy: true,
    isAvailable: () => true,
    isConfigured: () => true,
    configReason: () => null,
    healthState: () => 'up',
    getCapabilities: () => ({}),
    ...methods,
  };
}

// Prime the singleton's config cache as FRESH so loadConfig() short-circuits on
// TTL and never touches the DB. We then drive resolveProviders via the injected
// order. Each test sets `_cfg` explicitly.
function useProviders(list, { dbOk = true } = {}) {
  providerManager._cfg = { at: Date.now(), dbOk, order: dbOk ? list : null };
  if (!dbOk) providerManager.fallback = list;
}

// --- Sentinel fallthrough tests (existing) ---

test('execute skips a provider that returns ProviderFeatureNotSupported', async () => {
  const espn = fakeProvider('cricinfo', {
    async getData() {
      return new ProviderFeatureNotSupported('getData');
    },
  });
  const cb = fakeProvider('cricbuzz', {
    async getData() {
      return [{ ok: true }];
    },
  });
  useProviders([espn, cb]);

  const { data, provider } = await providerManager.execute('getData');
  assert.equal(provider, 'cricbuzz');
  assert.deepEqual(data, [{ ok: true }]);
});

test('execute skips ProviderIncompleteData and returns the next usable result', async () => {
  const espn = fakeProvider('cricinfo', {
    async getScorecard() {
      return new ProviderIncompleteData('getScorecard');
    },
  });
  const cb = fakeProvider('cricbuzz', {
    async getScorecard() {
      return { innings: [{ innings_number: 1 }] };
    },
  });
  useProviders([espn, cb]);

  const { provider } = await providerManager.execute('getScorecard');
  assert.equal(provider, 'cricbuzz');
});

test('execute returns the first provider when it yields usable data', async () => {
  const espn = fakeProvider('cricinfo', {
    async getData() {
      return [{ from: 'espn' }];
    },
  });
  const cb = fakeProvider('cricbuzz', {
    async getData() {
      throw new Error('should not be called');
    },
  });
  useProviders([espn, cb]);

  const { data, provider } = await providerManager.execute('getData');
  assert.equal(provider, 'cricinfo');
  assert.deepEqual(data, [{ from: 'espn' }]);
});

test('execute throws NoActiveProviderError when DB reachable but all disabled', async () => {
  useProviders([], { dbOk: true });
  await assert.rejects(
    () => providerManager.execute('getData'),
    (err) => err instanceof NoActiveProviderError,
  );
});

test('execute falls back to hardcoded order when DB is unreachable', async () => {
  const cb = fakeProvider('cricbuzz', {
    async getData() {
      return [{ from: 'fallback' }];
    },
  });
  useProviders([cb], { dbOk: false });

  const { provider, data } = await providerManager.execute('getData');
  assert.equal(provider, 'cricbuzz');
  assert.deepEqual(data, [{ from: 'fallback' }]);
});

test('execute throws (all failed) when every provider errors or yields nothing', async () => {
  const a = fakeProvider('cricinfo', {
    async getData() {
      return new ProviderFeatureNotSupported('getData');
    },
  });
  const b = fakeProvider('cricbuzz', {
    async getData() {
      throw new Error('boom');
    },
  });
  useProviders([a, b]);
  await assert.rejects(() => providerManager.execute('getData'), /All providers failed/);
});

// --- Primary / fallback ordering ---

test('Cricinfo primary → tried first when it supports the method', async () => {
  const cricinfo = fakeProvider('cricinfo', {
    async getMatchInfo() {
      return { matchId: '123', source: 'espn' };
    },
  });
  const cricbuzz = fakeProvider('cricbuzz', {
    async getMatchInfo() {
      throw new Error('should not be called');
    },
  });
  // Cricinfo first in the list = primary
  useProviders([cricinfo, cricbuzz]);

  const { data, provider } = await providerManager.execute('getMatchInfo', '123');
  assert.equal(provider, 'cricinfo');
  assert.deepEqual(data, { matchId: '123', source: 'espn' });
});

test('Cricinfo primary but unsupported capability → falls through to Cricbuzz', async () => {
  const cricinfo = fakeProvider('cricinfo', {
    async getLiveLine() {
      return new ProviderFeatureNotSupported('getLiveLine');
    },
  });
  const cricbuzz = fakeProvider('cricbuzz', {
    async getLiveLine() {
      return { latestBall: { runs: 4 } };
    },
  });
  // Cricinfo primary, Cricbuzz fallback
  useProviders([cricinfo, cricbuzz]);

  const { data, provider } = await providerManager.execute('getLiveLine', '123');
  assert.equal(provider, 'cricbuzz');
  assert.deepEqual(data, { latestBall: { runs: 4 } });
});

test('Cricinfo primary with missing series mapping → returns sentinel, falls through', async () => {
  const cricinfo = fakeProvider('cricinfo', {
    async getMatchInfo() {
      return new ProviderIncompleteData('getMatchInfo', 'missing_series_mapping');
    },
  });
  const cricbuzz = fakeProvider('cricbuzz', {
    async getMatchInfo() {
      return { matchId: '456', source: 'cricbuzz' };
    },
  });
  useProviders([cricinfo, cricbuzz]);

  const { data, provider } = await providerManager.execute('getMatchInfo', '456');
  assert.equal(provider, 'cricbuzz');
  assert.equal(data.source, 'cricbuzz');
});

// --- Misconfigured provider skip ---

test('CricketData missing API key → skipped as misconfigured', async () => {
  const cricketdata = fakeProvider('cricketdata', {
    isConfigured: () => false,
    configReason: () => 'missing_api_key',
    healthState: () => 'misconfigured',
    async getLiveMatches() {
      throw new Error('should not be called');
    },
  });
  const cricbuzz = fakeProvider('cricbuzz', {
    async getLiveMatches() {
      return [{ match_id: '1' }];
    },
  });
  useProviders([cricketdata, cricbuzz]);

  const { data, provider } = await providerManager.execute('getLiveMatches');
  assert.equal(provider, 'cricbuzz');
  assert.equal(data.length, 1);
});

// --- Health state ---

test('getHealthStatus exposes capabilities and state for all known providers', () => {
  const statuses = providerManager.getHealthStatus();
  assert.ok(statuses.length >= 2, 'should include at least cricbuzz and cricinfo');

  const cbStatus = statuses.find((s) => s.name === 'cricbuzz');
  assert.ok(cbStatus, 'should include cricbuzz');
  assert.equal(cbStatus.configured, true, 'cricbuzz needs no config');
  assert.ok(cbStatus.capabilities, 'cricbuzz should expose capabilities');
  assert.ok(Object.keys(cbStatus.capabilities).length > 0, 'cricbuzz must have capabilities');

  const ciStatus = statuses.find((s) => s.name === 'cricinfo');
  assert.ok(ciStatus, 'should include cricinfo');
  assert.equal(ciStatus.configured, true, 'cricinfo needs no API key');

  const cdStatus = statuses.find((s) => s.name === 'cricketdata');
  if (cdStatus) {
    // CricketData without key → misconfigured
    assert.ok(
      cdStatus.state === 'misconfigured' || cdStatus.configured === false || cdStatus.reason === 'missing_api_key',
      'CricketData should report misconfigured when no API key',
    );
  }
});

// --- Capabilities ---

test('Cricbuzz getCapabilities reports full for all methods', async () => {
  const cb = providerManager.getProvider('cricbuzz');
  const caps = cb.getCapabilities();
  assert.ok(Object.keys(caps).length > 20, 'Cricbuzz should have many capabilities');
  for (const [method, level] of Object.entries(caps)) {
    assert.equal(level, 'full', `Cricbuzz ${method} should be full`);
  }
});

test('Cricinfo getCapabilities reports mixed full/limited/unsupported', async () => {
  const ci = providerManager.getProvider('cricinfo');
  const caps = ci.getCapabilities();
  assert.equal(caps.matchInfo, 'full');
  assert.equal(caps.scorecard, 'full');
  assert.equal(caps.commentary, 'full');
  assert.equal(caps.liveLine, 'limited');        // derived from playbyplay
  assert.equal(caps.matchSquads, 'limited');      // from /summary rosters
  assert.equal(caps.matchNews, 'limited');         // from /summary news.articles
  assert.equal(caps.seriesTeams, 'limited');       // from /scoreboard teams
  assert.equal(caps.matchStats, 'limited');        // from /summary leaders
  assert.equal(caps.matchOvers, 'limited');        // derived from playbyplay
  assert.equal(caps.overByOver, 'limited');        // derived from playbyplay
  assert.equal(caps.ballsMap, 'limited');          // derived from playbyplay
  assert.equal(caps.playerInfo, 'full');           // roster cache + v3 athlete endpoint
  assert.equal(caps.pointsTable, 'full');          // ESPN /standings endpoint
  assert.equal(caps.fullSchedule, 'full');         // scoreboard calendar date ranges
  assert.equal(caps.teamInfo, 'limited');          // from roster cache
  assert.equal(caps.rankings, 'unsupported');      // 404 on API, 403 on HTML
  assert.equal(caps.newsStories, 'unsupported');   // 403 on HTML pages
  assert.equal(caps.highlights, 'unsupported');    // videos always empty
});

// --- Invalid config ---

test('invalidateConfig clears the TTL cache', () => {
  // Set a future cache time
  providerManager._cfg = { at: Date.now(), dbOk: true, order: [] };
  providerManager.invalidateConfig();
  assert.equal(providerManager._cfg.at, 0);
  assert.equal(providerManager._cfg.order, null);
});
