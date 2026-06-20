import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
  resolvePlayerImage,
  PLAYER_IMAGE_MODES,
  DEFAULT_PLAYER_IMAGE_MODE,
} from './player-images.js';

const ADMIN = 'https://cdn.example.com/uploads/players/123.png';
const PROVIDER = 'https://static.cricbuzz.com/a/img/v1/i2/c456/i.jpg';

test('admin_first prefers the admin image, then provider, then null', () => {
  assert.equal(
    resolvePlayerImage({ mode: 'admin_first', adminImage: ADMIN, providerImage: PROVIDER }),
    ADMIN,
  );
  assert.equal(
    resolvePlayerImage({ mode: 'admin_first', adminImage: null, providerImage: PROVIDER }),
    PROVIDER,
  );
  assert.equal(
    resolvePlayerImage({ mode: 'admin_first', adminImage: null, providerImage: null }),
    null,
  );
});

test('cricbuzz_first prefers the provider image, then admin', () => {
  assert.equal(
    resolvePlayerImage({ mode: 'cricbuzz_first', adminImage: ADMIN, providerImage: PROVIDER }),
    PROVIDER,
  );
  assert.equal(
    resolvePlayerImage({ mode: 'cricbuzz_first', adminImage: ADMIN, providerImage: null }),
    ADMIN,
  );
});

test('admin_only never falls back to provider', () => {
  assert.equal(
    resolvePlayerImage({ mode: 'admin_only', adminImage: ADMIN, providerImage: PROVIDER }),
    ADMIN,
  );
  assert.equal(
    resolvePlayerImage({ mode: 'admin_only', adminImage: null, providerImage: PROVIDER }),
    null,
  );
});

test('cricbuzz_only never falls back to admin', () => {
  assert.equal(
    resolvePlayerImage({ mode: 'cricbuzz_only', adminImage: ADMIN, providerImage: PROVIDER }),
    PROVIDER,
  );
  assert.equal(
    resolvePlayerImage({ mode: 'cricbuzz_only', adminImage: ADMIN, providerImage: null }),
    null,
  );
});

test('initials_only always returns null (no image)', () => {
  assert.equal(
    resolvePlayerImage({ mode: 'initials_only', adminImage: ADMIN, providerImage: PROVIDER }),
    null,
  );
});

test('unknown/empty mode falls back to the default (admin_first)', () => {
  assert.equal(DEFAULT_PLAYER_IMAGE_MODE, 'admin_first');
  assert.equal(
    resolvePlayerImage({ mode: 'nonsense', adminImage: ADMIN, providerImage: PROVIDER }),
    ADMIN,
  );
  assert.equal(
    resolvePlayerImage({ mode: '', adminImage: null, providerImage: PROVIDER }),
    PROVIDER,
  );
});

test('blank/whitespace image strings are treated as missing', () => {
  assert.equal(
    resolvePlayerImage({ mode: 'admin_first', adminImage: '   ', providerImage: PROVIDER }),
    PROVIDER,
  );
  assert.equal(
    resolvePlayerImage({ mode: 'admin_first', adminImage: '   ', providerImage: '  ' }),
    null,
  );
});

test('PLAYER_IMAGE_MODES exposes exactly the five supported modes', () => {
  assert.deepEqual(PLAYER_IMAGE_MODES, [
    'admin_first',
    'cricbuzz_first',
    'admin_only',
    'cricbuzz_only',
    'initials_only',
  ]);
});
