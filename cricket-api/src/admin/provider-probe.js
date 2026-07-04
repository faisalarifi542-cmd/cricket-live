/**
 * Provider capability probes for the admin "Test" button.
 * ----------------------------------------------------------------------------
 * The old admin test hit `base_url + ['/health', '/matches/live', ...]` for
 * EVERY provider. Those are the *app's* route shapes — they only exist on our
 * own Cricbuzz-backed API. Firing them at ESPN's `site.api.espn.com` 404s on
 * every path, so ESPN Cricinfo was persisted as `down` even though its
 * site.api is perfectly reachable. It just answers different endpoints.
 *
 * These probes instead exercise what each provider can actually do and return a
 * precise state:
 *   - up           — reachable, full capability
 *   - limited      — reachable, but some capability is structurally unavailable
 *                    (e.g. ESPN needs a series id it can't derive from a
 *                    Cricbuzz-origin match id — a mapping miss, NOT an outage)
 *   - down         — real transport/network failure
 *   - misconfigured— missing required config (e.g. CricketData API key)
 */
import axios from 'axios';
import providerManager from '../providers/provider-manager.js';
import { isProviderSentinel } from '../providers/provider-results.js';

const PROBE_TIMEOUT_MS = 10000;

/** ESPN site.api scoreboard header — the endpoint ESPN actually serves. */
async function probeCricinfo() {
  const started = Date.now();
  try {
    const res = await axios.get(
      'https://site.web.api.espn.com/apis/v2/scoreboard/header',
      { params: { sport: 'cricket' }, timeout: PROBE_TIMEOUT_MS, validateStatus: () => true },
    );
    const reachable = res.status >= 200 && res.status < 500 && res.data && typeof res.data !== 'string';
    if (!reachable) {
      return {
        status: 'down',
        latencyMs: Date.now() - started,
        capability_note: `ESPN site.api returned an unexpected response (HTTP ${res.status}).`,
        routes: [{ route: 'site.web.api/scoreboard/header', ok: false, statusCode: res.status }],
      };
    }
    // Reachable and serving valid scoreboard JSON → the provider transport is
    // healthy. (Cross-provider match-id mapping is a data-space caveat handled at
    // fetch time, not a provider health fault, so it must not downgrade status.)
    return {
      status: 'up',
      latencyMs: Date.now() - started,
      capability_note: 'Cricinfo site.api is reachable and serving cricket scoreboard data.',
      routes: [{ route: 'site.web.api/scoreboard/header', ok: true, statusCode: res.status }],
    };
  } catch (err) {
    return {
      status: 'down',
      latencyMs: Date.now() - started,
      capability_note: `ESPN site.api unreachable: ${err.message}`,
      routes: [{ route: 'site.web.api/scoreboard/header', ok: false, statusCode: 0, error: err.message }],
    };
  }
}

/** CricketData needs an API key; probe a light endpoint through the provider. */
async function probeCricketData() {
  const provider = providerManager.getProvider('cricketdata');
  if (provider && typeof provider.isConfigured === 'function' && !provider.isConfigured()) {
    return {
      status: 'misconfigured',
      latencyMs: 0,
      capability_note: 'CricketData API key is not configured; provider is skipped at runtime.',
      routes: [],
    };
  }
  const started = Date.now();
  try {
    const list = await provider.getLiveMatches();
    const ok = !isProviderSentinel(list);
    return {
      status: ok ? 'up' : 'limited',
      latencyMs: Date.now() - started,
      capability_note: ok ? null : 'CricketData responded but returned no usable data.',
      routes: [{ route: 'getLiveMatches', ok, statusCode: ok ? 200 : 0 }],
    };
  } catch (err) {
    return {
      status: 'down',
      latencyMs: Date.now() - started,
      capability_note: `CricketData request failed: ${err.message}`,
      routes: [{ route: 'getLiveMatches', ok: false, statusCode: 0, error: err.message }],
    };
  }
}

/** Cricbuzz (our own API): probe the configured base_url's real health route. */
async function probeCricbuzz(baseUrl, timeoutMs) {
  const base = String(baseUrl || '').replace(/\/+$/, '');
  const started = Date.now();
  try {
    const res = await axios.get(`${base}/health`, {
      timeout: Number(timeoutMs || PROBE_TIMEOUT_MS),
      validateStatus: () => true,
    });
    const ok = res.status >= 200 && res.status < 400;
    return {
      status: ok ? 'up' : 'down',
      latencyMs: Date.now() - started,
      capability_note: ok ? null : `Health route returned HTTP ${res.status}.`,
      routes: [{ route: '/health', ok, statusCode: res.status }],
    };
  } catch (err) {
    return {
      status: 'down',
      latencyMs: Date.now() - started,
      capability_note: `Base URL unreachable: ${err.message}`,
      routes: [{ route: '/health', ok: false, statusCode: 0, error: err.message }],
    };
  }
}

/**
 * Probe a provider by its type. Returns { status, latencyMs, capability_note,
 * routes }. `status` is one of up | limited | down | misconfigured.
 * Returns null for unknown/custom types so the caller can fall back to the
 * legacy generic base_url probe.
 * @param {string} providerType
 * @param {{ baseUrl?: string, timeoutMs?: number }} [opts]
 */
export async function probeProvider(providerType, opts = {}) {
  switch (providerType) {
    case 'cricinfo':
      return probeCricinfo();
    case 'cricketdata':
      return probeCricketData();
    case 'cricbuzz':
      return probeCricbuzz(opts.baseUrl, opts.timeoutMs);
    default:
      return null;
  }
}

/** Map a probe status to the DB `health_status` enum (kept simple for storage). */
export function toHealthStatus(status) {
  // Store 'up' as 'healthy' so a fully-reachable provider renders with the same
  // green badge as Cricbuzz (whose stored value is 'healthy'). 'limited' stays
  // its own value so "reachable but limited" is still distinguishable from a
  // real fault; 'down'/'misconfigured' pass through unchanged.
  if (status === 'up') return 'healthy';
  return status;
}
