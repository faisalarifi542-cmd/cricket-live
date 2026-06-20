import { query } from '../lib/db.js';
import { controlledFetch, providerFetch, sendAppResponse } from '../lib/data-control.js';
import providerManager from '../providers/provider-manager.js';
import { getRedis, cacheGetOrFetch, cacheGet, unwrapSWR, KEYS, TTL } from '../lib/redis.js';
import {
  acquireCacheLock,
  releaseCacheLock,
  consumeProviderBudget,
  logProviderFallback,
} from '../lib/cache-lock.js';
import { buildCommentaryFeed } from '../providers/cricbuzz/normalizer.js';
import logger from '../lib/logger.js';
import config from '../config/index.js';
import {
  buildPublicAppConfig,
  enrichMatchListWithStreams,
  fetchActiveStreamsForMatch,
  isLiveStreamingFeatureEnabled,
  publicStreamDto,
} from '../lib/public-app-state.js';
import {
  fetchManualMatchById,
  manualMatchToDetail,
  mergeManualMatches,
} from '../lib/manual-matches.js';
import { getMatchSummary, summaryToMatchDetail } from '../lib/match-index.js';
import { enrichTeamNodes } from '../lib/team-logos.js';
import { loadHomeLayout } from '../lib/home-layout.js';
import { resolveUploadFile } from '../lib/uploads.js';
import { universalSafeFor } from '../admin/routes/assets.routes.js';
import fs from 'node:fs';

// Phase 1b — warm entrypoints. The route plugin (`appRoutes`) populates these
// with bound closures at registration time; the in-process warmer scheduler
// (lib/phase1b-warmers.js) calls them on an interval. Kept here (not extracted)
// so the warmers reuse the EXACT same fetch/cache-write closures the routes use,
// guaranteeing identical cache key formats. Null until the routes are registered.
export const phase1bWarmEntrypoints = {
  warmHome: null,
  warmLiveScore: null,
  warmLiveCommentary: null,
};

/** Best-effort external id for a raw provider match object. */
function rawMatchId(m) {
  if (!m || typeof m !== 'object') return '';
  return String(m.match_id ?? m.matchId ?? m.id ?? '').trim();
}

/** De-duplicated pool of matches in priority order, capped to `limit`. */
function poolFrom(lists, limit) {
  const out = [];
  const seen = new Set();
  for (const list of lists) {
    for (const m of list || []) {
      const id = rawMatchId(m);
      if (!id || seen.has(id)) continue;
      seen.add(id);
      out.push(m);
      if (out.length >= limit) return out;
    }
  }
  return out;
}

/** Resolve manual external ids against available match pools, preserving order. */
function resolveManual(ids, lists, limit) {
  const byId = new Map();
  for (const list of lists) {
    for (const m of list || []) {
      const id = rawMatchId(m);
      if (id && !byId.has(id)) byId.set(id, m);
    }
  }
  const out = [];
  for (const id of ids || []) {
    const m = byId.get(String(id));
    if (m) out.push(m);
    if (out.length >= limit) break;
  }
  return out;
}

async function homeConfig() {
  const [sections, banners, featuredMatches, featuredSeries, featuredNews] = await Promise.all([
    query(`SELECT slug, title, section_type, payload, sort_order FROM homepage_sections WHERE is_active = 1 ORDER BY sort_order ASC`).catch(() => []),
    query(`SELECT placement, title, subtitle, image_url, cta_label, cta_url, sort_order FROM app_banners WHERE is_active = 1 ORDER BY sort_order ASC`).catch(() => []),
    query(`SELECT * FROM featured_matches WHERE is_active = 1 ORDER BY sort_order ASC`).catch(() => []),
    query(`SELECT * FROM featured_series WHERE is_active = 1 ORDER BY sort_order ASC`).catch(() => []),
    query(`SELECT * FROM featured_news WHERE is_active = 1 ORDER BY sort_order ASC`).catch(() => []),
  ]);
  return { sections, banners, featuredMatches, featuredSeries, featuredNews };
}

function appResponse(data, meta) {
  return { success: true, data, meta };
}

async function streamSummary(matchId, config = null) {
  const liveStreamsEnabled = isLiveStreamingFeatureEnabled(config || await buildPublicAppConfig());
  if (!liveStreamsEnabled) {
    return {
      hasStreams: false,
      hasStream: false,
      hasLiveStream: false,
      watchLiveEnabled: false,
      streamCount: 0,
      isPremiumStreamAvailable: false,
      defaultStreamId: null,
      streams: [],
      message: 'Live streams are currently unavailable.',
    };
  }
  const streams = await fetchActiveStreamsForMatch(matchId);
  const publicStreams = streams.map(publicStreamDto).filter(Boolean);
  return {
    hasStreams: publicStreams.length > 0,
    hasStream: publicStreams.length > 0,
    hasLiveStream: publicStreams.length > 0,
    watchLiveEnabled: publicStreams.length > 0,
    streamCount: publicStreams.length,
    isPremiumStreamAvailable: publicStreams.some((stream) => stream.isPremium),
    defaultStreamId: publicStreams[0]?.id || null,
    streams: publicStreams,
  };
}

