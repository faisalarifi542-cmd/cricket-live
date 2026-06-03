import { getPool } from '../lib/db.js';
import bcrypt from 'bcryptjs';
import logger from '../lib/logger.js';

async function seed() {
  const pool = getPool();

  try {
    logger.info('Seeding database...');

    // Create default admin user
    const passwordHash = await bcrypt.hash('admin123', 10);
    await pool.execute(
      `INSERT IGNORE INTO users (username, email, password_hash, role)
       VALUES (?, ?, ?, 'admin')`,
      ['admin', 'admin@cricket-api.local', passwordHash]
    );

    // Create a default free API key
    const apiKeyRaw = 'csk_demo_key_for_development_only';
    const keyHash = await bcrypt.hash(apiKeyRaw, 10);
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
    logger.info('Default admin: admin / admin123');
    logger.info(`Demo API key: ${apiKeyRaw}`);
  } catch (err) {
    logger.error(`Seed failed: ${err.message || err.toString()}`);
    console.error('Seed error:', err);
  } finally {
    await pool.end();
  }
}

seed();
