/**
 * PM2 ecosystem — CricPro backend (Phase 4).
 * =============================================================================
 * Two process groups, deliberately different exec modes:
 *
 *   cricket-api      cluster   N instances   public API + Phase 1b in-process warmers
 *   cricket-workers  fork      1 instance    BullMQ background workers (provider polling)
 *
 * WHY the split:
 *  - The API is stateless per request and safe to run as N clustered workers
 *    sharing one port (Node cluster round-robins connections). More instances =
 *    more CPU cores used for request handling.
 *  - The BullMQ workers must NOT be clustered. They are already distributed-single-
 *    flight via Redis-backed jobId schedulers; running N copies would not double
 *    provider fetches (the scheduler dedupes), but fork+1 keeps the process model
 *    simple and avoids N sets of in-process timers/limiters. Keep it as one named
 *    fork process.
 *
 * Phase 1b warmers run INSIDE every API instance, but only ONE instance does
 * provider work per tick: each warmer tick first takes the Redis leader lock
 * `lock:cache:warmer:{name}` (see lib/phase1b-warmers.js). The other instances
 * fail to acquire and skip that tick. So cluster mode does NOT multiply warmer
 * provider calls. Defense-in-depth: the per-key Phase 1a lock `lock:cache:{key}`
 * collapses any residual race to a single provider call cluster-wide.
 *
 * This file is .cjs because package.json sets "type": "module"; PM2 config must
 * be CommonJS.
 *
 * USAGE
 *   pm2 start ecosystem.config.cjs --only cricket-api
 *   pm2 start ecosystem.config.cjs --only cricket-workers
 *   pm2 start ecosystem.config.cjs            # both
 *
 * Instance count is configurable via PM2_API_INSTANCES (default "max" = one per
 * CPU core). On a small/shared VPS set e.g. PM2_API_INSTANCES=2 to leave cores
 * for MySQL/Redis. See DEPLOYMENT_PM2.md for rollback to a single instance.
 */
module.exports = {
  apps: [
    // ----------------------------------------------------------------------
    // Public API — CLUSTER mode. Hosts /app/*, /match/*, admin, and the Phase
    // 1b in-process warmers (leader-locked, so only one instance fetches/tick).
    // ----------------------------------------------------------------------
    {
      name: 'cricket-api',
      script: 'src/server.js',
      cwd: __dirname,
      exec_mode: 'cluster',
      // "max" = one instance per CPU core. Override with PM2_API_INSTANCES for a
      // safe fixed count on constrained VPSs (e.g. 2). Rollback to single
      // instance: set PM2_API_INSTANCES=1 (still cluster) or use the fork
      // command documented in DEPLOYMENT_PM2.md.
      instances: process.env.PM2_API_INSTANCES || 'max',
      autorestart: true,
      max_restarts: 10,
      min_uptime: '20s',
      // Restart an instance if it balloons past this (tune to VPS RAM).
      max_memory_restart: '600M',
      kill_timeout: 8000, // give graceful shutdown (stops warmers, drains WS) time
      wait_ready: false,
      env: {
        NODE_ENV: 'production',
        // --- Phase 1b: public base URL (required for the /app/home warmer) ---
        PUBLIC_BASE_URL: 'https://api.webcrichd.co',
        // --- Phase 1b master + per-warmer kill switches ---
        ENABLE_PHASE1B_WARMING: 'true',
        ENABLE_APP_HOME_WARMER: 'true',
        ENABLE_APP_CONFIG_WARMER: 'true',
        ENABLE_LIVEFAST_WARMER: 'true',
        ENABLE_LIVECOMM_WARMER: 'false',
        // Match-detail warming stays OFF until explicitly approved.
        ENABLE_MATCH_DETAIL_WARMER: 'false',
        // --- Phase 1b live-match warming cap ---
        // Conservative first-deploy value. Do NOT raise to 12 until logs confirm
        // provider load is safe and a raise is explicitly approved.
        MAX_WARM_LIVE_MATCHES: '5',
      },
    },

    // ----------------------------------------------------------------------
    // BullMQ background workers — FORK mode, single instance. NOT clustered.
    // Already distributed-single-flight via Redis jobId schedulers. These feed
    // the layer-B caches the public routes read. Do not run more than one.
    // ----------------------------------------------------------------------
    {
      name: 'cricket-workers',
      script: 'src/workers/index.js',
      cwd: __dirname,
      exec_mode: 'fork',
      instances: 1,
      autorestart: true,
      max_restarts: 10,
      min_uptime: '20s',
      max_memory_restart: '500M',
      kill_timeout: 8000,
      env: {
        NODE_ENV: 'production',
        // Workers do not warm /app/* and never run the Phase 1b warmers; the
        // warmer scheduler is only started by src/server.js (the API process).
        // Phase 1b flags are intentionally omitted here.
      },
    },
  ],
};
