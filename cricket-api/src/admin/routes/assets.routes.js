/**
 * App Assets admin routes.
 *
 * Lets operators manage admin-controlled decorative images (backgrounds,
 * overlays) that the Flutter app loads at runtime. Each asset is keyed by
 * (asset_key, theme). The app always ships a local fallback, so a missing or
 * inactive asset degrades gracefully.
 *
 * Reuses the settings.view / settings.write permissions (no new RBAC rows).
 * Image upload reuses the shared base64 → /uploads pipeline.
 */
import crypto from 'node:crypto';
import { adminAuth, requirePermissions } from '../auth.js';
import { withAudit } from '../audit.js';
import { query } from '../../lib/db.js';
import { saveBase64Image } from '../../lib/uploads.js';

// Predefined keys the app knows how to consume. The admin UI renders one row
// per key even before a URL is set, so operators see the full catalog. Keep in
// sync with the Flutter RemoteAssetsService key constants.
export const ASSET_KEYS = [
  // --- Live Player ---
  { key: 'live_player_bg_dark', category: 'Live Player', theme: 'dark', label: 'Live Player background (dark)', where: 'Live player screen backdrop (dark)', dimensions: '1080x1920', fallback: 'assets/images/live_stream/backgrounds/live_screen_dark_background.png', large: false, wired: true },
  { key: 'live_player_bg_light', category: 'Live Player', theme: 'light', label: 'Live Player background (light)', where: 'Live player screen backdrop (light)', dimensions: '1080x1920', fallback: null, large: false, wired: false },
  { key: 'player_surface_bg', category: 'Live Player', theme: 'both', label: 'Player video poster (16:9)', where: 'Live player video surface before playback starts', dimensions: '1280x720', fallback: 'assets/images/live_stream/backgrounds/stadium_player_background_clean_16x9.png', large: true, wired: true },
  // --- Home ---
  { key: 'home_hero_bg_dark', category: 'Home', theme: 'dark', label: 'Home hero background (dark)', where: 'Home hero + featured card (dark)', dimensions: '1080x600', fallback: 'assets/images/home/home_top_featured_card.png', large: true, wired: true },
  { key: 'home_hero_bg_light', category: 'Home', theme: 'light', label: 'Home hero background (light)', where: 'Home hero (light)', dimensions: '1080x600', fallback: 'assets/images/light_mode/hero_stadium_bg.png', large: false, wired: false },
  { key: 'home_backdrop', category: 'Home', theme: 'both', label: 'Home page backdrop', where: 'Home screen full backdrop', dimensions: '1080x1920', fallback: 'assets/images/home/futuristic_stadium_ui_backdrop.png', large: true, wired: true },
  { key: 'home_featured_card_bg', category: 'Home', theme: 'both', label: 'Home featured card background', where: 'Home featured card (reserved)', dimensions: '800x300', fallback: null, large: false, wired: false },
  // --- Matches ---
  { key: 'matches_backdrop', category: 'Matches', theme: 'both', label: 'Matches page backdrop', where: 'Matches screen full backdrop', dimensions: '1080x1920', fallback: 'assets/images/matches/matches_top_bg.png', large: false, wired: true },
  { key: 'match_card_live_bg', category: 'Matches', theme: 'both', label: 'Match card — live', where: 'Matches + Home live match cards', dimensions: '800x300', fallback: 'assets/images/matches/match_card_bg_live.png', large: false, wired: true },
  { key: 'match_card_upcoming_bg', category: 'Matches', theme: 'both', label: 'Match card — upcoming', where: 'Matches upcoming cards', dimensions: '800x300', fallback: 'assets/images/matches/match_card_bg_upcoming.png', large: false, wired: true },
  { key: 'match_card_finished_bg', category: 'Matches', theme: 'both', label: 'Match card — finished', where: 'Matches finished cards', dimensions: '800x300', fallback: 'assets/images/matches/match_card_bg_finished.png', large: false, wired: true },
  // --- Schedule ---
  { key: 'schedule_backdrop', category: 'Schedule', theme: 'both', label: 'Schedule header backdrop', where: 'Schedule screen top stadium header', dimensions: '1080x1920', fallback: 'assets/images/schedule/stadium_top_bg.png', large: true, wired: true },
  { key: 'schedule_match_card_bg', category: 'Schedule', theme: 'both', label: 'Schedule match card background', where: 'Schedule match cards', dimensions: '800x300', fallback: 'assets/images/schedule/match_card_bg.png', large: true, wired: true },
  // --- Match Details ---
  { key: 'match_details_header_bg', category: 'Match Details', theme: 'both', label: 'Match details score header', where: 'Match details score header (light + dark)', dimensions: '1080x720', fallback: 'assets/images/match_details/backgrounds/stadium_score_header_bg.png', large: true, wired: true },
  { key: 'stadium_bg_generic', category: 'Match Details', theme: 'both', label: 'Generic stadium background', where: 'Match details hero card stadium fill', dimensions: '1080x1920', fallback: 'assets/images/stadium_live.png', large: true, wired: true },
  // --- Series ---
  { key: 'series_hero_bg', category: 'Series', theme: 'both', label: 'Series detail hero background', where: 'Series detail hero', dimensions: '1080x400', fallback: 'assets/images/series/backgrounds/series_detail_hero_bg.png', large: true, wired: true },
  { key: 'series_backdrop', category: 'Series', theme: 'both', label: 'Series page top backdrop', where: 'Series detail screen backdrop', dimensions: '1080x1920', fallback: 'assets/images/series/backgrounds/series_page_top_backdrop.png', large: false, wired: true },
  { key: 'series_match_card_bg', category: 'Series', theme: 'both', label: 'Series match card background', where: 'Series overview + squads match cards', dimensions: '800x300', fallback: 'assets/images/series/backgrounds/series_match_card_bg.png', large: true, wired: true },
  { key: 'series_squad_section_bg', category: 'Series', theme: 'both', label: 'Series squad section background', where: 'Series squads section panel', dimensions: '1080x720', fallback: 'assets/images/series/backgrounds/series_squad_section_bg.png', large: true, wired: true },
  { key: 'series_stats_table_bg', category: 'Series', theme: 'both', label: 'Series stats table background', where: 'Series stats + points table panels', dimensions: '1080x720', fallback: 'assets/images/series/backgrounds/series_stats_table_bg.png', large: true, wired: true },
  { key: 'series_overview_panel_bg', category: 'Series', theme: 'both', label: 'Series overview panel background', where: 'Series overview info panel', dimensions: '1080x720', fallback: 'assets/images/series/backgrounds/series_overview_panel_bg.png', large: true, wired: true },
  { key: 'series_list_card_bg', category: 'Series', theme: 'both', label: 'Series list card background', where: 'Series list cards', dimensions: '800x400', fallback: 'assets/images/series/backgrounds/series_list_card_bg.png', large: false, wired: true },
  { key: 'series_empty_state_bg', category: 'Series', theme: 'both', label: 'Series empty state background', where: 'Series empty state panel', dimensions: '1080x720', fallback: 'assets/images/series/backgrounds/series_empty_state_bg.png', large: false, wired: true },
];

