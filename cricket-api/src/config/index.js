import 'dotenv/config';

const env = (key, fallback) => process.env[key] ?? fallback;
const int = (key, fallback) => parseInt(env(key, fallback), 10);
const bool = (key, fallback) => env(key, String(fallback)) === 'true';

const config = Object.freeze({
  env: env('NODE_ENV', 'development'),
  isDev: env('NODE_ENV', 'development') === 'development',
  isProd: env('NODE_ENV', 'development') === 'production',

  server: {
    port: int('PORT', 5000),
    host: env('HOST', '0.0.0.0'),
  },

  db: {
    host: env('DB_HOST', '127.0.0.1'),
    port: int('DB_PORT', 3306),
    user: env('DB_USER', 'webcrichdapi'),
    password: env('DB_PASSWORD', ''),
    database: env('DB_NAME', 'webcrichdapi'),
    pool: {
      min: int('DB_POOL_MIN', 2),
      max: int('DB_POOL_MAX', 20),
    },
  },

  redis: {
    url: env('REDIS_URL', 'redis://localhost:6379'),
    password: env('REDIS_PASSWORD', '') || undefined,
  },

  auth: {
    jwtSecret: env('JWT_SECRET', 'dev-secret-change-in-production'),
    jwtExpiresIn: env('JWT_EXPIRES_IN', '7d'),
    apiKeyHeader: env('API_KEY_HEADER', 'x-api-key'),
  },

  rateLimit: {
    max: int('RATE_LIMIT_MAX', 100),
    timeWindow: int('RATE_LIMIT_WINDOW_MS', 60000),
  },

  providers: {
    cricbuzz: {
      baseUrl: env('CRICBUZZ_BASE_URL', 'https://www.cricbuzz.com'),
    },
    cricketdata: {
      apiKey: env('CRICKETDATA_API_KEY', ''),
      baseUrl: env('CRICKETDATA_BASE_URL', 'https://api.cricapi.com/v1'),
    },
    cricinfo: {
      baseUrl: env('CRICINFO_BASE_URL', 'https://hs-consumer-api.espncricinfo.com/v1'),
    },
  },

  polling: {
    liveInterval: int('POLL_LIVE_INTERVAL', 3000),
    inningsBreakInterval: int('POLL_INNINGS_BREAK_INTERVAL', 15000),
    upcomingInterval: int('POLL_UPCOMING_INTERVAL', 300000),
    commentaryInterval: int('POLL_COMMENTARY_INTERVAL', 5000),
    scorecardInterval: int('POLL_SCORECARD_INTERVAL', 10000),
  },

  workers: {
    concurrency: int('WORKER_CONCURRENCY', 5),
    limiter: {
      max: int('WORKER_LIMITER_MAX', 10),
      duration: int('WORKER_LIMITER_DURATION', 1000),
    },
  },

  ws: {
    heartbeatInterval: int('WS_HEARTBEAT_INTERVAL', 30000),
    maxConnections: int('WS_MAX_CONNECTIONS', 50000),
  },

  monitoring: {
    logLevel: env('LOG_LEVEL', 'info'),
    metricsEnabled: bool('METRICS_ENABLED', true),
    metricsPort: int('METRICS_PORT', 9090),
  },

  cors: {
    origin: env('CORS_ORIGIN', '*'),
  },
});

export default config;
