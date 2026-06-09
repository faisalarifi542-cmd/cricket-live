import { query } from '../lib/db.js';
import { controlledFetch, providerFetch, sendAppResponse } from '../lib/data-control.js';
import providerManager from '../providers/provider-manager.js';
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
import { loadHomeLayout } from '../lib/home-layout.js';

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
  fastify.get('/app/config', async (_request, reply) => {
    const config = await buildPublicAppConfig();
    return sendAppResponse(reply, appResponse(config, { provider: 'admin' }));
  });

  fastify.post('/app/device/register', async (request, reply) => {
    const body = request.body || {};
    const subscriptionId = String(body.subscriptionId || body.subscription_id || '').trim();
    if (!subscriptionId) {
      return reply.code(400).send({ success: false, error: 'subscriptionId required' });
    }
    await query(
      `INSERT INTO app_devices
        (subscription_id, push_token, platform, app_version, build_number, language, permission_status, metadata, last_seen_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, NOW())
       ON DUPLICATE KEY UPDATE
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

  fastify.get('/app/home', async (_request, reply) => {
    const result = await controlledFetch({
      dataType: 'homeData',
      targetId: 'default',
      allowEmpty: true,
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
          ? (home.featuredSeries || []).slice(0, Math.max(1, Number(s.featuredSeries.maxItems) || 10))
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
    return sendAppResponse(reply, appResponse(result.data, result.meta));
  });

  fastify.get('/app/match/:id', async (request, reply) => {
    const { id } = request.params;
    const result = await controlledFetch({
      dataType: 'matchDetail',
      targetId: id,
      requiredId: true,
      fetcher: async () => {
        let detail;
        let provider = 'cricbuzz';
        try {
          detail = await providerManager.execute('getMatchInfo', id);
          provider = detail.provider || provider;
        } catch {
          detail = null;
        }

        // Fallback to admin-controlled manual match
        if (!detail?.data) {
          const manual = await fetchManualMatchById(id);
          if (manual) {
            detail = { data: manualMatchToDetail(manual), provider: 'admin' };
            provider = 'admin';
          }
        }

        const config = await buildPublicAppConfig();
        const streams = await streamSummary(id, config).catch(() => ({ hasStreams: false, hasLiveStream: false, watchLiveEnabled: false, streamCount: 0, isPremiumStreamAvailable: false, defaultStreamId: null, streams: [] }));
        return {
          data: {
            match: detail?.data || null,
            liveLineAvailable: ['live', 'in_progress'].includes(String(detail?.data?.status || '').toLowerCase()),
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
      },
    });
    return sendAppResponse(reply, appResponse(result.data, result.meta));
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
}
