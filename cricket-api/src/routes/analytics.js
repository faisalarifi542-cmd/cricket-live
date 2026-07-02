import { query } from '../lib/db.js';
import { recordPresence } from '../lib/presence.js';
import logger from '../lib/logger.js';

// Privacy-safe analytics ingest. Anonymous device_id / session_id only — never
// store name/email/phone/IMEI/GPS. Endpoint is public (no api-key) and must
// never fail loudly: a bad batch is dropped quietly so the app keeps working.

// Allowed event names. Anything else is ignored (prevents arbitrary-string
// cardinality blowups in the events table).
const VALID_EVENTS = new Set([
  'app_open',
  'session_start',
  'session_heartbeat',
  'screen_view',
  'match_open',
  'live_stream_open',
  'quality_selected',
  'pull_refresh',
  'retry_after_error',
  'notification_open',
  'rewarded_unlock',
  'ad_impression',
]);

const MAX_BATCH = 50;
const ID_MAX = 64;
const EVENT_MAX = 60;

function clampId(v) {
  if (v == null) return null;
  const s = String(v).trim();
  if (!s) return null;
  return s.slice(0, ID_MAX);
}

// Keep only small, non-identifying scalar fields from the payload. Drops nested
// objects, long strings, and anything that could smuggle PII.
function sanitizePayload(payload) {
  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) return {};
  const out = {};
  let count = 0;
  for (const [k, v] of Object.entries(payload)) {
    if (count >= 20) break;
    if (typeof k !== 'string' || k.length > 40) continue;
    if (v == null) continue;
    if (typeof v === 'string') {
      out[k] = v.slice(0, 120);
      count += 1;
    } else if (typeof v === 'number' || typeof v === 'boolean') {
      out[k] = v;
      count += 1;
    }
    // objects/arrays intentionally dropped
  }
  return out;
}

export default async function analyticsRoutes(fastify) {
  // POST /analytics/events — batch ingest. Returns 204 always (even on bad
  // input) so clients never retry-storm on validation errors.
  fastify.post('/analytics/events', async (request, reply) => {
    try {
      const body = request.body || {};
      const events = Array.isArray(body.events) ? body.events.slice(0, MAX_BATCH) : [];
      if (!events.length) return reply.code(204).send();

      const rows = [];
      let deviceUpsert = null; // most recent app_open device snapshot in batch
      const sessionUpserts = new Map(); // session_id -> session snapshot (deduped)

      for (const e of events) {
        if (!e || typeof e !== 'object') continue;
        const eventName = String(e.event_name || '').trim().slice(0, EVENT_MAX);
        if (!VALID_EVENTS.has(eventName)) continue;

        const deviceId = clampId(e.device_id);
        const sessionId = clampId(e.session_id);
        const payload = sanitizePayload(e.payload);

        rows.push([eventName, deviceId, sessionId, JSON.stringify(payload)]);

        // Track device dimensions from app_open for the devices upsert.
        if (eventName === 'app_open' && deviceId) {
          deviceUpsert = {
            deviceId,
            appVersion: typeof payload.app_version === 'string' ? payload.app_version.slice(0, 20) : null,
            platform: typeof payload.platform === 'string' ? payload.platform.slice(0, 10) : null,
            osVersion: typeof payload.os_version === 'string' ? payload.os_version.slice(0, 30) : null,
            country: typeof payload.country === 'string' ? payload.country.slice(0, 5) : null,
          };
        }

        // Track sessions from session_start / session_heartbeat. The session_id
        // is the PK in analytics_sessions, so multiple opens/resumes inside the
        // same 30-min window (same session_id) only bump last_seen — they do not
        // create extra "sessions". session_start sets started_at; a heartbeat
        // that arrives without a prior start still creates the row safely.
        if ((eventName === 'session_start' || eventName === 'session_heartbeat') && sessionId) {
          sessionUpserts.set(sessionId, {
            sessionId,
            deviceId,
            appVersion: typeof payload.app_version === 'string' ? payload.app_version.slice(0, 20) : null,
            platform: typeof payload.platform === 'string' ? payload.platform.slice(0, 10) : null,
          });
        }
      }

      if (rows.length) {
        // Bulk insert. Build one parameterized multi-row INSERT.
        const placeholders = rows.map(() => '(?, ?, ?, ?, NOW())').join(', ');
        const flat = rows.flat();
        await query(
          `INSERT INTO analytics_events (event_name, device_id, session_id, payload, created_at) VALUES ${placeholders}`,
          flat,
        ).catch((err) => logger.debug(`analytics insert failed: ${err.message}`));
      }

      if (deviceUpsert) {
        await query(
          `INSERT INTO analytics_devices (device_id, first_seen, last_seen, app_version, platform, os_version, country)
             VALUES (?, NOW(), NOW(), ?, ?, ?, ?)
           ON DUPLICATE KEY UPDATE
             last_seen = NOW(),
             app_version = COALESCE(VALUES(app_version), app_version),
             platform = COALESCE(VALUES(platform), platform),
             os_version = COALESCE(VALUES(os_version), os_version),
             country = COALESCE(VALUES(country), country)`,
          [deviceUpsert.deviceId, deviceUpsert.appVersion, deviceUpsert.platform, deviceUpsert.osVersion, deviceUpsert.country],
        ).catch((err) => logger.debug(`analytics device upsert failed: ${err.message}`));
      }

      // Upsert sessions. Keyed on session_id so repeated starts/heartbeats for
      // the same session only update last_seen — never insert duplicate rows.
      // started_at is set once on first insert and preserved thereafter, so
      // "Sessions today" counts distinct usage periods, not app opens.
      for (const s of sessionUpserts.values()) {
        await query(
          `INSERT INTO analytics_sessions (session_id, device_id, started_at, last_seen, app_version, platform)
             VALUES (?, ?, NOW(), NOW(), ?, ?)
           ON DUPLICATE KEY UPDATE
             last_seen = NOW(),
             device_id = COALESCE(VALUES(device_id), device_id),
             app_version = COALESCE(VALUES(app_version), app_version),
             platform = COALESCE(VALUES(platform), platform)`,
          [s.sessionId, s.deviceId, s.appVersion, s.platform],
        ).catch((err) => logger.debug(`analytics session upsert failed: ${err.message}`));
      }

      return reply.code(204).send();
    } catch (err) {
      // Never surface analytics errors to the client.
      logger.debug(`analytics ingest error: ${err.message}`);
      return reply.code(204).send();
    }
  });

  // POST /analytics/heartbeat — realtime presence. The app calls this every
  // 30–60s while active. Stores the anonymous device/session in a Redis
  // presence window (no PII, auto-expiring). Always 204 so the app never
  // retry-storms.
  fastify.post('/analytics/heartbeat', async (request, reply) => {
    try {
      const b = request.body || {};
      const deviceId = clampId(b.device_id);
      const sessionId = clampId(b.session_id);
      if (deviceId || sessionId) await recordPresence({ deviceId, sessionId });
      return reply.code(204).send();
    } catch (err) {
      logger.debug(`heartbeat error: ${err.message}`);
      return reply.code(204).send();
    }
  });
}
