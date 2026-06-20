import { CricbuzzProvider } from './cricbuzz/index.js';
import { CricinfoProvider } from './cricinfo/index.js';
import { CricketDataProvider } from './cricketdata/index.js';
import { getRedis, KEYS } from '../lib/redis.js';
import logger from '../lib/logger.js';
import { providerErrorsTotal } from '../lib/metrics.js';

/**
 * Provider Manager — orchestrates failover across data providers.
 *
 * Strategy:
 *   1. Try primary provider (Cricbuzz)
 *   2. On failure, try next provider by priority
 *   3. Track health per-provider with auto-recovery
 *   4. Log all failovers for monitoring
 */
class ProviderManager {
  constructor() {
    this.providers = [
      new CricbuzzProvider(),
      new CricinfoProvider(),
      new CricketDataProvider(),
    ].sort((a, b) => a.priority - b.priority);
  }

  /**
   * Execute a method across providers with automatic failover.
   * @param {string} method - Provider method name
   * @param  {...any} args - Arguments to pass
   * @returns {Promise<any>} Result from first successful provider
   */
  async execute(method, ...args) {
    const errors = [];

    for (const provider of this.providers) {
      if (!provider.isAvailable()) {
        logger.debug({ msg: 'Provider unavailable, skipping', provider: provider.name, method });
        continue;
      }

      if (typeof provider[method] !== 'function') {
        continue;
      }

      try {
        const result = await provider[method](...args);
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

    // All providers failed
    const errMsg = `All providers failed for ${method}: ${errors.map((e) => `${e.provider}(${e.error})`).join(', ')}`;
    logger.error(errMsg);
    throw new Error(errMsg);
  }

  /** Get health status of all providers */
  getHealthStatus() {
    return this.providers.map((p) => ({
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
    const provider = this.providers.find((p) => p.name === name);
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
