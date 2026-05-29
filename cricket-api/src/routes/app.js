import { query } from '../lib/db.js';
import { controlledFetch, providerFetch, sendAppResponse } from '../lib/data-control.js';
import providerManager from '../providers/provider-manager.js';

async function appSettings() {
  const rows = await query(`SELECT setting_key, setting_value FROM app_settings WHERE is_public = 1 OR is_public IS NULL`).catch(() => []);
  const config = {
    liveMatchesRefreshSeconds: 10,
    liveLineRefreshSeconds: 5,
    scorecardRefreshSeconds: 30,
    commentaryRefreshSeconds: 30,
    oversRefreshSeconds: 20,
    scheduleRefreshMinutes: 5,
    newsRefreshMinutes: 5,
    homeRefreshSeconds: 30,
  };
  for (const row of rows) {
    try { config[row.setting_key] = JSON.parse(row.setting_value); } catch { config[row.setting_key] = row.setting_value; }
  }
  return config;
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

export default async function appRoutes(fastify) {
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
          appSettings(),
        ]);
        const payload = {
          liveMatches: live.data || [],
          upcomingMatches: (upcoming.data || []).slice(0, 10),
          recentMatches: (recent.data || []).slice(0, 10),
          featuredMatch: home.featuredMatches?.[0] || null,
          featuredSeries: home.featuredSeries?.[0] || null,
          featuredNews: (news.data?.stories || []).slice(0, 5),
          quickAccess: home.sections || [],
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
        const [detail, streams, config] = await Promise.all([
          providerManager.execute('getMatchInfo', id),
          query(`SELECT COUNT(*) count FROM match_streams WHERE match_external_id = ? AND is_active = 1`, [id]).catch(() => [{ count: 0 }]),
          appSettings(),
        ]);
        return {
          data: {
            match: detail.data,
            liveLineAvailable: ['live', 'in_progress'].includes(String(detail.data?.status || '').toLowerCase()),
            streamsAvailable: Number(streams[0]?.count || 0) > 0,
            scorecardAvailable: true,
            commentaryAvailable: true,
            tabs: { scorecard: true, commentary: true, overs: true, squads: true, streams: Number(streams[0]?.count || 0) > 0 },
            config,
          },
          provider: detail.provider,
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
