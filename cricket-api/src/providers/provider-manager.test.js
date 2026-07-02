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
    ...methods,
  };
}

// Prime the singleton's config cache as FRESH so loadConfig() short-circuits on
// TTL and never touches the DB. We then drive resolveProviders via the injected
// order. Each test sets `_cfg` explicitly.
function useProviders(list, { dbOk = true } = {}) {
  providerManager._cfg = { at: Date.now(), dbOk, order: dbOk ? list : null };
  if (!dbOk) providerManager.fallback = list; // fallback path uses this.fallback
}

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
  // espn is first in priority order but yields no usable data → fall through.
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
  useProviders([], { dbOk: true }); // dbOk true + empty order = admin disabled all
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
  useProviders([cb], { dbOk: false }); // dbOk false → resolveProviders uses this.fallback

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