export default async function appRoutes(fastify) {
  // Public, unauthenticated static serving for admin-uploaded images. The
  // Flutter app loads these via Image.network (no API key), so this route is
  // treated as public (see resolveEndpointGroup → 'health').
  fastify.get('/uploads/:file', async (request, reply) => {
    const resolved = resolveUploadFile(request.params.file);
    if (!resolved) {
      return reply.code(404).send({ success: false, error: 'Not found' });
    }
    reply.header('Cache-Control', 'public, max-age=31536000, immutable');
    reply.type(resolved.contentType);
    return reply.send(fs.createReadStream(resolved.full));
  });

  fastify.get('/app/config', async (_request, reply) => {
    // Phase 1b: read through the appdata cache (key `appdata:app:config`) instead
    // of hitting MySQL on every request. Falls back to a live build on cache miss
    // (Phase 1a lock-protected). The data shape is unchanged; only added an X-Cache
    // meta. Invalidated by admin settings/ads/splash saves. The app-config warmer
    // keeps this key hot, so steady-state reads never touch MySQL.
    const result = await controlledFetch({
      dataType: 'appConfig',
      targetId: 'default',
      allowEmpty: false,
      fetcher: async () => ({ data: await buildPublicAppConfig(), provider: 'admin' }),
    });
    return sendAppResponse(reply, appResponse(result.data, result.meta));
  });

  // Public list of admin-managed decorative assets. Unauthenticated like
  // /uploads (the app loads these via Image.network with no API key). Returns
  // only active rows. The app keys these by asset_key + theme and always has a
  // local fallback, so an empty/missing list is safe.
  fastify.get('/app/assets', async (_request, reply) => {
    let rows = [];
    try {
      rows = await query(
        `SELECT asset_key, theme, url, version, updated_at
           FROM app_assets
          WHERE is_active = 1 AND url IS NOT NULL AND url <> ''
          ORDER BY asset_key ASC`,
      );
    } catch (err) {
      // Table may not exist yet on un-migrated backends — degrade to empty.
      rows = [];
    }
    const assets = rows.map((r) => ({
      key: r.asset_key,
      theme: r.theme || 'both',
      url: r.url,
      version: r.version || null,
      updatedAt: r.updated_at || null,
      // Whether a `both` asset may be used in light mode. Default false: the app
      // only shows a `both` upload in light mode when this is true, otherwise it
      // falls back to the bundled light design. Additive field — older apps that
      // ignore it keep their existing (dark-preferring) behavior.
      universalSafe: universalSafeFor(r.asset_key) === true,
    }));
    reply.header('Cache-Control', 'public, max-age=300');
    return sendAppResponse(reply, appResponse({ assets }, { provider: 'admin' }));
  });

  fastify.post('/app/device/register', async (request, reply) => {
    const body = request.body || {};
    const subscriptionId = String(body.subscriptionId || body.subscription_id || '').trim();
    if (!subscriptionId) {
      return reply.code(400).send({ success: false, error: 'subscriptionId required' });
    }
    const installId = String(body.installId || body.install_id || '').trim().slice(0, 64) || null;

    // Prefer the stable install_id for dedupe: if a row already exists for this
    // install (even with a now-rotated subscription_id), update it in place so a
    // refreshed OneSignal push token does NOT create a second device row. Falls
    // back to the legacy subscription_id upsert when no installId is sent (old
    // app builds) or no matching install row exists yet.
    if (installId) {
      const existing = await query(
        'SELECT id FROM app_devices WHERE install_id = ? LIMIT 1',
        [installId],
      ).catch(() => []);
      if (existing && existing.length) {
        await query(
          `UPDATE app_devices SET
            subscription_id = ?,
            push_token = ?,
            platform = ?,
            app_version = ?,
            build_number = ?,
            language = ?,
            permission_status = ?,
            metadata = ?,
            last_seen_at = NOW()
           WHERE install_id = ?`,
          [
            subscriptionId,
            body.pushToken || body.push_token || null,
            body.platform || 'unknown',
            body.appVersion || body.app_version || null,
            body.buildNumber || body.build_number || null,
            body.language || null,
            body.permissionStatus || body.permission_status || 'unknown',
            body.metadata ? JSON.stringify(body.metadata) : null,
            installId,
          ],
        );
        return { success: true };
      }
    }

    await query(
      `INSERT INTO app_devices
        (subscription_id, install_id, push_token, platform, app_version, build_number, language, permission_status, metadata, last_seen_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, NOW())
       ON DUPLICATE KEY UPDATE
        install_id = COALESCE(VALUES(install_id), install_id),
        push_token = VALUES(push_token),
        platform = VALUES(platform),
        app_version = VALUES(app_version),
        build_number = VALUES(build_number),
        language = VALUES(language),
        permission_status = VALUES(permission_status),
        metadata = VALUES(metadata),
        last_seen_at = NOW()`,
      [
        subscriptionId,
        installId,
        body.pushToken || body.push_token || null,
        body.platform || 'unknown',
        body.appVersion || body.app_version || null,
        body.buildNumber || body.build_number || null,
        body.language || null,
        body.permissionStatus || body.permission_status || 'unknown',
        body.metadata ? JSON.stringify(body.metadata) : null,
      ],
    );
    return { success: true };
  });

  fastify.put('/app/device/update', async (request, reply) => {
    const body = request.body || {};
    const subscriptionId = String(body.subscriptionId || body.subscription_id || '').trim();
    if (!subscriptionId) {
      return reply.code(400).send({ success: false, error: 'subscriptionId required' });
    }
    await query(
      `UPDATE app_devices SET
        push_token = COALESCE(?, push_token),
        permission_status = COALESCE(?, permission_status),
        metadata = COALESCE(?, metadata),
        last_seen_at = NOW()
       WHERE subscription_id = ?`,
      [
        body.pushToken || body.push_token || null,
        body.permissionStatus || body.permission_status || null,
        body.metadata ? JSON.stringify(body.metadata) : null,
        subscriptionId,
      ],
    );
    return { success: true };
  });

  // Builds (and caches via controlledFetch) the /app/home payload. Extracted from
  // the route handler so the Phase 1b home warmer can refresh the exact same
  // `appdata:app:home` envelope without an inbound request. `request` may be a
  // real Fastify request (route) or a lightweight synthetic one (warmer); only
  // its headers are used to build absolute image URLs. `force` makes the warmer
  // refresh past the TTL; `budgetExempt` keeps warmer refreshes off the budget.
  const runHomeFetch = async (request, { force = false, budgetExempt = false } = {}) => {
    // Resolve relative admin-uploaded image paths (e.g. `/uploads/x.png`) into
    // absolute URLs so the Flutter app can load them via Image.network. Mirrors
    // the logic used by /app/series-hero.
    const proto = request.headers['x-forwarded-proto'] || request.protocol || 'https';
    const host = request.headers['x-forwarded-host'] || request.headers.host;
    const absUrl = (u) => {
      const v = String(u || '').trim();
      if (!v) return '';
      if (/^https?:\/\//i.test(v)) return v;
      return host ? `${proto}://${host}${v.startsWith('/') ? '' : '/'}${v}` : v;
    };
    return controlledFetch({
      dataType: 'homeData',
      targetId: 'default',
      allowEmpty: true,
      force,
      budgetExempt,
      fetcher: async () => {
        const [live, upcoming, recent, news, home, config] = await Promise.all([
          providerFetch('liveMatches', 'getLiveMatches').catch(() => ({ data: [] })),
          providerFetch('upcomingMatches', 'getUpcomingMatches').catch(() => ({ data: [] })),
          providerFetch('recentMatches', 'getRecentMatches').catch(() => ({ data: [] })),
          providerFetch('news', 'getNewsStories').catch(() => ({ data: { stories: [] } })),
          homeConfig(),
          buildPublicAppConfig(),
        ]);
        const mergedLive = await mergeManualMatches(live.data || [], { status: 'live' });
        const [liveMatches, upcomingMatches, recentMatches] = await Promise.all([
          enrichMatchListWithStreams(mergedLive, { allowReplay: false }).catch(() => mergedLive),
          enrichMatchListWithStreams(upcoming.data || [], { allowReplay: false }).catch(() => upcoming.data || []),
          enrichMatchListWithStreams(recent.data || [], { allowReplay: false }).catch(() => recent.data || []),
        ]);

        // ---- Resolve the admin-managed home layout into section data --------
        const layout = await loadHomeLayout();
        const s = layout.sections;

        // Top Featured carousel.
        let topFeaturedMatches = [];
        if (s.topFeatured.enabled) {
          const max = Math.max(1, Number(s.topFeatured.maxItems) || 5);
          if (s.topFeatured.source === 'manual') {
            topFeaturedMatches = resolveManual(
              s.topFeatured.manualMatchIds,
              [liveMatches, upcomingMatches, recentMatches],
              max,
            );
          } else {
            const lists = s.topFeatured.filter === 'live'
              ? [liveMatches]
              : s.topFeatured.filter === 'upcoming'
                ? [upcomingMatches]
                : [liveMatches, upcomingMatches, recentMatches];
            topFeaturedMatches = poolFrom(lists, max);
          }
        }

        // Featured Matches showcase.
        let featuredMatchesList = [];
        if (s.featuredMatches.enabled) {
          const max = Math.max(1, Number(s.featuredMatches.maxItems) || 6);
          if (s.featuredMatches.source === 'manual') {
            const tableIds = (home.featuredMatches || [])
              .map((r) => String(r.match_external_id ?? r.external_id ?? '').trim())
              .filter(Boolean);
            const manualIds = s.featuredMatches.manualMatchIds?.length
              ? s.featuredMatches.manualMatchIds
              : tableIds;
            featuredMatchesList = resolveManual(
              manualIds,
              [liveMatches, upcomingMatches, recentMatches],
              max,
            );
          } else {
            featuredMatchesList = poolFrom([liveMatches, upcomingMatches], max);
          }
        }

        // Featured Series (manual admin entries).
        const featuredSeriesList = s.featuredSeries.enabled
          ? (home.featuredSeries || [])
              .slice(0, Math.max(1, Number(s.featuredSeries.maxItems) || 10))
              .map((row) => ({
                ...row,
                // Absolute URLs so Image.network works in the Flutter app.
                image_url: absUrl(row.image_url),
                team_a_logo: absUrl(row.team_a_logo),
                team_b_logo: absUrl(row.team_b_logo),
              }))
          : [];

        const payload = {
          // ---- New, predictable structure -------------------------------
          homeConfig: {
            sections: layout.sections,
            sectionOrder: layout.sectionOrder,
          },
          topFeaturedMatches,
          matches: liveMatches,
          featuredMatches: featuredMatchesList,
          featuredSeriesList,
          // ---- Backward-compatible fields (existing Flutter parsing) -----
          liveMatches,
          upcomingMatches: upcomingMatches.slice(0, 10),
          recentMatches: recentMatches.slice(0, 10),
          featuredMatch: home.featuredMatches?.[0] || null,
          featuredSeries: featuredSeriesList?.[0] || null,
          featuredNews: (news.data?.stories || []).slice(0, 5),
          quickAccess: home.sections || [],
          sections: home.sections || [],
          banners: home.banners || [],
          config,
        };
        return { data: payload, provider: live.meta?.provider || 'mixed' };
      },
    });
  };

  fastify.get('/app/home', async (request, reply) => {
    const result = await runHomeFetch(request);
    return sendAppResponse(reply, appResponse(result.data, result.meta));
  });

  // Phase 1b: register the home warmer. Uses a synthetic request whose host comes
  // from PUBLIC_BASE_URL so warmer-built absolute image URLs match the public
  // host. force+budgetExempt = proactive refresh that never consumes the public
  // fallback budget.
  phase1bWarmEntrypoints.warmHome = () => {
    const base = String(config.phase1b.baseUrl || '').trim();
    let host = '';
    let proto = 'https';
    if (base) {
      try {
        const u = new URL(base);
        host = u.host;
        proto = u.protocol.replace(':', '') || 'https';
      } catch { /* leave relative */ }
    }
    const syntheticReq = { headers: host ? { host, 'x-forwarded-proto': proto } : {}, protocol: proto };
    return runHomeFetch(syntheticReq, { force: true, budgetExempt: true });
  };

  // Admin-managed Series hero banner. Returns the first active featured_series
  // entry as a clean hero DTO (title/subtitle/format/date, background image and
  // the two flanking teams with server logo URLs). The Flutter Series screen
  // renders this when present and only falls back to deriving a hero from the
  // live series list when no admin hero is configured. Public (no API key) so
  // it follows the same access posture as /app/home.
  fastify.get('/app/series-hero', async (request, reply) => {
    const rows = await query(
      `SELECT * FROM featured_series WHERE is_active = 1 ORDER BY sort_order ASC, id ASC LIMIT 1`,
    ).catch(() => []);
    const row = rows[0] || null;
    const proto = request.headers['x-forwarded-proto'] || request.protocol || 'https';
    const host = request.headers['x-forwarded-host'] || request.headers.host;
    const abs = (u) => {
      const v = String(u || '').trim();
      if (!v) return null;
      if (/^https?:\/\//i.test(v)) return v;
      return host ? `${proto}://${host}${v.startsWith('/') ? '' : '/'}${v}` : v;
    };
    const hero = row
      ? {
          id: row.id,
          seriesId: String(row.series_external_id || '').trim(),
          title: row.title || '',
          subtitle: row.subtitle || '',
          formatText: row.format_text || '',
          dateRange: row.date_range || '',
          location: row.location || '',
          backgroundImage: abs(row.image_url),
          ctaLabel: row.cta_label || 'View Series',
          teamA: {
            name: row.team_a_name || '',
            shortName: row.team_a_short || '',
            logoUrl: abs(row.team_a_logo),
          },
          teamB: {
            name: row.team_b_name || '',
            shortName: row.team_b_short || '',
            logoUrl: abs(row.team_b_logo),
          },
        }
      : null;
    return sendAppResponse(reply, appResponse(hero, { provider: 'admin' }));
  });

  fastify.get('/app/match/:id', async (request, reply) => {
    const { id } = request.params;

    // A provider/manual/summary detail object is usable when it carries an id, a
    // status, or at least one named team — the same notion the public /match/:id
    // route uses. Anything else (null, HTML, {success:false}) is discarded so we
    // never cache or surface garbage as a match.
    const usableMatchDetail = (d) => {
      if (!d || typeof d !== 'object') return false;
      const hasId = !!(d.match_id || d.matchId || d.id);
      const hasStatus = !!d.status;
      const hasTeam = !!(d.team1?.name || d.team1?.short_name || d.team2?.name || d.team2?.short_name);
      return hasId || hasStatus || hasTeam;
    };

    // Build the composite Match Details payload around a (possibly partial) match
    // object. A top-level `matchId` is ALWAYS set so the data-control validator
    // (requiredId) passes on the composite envelope — the match id lives nested
    // under `.match`, so without this the whole endpoint 500s on every cache miss.
    const buildPayload = async (match, provider) => {
      const config = await buildPublicAppConfig();
      const streams = await streamSummary(id, config).catch(() => ({ hasStreams: false, hasLiveStream: false, watchLiveEnabled: false, streamCount: 0, isPremiumStreamAvailable: false, defaultStreamId: null, streams: [] }));
      // Enrich the match-detail team objects (real path: .data.match.team1/team2)
      // BEFORE the composite is cached, so cached payloads also carry the logo
      // fields. The global preSerialization hook re-applies this idempotently.
      if (match && typeof match === 'object') {
        await enrichTeamNodes([match.team1, match.team2]).catch(() => {});
      }
      return {
        data: {
          matchId: String(id),
          match: match || null,
          // Backward-compatible top-level aliases so Flutter screens reading
          // either data.team1/team2 or data.match.team1/team2 both get logos.
          team1: match?.team1 || null,
          team2: match?.team2 || null,
          liveLineAvailable: ['live', 'in_progress'].includes(String(match?.status || '').toLowerCase()),
          streamsAvailable: streams.hasStreams,
          hasLiveStream: streams.hasStreams,
          watchLiveEnabled: streams.watchLiveEnabled,
          streamCount: streams.streamCount,
          isPremiumStreamAvailable: streams.isPremiumStreamAvailable,
          streamBadgeText: streams.hasStreams ? (streams.isPremiumStreamAvailable ? 'Premium' : 'LIVE STREAM') : null,
          scorecardAvailable: true,
          commentaryAvailable: true,
          tabs: { scorecard: true, commentary: true, overs: true, squads: true, streams: streams.hasStreams },
          config,
          streams: streams.streams,
        },
        provider,
      };
    };

    // Resolve the best available match object: provider → manual → indexed
    // summary (livefast/home/schedule). Returns null only when the match is
    // genuinely unknown everywhere.
    const resolveMatch = async () => {
      let provider = 'cricbuzz';
      try {
        const detail = await providerManager.execute('getMatchInfo', id);
        if (usableMatchDetail(detail?.data)) return { match: detail.data, provider: detail.provider || provider };
      } catch {
        // provider blip — fall through to admin/summary fallbacks
      }
      const manual = await fetchManualMatchById(id).catch(() => null);
      if (manual) {
        const detail = manualMatchToDetail(manual);
        if (usableMatchDetail(detail)) return { match: detail, provider: 'admin' };
      }
      const summary = await getMatchSummary(id).catch(() => null);
      if (summary && (summary.team1?.name || summary.team1?.short_name || summary.team2?.name || summary.team2?.short_name)) {
        return { match: summaryToMatchDetail(summary), provider: 'summary' };
      }
      return null;
    };

    try {
      const result = await controlledFetch({
        dataType: 'matchDetail',
        targetId: id,
        requiredId: true,
        fetcher: async () => {
          const resolved = await resolveMatch();
          // No match anywhere: throw so controlledFetch serves STALE if present
          // and never caches a null match. The route catch below builds a safe
          // partial response when there is no stale either.
          if (!resolved) throw new Error('match detail unavailable: no provider/manual/summary data');
          return buildPayload(resolved.match, resolved.provider);
        },
      });
      return sendAppResponse(reply, appResponse(result.data, result.meta));
    } catch (err) {
      // Fail open: a match visible in Home/livefast must never yield a 500. Try
      // one more direct resolve (cheap, uses caches), else return a safe partial
      // summary. This response is NOT written to the matchDetail cache.
      logger.warn({ msg: 'app/match fail-open', matchId: id, error: err.message });
      const resolved = await resolveMatch().catch(() => null);
      const fallback = await buildPayload(resolved?.match || null, resolved?.provider || 'fallback');
      return sendAppResponse(reply, appResponse(fallback.data, {
        cache: 'FALLBACK',
        provider: fallback.provider,
        lastUpdated: new Date().toISOString(),
        ttl: 0,
        isStale: true,
      }));
    }
  });

  fastify.get('/app/series/:id', async (request, reply) => {
    const { id } = request.params;
    const result = await controlledFetch({
      dataType: 'seriesDetail',
      targetId: id,
      allowEmpty: true,
      fetcher: async () => {
        const detail = await providerManager.execute('getSeriesInfo', id);
        return {
          data: {
            series: detail.data,
            matches: detail.data?.matches || [],
            pointsTableAvailable: true,
            statsAvailable: true,
          },
          provider: detail.provider,
        };
      },
    });
    return sendAppResponse(reply, appResponse(result.data, result.meta));
  });

  fastify.get('/app/match/:id/streams', async (request, reply) => {
    const result = await controlledFetch({
      dataType: 'matchStreams',
      targetId: request.params.id,
      allowEmpty: true,
      fetcher: async () => {
        const config = await buildPublicAppConfig();
        const streams = await streamSummary(request.params.id, config);
        return { data: { matchId: request.params.id, ...streams }, provider: 'admin' };
      },
    });
    return sendAppResponse(reply, appResponse(result.data, result.meta));
  });

  fastify.get('/app/schedule', async (_request, reply) => {
    const result = await controlledFetch({
      dataType: 'schedule',
      targetId: 'all',
      allowEmpty: true,
      fetcher: async () => {
        const schedule = await providerManager.execute('getUpcomingSchedule', 'all');
        return { data: schedule.data || { days: [] }, provider: schedule.provider };
      },
    });
    return sendAppResponse(reply, appResponse(result.data, result.meta));
  });

  // ---------------------------------------------------------------------------
  // Lightweight live-score endpoint — Home polls THIS, not the heavy 30s
  // /app/home aggregate. For each requested id it fetches the fast per-match
  // Cricbuzz `/livescore/{id}` (getMatchInfo → miniscore) which advances within
  // a ball, and returns ONLY score/status fields. Tiny dedicated Redis cache
  // (LIVE_SCORE_FAST_TTL_MS, default 4s) + per-id single-flight so many polling
  // clients never fan out to the provider. No heavy series/images/streams/ads.
  // Response is no-store (see server.js onSend live-family list).
  // ---------------------------------------------------------------------------
  const LIVE_SCORE_FAST_TTL_MS = Number(process.env.LIVE_SCORE_FAST_TTL_MS || 4000);
  const liveScoreInflight = new Map();

  // Normalizes a cricket overs value so a full over reads correctly: balls roll
  // over at 6, e.g. 49.6 -> 50.0, 19.6 -> 20.0. Mirrors the Flutter
  // normalizeOversText so backend body + app display agree. Returns the input
  // unchanged when it isn't a parseable number.
  function normalizeOvers(value) {
    if (value === null || value === undefined) return value;
    const str = String(value).trim();
    if (str === '') return value;
    const parsed = Number(str);
    if (!Number.isFinite(parsed)) return value;
    const overs = Math.floor(parsed);
    const balls = Math.round((parsed - overs) * 10);
    if (balls >= 6) {
      const norm = overs + Math.floor(balls / 6);
      const rem = balls % 6;
      return rem === 0 ? `${norm}.0` : `${norm}.${rem}`;
    }
    return balls === 0 ? `${overs}.0` : `${overs}.${balls}`;
  }

  function projectInnings(list) {
    return (Array.isArray(list) ? list : []).map((i) => ({
      ...i,
      overs: normalizeOvers(i?.overs),
    }));
  }

  // Score-only projection of the normalized match-detail shape. Keys mirror the
  // detail payload so the Flutter CricketMatch parser maps them unchanged.
  function projectLiveScore(detail) {
    if (!detail || typeof detail !== 'object') return null;
    const t1 = detail.team1 || {};
    const t2 = detail.team2 || {};
    return {
      match_id: String(detail.match_id || ''),
      status: detail.status || '',
      status_text: detail.status_text || '',
      result: detail.result || '',
      current_innings: detail.current_innings ?? 0,
      target: detail.target ?? null,
      rem_runs_to_win: detail.rem_runs_to_win ?? null,
      current_run_rate: detail.current_run_rate ?? 0,
      required_run_rate: detail.required_run_rate ?? 0,
      // Only the fields the Home cards render — short id/name/code + innings.
      // Overs normalized (49.6 -> 50.0) so the body matches the app display.
      team1: { id: t1.id, name: t1.name, short_name: t1.short_name, innings: projectInnings(t1.innings) },
      team2: { id: t2.id, name: t2.name, short_name: t2.short_name, innings: projectInnings(t2.innings) },
      last_updated: detail.last_updated || new Date().toISOString(),
    };
  }

  // Compact, log-safe score string for diagnostics (no urls/keys/tokens).
  function scoreKeyOf(s) {
    if (!s) return 'none';
    const inn = (t) => (t?.innings || [])
      .map((i) => `${i.runs}/${i.wickets} (${i.overs})`).join(' & ') || '-';
    return `${s.team1?.short_name || '?'} ${inn(s.team1)} | ${s.team2?.short_name || '?'} ${inn(s.team2)} [${s.status}]`;
  }

  async function fetchLiveScoreFast(id, route, opts = {}) {
    const isWarmer = opts.caller === 'warmer';
    const cacheKey = `livefast:${id}`;
    const redis = getRedis();
    const now = Date.now();

    // 1) Fresh cache hit (< TTL old).
    try {
      const raw = await redis.get(cacheKey);
      if (raw) {
        const env = JSON.parse(raw);
        const age = now - (env.t || 0);
        if (age < LIVE_SCORE_FAST_TTL_MS) {
          logger.info(`LIVE_SCORE_FAST: match=${id} route=${route} cache=HIT age=${age} score=${scoreKeyOf(env.s)}`);
          return { score: env.s, cache: 'HIT', ageMs: age, provider: env.p || 'cricbuzz' };
        }
      }
    } catch {/* cache miss/parse — fall through to provider */}

    // 2) Single-flight per id so concurrent pollers share one provider call.
    //    In-memory map collapses pollers in THIS process; the Redis lock below
    //    (lock:cache:livefast:{id}) collapses across PM2 cluster processes, and
    //    the provider budget caps total fallback calls. Stale-on-error/last-good
    //    behavior is preserved.
    if (liveScoreInflight.has(id)) return liveScoreInflight.get(id);
    const work = (async () => {
      const started = Date.now();

      // Cross-process single-flight: only the lock holder calls the provider.
      const lockToken = await acquireCacheLock(cacheKey);
      if (!lockToken) {
        // Another process is rebuilding: wait briefly for its fresh write, else
        // serve whatever (possibly stale) value exists rather than fanning out.
        const deadline = Date.now() + 1200;
        while (Date.now() < deadline) {
          await new Promise((r) => setTimeout(r, 100));
          try {
            const raw = await redis.get(cacheKey);
            if (raw) {
              const env = JSON.parse(raw);
              const age = Date.now() - (env.t || 0);
              return { score: env.s, cache: age < LIVE_SCORE_FAST_TTL_MS ? 'HIT' : 'STALE', ageMs: age, provider: env.p || 'cricbuzz' };
            }
          } catch {/* keep waiting */}
        }
        logProviderFallback({ route, key: cacheKey, reason: 'miss', outcome: 'waiter-empty-livescore' });
        return { score: null, cache: 'ERROR', ageMs: 0, provider: 'cricbuzz', error: 'rebuild in progress' };
      }

      try {
        // Warmers are budget-exempt (scheduled background refresh, not a public
        // fallback) — consistent with BullMQ worker calls.
        const budget = isWarmer
          ? { allowed: true, count: 0 }
          : await consumeProviderBudget(`livefast:${id}`);
        if (!budget.allowed) {
          try {
            const raw = await redis.get(cacheKey);
            if (raw) {
              const env = JSON.parse(raw);
              logProviderFallback({ route, key: cacheKey, reason: 'miss', outcome: 'budget-exhausted-stale-livescore', budgetCount: budget.count });
              return { score: env.s, cache: 'STALE', ageMs: Date.now() - (env.t || 0), provider: env.p || 'cricbuzz' };
            }
          } catch {/* no stale */}
        }
        const detail = await providerManager.execute('getMatchInfo', id);
        const score = projectLiveScore(detail?.data || detail);
        const provider = detail?.provider || 'cricbuzz';
        const providerMs = Date.now() - started;
        if (score) {
          try {
            // setex (seconds) works on both ioredis and the in-memory fallback.
            // Physical TTL = logical window + grace, rounded up to whole seconds.
            const physicalSec = Math.ceil(LIVE_SCORE_FAST_TTL_MS / 1000) + 11;
            await redis.setex(cacheKey, physicalSec,
              JSON.stringify({ s: score, t: Date.now(), p: provider }));
          } catch {/* cache write best-effort */}
        }
        logger.info(`LIVE_SCORE_FAST: match=${id} route=${route} cache=MISS age=0 provider=getMatchInfo providerMs=${providerMs} score=${scoreKeyOf(score)}`);
        return { score, cache: 'MISS', ageMs: 0, provider, providerMs };
      } catch (err) {
        // Serve a stale cached score on provider failure rather than nothing.
        try {
          const raw = await redis.get(cacheKey);
          if (raw) {
            const env = JSON.parse(raw);
            logger.info(`LIVE_SCORE_FAST: match=${id} route=${route} cache=STALE age=${Date.now() - (env.t || 0)} err=${err.message} score=${scoreKeyOf(env.s)}`);
            return { score: env.s, cache: 'STALE', ageMs: Date.now() - (env.t || 0), provider: env.p || 'cricbuzz', error: err.message };
          }
        } catch {/* no stale either */}
        logger.info(`LIVE_SCORE_FAST: match=${id} route=${route} cache=ERROR err=${err.message}`);
        return { score: null, cache: 'ERROR', ageMs: 0, provider: 'cricbuzz', error: err.message };
      } finally {
        await releaseCacheLock(cacheKey, lockToken);
      }
    })().finally(() => {
      liveScoreInflight.delete(id);
    });
    liveScoreInflight.set(id, work);
    return work;
  }

  fastify.get('/app/live-scores', async (request, reply) => {
    const route = '/app/live-scores';
    const idsParam = String(request.query?.ids || '').trim();
    const ids = idsParam
      .split(',')
      .map((s) => s.trim())
      .filter(Boolean)
      .slice(0, 12); // cap fan-out per request
    if (ids.length === 0) {
      return reply.send({ success: true, data: [], meta: { count: 0 } });
    }
    const results = await Promise.all(ids.map((id) => fetchLiveScoreFast(id, route)));
    const data = [];
    let maxAge = 0;
    let anyStale = false;
    let anyMiss = false;
    let anyError = false;
    const scoreKeys = [];
    for (const r of results) {
      if (r?.score) {
        data.push({
          ...r.score,
          cacheAgeMs: r.ageMs,
          cacheStatus: r.cache,
          providerName: r.provider,
        });
        scoreKeys.push(scoreKeyOf(r.score));
      }
      if (r?.ageMs > maxAge) maxAge = r.ageMs;
      if (r?.cache === 'STALE') anyStale = true;
      if (r?.cache === 'MISS') anyMiss = true;
      if (r?.cache === 'ERROR') anyError = true;
    }
    // Aggregate cache verdict across the requested ids. Single-id requests get
    // the exact per-id status; multi-id reflects the "worst" freshness.
    const aggCache = anyError
      ? 'ERROR'
      : anyStale
        ? 'STALE'
        : anyMiss
          ? 'MISS'
          : 'HIT';
    reply.header('X-Cache', aggCache);
    reply.header('X-Cache-Age-Ms', String(maxAge));
    // Always emit so curl/CDN debugging sees an explicit value, not a missing
    // header. True when any requested id was served from the stale window.
    reply.header('X-Stale', anyStale ? 'true' : 'false');
    // Compact, log-safe combined score key (no urls/keys/tokens). Header values
    // must be single-line ASCII — join ids with ' ;; ' and strip control chars.
    if (scoreKeys.length > 0) {
      const headerVal = scoreKeys.join(' ;; ').replace(/[\r\n]+/g, ' ').slice(0, 400);
      reply.header('X-Score-Key', headerVal);
    }
    return reply.send({
      success: true,
      data,
      meta: { count: data.length, requested: ids.length, maxCacheAgeMs: maxAge, cache: aggCache },
    });
  });

  // ---------------------------------------------------------------------------
  // GET /app/live-commentary?ids=<matchId>  — COMPLETE, layered commentary.
  //
  // AUTHORITATIVE BASE: the full per-innings Cricbuzz commentary
  // (`/full-commentary/{innings}` → buildCommentaryFeed) is the source of truth
  // for the Commentary tab — complete rich history, classified, deduped, with
  // isKeyEvent. This is the SAME builder `/match/:id/full-commentary` uses, so
  // the fast endpoint returns the full list, never a 20-item page.
  //
  // LATEST-BALL SUPPLEMENT: `/comm` (and, only if still behind, `/balls-map` for
  // the current innings) is used ONLY to add the newest ball when the full feed
  // is one delivery behind the live miniscore. A tiny fast page can never replace
  // the full list — it can only contribute a missing latest ball.
  //
  // CACHING: per-innings full-commentary cache (short TTL for the current/live
  // innings, long TTL for already-completed innings which won't change) +
  // single-flight per id. Score over is read from the warm `livefast:{id}` cache
  // (no extra provider call). Stale-on-error keeps the last good full feed.
  // ---------------------------------------------------------------------------
  const LIVE_COMMENTARY_FAST_TTL_MS =
    Number(process.env.LIVE_COMMENTARY_FAST_TTL_MS || 5000);
  const liveCommentaryInflight = new Map();

  // Cricket ball index: over.ball -> absolute deliveries. 1.3 => 1*6+3 = 9.
  // This is the ONLY correct way to compare overs (1.6 is NOT > 2.0 decimally,
  // but 1.5 < 2.0 in deliveries). Returns -1 when there is no valid over.
  function ballIndex(over, ball) {
    const o = Number(over);
    const b = Number(ball);
    if (!Number.isFinite(o)) return -1;
    // A combined "1.3" already encodes the ball — split it so 1.3 != over 1.3.
    if (Number.isFinite(b)) return Math.floor(o) * 6 + Math.floor(b);
    const whole = Math.floor(o);
    const frac = Math.round((o - whole) * 10);
    return whole * 6 + frac;
  }

  // Splits a Cricbuzz over metric ("1.2", 1.2) into integer over + ball.
  function overBallOf(metric) {
    const m = Number(metric);
    if (!Number.isFinite(m)) return { over: null, ball: null };
    const over = Math.floor(m);
    const ball = Math.round((m - over) * 10);
    return { over, ball };
  }

  // Latest delivery (highest ball index) across feed/supplement item shapes.
  // Handles both the feed shape (over="1.3", isBall) and the comm shape
  // (over=int, ball). Notes (no over) are ignored.
  function latestBallOf(items) {
    let best = { idx: -1, over: null, ball: null };
    if (!Array.isArray(items)) return best;
    for (const it of items) {
      const over = it?.over;
      if (over === null || over === undefined || `${over}`.trim() === '') continue;
      const idx = ballIndex(over, it?.ball);
      if (idx > best.idx) {
        const whole = Math.floor(Number(over));
        const b = it?.ball !== undefined && it?.ball !== null
          ? Number(it.ball)
          : Math.round((Number(over) - whole) * 10);
        best = { idx, over: whole, ball: b || 0 };
      }
    }
    return best;
  }

  // "over.ball" string for logs/headers, or 'note'/'-'.
  function overStr(latest) {
    if (!latest || latest.idx < 0) return 'note';
    return `${latest.over}.${latest.ball}`;
  }

  // Latest over.ball present in a list (for logs/headers).
  function latestOverOf(items) {
    return overStr(latestBallOf(items));
  }

  // Current live over from the score projection cached at livefast:{id}. Returns
  // the newest over across both teams AND the current innings number, so the
  // full-commentary layer knows which innings is still live (short TTL) vs done.
  function scoreLatestFromProjection(s) {
    let best = { idx: -1, over: null, ball: null };
    if (!s || typeof s !== 'object') return { latest: best, currentInnings: 0, status: '' };
    const scan = (team) => {
      const inns = Array.isArray(team?.innings) ? team.innings : [];
      for (const i of inns) {
        const { over, ball } = overBallOf(i?.overs);
        if (over === null) continue;
        const idx = ballIndex(over, ball);
        if (idx > best.idx) best = { idx, over, ball };
      }
    };
    scan(s.team1);
    scan(s.team2);
    return {
      latest: best,
      currentInnings: Number(s.current_innings || 0),
      status: String(s.status || '').toLowerCase(),
    };
  }

  // Classifies a ball outcome into the labels the app expects, so a balls-map
  // delivery (which has no commentary prose) still renders a proper pill.
  function classifyBall(event, runs, isWicket) {
    if (isWicket) return { type: 'wicket', label: 'WICKET' };
    if (event === 'FOUR' || runs === 4) return { type: 'four', label: 'FOUR' };
    if (event === 'SIX' || runs === 6) return { type: 'six', label: 'SIX' };
    if (!runs || runs === 0) return { type: 'dot', label: 'DOT BALL' };
    return { type: 'run', label: `${runs} RUN${runs === 1 ? '' : 'S'}` };
  }

  // One supplement item (comm or balls-map) in the SAME shape buildCommentaryFeed
  // emits, so it dedupes by innings + over.ball against the feed on the client
  // (canonical key) and renders an identical card.
  function toFeedShape(over, ball, innings, type, label, text, runs, flags, ts, source) {
    return {
      id: `${source}-${innings}-${over}-${ball}-${ts || 0}`,
      innings,
      innings_number: innings,
      over: `${over}.${ball}`,
      ball,
      ballNbr: ball,
      teamShort: flags.teamShort || '',
      team: flags.team || '',
      text: text || label,
      rawText: text || '',
      type,
      label,
      isBall: true,
      isWicket: type === 'wicket',
      isBoundary: type === 'four' || type === 'six',
      isKeyEvent: type === 'wicket' || type === 'four' || type === 'six',
      runs,
      source,
      timestamp: ts || 0,
    };
  }

  // /comm normalized rows (over=int, ball, event, runs, is_*) → feed shape.
  function commToItems(commItems) {
    const out = [];
    for (const c of commItems || []) {
      const over = c?.over;
      if (over === null || over === undefined || `${over}`.trim() === '') continue;
      const o = Math.floor(Number(over));
      const b = Number(c.ball) || 0;
      const isWicket = c.is_wicket === true;
      const runs = Number(c.runs) || 0;
      const cls = classifyBall(
        c.is_four ? 'FOUR' : c.is_six ? 'SIX' : (c.event || ''), runs, isWicket);
      out.push(toFeedShape(o, b, c.innings_number || 0, cls.type, cls.label,
        (c.text || '').toString(), runs,
        { team: c.batsman ? '' : '' }, c.timestamp, 'comm'));
    }
    return out;
  }

  // normalized balls-map (`{balls:[...]}`) → feed shape.
  function ballsMapToItems(bmData, fallbackInnings) {
    const balls = Array.isArray(bmData?.balls) ? bmData.balls : [];
    const out = [];
    for (const b of balls) {
      const { over, ball } = overBallOf(b.overNumber);
      if (over === null) continue;
      const isWicket = b.event === 'WICKET';
      const runs = Number(b.totalRuns) || 0;
      const cls = classifyBall(b.event, runs, isWicket);
      const inn = b.inningsId || fallbackInnings || 0;
      out.push(toFeedShape(over, ball, inn, cls.type, cls.label,
        b.ballLabel ? String(b.ballLabel) : cls.label, runs, {}, b.timestamp, 'balls-map'));
    }
    return out;
  }

  // Reads the warm score projection: latest over + current innings + status.
  async function readScoreState(id) {
    try {
      const redis = getRedis();
      const raw = await redis.get(`livefast:${id}`);
      if (raw) {
        const env = JSON.parse(raw);
        return scoreLatestFromProjection(env.s);
      }
    } catch {/* fall through */}
    return { latest: { idx: -1, over: null, ball: null }, currentInnings: 0, status: '' };
  }

  // Fetches + builds the COMPLETE commentary feed for a match across innings.
  // Each innings is cached independently: the live/current innings gets a short
  // TTL (fresh) while already-completed innings get a long TTL (won't change),
  // so we never hammer full-commentary for settled innings. Returns the built
  // feed ({ matchId, innings, items }) or null on total failure.
  async function fetchFullFeed(id, scoreState) {
    const curInn = scoreState.currentInnings || 0;
    const matchDone = ['completed', 'complete', 'finished', 'abandoned', 'no_result']
      .includes(scoreState.status);

    // Which innings to fetch. Default to 2 (limited overs); a cached scorecard
    // with more innings (Tests) bumps it up. Never below the current innings.
    let inningsCount = 2;
    try {
      const sc = unwrapSWR(await cacheGet(KEYS.matchScorecard(id)));
      if (Array.isArray(sc?.innings) && sc.innings.length > 2) {
        inningsCount = Math.min(4, sc.innings.length);
      }
    } catch {/* scorecard optional */}
    if (curInn > inningsCount) inningsCount = Math.min(4, curInn);

    const nums = Array.from({ length: inningsCount }, (_, i) => i + 1);
    const perInnCounts = [];
    const results = await Promise.allSettled(nums.map(async (n) => {
      // A completed match, or an innings strictly before the current one, is
      // settled → long TTL. The live/current innings → short TTL.
      const settled = matchDone || (curInn > 0 && n < curInn);
      const ttl = settled ? TTL.FULL_COMMENTARY_DONE : TTL.FULL_COMMENTARY_LIVE;
      const { data } = await cacheGetOrFetch(
        KEYS.fullCommentary(id, n), ttl,
        async () => (await providerManager.execute('getFullCommentary', id, String(n))).data,
      );
      return { n, data };
    }));

    const inningsList = [];
    for (const res of results) {
      if (res.status !== 'fulfilled' || !res.value?.data) {
        perInnCounts.push(0);
        continue;
      }
      const { n, data } = res.value;
      const list = Array.isArray(data?.commentary) ? data.commentary : [];
      perInnCounts.push(list.length);
      if (!list.length) continue; // don't fail the whole feed on one empty innings
      inningsList.push({
        inningsId: data.inningsId || n,
        teamName: list[0]?.batTeamName || '',
        commentary: list,
      });
    }

    if (!inningsList.length) return { feed: null, perInnCounts, inningsCount };
    const feed = buildCommentaryFeed(id, inningsList);
    return { feed, perInnCounts, inningsCount };
  }

  async function fetchLiveCommentaryFast(id, route, opts = {}) {
    const isWarmer = opts.caller === 'warmer';
    const cacheKey = `livecomm:${id}`;
    const redis = getRedis();
    const now = Date.now();

    // 1) Fresh cache hit (< TTL old).
    try {
      const raw = await redis.get(cacheKey);
      if (raw) {
        const env = JSON.parse(raw);
        const age = now - (env.t || 0);
        if (age < LIVE_COMMENTARY_FAST_TTL_MS) {
          logger.info(`LIVE_COMMENTARY_FULL: match=${id} route=${route} cache=HIT source=${env.src || 'full-commentary'} scoreOver=${env.so || '-'} latest=${latestOverOf(env.c)} complete=${env.ch ? 'true' : 'false'} providerLag=${env.lag ? 'true' : 'false'} candidates=${env.cand || '-'} count=${(env.c || []).length} age=${age}`);
          return { items: env.c, cache: 'HIT', ageMs: age, provider: env.p || 'cricbuzz', source: env.src || 'full-commentary', scoreOver: env.so || null, providerLag: !!env.lag, completeHistory: !!env.ch, candidates: env.candArr || [] };
        }
      }
    } catch {/* cache miss/parse — fall through to provider */}

    // 2) Single-flight per id so concurrent pollers share one provider pass.
    //    In-memory map collapses pollers in THIS process; the Redis lock
    //    (lock:cache:livecomm:{id}) collapses across PM2 cluster processes, and
    //    the provider budget caps total fallback calls. Stale-on-error/last-good
    //    behavior is preserved.
    if (liveCommentaryInflight.has(id)) return liveCommentaryInflight.get(id);
    const work = (async () => {
      const started = Date.now();

      const lockToken = await acquireCacheLock(cacheKey);
      if (!lockToken) {
        // Another process is rebuilding: wait briefly, then serve whatever exists.
        const deadline = Date.now() + 1200;
        while (Date.now() < deadline) {
          await new Promise((r) => setTimeout(r, 100));
          try {
            const raw = await redis.get(cacheKey);
            if (raw) {
              const env = JSON.parse(raw);
              const age = Date.now() - (env.t || 0);
              return { items: env.c, cache: age < LIVE_COMMENTARY_FAST_TTL_MS ? 'HIT' : 'STALE', ageMs: age, provider: env.p || 'cricbuzz', source: env.src || 'full-commentary', scoreOver: env.so || null, providerLag: !!env.lag, completeHistory: !!env.ch, candidates: env.candArr || [] };
            }
          } catch {/* keep waiting */}
        }
        logProviderFallback({ route, key: cacheKey, reason: 'miss', outcome: 'waiter-empty-livecomm' });
        return { items: [], cache: 'ERROR', ageMs: 0, provider: 'cricbuzz', source: 'full-commentary', scoreOver: null, providerLag: false, completeHistory: false, candidates: [], error: 'rebuild in progress' };
      }

      try {
        const budget = isWarmer
          ? { allowed: true, count: 0 }
          : await consumeProviderBudget(`livecomm:${id}`);
        if (!budget.allowed) {
          try {
            const raw = await redis.get(cacheKey);
            if (raw) {
              const env = JSON.parse(raw);
              logProviderFallback({ route, key: cacheKey, reason: 'miss', outcome: 'budget-exhausted-stale-livecomm', budgetCount: budget.count });
              return { items: env.c, cache: 'STALE', ageMs: Date.now() - (env.t || 0), provider: env.p || 'cricbuzz', source: env.src || 'full-commentary', scoreOver: env.so || null, providerLag: !!env.lag, completeHistory: !!env.ch, candidates: env.candArr || [] };
            }
          } catch {/* no stale */}
        }
        const scoreState = await readScoreState(id);
        const score = scoreState.latest;

        // AUTHORITATIVE: complete full-commentary feed (per-innings cached).
        const { feed, perInnCounts, inningsCount } = await fetchFullFeed(id, scoreState);
        const baseItems = feed?.items || [];
        const feedLatest = latestBallOf(baseItems);
        const completeHistory = baseItems.length > 0;

        const candidates = [];
        for (let n = 0; n < perInnCounts.length; n++) {
          if (perInnCounts[n] > 0) {
            candidates.push({ source: `full-commentary/${n + 1}`, latest: '-', count: perInnCounts[n] });
          }
        }

        // SUPPLEMENT: only add the latest ball when the full feed is behind the
        // live score. /comm first (rich text); /balls-map only if still behind.
        let supplement = [];
        let chosenSource = completeHistory ? 'full-commentary' : 'comm';
        const feedBehind = score.idx >= 0 && feedLatest.idx >= 0 && feedLatest.idx < score.idx;
        const noFeed = !completeHistory;
        if (feedBehind || noFeed) {
          try {
            const commRes = await providerManager.execute('getCommentary', id);
            const commRaw = Array.isArray(commRes?.data) ? commRes.data
              : (Array.isArray(commRes) ? commRes : []);
            const commItems = commToItems(commRaw);
            const commLatest = latestBallOf(commItems);
            candidates.push({ source: 'comm', latest: overStr(commLatest), count: commItems.length });
            supplement = commItems;
            if (commLatest.idx > feedLatest.idx) chosenSource = completeHistory ? 'full-commentary+comm' : 'comm';

            // Still behind after /comm → balls-map for the current innings.
            const supLatest = latestBallOf([...baseItems, ...supplement]);
            if (score.idx >= 0 && supLatest.idx < score.idx) {
              const inn = scoreState.currentInnings || commRaw[0]?.innings_number || 1;
              try {
                const bmRes = await providerManager.execute('getBallsMap', id, String(inn));
                const bmItems = ballsMapToItems(bmRes?.data, inn);
                const bmLatest = latestBallOf(bmItems);
                candidates.push({ source: 'balls-map', latest: overStr(bmLatest), count: bmItems.length });
                supplement = [...supplement, ...bmItems];
                if (bmLatest.idx > supLatest.idx) chosenSource = completeHistory ? 'full-commentary+balls-map' : 'balls-map';
              } catch (e) {
                candidates.push({ source: 'balls-map', latest: '-', count: 0, error: e.message });
              }
            }
          } catch (e) {
            candidates.push({ source: 'comm', latest: '-', count: 0, error: e.message });
          }
        }

        // MERGE: full feed is the base; supplement only ADDS deliveries the feed
        // doesn't have yet (keyed by innings + over.ball). The feed's richer text
        // always wins — a supplement never overwrites an existing feed row.
        const byKey = new Map();
        const keyOf = (it) => {
          const over = it?.over;
          if (over === null || over === undefined || `${over}`.trim() === '') {
            return `n:${it?.innings || it?.innings_number || 0}:${it?.id || (it?.text || '').slice(0, 60)}`;
          }
          const o = Math.floor(Number(over));
          const b = it?.ball !== undefined && it?.ball !== null
            ? Number(it.ball) : Math.round((Number(over) - o) * 10);
          return `b:${it?.innings || it?.innings_number || 0}:${o}.${b || 0}`;
        };
        for (const it of baseItems) if (!byKey.has(keyOf(it))) byKey.set(keyOf(it), it);
        for (const it of supplement) if (!byKey.has(keyOf(it))) byKey.set(keyOf(it), it);
        const merged = [...byKey.values()].sort((a, b) => {
          const innA = Number(a.innings || a.innings_number || 0);
          const innB = Number(b.innings || b.innings_number || 0);
          if (innA !== innB) return innB - innA;
          const ia = ballIndex(a.over, a.ball);
          const ib = ballIndex(b.over, b.ball);
          if (ia !== ib) return ib - ia;
          return (b.timestamp || 0) - (a.timestamp || 0);
        });

        const mergedLatest = latestBallOf(merged);
        const providerLag = score.idx >= 0 && mergedLatest.idx >= 0 && mergedLatest.idx < score.idx;
        const provider = 'cricbuzz';
        const providerMs = Date.now() - started;
        const candStr = candidates.map((c) => `${c.source}:${c.count}`).join(',');

        try {
          const physicalSec = Math.ceil(LIVE_COMMENTARY_FAST_TTL_MS / 1000) + 11;
          await redis.setex(cacheKey, physicalSec, JSON.stringify({
            c: merged, t: Date.now(), p: provider, src: chosenSource,
            so: overStr(score), lag: providerLag, ch: completeHistory,
            cand: candStr, candArr: candidates,
          }));
        } catch {/* cache write best-effort */}

        logger.info(`LIVE_COMMENTARY_FULL: match=${id} route=${route} cache=MISS innings=${perInnCounts.map((_, n) => n + 1).join(',')} fullCounts=${perInnCounts.join(',')} source=${chosenSource} scoreOver=${overStr(score)} latest=${overStr(mergedLatest)} complete=${completeHistory ? 'true' : 'false'} providerLag=${providerLag ? 'true' : 'false'} candidates=${candStr} count=${merged.length} providerMs=${providerMs}`);
        return { items: merged, cache: 'MISS', ageMs: 0, provider, providerMs, source: chosenSource, scoreOver: overStr(score), providerLag, completeHistory, candidates };
      } catch (err) {
        // Serve the last good full feed on failure rather than nothing.
        try {
          const raw = await redis.get(cacheKey);
          if (raw) {
            const env = JSON.parse(raw);
            logger.info(`LIVE_COMMENTARY_FULL: match=${id} route=${route} cache=STALE source=${env.src || 'full-commentary'} scoreOver=${env.so || '-'} latest=${latestOverOf(env.c)} complete=${env.ch ? 'true' : 'false'} providerLag=${env.lag ? 'true' : 'false'} count=${(env.c || []).length} age=${Date.now() - (env.t || 0)} err=${err.message}`);
            return { items: env.c, cache: 'STALE', ageMs: Date.now() - (env.t || 0), provider: env.p || 'cricbuzz', source: env.src || 'full-commentary', scoreOver: env.so || null, providerLag: !!env.lag, completeHistory: !!env.ch, candidates: env.candArr || [], error: err.message };
          }
        } catch {/* no stale either */}
        logger.info(`LIVE_COMMENTARY_FULL: match=${id} route=${route} cache=ERROR err=${err.message}`);
        return { items: [], cache: 'ERROR', ageMs: 0, provider: 'cricbuzz', source: 'full-commentary', scoreOver: null, providerLag: false, completeHistory: false, candidates: [], error: err.message };
      } finally {
        await releaseCacheLock(cacheKey, lockToken);
      }
    })().finally(() => {
      liveCommentaryInflight.delete(id);
    });
    liveCommentaryInflight.set(id, work);
    return work;
  }

  // Phase 1b: register the per-match live warmers. They call the SAME fetch
  // functions the routes use (identical livefast:{id} / livecomm:{id} formats),
  // with caller:'warmer' so provider calls are budget-exempt and logged with
  // route='warmer' (separable from public-route fallbacks).
  phase1bWarmEntrypoints.warmLiveScore = (id) => fetchLiveScoreFast(id, 'warmer', { caller: 'warmer' });
  phase1bWarmEntrypoints.warmLiveCommentary = (id) => fetchLiveCommentaryFast(id, 'warmer', { caller: 'warmer' });

  fastify.get('/app/live-commentary', async (request, reply) => {
    const route = '/app/live-commentary';
    const idsParam = String(request.query?.ids || '').trim();
    const ids = idsParam
      .split(',')
      .map((s) => s.trim())
      .filter(Boolean)
      .slice(0, 8); // cap fan-out per request
    if (ids.length === 0) {
      return reply.send({ success: true, data: [], meta: { count: 0 } });
    }
    const results = await Promise.all(ids.map((id) => fetchLiveCommentaryFast(id, route)));
    const data = [];
    let maxAge = 0;
    let anyStale = false;
    let anyMiss = false;
    let anyError = false;
    let anyLag = false;
    let allComplete = true;
    for (let i = 0; i < results.length; i++) {
      const r = results[i];
      data.push({
        match_id: ids[i],
        items: r?.items || [],
        cacheAgeMs: r?.ageMs ?? 0,
        cacheStatus: r?.cache || 'ERROR',
        providerName: r?.provider || 'cricbuzz',
        source: r?.source || 'full-commentary',
        latestOver: latestOverOf(r?.items),
        scoreOver: r?.scoreOver || null,
        providerLag: !!r?.providerLag,
        completeHistory: !!r?.completeHistory,
        sourceCandidates: (r?.candidates || []).map((c) => ({ source: c.source, latest: c.latest, count: c.count })),
      });
      if (r?.ageMs > maxAge) maxAge = r.ageMs;
      if (r?.cache === 'STALE') anyStale = true;
      if (r?.cache === 'MISS') anyMiss = true;
      if (r?.cache === 'ERROR') anyError = true;
      if (r?.providerLag) anyLag = true;
      if (!r?.completeHistory) allComplete = false;
    }
    const aggCache = anyError
      ? 'ERROR'
      : anyStale
        ? 'STALE'
        : anyMiss
          ? 'MISS'
          : 'HIT';
    const first = data[0] || {};
    reply.header('X-Cache', aggCache);
    reply.header('X-Cache-Age-Ms', String(maxAge));
    reply.header('X-Stale', anyStale ? 'true' : 'false');
    reply.header('X-Commentary-Source', first.source || 'full-commentary');
    reply.header('X-Commentary-Provider-Lag', anyLag ? 'true' : 'false');
    reply.header('X-Commentary-Complete-History', allComplete ? 'true' : 'false');
    reply.header('X-Commentary-Score-Over', String(first.scoreOver || '-'));
    // Log-safe latest-over per id (no urls/keys/tokens).
    const latestKeys = data.map((d) => `${d.match_id}:${d.latestOver}`).join(' ;; ');
    reply.header('X-Commentary-Latest', latestKeys.replace(/[\r\n]+/g, ' ').slice(0, 400));
    return reply.send({
      success: true,
      data,
      meta: {
        count: data.length,
        requested: ids.length,
        maxCacheAgeMs: maxAge,
        cache: aggCache,
        source: first.source || 'full-commentary',
        providerLag: anyLag,
        completeHistory: allComplete,
      },
    });
  });
}
