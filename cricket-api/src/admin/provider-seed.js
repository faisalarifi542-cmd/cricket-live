import { query } from '../lib/db.js';

export const DEFAULT_PROVIDER = {
  slug: 'webcrichd-cricbuzz',
  name: 'WebCricHD Cricbuzz API',
  providerType: 'cricbuzz',
  baseUrl: 'https://api.webcrichd.co',
  description: 'Primary app cricket data API powered by the Cricbuzz provider inside cricket-api.',
  priority: 1,
  timeoutMs: 8000,
  rateLimitPerMinute: 60,
  role: 'primary',
};

// ESPN Cricinfo fallback provider (site.api / site.web.api JSON). Seeded active
// at priority 2 so the app tries Cricbuzz first, then ESPN for matches the
// primary lacks. Admin can reorder/disable it from the Providers page.
export const CRICINFO_PROVIDER = {
  slug: 'espn-cricinfo',
  name: 'ESPN Cricinfo',
  providerType: 'cricinfo',
  baseUrl: 'https://site.api.espn.com',
  description: 'Fallback cricket data provider powered by ESPN Cricinfo public site.api endpoints.',
  priority: 2,
  timeoutMs: 10000,
  rateLimitPerMinute: 60,
  role: 'fallback',
};

export async function ensureProviderSchema() {
  await query(`
    CREATE TABLE IF NOT EXISTS api_providers (
      id INT AUTO_INCREMENT PRIMARY KEY,
      slug VARCHAR(120) NOT NULL UNIQUE,
      name VARCHAR(160) NOT NULL,
      provider_type VARCHAR(50) DEFAULT 'custom',
      base_url VARCHAR(500) NULL,
      description TEXT NULL,
      priority INT DEFAULT 100,
      timeout_ms INT DEFAULT 8000,
      rate_limit_per_minute INT DEFAULT 60,
      is_active TINYINT(1) DEFAULT 1,
      health_status VARCHAR(30) DEFAULT 'unknown',
      last_success_at DATETIME NULL,
      last_failure_at DATETIME NULL,
      metadata JSON NULL,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    )
  `);
  const columns = await query(`SHOW COLUMNS FROM api_providers`).catch(() => []);
  const names = new Set(columns.map((c) => c.Field));
  const add = async (name, sql) => {
    if (!names.has(name)) await query(`ALTER TABLE api_providers ADD COLUMN ${sql}`);
  };
  await add('provider_type', `provider_type VARCHAR(50) DEFAULT 'custom' AFTER name`);
  await add('timeout_ms', `timeout_ms INT DEFAULT 8000 AFTER priority`);
  await add('rate_limit_per_minute', `rate_limit_per_minute INT DEFAULT 60 AFTER timeout_ms`);
  await add('health_status', `health_status VARCHAR(30) DEFAULT 'unknown' AFTER is_active`);
  await add('last_success_at', `last_success_at DATETIME NULL AFTER health_status`);
  await add('last_failure_at', `last_failure_at DATETIME NULL AFTER last_success_at`);
  await add('metadata', `metadata JSON NULL AFTER last_failure_at`);
}

export async function ensureDefaultProvider() {
  await ensureProviderSchema();
  const meta = JSON.stringify({ role: DEFAULT_PROVIDER.role, source: 'cricket-api', appBaseUrl: DEFAULT_PROVIDER.baseUrl });
  await query(
    `INSERT INTO api_providers
       (slug, name, provider_type, base_url, description, priority, timeout_ms,
        rate_limit_per_minute, is_active, health_status, metadata)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, 'unknown', ?)
     ON DUPLICATE KEY UPDATE
       name = VALUES(name),
       provider_type = VALUES(provider_type),
       base_url = VALUES(base_url),
       description = VALUES(description),
       priority = VALUES(priority),
       timeout_ms = VALUES(timeout_ms),
       rate_limit_per_minute = VALUES(rate_limit_per_minute),
       is_active = 1,
       metadata = VALUES(metadata)`,
    [
      DEFAULT_PROVIDER.slug,
      DEFAULT_PROVIDER.name,
      DEFAULT_PROVIDER.providerType,
      DEFAULT_PROVIDER.baseUrl,
      DEFAULT_PROVIDER.description,
      DEFAULT_PROVIDER.priority,
      DEFAULT_PROVIDER.timeoutMs,
      DEFAULT_PROVIDER.rateLimitPerMinute,
      meta,
    ],
  );
  await ensureCricinfoProvider();
  const rows = await query(`SELECT * FROM api_providers WHERE slug = ? LIMIT 1`, [DEFAULT_PROVIDER.slug]);
  return rows[0] || null;
}

/**
 * Seed the ESPN Cricinfo fallback row. Unlike the primary, this deliberately
 * does NOT force `is_active` on update — the row is created enabled, but if an
 * admin later disables it, that choice must survive subsequent seed runs (this
 * function runs on every admin providers GET).
 */
export async function ensureCricinfoProvider() {
  await ensureProviderSchema();
  const meta = JSON.stringify({ role: CRICINFO_PROVIDER.role, source: 'cricket-api', appBaseUrl: CRICINFO_PROVIDER.baseUrl });
  await query(
    `INSERT INTO api_providers
       (slug, name, provider_type, base_url, description, priority, timeout_ms,
        rate_limit_per_minute, is_active, health_status, metadata)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, 'unknown', ?)
     ON DUPLICATE KEY UPDATE
       name = VALUES(name),
       provider_type = VALUES(provider_type),
       base_url = VALUES(base_url),
       description = VALUES(description),
       priority = VALUES(priority),
       timeout_ms = VALUES(timeout_ms),
       rate_limit_per_minute = VALUES(rate_limit_per_minute),
       metadata = VALUES(metadata)`,
    [
      CRICINFO_PROVIDER.slug,
      CRICINFO_PROVIDER.name,
      CRICINFO_PROVIDER.providerType,
      CRICINFO_PROVIDER.baseUrl,
      CRICINFO_PROVIDER.description,
      CRICINFO_PROVIDER.priority,
      CRICINFO_PROVIDER.timeoutMs,
      CRICINFO_PROVIDER.rateLimitPerMinute,
      meta,
    ],
  );
}
