import mysql from 'mysql2/promise';
import config from '../config/index.js';
import logger from './logger.js';

let pool;

export function getPool() {
  if (!pool) {
    pool = mysql.createPool({
      host: config.db.host,
      port: config.db.port,
      user: config.db.user,
      password: config.db.password,
      database: config.db.database,
      waitForConnections: true,
      connectionLimit: config.db.pool.max,
      queueLimit: 0,
      idleTimeout: 30_000,
      connectTimeout: 5_000,
      charset: 'utf8mb4',
    });

    logger.debug('MySQL pool created');
  }
  return pool;
}

export async function query(text, params) {
  const start = Date.now();
  const [rows, fields] = await getPool().execute(text, params);
  const duration = Date.now() - start;

  if (duration > 500) {
    logger.warn({ msg: 'Slow query', duration, text: text.substring(0, 100) });
  }

  return rows;
}

export async function transaction(fn) {
  const conn = await getPool().getConnection();
  try {
    await conn.beginTransaction();
    const result = await fn(conn);
    await conn.commit();
    return result;
  } catch (err) {
    await conn.rollback();
    throw err;
  } finally {
    conn.release();
  }
}

export async function shutdownDb() {
  if (pool) {
    await pool.end();
    logger.info('MySQL pool closed');
  }
}
