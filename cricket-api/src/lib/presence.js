/**
 * Realtime presence (active users right now).
 * ----------------------------------------------------------------------------
 * The app sends a lightweight heartbeat every 30–60s while active. Each
 * heartbeat ZADDs the device/session into a Redis sorted set scored by the
 * current epoch-ms. "Active now" = members scored within the last WINDOW.
 * Stale members are trimmed on every read/write, so a user who closed the app
 * drops out automatically once their heartbeats stop (no stale users counted).
 *
 * No PII — only the anonymous device_id / session_id are stored, and only for
 * the short presence window.
 */
import { getRedis } from './redis.js';

const PRESENCE_DEVICES = 'analytics:presence:devices';
const PRESENCE_SESSIONS = 'analytics:presence:sessions';

// A device counts as "active" if seen within this window. Slightly longer than
// the app's 30–60s heartbeat so a single dropped beat doesn't flap the count.
export const PRESENCE_WINDOW_MS = 120 * 1000;

export async function recordPresence({ deviceId, sessionId } = {}) {
  if (!deviceId && !sessionId) return;
  const redis = getRedis();
  const now = Date.now();
  const cutoff = now - PRESENCE_WINDOW_MS;
  const p = redis.pipeline();
  if (deviceId) p.zadd(PRESENCE_DEVICES, now, deviceId);
  if (sessionId) p.zadd(PRESENCE_SESSIONS, now, sessionId);
  p.zremrangebyscore(PRESENCE_DEVICES, 0, cutoff);
  p.zremrangebyscore(PRESENCE_SESSIONS, 0, cutoff);
  await p.exec().catch(() => null);
}

export async function getPresence() {
  const redis = getRedis();
  const cutoff = Date.now() - PRESENCE_WINDOW_MS;
  const p = redis.pipeline();
  p.zremrangebyscore(PRESENCE_DEVICES, 0, cutoff);
  p.zremrangebyscore(PRESENCE_SESSIONS, 0, cutoff);
  p.zcard(PRESENCE_DEVICES);
  p.zcard(PRESENCE_SESSIONS);
  const res = await p.exec().catch(() => null);
  // ioredis pipeline returns [[err, result], ...]; zcard results are last two.
  const activeUsers = res ? Number(res[2]?.[1] || 0) : 0;
  const activeSessions = res ? Number(res[3]?.[1] || 0) : 0;
  return { activeUsers, activeSessions, windowSeconds: PRESENCE_WINDOW_MS / 1000 };
}