// Image upload guidance surfaced in the admin /assets UI. Keep large decorative
// backgrounds small: the whole point of remote assets is to shrink the APK, so
// re-uploading a 2MB PNG defeats it.
export const UPLOAD_GUIDANCE = {
  preferFormats: ['WebP', 'JPG'],
  maxUploadBytes: 2 * 1024 * 1024, // 2 MB hard ceiling
  recommendedWidth: 1080, // backgrounds look crisp at 1080px wide
  notes: [
    'Prefer WebP or JPG over PNG for photographic backgrounds.',
    'Max upload size 2 MB; aim for under 300 KB for card backgrounds.',
    'Recommended width 1080px for full-screen backgrounds.',
    'Avoid huge PNGs unless transparency is genuinely required.',
  ],
};

const VALID_THEMES = new Set(['light', 'dark', 'both']);

// Card / panel / decorative-background keys that support SEPARATE dark, light,
// and both uploads. For these, a `both` upload is treated as dark-only by the
// app (see universalSafe below): it is shown in dark mode but NEVER in light
// mode, so a dark image uploaded as `both` can no longer bleed into light mode.
// Admins should upload a dedicated light asset (theme=light) for light mode;
// until then light mode uses the bundled light/local fallback.
export const THEMED_BG_KEYS = new Set([
  'match_card_live_bg',
  'match_card_upcoming_bg',
  'match_card_finished_bg',
  'schedule_match_card_bg',
  'series_match_card_bg',
  'series_list_card_bg',
  'series_overview_panel_bg',
  'series_squad_section_bg',
  'series_stats_table_bg',
  'series_empty_state_bg',
  'match_details_header_bg',
  'stadium_bg_generic',
  'schedule_backdrop',
  'series_backdrop',
  'home_backdrop',
]);

