import client from 'prom-client';
import config from '../config/index.js';

const register = new client.Registry();

if (config.monitoring.metricsEnabled) {
  client.collectDefaultMetrics({ register });
}

// HTTP request metrics
export const httpRequestDuration = new client.Histogram({
  name: 'http_request_duration_seconds',
  help: 'Duration of HTTP requests in seconds',
  labelNames: ['method', 'route', 'status_code'],
  buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5],
  registers: [register],
});

export const httpRequestTotal = new client.Counter({
  name: 'http_requests_total',
  help: 'Total number of HTTP requests',
  labelNames: ['method', 'route', 'status_code'],
  registers: [register],
});

// WebSocket metrics
export const wsConnectionsGauge = new client.Gauge({
  name: 'ws_active_connections',
  help: 'Number of active WebSocket connections',
  registers: [register],
});

export const wsMessagesTotal = new client.Counter({
  name: 'ws_messages_total',
  help: 'Total WebSocket messages sent',
  labelNames: ['event'],
  registers: [register],
});

// Provider metrics
export const providerRequestDuration = new client.Histogram({
  name: 'provider_request_duration_seconds',
  help: 'Duration of provider API requests',
  labelNames: ['provider', 'endpoint', 'status'],
  buckets: [0.05, 0.1, 0.25, 0.5, 1, 2, 5],
  registers: [register],
});

export const providerErrorsTotal = new client.Counter({
  name: 'provider_errors_total',
  help: 'Total provider errors',
  labelNames: ['provider', 'error_type'],
  registers: [register],
});

// Cache metrics
export const cacheHitsTotal = new client.Counter({
  name: 'cache_hits_total',
  help: 'Total cache hits',
  labelNames: ['key_type'],
  registers: [register],
});

export const cacheMissesTotal = new client.Counter({
  name: 'cache_misses_total',
  help: 'Total cache misses',
  labelNames: ['key_type'],
  registers: [register],
});

// Worker metrics
export const workerJobDuration = new client.Histogram({
  name: 'worker_job_duration_seconds',
  help: 'Duration of worker jobs',
  labelNames: ['worker', 'status'],
  buckets: [0.01, 0.05, 0.1, 0.5, 1, 5],
  registers: [register],
});

export const activeMatchesGauge = new client.Gauge({
  name: 'active_matches_count',
  help: 'Number of currently live matches being polled',
  registers: [register],
});

export { register };
