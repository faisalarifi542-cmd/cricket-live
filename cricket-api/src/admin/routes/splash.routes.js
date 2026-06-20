/**
 * Splash screen admin routes.
 *
 * Convenience CRUD over the 8 `splash_*` keys in `app_settings` (group
 * `splash`). Reuses the settings.view / settings.write permissions and the
 * shared base64 → /uploads image pipeline (so the admin page can upload splash
 * art the same way /assets does). The public `splash` block in /app/config is
 * built from these same rows by buildPublicAppConfig → buildSplashConfig.
 */
import { adminAuth, requirePermissions } from '../auth.js';
import { withAudit } from '../audit.js';
import { query } from '../../lib/db.js';
import { saveBase64Image } from '../../lib/uploads.js';
import { getRedis } from '../../lib/redis.js';
import {
  SPLASH_SETTING_KEYS,
  SPLASH_DEFAULTS,
  SPLASH_ASSET_SLOTS,
  buildSplashConfig,
} from '../../lib/splash-config.js';

function parseSettingValue(value) {
  if (value == null) return null;
  if (typeof value !== 'string') return value;
  try { return JSON.parse(value); } catch { return value; }
}

// Coerce an incoming value to the right primitive for each splash key so the
// admin form can post strings/numbers/booleans uniformly.
function coerceSplashValue(key, value) {
  if (key === 'splash_enabled' || key === 'splash_skip_after_first_launch') {
    if (typeof value === 'boolean') return value;
    const t = String(value).trim().toLowerCase();
    return ['1', 'true', 'yes', 'on'].includes(t);
  }
  if (key === 'splash_duration_ms') {
    const n = Number(value);
    if (!Number.isFinite(n)) return SPLASH_DEFAULTS[key];
    return Math.min(10000, Math.max(800, Math.round(n)));
  }
  // URL keys: trimmed string (may be empty to clear).
  return String(value ?? '').trim();
}

async function loadSplashSettings() {
  let rows = [];
  try {
    rows = await query(
      `SELECT setting_key, setting_value FROM app_settings WHERE setting_key IN (${SPLASH_SETTING_KEYS.map(() => '?').join(', ')})`,
      SPLASH_SETTING_KEYS,
    );
  } catch {
    rows = [];
  }
  const map = { ...SPLASH_DEFAULTS };
  for (const row of rows) {
    map[row.setting_key] = parseSettingValue(row.setting_value);
  }
  return map;
}

async function invalidateConfigCache() {
  const redis = getRedis();
  await redis
    .del('appdata:app:config', 'app:config')
    .catch(() => null);
}

export default async function splashRoutes(fastify) {
  fastify.addHook('preHandler', adminAuth);

  // ---------- Read current splash settings + resolved public config ----------
  fastify.get('/', { preHandler: [requirePermissions('settings.view')] }, async () => {
    const settings = await loadSplashSettings();
    return {
      success: true,
      data: {
        settings,
        resolved: buildSplashConfig(settings),
        slots: SPLASH_ASSET_SLOTS,
        keys: SPLASH_SETTING_KEYS,
        defaults: SPLASH_DEFAULTS,
      },
    };
  });

  // ---------- Image upload (base64 → saved file + absolute public URL) ----------
  fastify.post(
    '/upload-image',
    { preHandler: [requirePermissions('settings.write')], bodyLimit: 8 * 1024 * 1024 },
    async (request, reply) => {
      const body = request.body || {};
      const data = body.dataUrl || body.data || body.image || '';
      try {
        const { relativeUrl, bytes } = saveBase64Image(data, body.mimeType || '');
        const proto = request.headers['x-forwarded-proto'] || request.protocol || 'https';
        const host = request.headers['x-forwarded-host'] || request.headers.host;
        const url = host ? `${proto}://${host}${relativeUrl}` : relativeUrl;
        await withAudit(
          request,
          { action: 'splash.image.upload', entityType: 'upload', newValue: { url, bytes } },
          async () => null,
        );
        return reply.code(201).send({ success: true, url, relativeUrl, bytes });
      } catch (err) {
        return reply
          .code(err.statusCode || 500)
          .send({ success: false, error: err.message || 'Upload failed' });
      }
    },
  );

  // ---------- Bulk update splash settings ----------
  fastify.put('/', { preHandler: [requirePermissions('settings.write')] }, async (request, reply) => {
    const body = request.body || {};
    // Accept either { settings: {...} } or a flat body of splash_* keys.
    const incoming = body.settings && typeof body.settings === 'object' ? body.settings : body;
    const updates = [];
    for (const key of SPLASH_SETTING_KEYS) {
      if (incoming[key] === undefined) continue;
      updates.push([key, coerceSplashValue(key, incoming[key])]);
    }
    if (!updates.length) {
      return reply.code(400).send({ success: false, error: 'No splash settings provided' });
    }
    const old = await loadSplashSettings();
    await withAudit(
      request,
      {
        action: 'splash.update',
        entityType: 'app_setting',
        entityId: 'splash',
        oldValue: old,
        newValue: Object.fromEntries(updates),
      },
      async () => {
        for (const [key, value] of updates) {
          await query(
            `INSERT INTO app_settings (setting_key, setting_value, setting_group, \`group\`, is_public, description, updated_by)
               VALUES (?, ?, 'splash', 'splash', 1, 'Premium splash screen', ?)
               ON DUPLICATE KEY UPDATE setting_value = VALUES(setting_value),
                                       setting_group = 'splash',
                                       \`group\` = 'splash',
                                       is_public = 1,
                                       updated_by = VALUES(updated_by)`,
            [key, JSON.stringify(value), request.adminUser.id],
          );
        }
      },
    );
    await invalidateConfigCache();
    const settings = await loadSplashSettings();
    return { success: true, data: { settings, resolved: buildSplashConfig(settings) } };
  });
}
