import { getRedis } from './redis.js';

/**
 * Invalidate the public app-facing config/home caches so admin edits take effect
 * immediately instead of waiting for the TTL to lapse or the Phase 1b warmer to
 * next refresh (≤ ~60s otherwise). Best-effort — a Redis hiccup must never fail
 * the admin write that triggered it.
 *
 * Keys mirror what the public routes read:
 *   - appdata:app:config  → /app/config        (Phase 1b controlledFetch envelope)
 *   - appdata:app:home    → /app/home          (Phase 1b controlledFetch envelope)
 *   - app:config, home:config → legacy keys kept for backward compatibility
 *
 * This is the single source of truth reused by the settings, ads, splash and
 * homepage admin invalidation paths — do not re-implement it per route.
 */
export async function invalidatePublicConfigCaches() {
  try {
    await getRedis().del('appdata:app:config', 'appdata:app:home', 'app:config', 'home:config');
  } catch { /* cache invalidation is best-effort */ }
}
