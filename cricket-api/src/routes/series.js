import { cacheGet, cacheGetOrFetch, cacheSet, KEYS, TTL } from '../lib/redis.js';
import providerManager from '../providers/provider-manager.js';
import { cacheMiddleware } from '../middleware/cache.js';
import logger from '../lib/logger.js';

/**
 * Computes the normalized series status: `ongoing`, `upcoming`, `completed`
 * or `''` (unknown). Date-based completion (endDate in the past) takes
 * precedence over the start-window heuristic so finished editions are never
 * shown as Upcoming. A genuine live match always wins.
 */
export function computeSeriesStatus({ isLive, startMs, endMs, now, dayMs = 86400000 }) {
  if (isLive) return 'ongoing';
  if (endMs && endMs < now) return 'completed';
  if (startMs && startMs > now) return 'upcoming';
  if (startMs && endMs && startMs <= now && now <= endMs) return 'ongoing';
  if (startMs && startMs <= now + dayMs && (!endMs || endMs >= now)) return 'ongoing';
  return '';
}

// Builds "1 Test • 3 ODIs • 3 T20Is" from a {FORMAT: count} map. Cricbuzz
// reports 20-over internationals as "T20"; we show them as T20I for
// international tours and plain T20 for leagues/domestic competitions.
export function buildFormatLabel(counts, category) {
  const plural = (label, n) => (n > 0 ? `${n} ${label}${n > 1 ? 's' : ''}` : '');
  const cat = String(category || '').toLowerCase();
  const t20Label = !cat || cat.includes('international') ? 'T20I' : 'T20';
  const parts = [
    plural('Test', counts.TEST || 0),
    plural('ODI', counts.ODI || 0),
    plural(t20Label, counts.T20 || 0),
    plural('T10', counts.T10 || 0),
    plural('Hundred', counts.HUNDRED || counts.THE100 || 0),
  ].filter(Boolean);
  return parts.join(' • ');
}

// Maps a normalized match_format ('test'/'odi'/'t20'/'t10') to the uppercase
// bucket key buildFormatLabel expects.
export function formatBucketKey(matchFormat) {
  const f = String(matchFormat || '').toUpperCase();
  if (f.includes('TEST')) return 'TEST';
  if (f.includes('ODI')) return 'ODI';
  if (f.includes('T20')) return 'T20';
  if (f.includes('T10')) return 'T10';
  if (f.includes('HUNDRED') || f.includes('100')) return 'HUNDRED';
  return '';
}

/**
 * AUTHORITATIVE full-series format summary from a series' OWN match list. Counts
 * each match by format and returns the count-aware label + total. This is the
 * fix for partial match-window data (e.g. ICC Women's T20 World Cup showing
 * "8 T20s" instead of the real "33 T20s") — the series detail match list carries
 * every match, the upcoming-window feeds only a slice. Pure + testable.
 */
export function summarizeSeriesFormat(matches, category) {
  const counts = {};
  let count = 0;
  for (const m of matches || []) {
    count += 1;
    const key = formatBucketKey(m.match_format || m.matchFormat);
    if (key) counts[key] = (counts[key] || 0) + 1;
  }
  return { format: buildFormatLabel(counts, category), matchCount: count || null, counts };
}

