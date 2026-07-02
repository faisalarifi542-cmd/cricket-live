import { CricbuzzProvider } from './cricbuzz/index.js';
import { CricinfoProvider } from './cricinfo/index.js';
import { CricketDataProvider } from './cricketdata/index.js';
import { isUsableResult, isProviderSentinel } from './provider-results.js';
import { query } from '../lib/db.js';
import { getRedis, KEYS } from '../lib/redis.js';
import logger from '../lib/logger.js';
import { providerErrorsTotal } from '../lib/metrics.js';

/**
 * Provider Manager — orchestrates failover across data providers.
 *
 * Order + enablement are DB-DRIVEN: the admin panel writes to `api_providers`
 * (priority + is_active per provider_type) and this manager reads that config
 * through a lazy TTL cache (mirrors lib/team-logos.js). Admin edits therefore
 * change which provider the app tries first and whether a provider participates
 * at all.
 *
 * Three config states are handled distinctly:
 *   1. DB unreachable      → fall back to the hardcoded priority order (never break).
 *   2. DB has ≥1 active row → use exactly that order/enablement.
 *   3. DB reachable, ALL disabled → controlled "no active provider" error; we do
 *      NOT silently revert to hardcoded, because that would ignore a deliberate
 *      admin decision to disable everything.
 *
 * A provider method may RETURN a typed sentinel (ProviderFeatureNotSupported /
 * ProviderIncompleteData) to signal "I can't serve usable data for this" without
 * throwing. execute() treats a non-usable result as a soft failure and continues
 * to the next provider, so a thin fallback response never masks a fuller one.
 */

const CONFIG_TTL_MS = 45_000;

/** Raised when the DB is reachable but the admin has disabled every provider. */
export class NoActiveProviderError extends Error {
  constructor(method) {
    super(`No active data provider configured (all disabled) for ${method}`);
    this.name = 'NoActiveProviderError';
    this.code = 'NO_ACTIVE_PROVIDER';
  }
}

class ProviderManager {
  constructor() {
    // Instantiate each provider ONCE and key by provider_type. Instances hold
    // live health state (healthy/consecutiveFailures), so config refreshes only
    // reorder/filter these — they are never re-created.
    this.byType = new Map([
      ['cricbuzz', new CricbuzzProvider()],
      ['cricinfo', new CricinfoProvider()],
      ['cricketdata', new CricketDataProvider()],
    ]);

    // Hardcoded safe fallback = the historical fixed priority order.
    this.fallback = [...this.byType.values()].sort((a, b) => a.priority - b.priority);

    // Lazy config cache: { at, dbOk, order } where order is an array of provider
    // instances (empty array = admin disabled all; null = use fallback).
    this._cfg = { at: 0, dbOk: false, order: null };
  }

  /**
   * Load provider config from `api_providers` behind a TTL cache. On the hot
   * path this returns the cached object without touching the DB. Degrades to a
   * fallback marker on any DB error.
   * @returns {Promise<{dbOk: boolean, order: Array|null}>}
   */
  async loadConfig() {
    const now = Date.now();
    if (this._cfg.at !== 0 && now - this._cfg.at < CONFIG_TTL_MS) {
      return this._cfg;
    }
    try {
      const rows = await query(
        `SELECT provider_type, priority, is_active
           FROM api_providers
          ORDER BY priority ASC, id ASC`,
      );
      const active = rows.filter(
        (r) => Number(r.is_active) === 1 && this.byType.has(r.provider_type),
      );
      const order = active.map((r) => this.byType.get(r.provider_type));
      // dbOk=true even when order is empty — that means "admin disabled all",
      // which is a real decision distinct from a DB failure.
      this._cfg = { at: now, dbOk: true, order };
    } catch (err) {
      logger.warn({ msg: 'Provider config load failed; using hardcoded order', error: err.message });
      this._cfg = { at: now, dbOk: false, order: null };
    }
    return this._cfg;
  }

  /** Resolve the ordered provider instances to try for this call. */
  resolveProviders(cfg) {
    if (!cfg.dbOk || cfg.order == null) return this.fallback; // DB down → safe fallback
    return cfg.order; // may be [] when admin disabled everything
  }

  /** Force the next execute() to reload config from the DB. */
  invalidateConfig() {
    this._cfg = { at: 0, dbOk: false, order: null };
  }

  /**
   * Execute a method across providers with automatic failover.
   * @param {string} method - Provider method name
   * @param  {...any} args - Arguments to pass
   * @returns {Promise<{data: any, provider: string}>} First usable result.
   */
  async execute(method, ...args) {
    const cfg = await this.loadConfig();
    const providers = this.resolveProviders(cfg);

    // DB reachable but every provider disabled → controlled error (not a 500;
    // public routes already catch provider failures into empty-but-OK responses).
    if (cfg.dbOk && providers.length === 0) {
      logger.warn({ msg: 'All providers disabled by admin', method });
      throw new NoActiveProviderError(method);
    }

    const errors = [];

    for (const provider of providers) {
      if (!provider.isAvailable()) {
        logger.debug({ msg: 'Provider unavailable, skipping', provider: provider.name, method });
        continue;
      }

      if (typeof provider[method] !== 'function') {
        continue;
      }

      try {
        const result = await provider[method](...args);
        // A typed sentinel / null means "no usable data here" — treat as a soft
        // failure and continue to the next provider rather than returning it.
        if (!isUsableResult(result)) {
          const reason = isProviderSentinel(result) ? result.reason : 'no data';
          errors.push({ provider: provider.name, error: reason });
          logger.debug({ msg: 'Provider returned no usable data, trying next', provider: provider.name, method, reason });
          continue;
        }
        if (errors.length > 0) {
          logger.info({
            msg: 'Provider failover succeeded',
            method,
            failedProviders: errors.map((e) => e.provider),
            successProvider: provider.name,
          });
        }
        return { data: result, provider: provider.name };
      } catch (err) {
        errors.push({ provider: provider.name, error: err.message });
        providerErrorsTotal.inc({ provider: provider.name, error_type: 'failover' });
        logger.warn({
          msg: 'Provider failed, trying next',
          provider: provider.name,
          method,
          error: err.message,
        });
      }
    }

    // All providers failed / had no usable data.
    const errMsg = `All providers failed for ${method}: ${errors.map((e) => `${e.provider}(${e.error})`).join(', ')}`;
    logger.error(errMsg);
    throw new Error(errMsg);
  }

  /** Get health status of all known providers (regardless of DB enablement). */
  getHealthStatus() {
    return [...this.byType.values()].map((p) => ({
      name: p.name,
      priority: p.priority,
      healthy: p.healthy,
      available: p.isAvailable(),
      consecutiveFailures: p.consecutiveFailures,
      lastFailure: p.lastFailure ? new Date(p.lastFailure).toISOString() : null,
    }));
  }

  /** Persist health to Redis for cross-process visibility */
  async persistHealth() {
    const redis = getRedis();
    const health = this.getHealthStatus();
    for (const p of health) {
      await redis.setex(KEYS.providerHealth(p.name), 60, JSON.stringify(p));
    }
  }

  /** Force-reset a provider's health */
  resetProvider(name) {
    const provider = [...this.byType.values()].find((p) => p.name === name);
    if (provider) {
      provider.healthy = true;
      provider.consecutiveFailures = 0;
      provider.lastFailure = null;
      logger.info({ msg: 'Provider health reset', provider: name });
    }
  }
}

// Singleton
const providerManager = new ProviderManager();
export default providerManager;
