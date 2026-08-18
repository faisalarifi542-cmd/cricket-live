import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';
import { getPool } from '../lib/db.js';
import bcrypt from 'bcryptjs';
import logger from '../lib/logger.js';

// SEED-1: this script used to hardcode a well-known admin username/password pair
// (and a published demo
// API key) with NO environment gate, so `npm run seed` pointed at a production
// database silently created an admin account whose password is committed to this
// repository. The credentials now come from the environment, fall back to a
// random secret that is printed exactly once, and the whole script refuses to run
// in production unless the operator explicitly forces it.
//
// Mirrors the already-safe pattern in src/admin/db/admin-seed.js.

/** bcrypt cost. 12 matches admin-seed.js; the old value here was 10. */
const BCRYPT_COST = 12;

/**
 * Decide the dev-seed credentials from the environment.
 * Exported for tests — it must never return a hardcoded password.
 */
export function resolveSeedCredentials(env = process.env) {
  const explicitPassword = env.SEED_ADMIN_PASSWORD;
  const explicitApiKey = env.SEED_API_KEY;
  return {
    username: env.SEED_ADMIN_USERNAME || 'admin',
    email: (env.SEED_ADMIN_EMAIL || 'admin@cricket-api.local').toLowerCase(),
    // base64url so the value is safe to paste into a shell or a header.
    password: explicitPassword || crypto.randomBytes(16).toString('base64url'),
    apiKey: explicitApiKey || `csk_${crypto.randomBytes(24).toString('base64url')}`,
    generatedPassword: !explicitPassword,
    generatedApiKey: !explicitApiKey,
  };
}

/**
 * Refuse to seed a production database with development fixtures.
 * Returns a reason string when seeding must be blocked, else null.
 */
export function blockedReason(env = process.env) {
  const isProd = String(env.NODE_ENV || '').toLowerCase() === 'production';
  if (!isProd) return null;
  if (String(env.SEED_FORCE || '') === '1') return null;
  return (
    'Refusing to run the development seed with NODE_ENV=production. This script ' +
    'inserts demo fixtures (test match, placeholder stream) that must never exist ' +
    'in production. Use src/admin/db/admin-seed.js for real deployments, or set ' +
    'SEED_FORCE=1 together with SEED_ADMIN_PASSWORD to override deliberately.'
  );
}

async function seed() {
  const blocked = blockedReason();
  if (blocked) {
    logger.error(`Seed aborted: ${blocked}`);
    console.error(`\nSeed aborted.\n${blocked}\n`);
    process.exitCode = 1;
    return;
  }

  const pool = getPool();
  const creds = resolveSeedCredentials();

  try {
    logger.info('Seeding database...');

    // Create default admin user
    const passwordHash = await bcrypt.hash(creds.password, BCRYPT_COST);
    await pool.execute(
      `INSERT IGNORE INTO users (username, email, password_hash, role)
       VALUES (?, ?, ?, 'admin')`,
      [creds.username, creds.email, passwordHash]
    );

    // Create a default free API key
    const apiKeyRaw = creds.apiKey;
    const keyHash = await bcrypt.hash(apiKeyRaw, BCRYPT_COST);
    await pool.execute(
      `INSERT IGNORE INTO api_keys (key_hash, name, email, tier, rate_limit)
       VALUES (?, 'Demo Key', 'demo@cricket-api.local', 'free', 100)`,
      [keyHash]
    );

    // Seed admin-controlled test live match
    const testMatchId = '999001';
    await pool.execute(
      `INSERT IGNORE INTO manual_matches
       (match_external_id, title, team1_name, team2_name, team1_short, team2_short,
        status, match_state, venue, is_live, is_test, is_enabled, sort_order)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        testMatchId,
        'Afghanistan vs India - Test Live Stream',
        'Afghanistan',
        'India',
        'AFG',
        'IND',
        'live',
        'live',
        'Test Stream Venue',
        1, 1, 1, 1,
      ]
    );

    // Seed a placeholder HLS stream for the test match
    await pool.execute(
      `INSERT IGNORE INTO match_streams
       (match_external_id, match_title, title, team_a, team_b,
        quality, language, server_name, stream_type, stream_url,
        is_active, is_premium, priority, status)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        testMatchId,
        'Afghanistan vs India - Test Live Stream',
        'Test HLS Stream',
        'Afghanistan',
        'India',
        'HD',
        'English',
        'Server 1',
        'hls',
        'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
        1, 0, 1, 'unknown',
      ]
    );

    logger.info('Database seeded successfully');
    // Never log the credentials themselves through the app logger (it can ship to
    // files/aggregators). Print to stdout once, and only what the operator does
    // not already know because they supplied it via the environment.
    if (creds.generatedPassword || creds.generatedApiKey) {
      console.log('==============================================');
      console.log(' Development seed credentials (save these now):');
      if (creds.generatedPassword) {
        console.log(`   admin user:   ${creds.username}`);
        console.log(`   admin pass:   ${creds.password}`);
      }
      if (creds.generatedApiKey) {
        console.log(`   demo api key: ${apiKeyRaw}`);
      }
      console.log('==============================================');
      console.log(' Set SEED_ADMIN_PASSWORD / SEED_API_KEY to pin these values.');
    } else {
      logger.info('Seeded admin + demo API key from the supplied environment values');
    }
  } catch (err) {
    logger.error(`Seed failed: ${err.message || err.toString()}`);
    console.error('Seed error:', err);
    process.exitCode = 1;
  } finally {
    await pool.end();
  }
}

// Only seed when executed directly (`node src/db/seed.js`). Importing this module
// — as the regression test does — must not touch the database.
if (process.argv[1] && fileURLToPath(import.meta.url) === resolve(process.argv[1])) {
  seed();
}
