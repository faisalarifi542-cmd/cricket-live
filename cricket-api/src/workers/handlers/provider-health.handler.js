import providerManager from '../../providers/provider-manager.js';
import logger from '../../lib/logger.js';

/**
 * Periodically checks provider health and persists status to Redis.
 * Enables cross-process provider state visibility.
 */
export async function handleProviderHealth(job) {
  const health = providerManager.getHealthStatus();
  await providerManager.persistHealth();

  const unhealthy = health.filter((p) => !p.healthy);
  if (unhealthy.length > 0) {
    logger.warn({
      msg: 'Unhealthy providers detected',
      providers: unhealthy.map((p) => p.name),
    });
  }

  // Try to recover unhealthy providers with a lightweight probe
  for (const p of unhealthy) {
    if (p.available) {
      // Cooldown expired, provider is auto-recovering
      logger.info({ msg: 'Provider auto-recovering', provider: p.name });
    }
  }

  logger.debug({ msg: 'Provider health check completed', status: health });
}
