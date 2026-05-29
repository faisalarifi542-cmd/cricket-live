import winston from 'winston';
import config from '../config/index.js';

const { combine, timestamp, json, errors, colorize, printf } = winston.format;

const devFormat = combine(
  colorize(),
  timestamp({ format: 'HH:mm:ss' }),
  errors({ stack: true }),
  printf(({ timestamp, level, message, stack, ...meta }) => {
    const metaStr = Object.keys(meta).length ? ` ${JSON.stringify(meta)}` : '';
    return `${timestamp} ${level}: ${stack || message}${metaStr}`;
  })
);

const prodFormat = combine(
  timestamp(),
  errors({ stack: true }),
  json()
);

const logger = winston.createLogger({
  level: config.monitoring.logLevel,
  format: config.isProd ? prodFormat : devFormat,
  defaultMeta: { service: 'cricket-api' },
  transports: [
    new winston.transports.Console(),
    ...(config.isProd
      ? [
          new winston.transports.File({ filename: 'logs/error.log', level: 'error', maxsize: 10_000_000, maxFiles: 5 }),
          new winston.transports.File({ filename: 'logs/combined.log', maxsize: 50_000_000, maxFiles: 10 }),
        ]
      : []),
  ],
});

export default logger;
