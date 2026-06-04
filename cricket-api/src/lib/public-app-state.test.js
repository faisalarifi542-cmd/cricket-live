import { test } from 'node:test';
import assert from 'node:assert/strict';

import { resolveAdsEnabled } from './public-app-state.js';

test('saved show_ads=true wins over legacy enableAds default false', () => {
  // This is the exact "Ads ON saves as OFF" regression: legacy default is
  // false but the admin explicitly saved show_ads=true.
  assert.equal(resolveAdsEnabled({ show_ads: true }, false), true);
});

test('saved show_ads=false is honored even if legacy enableAds is true', () => {
  assert.equal(resolveAdsEnabled({ show_ads: false }, true), false);
});

test('falls back to legacy enableAds when no ads_config is present', () => {
  assert.equal(resolveAdsEnabled({}, true), true);
  assert.equal(resolveAdsEnabled({}, false), false);
  assert.equal(resolveAdsEnabled(null, true), true);
});

test('falls back to legacy when ads_config has no show_ads key', () => {
  assert.equal(resolveAdsEnabled({ test_mode: true }, true), true);
  assert.equal(resolveAdsEnabled({ test_mode: true }, false), false);
});

test('accepts stringy/numeric truthy values for show_ads', () => {
  assert.equal(resolveAdsEnabled({ show_ads: 'true' }, false), true);
  assert.equal(resolveAdsEnabled({ show_ads: 1 }, false), true);
  assert.equal(resolveAdsEnabled({ show_ads: 'off' }, true), false);
  assert.equal(resolveAdsEnabled({ show_ads: 0 }, true), false);
});
