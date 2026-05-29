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