export default async function seriesRoutes(fastify) {
  function normalizePointsTableResponse(seriesId, raw, seriesName = '') {
    const groups = Array.isArray(raw?.groups)
      ? raw.groups
      : Array.isArray(raw?.pointsTable)
        ? raw.pointsTable.map((group) => ({
            name: group.groupName || group.name || 'Points Table',
            rows: Array.isArray(group.rows)
              ? group.rows
              : Array.isArray(group.pointsTableInfo)
                ? group.pointsTableInfo
                : Array.isArray(group.teams)
                  ? group.teams
                  : [],
          }))
        : [];

    const rows = groups.flatMap((group) => {
      const entries = Array.isArray(group.rows)
        ? group.rows
        : Array.isArray(group.teams)
          ? group.teams
          : Array.isArray(group.pointsTableInfo)
            ? group.pointsTableInfo
            : [];

      return entries.map((team, index) => ({
        ...team,
        groupName: group.name || group.groupName || '',
        rank: team.rank || team.position || index + 1,
        teamId: String(team.teamId || team.team_id || ''),
        teamName: team.teamName || team.team_name || '',
        teamShortName: team.teamShortName || team.teamShort || team.team_short || '',
        logoUrl: team.logoUrl || team.logo_url || '',
      }));
    });

    const teams = rows.map((team, index) => ({
      position: team.position || team.rank || index + 1,
      teamId: String(team.teamId || team.team_id || ''),
      teamName: team.teamName || team.team_name || '',
      teamShort: team.teamShort || team.teamShortName || team.team_short || '',
      played: team.played || team.matches || team.matchesPlayed || 0,
      won: team.won || team.matchesWon || 0,
      lost: team.lost || team.matchesLost || 0,
      tied: team.tied || team.matchesTied || 0,
      noResult: team.noResult ?? team.no_result ?? team.noRes ?? 0,
      nrr: Number(team.nrr || 0),
      points: Number(team.points || 0),
      qualified: team.qualified || false,
      logoUrl: team.logoUrl || team.logo_url || '',
    }));

    return {
      seriesId: String(seriesId),
      seriesName,
      groups: teams.length ? [{ name: rows[0]?.groupName || 'Points Table', rows: teams }] : [],
      rows: teams,
      source: raw?.source || 'cricbuzz',
      updatedAt: new Date().toISOString(),
    };
  }

  function normalizeSeriesSchedule(seriesId, result) {
    const matches = (result?.matches || []).map((m) => ({
      matchId: String(m.match_id || m.matchId || ''),
      matchDesc: m.match_desc || m.matchDesc || '',
      matchFormat: m.match_format || m.matchFormat || '',
      status: m.status || '',
      statusText: m.status_text || m.statusText || '',
      team1: m.team1 || null,
      team2: m.team2 || null,
      venue: m.venue?.name || '',
      city: m.venue?.city || '',
      startTime: m.start_time || m.startTime || null,
      endTime: m.end_time || m.endTime || null,
      score: m.score || {},
      result: m.result || (m.status === 'completed' ? m.status_text : ''),
    }));

    return {
      seriesId: String(seriesId),
      seriesName: result?.seriesName || '',
      matches,
      updatedAt: new Date().toISOString(),
    };
  }

  function text(value) {
    return String(value ?? '').trim();
  }

  function cricbuzzImageUrl(imageId) {
    const id = text(imageId);
    return id ? `https://static.cricbuzz.com/a/img/v1/i1/c${id}/i.jpg` : '';
  }

  function normalizeSeriesTeam(team) {
    if (!team || typeof team !== 'object') return null;
    const id = text(team.teamId || team.team_id || team.id);
    const name = text(team.teamName || team.team_name || team.name);
    const shortName = text(
      team.teamShortName ||
        team.teamShort ||
        team.team_short ||
        team.shortName ||
        team.short_name ||
        team.teamSName
    );
    const imageId = text(team.imageId || team.image_id || team.faceImageId);
    const logoUrl = text(team.logoUrl || team.logo_url || team.logo || team.imageUrl || team.image_url) || cricbuzzImageUrl(imageId);

    if (!name && !id && !shortName) return null;
    const nameKey = name.toLowerCase();
    const shortKey = shortName.toLowerCase();
    if (['team', 'tbc', 'tbd'].includes(nameKey) || ['tea', 'tbc', 'tbd'].includes(shortKey)) return null;

    return {
      teamId: id,
      team_id: id,
      teamName: name,
      team_name: name,
      teamShortName: shortName,
      teamShort: shortName,
      team_short: shortName,
      logoUrl,
      logo_url: logoUrl,
      imageId,
      image_id: imageId,
      players: Array.isArray(team.players) ? team.players : Array.isArray(team.squad) ? team.squad : [],
    };
  }

  function cleanSeriesTeams(rawTeams = []) {
    const teams = [];
    const seen = new Set();
    for (const rawTeam of rawTeams) {
      const team = normalizeSeriesTeam(rawTeam);
      if (!team) continue;
      const key = team.teamId || `${team.teamName.toLowerCase()}|${team.teamShortName.toLowerCase()}`;
      if (!key || seen.has(key)) continue;
      seen.add(key);
      teams.push(team);
    }
    return teams;
  }

  function deriveTeamsFromSeriesMatches(matches = []) {
    const teams = [];
    for (const match of matches) {
      if (match?.team1) teams.push(match.team1);
      if (match?.team2) teams.push(match.team2);
    }
    return cleanSeriesTeams(teams);
  }

  function normalizeStatsAlias(type) {
    const t = String(type || '').toLowerCase();
    if (['batting', 'bat', 'oranges', 'orange-cap', 'orange', 'runs', 'most-runs', 'mostruns'].includes(t)) return 'mostRuns';
    if (['bowling', 'bowl', 'purple-cap', 'purple', 'wickets', 'most-wickets', 'mostwickets'].includes(t)) return 'mostWickets';
    return type;
  }

  function normalizeStatTableForApp(table, requestedType) {
    const players = table?.players || [];
    const isBowling = String(requestedType).toLowerCase().includes('wicket') || String(requestedType).toLowerCase().includes('bowl');
    return {
      header: table?.header || requestedType,
      category: table?.category || '',
      type: requestedType,
      players: players.map((p, index) => {
        const stats = p.stats || p;
        if (isBowling) {
          return {
            rank: index + 1,
            playerId: String(p.playerId || p.player_id || ''),
            playerName: p.playerName || p.player_name || '',
            team: p.team || p.Team || '',
            matches: Number(stats.Mat || stats.Matches || stats.MATCHES || stats.matches || 0),
            innings: Number(stats.Inns || stats.INNS || stats.innings || 0),
            overs: stats.Overs || stats.OVERS || stats.O || stats.overs || '',
            wickets: Number(stats.Wkts || stats.Wickets || stats.WKTS || stats.wickets || 0),
            economy: Number(stats.Econ || stats.Economy || stats.ECON || stats.economy || 0),
            average: Number(stats.Avg || stats.Average || stats.AVG || stats.average || 0),
            bestBowling: stats.BBI || stats.Best || stats.BEST || stats.bestBowling || '',
            fourWickets: Number(stats['4W'] || stats['4-FERS'] || stats.fourWickets || 0),
            fiveWickets: Number(stats['5W'] || stats['5-FERS'] || stats.fiveWickets || 0),
            imageUrl: p.imageUrl || '',
          };
        }
        return {
          rank: index + 1,
          playerId: String(p.playerId || p.player_id || ''),
          playerName: p.playerName || p.player_name || '',
          team: p.team || p.Team || '',
          matches: Number(stats.Mat || stats.Matches || stats.MATCHES || stats.matches || 0),
          innings: Number(stats.Inns || stats.INNS || stats.innings || 0),
          runs: Number(stats.Runs || stats.RUNS || stats.runs || 0),
          average: Number(stats.Avg || stats.Average || stats.AVG || stats.average || 0),
          strikeRate: Number(stats.SR || stats.StrikeRate || stats.strikeRate || 0),
          highestScore: stats.HS || stats['HS'] || stats.highestScore || '',
          fours: Number(stats['4s'] || stats.Fours || stats.fours || 0),
          sixes: Number(stats['6s'] || stats.Sixes || stats.sixes || 0),
          hundreds: Number(stats['100s'] || stats.hundreds || 0),
          fifties: Number(stats['50s'] || stats.fifties || 0),
          imageUrl: p.imageUrl || '',
        };
      }),
      headers: table?.headers || [],
      filters: table?.filters || null,
    };
  }

  function toAppStatsType(providerType) {
    return providerType === 'mostWickets' ? 'bowling' : 'batting';
  }

  function toStatsRows(table, providerType) {
    const normalized = normalizeStatTableForApp(table, providerType);
    return {
      type: toAppStatsType(providerType),
      rows: normalized.players,
      players: normalized.players,
      headers: normalized.headers,
      filters: normalized.filters,
    };
  }

  async function fetchSeriesStatsTable(seriesId, providerType) {
    const cacheKey = KEYS.seriesStatsTable(seriesId, providerType);
    const cached = await cacheGet(cacheKey);
    if (cached?.players?.length) {
      return { table: cached, fromCache: true, sourcePath: `/api/cricket-series/series-stats/${seriesId}/${providerType}` };
    }

    const result = await providerManager.execute('getSeriesStatsTable', seriesId, providerType);
    const table = result?.data || null;
    if (table?.players?.length) {
      await cacheSet(cacheKey, table, TTL.SERIES_STATS_TABLE);
    }
    return { table, fromCache: false, sourcePath: `/api/cricket-series/series-stats/${seriesId}/${providerType}` };
  }

  function emptyStatsResponse(seriesId, type, sourcePath, table) {
    const emptyTable = {
      header: type || 'grouped',
      category: '',
      type: type || 'grouped',
      rows: [],
      players: [],
      headers: [],
      filters: null,
    };
    return {
      success: true,
      seriesId: String(seriesId),
      ...(type ? { type } : {}),
      data: type ? emptyTable : { batting: emptyTable, bowling: emptyTable, items: [] },
      count: 0,
      counts: { batting: 0, bowling: 0 },
      message: 'Series stats are not available for this series yet.',
      debug: {
        type: type || 'grouped',
        sourcePath,
        rawKeys: table ? Object.keys(table) : [],
        reason: 'No stats rows found',
      },
    };
  }

  async function fetchPointsTable(seriesId) {
    const extractRows = (value) => {
      if (Array.isArray(value?.groups)) {
        return value.groups.flatMap((group) => Array.isArray(group.rows)
          ? group.rows
          : Array.isArray(group.teams)
            ? group.teams
            : Array.isArray(group.pointsTableInfo)
              ? group.pointsTableInfo
              : []);
      }
      if (Array.isArray(value?.rows)) return value.rows;
      if (Array.isArray(value?.pointsTable)) {
        return value.pointsTable.flatMap((group) => Array.isArray(group.pointsTableInfo)
          ? group.pointsTableInfo
          : Array.isArray(group.rows)
            ? group.rows
            : []);
      }
      return Array.isArray(value) ? value : [];
    };

    const hasUsableRows = (value) => extractRows(value).some((team) => {
      const name = team.teamName || team.team_name || team.teamFullName || '';
      const played = Number(team.played || team.matches || team.matchesPlayed || 0);
      const won = Number(team.won || team.matchesWon || 0);
      const lost = Number(team.lost || team.matchesLost || 0);
      const points = Number(team.points || 0);
      return name && name !== 'Team' && (played || won || lost || points);
    });
    let data = await cacheGet(KEYS.pointsTable(seriesId));
    const cachedHasRows = hasUsableRows(data);
    let fromCache = !!cachedHasRows;

    if (!cachedHasRows) {
      const result = await providerManager.execute('getPointsTable', seriesId);
      data = result?.data || result || [];
      const hasRows = hasUsableRows(data);
      if (hasRows) await cacheSet(KEYS.pointsTable(seriesId), data, TTL.POINTS_TABLE);
      fromCache = false;
    }

    return { data, fromCache };
  }

  /**
   * Enriches the thin Cricbuzz series list (id + name only) with status,
   * date range, format breakdown, match count and the two representative
   * teams. Status is derived from genuine signals only — the set of series
   * that currently have a live match, plus the date window of scheduled
   * matches — never guessed. Schedule/live lookups are best-effort so the
   * base list is always returned even if they fail.
   */
  async function enrichSeriesList() {
    const baseRaw = (await cacheGetOrFetch(
      KEYS.seriesList(),
      TTL.SERIES,
      async () => (await providerManager.execute('getSeriesList')).data,
    )).data || [];

    const agg = new Map();
    const liveSeries = new Set();

    // Cricbuzz exposes the same Series tabs the app needs as separate schedule
    // feeds. The feed `type` is the AUTHORITATIVE category for every series it
    // lists, and a typed feed often still carries recently-ended editions the
    // upcoming-biased `all` feed has dropped — so merging all five both tags
    // category reliably AND recovers recent completed series (whose dates only
    // come from schedule matches). Each fetch is best-effort; a failed feed is
    // skipped and the base list is still returned.
    const SCHEDULE_TYPES = ['all', 'international', 'domestic', 'league', 'women'];
    // Stronger (more specific) category wins when a series appears in several
    // feeds, e.g. a women's league surfaces under both `league` and `women`.
    const CATEGORY_RANK = { women: 4, league: 3, domestic: 2, international: 1 };

    const FEED_TYPES = SCHEDULE_TYPES;

    // `getFullSchedule` parses the REAL Cricbuzz series schedule LIST
    // (/cricket-schedule/series/all), returning each series' AUTHORITATIVE
    // date range. This is the source of truth for status — it must override
    // any match-window dates derived from the upcoming feeds.
    const settled = await Promise.allSettled([
      ...SCHEDULE_TYPES.map((t) => providerManager.execute('getUpcomingSchedule', t)),
      providerManager.execute('getFullSchedule'),
      providerManager.execute('getLiveMatches'),
    ]);
    const scheduleResults = settled.slice(0, FEED_TYPES.length);
    const fullScheduleRes = settled[FEED_TYPES.length];
    const liveRes = settled[FEED_TYPES.length + 1];

    // seriesId -> { start, end } (epoch ms) from the authoritative series list.
    const seriesDateRange = new Map();
    if (fullScheduleRes.status === 'fulfilled') {
      for (const row of fullScheduleRes.value?.data || fullScheduleRes.value || []) {
        const sid = String(row.series_id || '');
        if (!sid) continue;
        const start = row.start_date ? Date.parse(row.start_date) : null;
        const end = row.end_date ? Date.parse(row.end_date) : null;
        if (start || end) seriesDateRange.set(sid, { start, end, name: row.name || '' });
      }
    }

    scheduleResults.forEach((scheduleRes, feedIndex) => {
      if (scheduleRes.status !== 'fulfilled') return;
      const feedType = FEED_TYPES[feedIndex];
      // `all` is not a category; rely on the per-series seriesCategory there.
      const feedCategory = feedType === 'all' ? '' : feedType;
      const feedRank = CATEGORY_RANK[feedCategory] || 0;
      const days = scheduleRes.value?.data?.days || [];
      for (const day of days) {
        for (const s of day.series || []) {
          const sid = String(s.seriesId || '');
          if (!sid) continue;
          let a = agg.get(sid);
          if (!a) {
            a = { name: '', start: null, end: null, counts: {}, teams: null, category: '', categoryRank: 0, count: 0, seen: new Set() };
            agg.set(sid, a);
          }
          // Authoritative category: a stronger typed feed wins; otherwise fall
          // back to the per-series seriesCategory carried by the `all` feed.
          if (feedRank > a.categoryRank) {
            a.category = feedCategory;
            a.categoryRank = feedRank;
          } else if (a.categoryRank === 0 && s.category) {
            a.category = s.category;
          }
          if (!a.name && s.seriesName) a.name = s.seriesName;
          for (const mt of s.matches || []) {
            // A multi-day Test is repeated under every day header — and the
            // same match also recurs across feeds — so count each real match
            // (by id) only once so formats/counts/dates stay accurate.
            const mid = String(mt.matchId || '');
            if (mid && a.seen.has(mid)) continue;
            if (mid) a.seen.add(mid);
            a.count += 1;
            const fmt = String(mt.matchFormat || '').toUpperCase().replace(/[^A-Z0-9]/g, '');
            if (fmt) a.counts[fmt] = (a.counts[fmt] || 0) + 1;
            const st = Number(mt.startTime) || null;
            const en = Number(mt.endTime) || null;
            if (st && (a.start === null || st < a.start)) a.start = st;
            if (en && (a.end === null || en > a.end)) a.end = en;
            // The full-schedule feed tags each match with a live `state`
            // ("In Progress", etc.); use it as a genuine ongoing signal so a
            // series with a match underway right now is Ongoing even before the
            // separate live-matches feed catches up.
            if (/progress|innings break|rain|wet|tea|lunch|stumps|delay/i.test(String(mt.state || ''))) {
              liveSeries.add(sid);
            }
            if (!a.teams && mt.team1?.name && mt.team2?.name) {
              a.teams = [
                { name: mt.team1.name, shortName: mt.team1.shortName || '', logoUrl: mt.team1.logoUrl || '' },
                { name: mt.team2.name, shortName: mt.team2.shortName || '', logoUrl: mt.team2.logoUrl || '' },
              ];
            }
          }
        }
      }
    });

    if (liveRes.status === 'fulfilled') {
      for (const m of liveRes.value?.data || []) {
        const sid = String(m.source_series_id || m.series_id || '');
        if (sid) liveSeries.add(sid);
      }
    }

    const now = Date.now();
    const dayMs = 24 * 60 * 60 * 1000;
    // Section-B-only additions are bounded to a window around "now" so the list
    // stays focused on current cricket: recently-ended tours through the next
    // few months, never the entire all-time series catalogue.
    const WIN_PAST = 45 * dayMs;
    const WIN_FUTURE = 150 * dayMs;

    // MASTER SET of series ids = thin base list ∪ schedule-feed series ∪ the
    // authoritative Cricbuzz series LIST (Section B) within the current window.
    // Unioning Section B is what RECOVERS recently-completed tours (Afghanistan
    // tour of India, Australia tour of Bangladesh) that the upcoming-biased base
    // list / feeds drop entirely — previously the code only OVERRODE dates of
    // series already in the base list, so a dropped series never appeared.
    const baseById = new Map();
    for (const s of baseRaw) {
      const sid = String(s.series_id || s.seriesId || s.id || '');
      if (sid) baseById.set(sid, s);
    }
    const ids = new Set(baseById.keys());
    for (const sid of agg.keys()) ids.add(sid);
    for (const [sid, r] of seriesDateRange) {
      const inWindow = (r.end == null || r.end >= now - WIN_PAST)
        && (r.start == null || r.start <= now + WIN_FUTURE);
      if (inWindow) ids.add(sid);
    }

    // First pass: fold the authoritative Cricbuzz series-list dates together
    // with the min/max of the matches we saw across the schedule feeds.
    const enriched = [...ids].map((sid) => {
      const s = baseById.get(sid) || {};
      const a = agg.get(sid);
      let startMs = s.start_date ? Date.parse(s.start_date) : null;
      let endMs = s.end_date ? Date.parse(s.end_date) : null;
      let format = '';
      let teams = [];
      let matchCount = null;
      let name = s.name || s.seriesName || '';
      if (a) {
        // Match-window dates only EXTEND coverage when no authoritative range
        // exists yet — they never shrink or replace it (see override below).
        if (a.start && (startMs === null || a.start < startMs)) startMs = a.start;
        if (a.end && (endMs === null || a.end > endMs)) endMs = a.end;
        format = buildFormatLabel(a.counts, a.category);
        teams = a.teams || [];
        matchCount = a.count || null;
        if (a.name) name = a.name;
      }

      // AUTHORITATIVE OVERRIDE: the real Cricbuzz series schedule list gives the
      // true series-level date range. It WINS over both the thin base-list dates
      // and any match-window min/max — this is what fixes "ICC Women's T20 World
      // Cup 2026" showing Upcoming (its span is Jun 12 – Jul 05, not its next
      // upcoming match), and gives ended tours (Afghanistan, Australia/Bangladesh)
      // their real past end dates so they classify Completed.
      const authRange = seriesDateRange.get(sid);
      if (authRange) {
        if (authRange.start) startMs = authRange.start;
        if (authRange.end) endMs = authRange.end;
        if (authRange.name && (!name || name.length < authRange.name.length)) {
          name = authRange.name;
        }
      }
      return { s, sid, a, startMs, endMs, format, teams, matchCount, name, category: a?.category || '' };
    });

    // AUTHORITATIVE full-series metadata recovery. The match-window aggregation
    // only sees matches inside the current upcoming window, so a long tournament
    // shows a PARTIAL count/format (e.g. ICC Women's T20 World Cup as "8 T20s"
    // instead of the real "33 T20s"). Each series' OWN match list (the cached
    // series detail page) carries the full set; we re-derive count/format/teams
    // from it and override the match-window values. We also fill date gaps the
    // schedule feeds left (never overriding the Section-B authoritative dates).
    // Bounded to ongoing + undated series (the ones whose data is visible and
    // must be exact) so we never fan out across the whole catalogue.
    const needMeta = enriched.filter((e) => {
      const undated = e.startMs === null && e.endMs === null;
      const status = computeSeriesStatus({
        isLive: liveSeries.has(e.sid), startMs: e.startMs, endMs: e.endMs, now, dayMs,
      });
      return status === 'ongoing' || undated;
    });
    if (needMeta.length > 0) {
      const RECOVER_LIMIT = 30; // cap extra provider calls per (cached) rebuild
      const targets = needMeta.slice(0, RECOVER_LIMIT);
      for (let i = 0; i < targets.length; i += 4) {
        const batch = targets.slice(i, i + 4);
        // eslint-disable-next-line no-await-in-loop
        await Promise.allSettled(batch.map(async (e) => {
          const meta = await recoverSeriesMeta(e.sid);
          // Full-series count/format from the series' own match list overrides
          // the partial match-window aggregation (fixes WWC 8 → 33 T20s). Reuse
          // the same category so the label style (T20 vs T20I) is unchanged.
          if (meta.count > 0) {
            const label = buildFormatLabel(meta.counts, e.category);
            if (label) e.format = label;
            e.matchCount = meta.count;
          }
          if ((!e.teams || e.teams.length === 0) && meta.teams) e.teams = meta.teams;
          // Prefer the FULL team list when the series' own match list yields
          // more teams than the partial schedule-window aggregation (so
          // multi-team tournaments/leagues show all teams, not just 2).
          if (meta.teams && meta.teams.length > (e.teams?.length || 0)) {
            e.teams = meta.teams;
          }
          if (meta.teamCount && meta.teamCount > (e.teamCount || 0)) {
            e.teamCount = meta.teamCount;
          }
          // Fill date gaps only — Section B authoritative dates always win.
          if (e.startMs === null && meta.start) e.startMs = meta.start;
          if (e.endMs === null && meta.end) e.endMs = meta.end;
          if (!e.name && meta.seriesName) e.name = meta.seriesName;
          if (meta.count > 0 || meta.start || meta.end) {
            logger.info({ msg: 'Recovered authoritative series meta', seriesId: e.sid, count: meta.count, start: meta.start, end: meta.end });
          }
        }));
      }
    }

    return enriched.map((e) => {
      const { s, sid, startMs, endMs, format, teams, matchCount, name, category } = e;

      // Normalized status precedence (same rules mirrored in the Flutter
      // client): a genuine live match wins; otherwise an end date in the past
      // means Completed (this is what fixes finished editions like IPL 2026
      // being mislabelled Upcoming); a future start means Upcoming; a date
      // window spanning now means Ongoing.
      const computedStatus = computeSeriesStatus({
        isLive: liveSeries.has(sid),
        startMs,
        endMs,
        now,
        dayMs,
      });
      // When no dates are available, fall back to the raw Cricbuzz status
      // string so the Flutter client has at least a text signal to work with.
      const rawStatus = String(s.status || '').toLowerCase();
      const status = computedStatus || rawStatus;

      return {
        series_id: sid,
        name,
        season: s.season || '',
        status,
        // Additive, optional: authoritative Cricbuzz category
        // (international/domestic/league/women) when known. Existing clients
        // that ignore it are unaffected.
        category,
        start_date: startMs ? new Date(startMs).toISOString() : null,
        end_date: endMs ? new Date(endMs).toISOString() : null,
        format,
        matchCount,
        teams,
      };
    });
  }

  /**
   * Best-effort recovery of a series' AUTHORITATIVE full-series metadata from
   * its own (strictly-filtered, cached) match list: real start/end span (epoch
   * ms), total match count, per-format counts and the two representative teams.
   * Used to override the partial match-window aggregation for visible series and
   * to date series the upcoming-biased feeds left undated. Never throws; returns
   * empty values on any miss.
   */
  async function recoverSeriesMeta(seriesId) {
    try {
      const res = await fetchSeriesMatches(seriesId);
      let start = null;
      let end = null;
      let count = 0;
      const counts = {};
      for (const m of res?.matches || []) {
        const st = m.start_time ? Date.parse(m.start_time) : null;
        const en = m.end_time ? Date.parse(m.end_time) : null;
        if (Number.isFinite(st) && (start === null || st < start)) start = st;
        // Some completed matches omit end_time; fall back to the start instant.
        const e = Number.isFinite(en) ? en : st;
        if (Number.isFinite(e) && (end === null || e > end)) end = e;
        count += 1;
        const key = formatBucketKey(m.match_format);
        if (key) counts[key] = (counts[key] || 0) + 1;
      }
      // FULL distinct participating-team list from the series' own match list.
      // This is what makes multi-team tournaments/leagues (e.g. ICC Women's T20
      // World Cup) expose all teams instead of a single 2-team match identity.
      // Genuine bilateral tours naturally yield just their two teams here.
      const teamList = deriveTeamsFromSeriesMatches(res?.matches || []);
      const teams = teamList.length ? teamList : null;
      return {
        start,
        end,
        count,
        counts,
        teams,
        teamCount: teamList.length,
        seriesName: res?.seriesName || '',
      };
    } catch (err) {
      logger.warn({ msg: 'recoverSeriesMeta failed', seriesId, error: err.message });
      return { start: null, end: null, count: 0, counts: {}, teams: null, teamCount: 0, seriesName: '' };
    }
  }

  // GET /series
  // ?refresh=true bypasses Redis cache and recomputes the enriched list immediately.
  // Use this after a backend deploy or when the cached status/dates are stale.
  fastify.get('/series', {
    schema: { description: 'Get all series', tags: ['Series'] },
  }, async (request, reply) => {
    const forceRefresh = request.query.refresh === 'true';
    const CACHE_KEY = 'series:list:enriched:v2';
    if (forceRefresh) {
      await cacheSet(CACHE_KEY, null, 1); // expire immediately
      logger.info({ msg: 'Series list cache busted via ?refresh=true' });
    }
    const { data } = await cacheGetOrFetch(CACHE_KEY, TTL.SERIES, enrichSeriesList);
    return { success: true, data: data || [], fromCache: !forceRefresh };
  });

  /**
   * Helper: fetch series data and strictly filter matches by source_series_id.
   * NEVER relabels matches — preserves original Cricbuzz series IDs.
   */
  async function fetchSeriesMatches(requestedSeriesId) {
    const cacheKey = `series:${requestedSeriesId}:data:v4`;
    const { data } = await cacheGetOrFetch(
      cacheKey,
      TTL.SERIES,
      async () => {
        const result = await providerManager.execute('getSeriesInfo', requestedSeriesId);
        return result.data;
      }
    );

    const seriesData = data?.matches ? data : { seriesId: requestedSeriesId, seriesName: data?.seriesName || '', matches: Array.isArray(data) ? data : [] };
    const allMatches = seriesData.matches || [];

    // STRICT FILTER: Only include matches whose ORIGINAL source series ID matches the requested one.
    // NEVER relabel or inject series_id — each match keeps its original Cricbuzz data.
    const filtered = [];
    const rejected = [];

    for (const m of allMatches) {
      const sourceId = String(m.source_series_id || m.series_id || '');
      if (sourceId === String(requestedSeriesId)) {
        filtered.push(m);
      } else if (sourceId === '') {
        // Match has no seriesId at all — cannot verify, exclude it
        rejected.push({ match_id: m.match_id, teams: `${m.team1?.name || '?'} vs ${m.team2?.name || '?'}`, reason: 'no_source_series_id' });
      } else {
        rejected.push({ match_id: m.match_id, teams: `${m.team1?.name || '?'} vs ${m.team2?.name || '?'}`, source_series_id: sourceId, source_series_name: m.source_series_name || m.series_name || '', reason: 'wrong_series' });
      }
    }

    if (rejected.length > 0) {
      logger.info({ msg: 'Series match filter', requestedSeriesId, accepted: filtered.length, rejected: rejected.length });
    }

    return {
      seriesId: requestedSeriesId,
      seriesName: seriesData.seriesName || '',
      matches: filtered,
      totalFetched: allMatches.length,
      totalFiltered: filtered.length,
    };
  }

  // GET /series/:id
  fastify.get('/series/:id', {
    schema: {
      description: 'Get series details and matches',
      tags: ['Series'],
      params: { type: 'object', properties: { id: { type: 'string' } }, required: ['id'] },
    },
  }, async (request, reply) => {
    const { id } = request.params;
    const result = await fetchSeriesMatches(id);
    if (!result) return reply.code(404).send({ success: false, error: 'Series not found' });
    return { success: true, ...result };
  });

  // GET /series/:id/matches — source of truth for series-specific matches
  fastify.get('/series/:id/matches', {
    schema: {
      description: 'Get only matches belonging to this series (strict source_series_id filtering). Supports ?status=live|upcoming|completed.',
      tags: ['Series'],
      params: { type: 'object', properties: { id: { type: 'string' } }, required: ['id'] },
      querystring: {
        type: 'object',
        properties: {
          status: { type: 'string', enum: ['live', 'upcoming', 'completed'], description: 'Filter by match status' },
        },
      },
    },
  }, async (request, reply) => {
    const { id } = request.params;
    const { status } = request.query;

    const result = await fetchSeriesMatches(id);
    let matches = result.matches;

    // Apply status filter if provided
    if (status) {
      matches = matches.filter((m) => m.status === status);
    }

    return {
      success: true,
      seriesId: id,
      seriesName: result.seriesName,
      data: matches,
      totalFetched: result.totalFetched,
      totalFiltered: matches.length,
      ...(matches.length === 0 ? { message: 'No matches available for this series yet' } : {}),
    };
  });

  // GET /points-table/:seriesId
  fastify.get('/points-table/:seriesId', {
    schema: {
      description: 'Get points table for a series',
      tags: ['Series'],
      params: { type: 'object', properties: { seriesId: { type: 'string' } }, required: ['seriesId'] },
    },
  }, async (request, reply) => {
    const { seriesId } = request.params;
    try {
      const { data, fromCache } = await fetchPointsTable(seriesId);
      const response = normalizePointsTableResponse(seriesId, data);
      
      reply.header('X-Cache', fromCache ? 'HIT' : 'MISS');
      return {
        success: true,
        seriesId,
        data: response,
        ...response,
        fromCache,
        message: response.groups.length === 0
          ? (data?.message || 'Points table is not available for this series yet.')
          : null,
      };
    } catch (err) {
      logger.error({ msg: '[FIXED] Points table fetch failed', seriesId, error: err.message });
      return {
        success: false,
        seriesId,
        data: null,
        message: 'Points table source not found',
        debug: { reason: err.message },
      };
    }
  });

  // GET /series/:id/points-table — app-facing points-table path
  fastify.get('/series/:id/points-table', {
    schema: {
      description: 'Get points table for a series',
      tags: ['Series'],
      params: { type: 'object', properties: { id: { type: 'string' } }, required: ['id'] },
    },
  }, async (request, reply) => {
    const { id } = request.params;
    try {
      const { data, fromCache } = await fetchPointsTable(id);
      const series = await fetchSeriesMatches(id).catch(() => ({ seriesName: '' }));
      const response = normalizePointsTableResponse(id, data, series.seriesName);
      reply.header('X-Cache', fromCache ? 'HIT' : 'MISS');
      return {
        success: true,
        ...response,
        data: response,
        fromCache,
        message: response.groups.length === 0 ? (data?.message || 'Points table is not available for this series yet.') : null,
      };
    } catch (err) {
      logger.error({ msg: 'Points table fetch failed', seriesId: id, error: err.message });
      return { success: false, seriesId: id, data: null, message: 'Points table source not found', debug: { reason: err.message } };
    }
  });

  // GET /series/:id/stats
  fastify.get('/series/:id/stats', {
    schema: {
      description: 'Get available stat types for a series',
      tags: ['Series'],
      params: { type: 'object', properties: { id: { type: 'string' } }, required: ['id'] },
      response: {
        200: {
          type: 'object',
          properties: {
            success: { type: 'boolean' },
            seriesId: { type: 'string' },
            data: { type: 'object', nullable: true, additionalProperties: true },
            counts: {
              type: 'object',
              nullable: true,
              additionalProperties: true,
            },
            message: { type: 'string', nullable: true },
            debug: { type: 'object', nullable: true, additionalProperties: true },
          },
        },
      },
    },
  }, async (request, reply) => {
    const { id } = request.params;
    try {
      const [battingResult, bowlingResult] = await Promise.all([
        fetchSeriesStatsTable(id, 'mostRuns'),
        fetchSeriesStatsTable(id, 'mostWickets'),
      ]);
      const batting = toStatsRows(battingResult.table, 'mostRuns');
      const bowling = toStatsRows(bowlingResult.table, 'mostWickets');

      if (!batting.rows.length && !bowling.rows.length) {
        reply.header('X-Cache', 'MISS');
        return emptyStatsResponse(
          id,
          null,
          `${battingResult.sourcePath}, ${bowlingResult.sourcePath}`,
          { batting: battingResult.table, bowling: bowlingResult.table },
        );
      }

      reply.header('X-Cache', battingResult.fromCache && bowlingResult.fromCache ? 'HIT' : 'MISS');
      return {
        success: true,
        seriesId: id,
        data: { batting, bowling, items: [...batting.rows, ...bowling.rows] },
        counts: {
          batting: batting.rows.length,
          bowling: bowling.rows.length,
        },
        message: null,
      };
    } catch (err) {
      return {
        success: false,
        seriesId: id,
        data: null,
        message: 'Series stats source returned no rows',
        debug: {
          type: 'grouped',
          sourcePath: `/api/cricket-series/series-stats/${id}/mostRuns, /api/cricket-series/series-stats/${id}/mostWickets`,
          rawKeys: [],
          reason: err.message,
        },
      };
    }
  });

  // GET /series/:id/stats/:type
  fastify.get('/series/:id/stats/:type', {
    schema: {
      description: 'Get stat table (player rankings) for a series by stat type',
      tags: ['Series'],
      params: {
        type: 'object',
        properties: {
          id: { type: 'string' },
          type: { type: 'string', description: 'Stat type e.g. mostRuns, mostWickets' },
        },
        required: ['id', 'type'],
      },
      response: {
        200: {
          type: 'object',
          properties: {
            success: { type: 'boolean' },
            seriesId: { type: 'string' },
            type: { type: 'string' },
            providerType: { type: 'string', nullable: true },
            data: { type: 'object', nullable: true, additionalProperties: true },
            count: { type: 'integer', nullable: true },
            message: { type: 'string', nullable: true },
            debug: { type: 'object', nullable: true, additionalProperties: true },
          },
        },
      },
    },
  }, async (request, reply) => {
    const { id, type } = request.params;
    const providerType = normalizeStatsAlias(type);
    try {
      const { table, fromCache, sourcePath } = await fetchSeriesStatsTable(id, providerType);
      const data = toStatsRows(table, providerType);
      reply.header('X-Cache', fromCache ? 'HIT' : 'MISS');
      if (!data.rows.length) {
        return emptyStatsResponse(id, toAppStatsType(providerType), sourcePath, table);
      }
      return {
        success: true,
        seriesId: id,
        type: toAppStatsType(providerType),
        providerType,
        data: { ...data, items: data.rows },
        count: data.rows.length,
        message: null,
      };
    } catch (err) {
      return {
        success: false,
        seriesId: id,
        type: toAppStatsType(providerType),
        data: null,
        message: 'Series stats source returned no rows',
        debug: {
          type: toAppStatsType(providerType),
          sourcePath: `/api/cricket-series/series-stats/${id}/${providerType}`,
          rawKeys: [],
          reason: err.message,
        },
      };
    }
  });

  // GET /series/:id/schedule
  fastify.get('/series/:id/schedule', {
    schema: {
      description: 'Get app-ready series schedule',
      tags: ['Series'],
      params: { type: 'object', properties: { id: { type: 'string' } }, required: ['id'] },
    },
  }, async (request) => {
    const { id } = request.params;
    const result = await fetchSeriesMatches(id);
    const data = normalizeSeriesSchedule(id, result);
    return {
      success: true,
      ...data,
      data,
      message: data.matches.length === 0 ? 'No schedule available for this series' : null,
    };
  });

  // GET /series/:id/news
  fastify.get('/series/:id/news', {
    schema: {
      description: 'Get news stories for a series',
      tags: ['Series'],
      params: { type: 'object', properties: { id: { type: 'string' } }, required: ['id'] },
      querystring: {
        type: 'object',
        properties: {
          cursor: { type: 'string', description: 'Pagination cursor (story ID)' },
          limit: { type: 'integer', minimum: 1, maximum: 50, default: 10 },
        },
      },
    },
  }, async (request, reply) => {
    const { id } = request.params;
    const { cursor, limit = 10 } = request.query;
    try {
      const { data } = await cacheGetOrFetch(
        KEYS.seriesNews(id, cursor),
        TTL.SERIES_NEWS,
        async () => (await providerManager.execute('getSeriesNews', id, cursor || undefined)).data
      );
      if (!data || !data.stories) {
        return { success: true, seriesId: id, data: { stories: [], nextCursor: null }, message: 'No news available for this series' };
      }
      const stories = data.stories.slice(0, limit);
      return { success: true, seriesId: id, data: { stories, nextCursor: data.nextCursor || null }, message: null };
    } catch {
      return { success: true, seriesId: id, data: { stories: [], nextCursor: null }, message: 'Series news not available' };
    }
  });

  // GET /series/:id/teams - Series teams list
  fastify.get('/series/:id/teams', {
    schema: {
      description: 'Get teams participating in a series',
      tags: ['Series'],
      params: { type: 'object', properties: { id: { type: 'string' } }, required: ['id'] },
    },
  }, async (request) => {
    const { id } = request.params;
    try {
      const cached = await cacheGet(KEYS.seriesTeams(id));
      const cachedTeams = cleanSeriesTeams(
        Array.isArray(cached?.teams)
          ? cached.teams
          : Array.isArray(cached?.data?.teams)
            ? cached.data.teams
            : Array.isArray(cached)
              ? cached
              : []
      );
      if (cachedTeams.length > 0) {
        return {
          success: true,
          seriesId: id,
          data: { ...(cached || {}), teams: cachedTeams },
          teams: cachedTeams,
          count: cachedTeams.length,
          updatedAt: new Date().toISOString(),
          fromCache: true,
        };
      }

      const result = await providerManager.execute('getSeriesTeams', id);
      const rawTeamsData = result?.data || { teams: [] };
      const rawList = Array.isArray(rawTeamsData.teams)
        ? rawTeamsData.teams
        : Array.isArray(rawTeamsData.data)
          ? rawTeamsData.data
          : Array.isArray(rawTeamsData.items)
            ? rawTeamsData.items
            : [];
      let cleanList = cleanSeriesTeams(rawList);

      if (cleanList.length === 0) {
        const matchesResult = await fetchSeriesMatches(id);
        cleanList = deriveTeamsFromSeriesMatches(matchesResult?.matches || []);
        if (cleanList.length > 0) {
          logger.info({
            msg: 'Derived series teams from matches',
            seriesId: id,
            teams: cleanList.length,
            matches: matchesResult?.matches?.length || 0,
          });
        }
      }

      const teamsData = {
        ...rawTeamsData,
        seriesId: id,
        teams: cleanList,
        count: cleanList.length,
        source: cleanList.length > 0 && rawList.length === 0 ? 'cricbuzz:matches-derived' : (rawTeamsData.source || 'cricbuzz'),
      };

      if (cleanList.length > 0) {
        await cacheSet(KEYS.seriesTeams(id), teamsData, cleanList.length > 0 ? TTL.SQUADS : 30);
      }

      return {
        success: true,
        seriesId: id,
        data: teamsData,
        teams: cleanList,
        count: cleanList.length,
        updatedAt: new Date().toISOString(),
        fromCache: false,
        message: cleanList.length === 0 ? 'No teams data available for this series' : null,
      };
    } catch (err) {
      logger.warn({ msg: 'Failed to fetch series teams', seriesId: id, error: err.message });
      return {
        success: true,
        seriesId: id,
        data: { teams: [] },
        teams: [],
        count: 0,
        updatedAt: new Date().toISOString(),
        message: 'Series teams not available',
      };
    }
  });

  // --- Series squads helpers ------------------------------------------------

  // Picks the match in a series most likely to have an announced squad:
  // prefer live, then the nearest upcoming, then the most recent completed.
  function pickSquadMatch(matches = []) {
    if (!matches.length) return null;
    const byStatus = (s) => matches.filter((m) => m.status === s);
    const live = byStatus('live');
    if (live.length) return live[0];
    const upcoming = byStatus('upcoming').sort((a, b) =>
      Number(a.start_time || a.startTime || 0) - Number(b.start_time || b.startTime || 0));
    if (upcoming.length) return upcoming[0];
    const completed = byStatus('completed').sort((a, b) =>
      Number(b.start_time || b.startTime || 0) - Number(a.start_time || a.startTime || 0));
    if (completed.length) return completed[0];
    return matches[0];
  }

  function teamLogoFromMatchTeam(team) {
    if (!team) return '';
    return text(team.logo_url || team.logoUrl)
      || cricbuzzImageUrl(text(team.image_id || team.imageId));
  }

  const supportStaffPattern = /\b(?:head\s+coach|assistant\s+coach|batting\s+coach|bowling\s+coach|fielding\s+coach|support\s+staff|team\s+manager|manager|physio|analyst|selector|mentor|coach)\b/i;

  function isSupportStaffPlayer(player) {
    const combined = [
      player?.name,
      player?.role,
      player?.playerName,
      player?.title,
    ].map(text).join(' ');
    return supportStaffPattern.test(combined);
  }

  // Normalizes a squad team (from match squads) into the app-friendly shape
  // with face image URLs resolved by player id.
  function normalizeSquadTeam(squadTeam, matchTeam) {
    if (!squadTeam) return null;
    const players = [
      ...(Array.isArray(squadTeam.playing_xi) ? squadTeam.playing_xi : []),
      ...(Array.isArray(squadTeam.bench) ? squadTeam.bench : []),
    ];
    const mapped = players.filter((p) => !isSupportStaffPlayer(p)).map((p) => {
      const playerId = text(p.player_id || p.playerId);
      // Only use a genuine Cricbuzz face image resolved at scrape time. We never
      // synthesise an image URL from the player id (that produced wrong faces),
      // so a missing image yields null and the app shows an initials avatar.
      const imageUrl = text(p.image_url || p.imageUrl);
      const hasImage = imageUrl.length > 0;
      return {
        playerId,
        name: text(p.name),
        role: text(p.role),
        isCaptain: !!(p.is_captain || p.isCaptain),
        isWicketKeeper: !!(p.is_wicketkeeper || p.isWicketKeeper),
        isSubstitute: !!(p.is_substitute || p.isSubstitute),
        isImpactPlayer: !!(p.is_impact_player || p.isImpactPlayer),
        imageUrl: hasImage ? imageUrl : null,
        imageSource: hasImage ? 'cricbuzz' : 'none',
        profileUrl: playerId ? `https://www.cricbuzz.com/profiles/${playerId}` : '',
      };
    }).filter((p) => p.name);

    const teamName = text(squadTeam.team_name || squadTeam.teamName || matchTeam?.name);
    const teamShort = text(squadTeam.team_short || squadTeam.teamShort || matchTeam?.short_name);
    return {
      teamId: text(squadTeam.teamId || matchTeam?.id),
      teamName,
      teamShortName: teamShort,
      logoUrl: text(squadTeam.logoUrl) || teamLogoFromMatchTeam(matchTeam),
      players: mapped,
      playerCount: mapped.length,
    };
  }

  // Builds the new grouped squads payload from the Cricbuzz series-squads API.
  // Returns { formats: [ { format, teams: [ { teamName, teamShortName,
  // squadId, logoUrl, players[] } ] } ] } or null when nothing is available.
  async function buildGroupedSeriesSquads(seriesId, seriesName) {
    let groups = [];
    try {
      const res = await providerManager.execute('getSeriesSquadGroups', seriesId);
      groups = Array.isArray(res?.data) ? res.data : Array.isArray(res) ? res : [];
    } catch (err) {
      logger.warn({ msg: 'getSeriesSquadGroups failed', seriesId, error: err.message });
    }
    if (!groups.length) return null;

    logger.info({
      msg: '[Squads] discovered groups',
      seriesId,
      count: groups.length,
      groups: groups.map((g) => ({
        squadId: g.squadId,
        format: g.format,
        teamName: g.teamName,
        teamId: g.teamId,
      })),
    });

    // Resolve each squad group's players in parallel (best-effort). Each squad
    // gets its OWN fresh players array — never shared by reference.
    const resolved = await Promise.all(groups.map(async (g) => {
      try {
        const res = await providerManager.execute('getSeriesSquad', seriesId, g.squadId);
        const squad = res?.data || res || {};
        const players = Array.isArray(squad.players)
            ? squad.players.map((p) => ({ ...p }))
            : [];
        logger.info({
          msg: '[Squads] resolved squad',
          seriesId,
          squadId: g.squadId,
          format: g.format,
          teamName: g.teamName,
          playerCount: players.length,
          first5: players.slice(0, 5).map((p) => p.name),
        });
        return { group: g, players };
      } catch (err) {
        logger.warn({ msg: '[Squads] getSeriesSquad failed', seriesId, squadId: g.squadId, error: err.message });
        return { group: g, players: [] };
      }
    }));

    // Group by format, preserving discovery order.
    const formatOrder = [];
    const byFormat = new Map();
    for (const { group, players } of resolved) {
      const fmt = group.format || group.squadType || 'Squad';
      if (!byFormat.has(fmt)) {
        byFormat.set(fmt, []);
        formatOrder.push(fmt);
      }
      const shortName = generateShortNameSafe(group.teamName);
      byFormat.get(fmt).push({
        teamId: group.teamId || '',
        teamName: group.teamName || '',
        teamShortName: shortName,
        squadId: group.squadId || '',
        logoUrl: group.imageId ? cricbuzzImageUrl(group.imageId) : '',
        players,
        playerCount: players.length,
      });
    }

    const formats = formatOrder.map((format) => ({
      format,
      teams: byFormat.get(format),
    }));

    // Flat team list (for legacy clients only). Deduped by team identity,
    // keeping the squad with the most players. Never merges player arrays.
    const flatByTeam = new Map();
    for (const f of formats) {
      for (const t of f.teams) {
        const key = (t.teamId || t.teamName || t.teamShortName || t.squadId)
            .toString()
            .toLowerCase();
        const existing = flatByTeam.get(key);
        if (!existing || t.players.length > existing.players.length) {
          flatByTeam.set(key, t);
        }
      }
    }

    return {
      seriesId: String(seriesId),
      seriesName: seriesName || '',
      formats,
      teams: [...flatByTeam.values()],
      updatedAt: new Date().toISOString(),
    };
  }

  function generateShortNameSafe(name = '') {
    const n = text(name);
    if (!n) return '';
    // Known multi-word countries → conventional abbreviations.
    const map = {
      'south africa': 'SA', 'new zealand': 'NZ', 'sri lanka': 'SL',
      'west indies': 'WI', 'united states': 'USA', 'united arab emirates': 'UAE',
      'papua new guinea': 'PNG', 'hong kong': 'HK',
    };
    const key = n.toLowerCase();
    if (map[key]) return map[key];
    const words = n.split(/\s+/).filter(Boolean);
    if (words.length === 1) return words[0].slice(0, 3).toUpperCase();
    return words.map((w) => w[0]).join('').slice(0, 3).toUpperCase();
  }

  // GET /series/:id/squads — real player squads (with face images) for every
  // team and format in the series, sourced from the Cricbuzz series-squads API.
  // Falls back to deriving a single match's squad when the squad index is
  // unavailable.
  fastify.get('/series/:id/squads', {
    schema: {
      description: 'Get grouped squads (per team per format) for a series',
      tags: ['Series'],
      params: { type: 'object', properties: { id: { type: 'string' } }, required: ['id'] },
    },
  }, async (request, reply) => {
    const { id } = request.params;
    try {
      const cached = await cacheGet(KEYS.seriesSquads(id));
      if (cached?.formats?.some((f) => f.teams?.some((t) => (t.players || []).length > 0))) {
        reply.header('X-Cache', 'HIT');
        return { success: true, seriesId: id, ...cached, data: cached, fromCache: true };
      }

      const series = await fetchSeriesMatches(id).catch(() => ({ seriesName: '', matches: [] }));

      // Primary: grouped series squads (multi-format, both teams, full squads).
      const grouped = await buildGroupedSeriesSquads(id, series.seriesName);
      if (grouped && grouped.formats.some((f) => f.teams.some((t) => t.players.length > 0))) {
        await cacheSet(KEYS.seriesSquads(id), grouped, TTL.SQUADS);
        reply.header('X-Cache', 'MISS');
        return { success: true, ...grouped, data: grouped, fromCache: false, message: null };
      }

      // Fallback: derive from a representative match's squad page.
      logger.warn({
        msg: '[Squads] grouped squads empty — using match-squad fallback',
        seriesId: id,
      });
      const matches = series.matches || [];
      const squadMatch = pickSquadMatch(matches);
      if (squadMatch) {
        const matchId = text(squadMatch.match_id || squadMatch.matchId);
        const squadResult = await providerManager.execute('getMatchSquads', matchId).catch(() => null);
        const squad = squadResult?.data || null;
        const teams = [];
        const t1 = normalizeSquadTeam(squad?.team1, squadMatch.team1);
        const t2 = normalizeSquadTeam(squad?.team2, squadMatch.team2);
        if (t1 && t1.players.length) teams.push(t1);
        if (t2 && t2.players.length) teams.push(t2);
        if (teams.some((t) => t.players.length > 0)) {
          const payload = {
            seriesId: id,
            seriesName: series.seriesName || '',
            sourceMatchId: matchId,
            formats: [{ format: '', teams }],
            teams,
            updatedAt: new Date().toISOString(),
          };
          await cacheSet(KEYS.seriesSquads(id), payload, TTL.SQUADS);
          reply.header('X-Cache', 'MISS');
          return { success: true, ...payload, data: payload, fromCache: false, message: null };
        }
      }

      return {
        success: true,
        seriesId: id,
        seriesName: series.seriesName || '',
        formats: [],
        teams: [],
        data: { formats: [], teams: [] },
        message: 'Squads have not been announced for this series yet.',
      };
    } catch (err) {
      logger.warn({ msg: 'Failed to fetch series squads', seriesId: id, error: err.message });
      return {
        success: true,
        seriesId: id,
        formats: [],
        teams: [],
        data: { formats: [], teams: [] },
        message: 'Squads are not available for this series yet.',
      };
    }
  });
}