/**
 * Whether a `both` upload for [key] may be used in LIGHT mode.
 *
 * Default false for every key: a `both` asset is assumed authored for dark mode
 * and must be explicitly opted-in to appear in light mode. Card/panel/background
 * keys stay false by design so dark `both` images never appear in light mode.
 * (Flip a key to true here only once you have a `both` asset that is visually
 * verified to look correct in BOTH themes.)
 */
export function universalSafeFor(/* key */) {
  return false;
}

/**
 * Expands the catalog so themed-background keys surface three upload slots
 * (dark / light / both) while every other key keeps its single declared theme.
 * Each expanded entry carries `universalSafe` (false by default) so the admin
 * UI and the app agree on whether a `both` asset is light-safe.
 */
export function expandedAssetCatalog() {
  const out = [];
  for (const def of ASSET_KEYS) {
    const themes = THEMED_BG_KEYS.has(def.key) ? ['dark', 'light', 'both'] : [def.theme];
    for (const theme of themes) {
      out.push({ ...def, theme, universalSafe: universalSafeFor(def.key) });
    }
  }
  return out;
}

function shortHash(input) {
  return crypto.createHash('sha1').update(String(input)).digest('hex').slice(0, 12);
}

export default async function assetsRoutes(fastify) {
  fastify.addHook('preHandler', adminAuth);

  // ---------- List: predefined catalog merged with stored rows ----------
  fastify.get('/', { preHandler: [requirePermissions('settings.view')] }, async () => {
    let rows = [];
    try {
      rows = await query(`SELECT * FROM app_assets ORDER BY asset_key ASC`);
    } catch {
      rows = [];
    }
    const byKeyTheme = new Map();
    for (const r of rows) byKeyTheme.set(`${r.asset_key}:${r.theme}`, r);

    const catalog = expandedAssetCatalog().map((def) => {
      const row = byKeyTheme.get(`${def.key}:${def.theme}`);
      return {
        key: def.key,
        theme: def.theme,
        category: def.category || 'Other',
        label: def.label,
        where: def.where || null,
        dimensions: def.dimensions,
        fallback: def.fallback || null,
        large: !!def.large,
        wired: !!def.wired,
        themed: THEMED_BG_KEYS.has(def.key),
        universalSafe: !!def.universalSafe,
        url: row?.url || null,
        version: row?.version || null,
        is_active: row ? !!row.is_active : false,
        updated_at: row?.updated_at || null,
        configured: !!row,
      };
    });
    // Include any stored rows whose key is not in the predefined catalog.
    for (const r of rows) {
      if (!catalog.some((d) => d.key === r.asset_key && d.theme === r.theme)) {
        catalog.push({
          key: r.asset_key,
          theme: r.theme,
          category: 'Custom',
          label: r.asset_key,
          where: null,
          dimensions: null,
          fallback: null,
          large: false,
          wired: false,
          themed: false,
          universalSafe: false,
          url: r.url || null,
          version: r.version || null,
          is_active: !!r.is_active,
          updated_at: r.updated_at || null,
          configured: true,
        });
      }
    }
    return { success: true, data: catalog, guidance: UPLOAD_GUIDANCE };
  });

  // ---------- Image upload (base64 JSON → saved file + public URL) ----------
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
          { action: 'assets.image.upload', entityType: 'upload', newValue: { url, bytes } },
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

  // ---------- Upsert an asset (create or replace url/active) ----------
  fastify.put('/:key/:theme', { preHandler: [requirePermissions('settings.write')] }, async (request, reply) => {
    const key = String(request.params.key || '').trim();
    const theme = String(request.params.theme || 'both').trim();
    if (!key) return reply.code(400).send({ success: false, error: 'asset_key required' });
    if (!VALID_THEMES.has(theme)) {
      return reply.code(400).send({ success: false, error: 'theme must be light, dark, or both' });
    }
    const body = request.body || {};
    const url = body.url === undefined ? null : (body.url ? String(body.url).trim() : null);
    const isActive = body.is_active === undefined ? 1 : (body.is_active ? 1 : 0);
    // Version = caller-supplied or derived from url so the app busts its cache.
    const version = body.version ? String(body.version).slice(0, 40) : (url ? shortHash(url) : null);

    await withAudit(
      request,
      { action: 'assets.upsert', entityType: 'app_asset', entityId: `${key}:${theme}`, newValue: { url, isActive, version } },
      async () =>
        query(
          `INSERT INTO app_assets (asset_key, theme, url, version, is_active, updated_by)
           VALUES (?, ?, ?, ?, ?, ?)
           ON DUPLICATE KEY UPDATE url = VALUES(url), version = VALUES(version),
             is_active = VALUES(is_active), updated_by = VALUES(updated_by)`,
          [key, theme, url, version, isActive, request.adminUser.id],
        ),
    );
    return { success: true };
  });

  // ---------- Toggle active ----------
  fastify.patch('/:key/:theme/active', { preHandler: [requirePermissions('settings.write')] }, async (request, reply) => {
    const key = String(request.params.key || '').trim();
    const theme = String(request.params.theme || 'both').trim();
    const isActive = (request.body || {}).is_active ? 1 : 0;
    const existing = await query(`SELECT id FROM app_assets WHERE asset_key = ? AND theme = ? LIMIT 1`, [key, theme]);
    if (!existing.length) return reply.code(404).send({ success: false, error: 'Asset not configured' });
    await withAudit(
      request,
      { action: 'assets.toggle', entityType: 'app_asset', entityId: `${key}:${theme}`, newValue: { isActive } },
      async () => query(`UPDATE app_assets SET is_active = ?, updated_by = ? WHERE asset_key = ? AND theme = ?`, [isActive, request.adminUser.id, key, theme]),
    );
    return { success: true };
  });

  // ---------- Delete (reverts app to bundled fallback) ----------
  fastify.delete('/:key/:theme', { preHandler: [requirePermissions('settings.write')] }, async (request, reply) => {
    const key = String(request.params.key || '').trim();
    const theme = String(request.params.theme || 'both').trim();
    const old = await query(`SELECT * FROM app_assets WHERE asset_key = ? AND theme = ?`, [key, theme]);
    if (!old.length) return reply.code(404).send({ success: false, error: 'Not found' });
    await withAudit(
      request,
      { action: 'assets.delete', entityType: 'app_asset', entityId: `${key}:${theme}`, oldValue: old[0] },
      async () => query(`DELETE FROM app_assets WHERE asset_key = ? AND theme = ?`, [key, theme]),
    );
    return { success: true };
  });
}
