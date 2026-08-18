/**
 * Normalizes ESPN Cricinfo (site.api / site.web.api) responses into the SAME
 * internal schema the Cricbuzz normalizer emits, so downstream routes/clients
 * cannot tell which provider answered.
 *
 * ESPN vocabulary reference:
 *   - match/event id = `event.id`; series/league id = `league.id`
 *   - state: `pre` (upcoming) | `in` (live) | `post` (completed)
 *   - `class.eventType` = ODI | T20 | TEST | ... ; `class.internationalClassId`
 *   - competitor `score` is a STRING: "298/5", "173 (42.3/50 ov, target 299)"
 *   - competitor `linescores[]` carry per-innings {period, runs, wickets, overs}
 *   - per-player stats live in rosters[].roster[].linescores[period].linescores[]
 *     .statistics.categories[].stats[] as flat {name, value, displayValue} pairs
 */

// --- small utilities -------------------------------------------------------

import { derivePhase } from '../../lib/match-phase.js';

function iso(value) {
  if (!value) return null;
  try {
    const d = value instanceof Date ? value : new Date(value);
    return Number.isNaN(d.getTime()) ? null : d.toISOString();
  } catch {
    return null;
  }
}

/** ESPN state (`pre`/`in`/`post`) → internal status. */
export function mapState(state, statusText = '') {
  const s = String(state || '').toLowerCase();
  if (s === 'in') return 'live';
  if (s === 'pre') return 'upcoming';
  if (s === 'post') {
    const t = String(statusText || '').toLowerCase();
    if (t.includes('abandon')) return 'abandoned';
    if (t.includes('no result')) return 'no_result';
    return 'completed';
  }
  return 'upcoming';
}

/** ESPN eventType/class → internal match_format token (t20/odi/test). */
export function mapFormat(eventType) {
  const t = String(eventType || '').toLowerCase().replace(/[^a-z0-9]/g, '');
  if (t.includes('test')) return 'test';
  if (t.includes('t20') || t.includes('t20i')) return 't20';
  if (t.includes('odi') || t.includes('od')) return 'odi';
  if (t.includes('t10')) return 't10';
  if (t.includes('hundred')) return 'hundred';
  return String(eventType || '').toLowerCase();
}

/**
 * Parse an ESPN competitor score string into {runs, wickets, overs}.
 * Handles: "298/5", "173 (42.3/50 ov, target 299)", "120/3 (18.2 ov)",
 * "350" (all out, no wicket count), "" / null → zeros.
 */
export function parseScore(scoreStr) {
  const out = { runs: 0, wickets: 0, overs: 0 };
  if (!scoreStr) return out;
  const str = String(scoreStr).trim();
  // runs/wickets — "298/5" or leading "173"
  const rw = /^(\d+)(?:\/(\d+))?/.exec(str);
  if (rw) {
    out.runs = parseInt(rw[1], 10) || 0;
    out.wickets = rw[2] != null ? parseInt(rw[2], 10) || 0 : 0;
  }
  // overs — inside parens like "(42.3/50 ov" or "(18.2 ov)"
  const ov = /\(?\s*(\d+(?:\.\d+)?)\s*(?:\/\s*\d+)?\s*ov/i.exec(str);
  if (ov) out.overs = parseFloat(ov[1]) || 0;
  return out;
}

function num(value, fallback = 0) {
  const n = Number(value);
  return Number.isFinite(n) ? n : fallback;
}

// --- match list / summaries ------------------------------------------------

function teamFromCompetitor(c) {
  const t = c?.team || c || {};
  return {
    id: String(t.id ?? c?.id ?? ''),
    name: t.displayName || t.name || t.location || '',
    short_name: t.abbreviation || t.shortDisplayName || '',
  };
}

/** Build the internal score{team1:[...], team2:[...]} from competitor linescores. */
function scoreFromCompetitors(comps) {
  const inningsOf = (c) => {
    // Prefer structured linescores; fall back to the score string. A real
    // innings has runs or wickets — overs is pre-filled to the format max even
    // for a side that has not batted, so it must NOT qualify a placeholder.
    const ls = Array.isArray(c?.linescores) ? c.linescores : [];
    const real = ls.filter((l) => num(l.runs) || num(l.wickets));
    if (real.length) {
      return real.map((l) => ({
        runs: num(l.runs),
        wickets: num(l.wickets),
        overs: num(l.overs),
        innings_number: num(l.period, undefined) || undefined,
      }));
    }
    if (c?.score) {
      const p = parseScore(c.score);
      return p.runs || p.overs ? [{ ...p, innings_number: 1 }] : [];
    }
    return [];
  };
  return {
    team1: comps[0] ? inningsOf(comps[0]) : [],
    team2: comps[1] ? inningsOf(comps[1]) : [],
  };
}

/**
 * Normalize one ESPN event (from scoreboard/header league.events[]) into an
 * internal match summary. `seriesId`/`seriesName` come from the enclosing league.
 */
export function normalizeEvent(ev, seriesId = '', seriesName = '') {
  const comps = Array.isArray(ev?.competitors) ? ev.competitors : [];
  const status = ev?.fullStatus?.type?.state || ev?.status;
  const statusText =
    ev?.fullStatus?.type?.description ||
    ev?.fullStatus?.summary ||
    ev?.summary ||
    '';
  const battingComp = comps.find((c) =>
    (c.linescores || []).some((l) => l.isCurrent || l.isBatting),
  );
  const coarseStatus = mapState(status, statusText);
  return {
    match_id: String(ev?.id || ev?.competitionId || ''),
    series_id: String(seriesId || ''),
    series_name: seriesName || '',
    match_format: mapFormat(ev?.class?.eventType || ev?.eventType),
    match_type: ev?.class?.generalClassCard || ev?.class?.name || '',
    match_desc: ev?.title || ev?.name || '',
    status: coarseStatus,
    phase: derivePhase(coarseStatus, statusText),
    status_text: statusText,
    short_status: ev?.fullStatus?.type?.shortDetail || ev?.status || '',
    team1: comps[0] ? teamFromCompetitor(comps[0]) : { id: '', name: '', short_name: '' },
    team2: comps[1] ? teamFromCompetitor(comps[1]) : { id: '', name: '', short_name: '' },
    venue: { name: ev?.location || '', city: '', country: '' },
    start_time: iso(ev?.date),
    end_time: iso(ev?.endDate),
    current_innings: 0,
    curr_bat_team_id: battingComp ? String(battingComp.id || battingComp.team?.id || '') : null,
    match_image_url: '',
    score: scoreFromCompetitors(comps),
    last_updated: new Date().toISOString(),
  };
}

/**
 * Flatten a scoreboard/header payload into a filtered internal match list.
 * @param {object} raw - scoreboard/header response
 * @param {'live'|'upcoming'|'recent'|null} filter
 */
export function normalizeMatchList(raw, filter = null) {
  const leagues = raw?.sports?.[0]?.leagues || raw?.leagues || [];
  const matches = [];
  for (const league of leagues) {
    const sId = String(league?.id || '');
    const sName = league?.name || league?.shortName || '';
    for (const ev of league?.events || []) {
      const m = normalizeEvent(ev, sId, sName);
      if (filter === 'live' && m.status !== 'live') continue;
      if (filter === 'upcoming' && m.status !== 'upcoming') continue;
      if (
        filter === 'recent' &&
        !['completed', 'abandoned', 'no_result'].includes(m.status)
      ) {
        continue;
      }
      matches.push(m);
    }
  }
  return matches;
}

// --- match detail ----------------------------------------------------------

/** Normalize a /summary response's header into an internal match-detail object. */
export function normalizeMatchDetail(raw) {
  const header = raw?.header || {};
  const comp = (header.competitions || [])[0] || {};
  const comps = comp.competitors || [];
  const status = comp?.status?.type?.state;
  const statusText = comp?.status?.type?.description || comp?.status?.summary || '';
  const league = (header.leagues || [])[0] || header.league || {};
  const toss = (raw?.notes || []).find((n) => n.type === 'toss');

  const teamWithInnings = (c) => ({
    ...teamFromCompetitor(c),
    innings: (c?.linescores || [])
      .filter((l) => num(l.runs) || num(l.wickets))
      .map((l) => ({
        runs: num(l.runs),
        wickets: num(l.wickets),
        overs: num(l.overs),
        innings_number: num(l.period, undefined) || undefined,
      })),
  });

  const coarseStatus = mapState(status, statusText);
  return {
    match_id: String(header.id || comp.id || ''),
    series_id: String(league.id || ''),
    series_name: league.name || header.league?.name || '',
    match_format: mapFormat(comp?.class?.eventType || comp?.class?.name),
    match_type: comp?.class?.generalClassCard || comp?.class?.name || '',
    match_desc: header.title || header.name || '',
    status: coarseStatus,
    phase: derivePhase(coarseStatus, statusText),
    status_text: statusText,
    team1: comps[0] ? teamWithInnings(comps[0]) : { id: '', name: '', short_name: '', innings: [] },
    team2: comps[1] ? teamWithInnings(comps[1]) : { id: '', name: '', short_name: '', innings: [] },
    venue: { name: comp?.venue?.fullName || '', city: comp?.venue?.address?.city || '', country: '' },
    start_time: iso(comp.date || header.date),
    toss: { winner: '', decision: toss?.text || '' },
    result: statusText,
    innings: [],
    last_updated: new Date().toISOString(),
  };
}

// --- scorecard -------------------------------------------------------------

/** Pull a flat stat value by name from an ESPN player-innings stats block. */
function statVal(statsBlock, name) {
  const cats = statsBlock?.statistics?.categories || [];
  for (const cat of cats) {
    for (const st of cat.stats || []) {
      if (st.name === name) return st.value;
    }
  }
  return undefined;
}

/**
 * Build the internal scorecard from a /summary response's rosters + linescores.
 * Returns null when no innings/roster data is present (caller emits a sentinel).
 */
export function normalizeScorecard(raw) {
  const header = raw?.header || {};
  const comp = (header.competitions || [])[0] || {};
  const comps = comp.competitors || [];
  const rosters = raw?.rosters || [];
  if (!comps.length || !rosters.length) return null;

  // Team roster lookup by team id.
  const rosterByTeam = new Map();
  for (const r of rosters) rosterByTeam.set(String(r.team?.id || ''), r);

  // Determine the innings order from competitor linescores (period = innings#).
  // ESPN lists a linescore period for BOTH competitors even when only one batted
  // in it — the non-batting side is a placeholder (runs:0, wickets:0, overs:=
  // format max). A real innings always has runs or wickets, so filter on those
  // and NOT on overs (which is pre-filled) to drop the phantom placeholders.
  const inningsMeta = [];
  for (const c of comps) {
    const teamId = String(c.id || c.team?.id || '');
    for (const l of c.linescores || []) {
      if (!(num(l.runs) || num(l.wickets))) continue;
      inningsMeta.push({
        period: num(l.period),
        battingTeamId: teamId,
        battingTeamName: c.team?.displayName || c.team?.name || '',
        total: { runs: num(l.runs), wickets: num(l.wickets), overs: num(l.overs) },
      });
    }
  }
  // A team can bat twice (Tests) in the same period numbering across competitors,
  // so order by period then by the innings' running total is not reliable; ESPN's
  // period already encodes chronology per competitor. Sort by period, then keep a
  // stable competitor order for same-period (multi-innings) cases.
  inningsMeta.sort((a, b) => a.period - b.period);
  if (!inningsMeta.length) return null;

  const battingRow = (player) => {
    const periods = player.linescores || [];
    return periods;
  };

  const innings = inningsMeta.map((meta, idx) => {
    const battingTeam = rosterByTeam.get(meta.battingTeamId);
    const bowlingTeam = rosters.find((r) => String(r.team?.id || '') !== meta.battingTeamId);

    const batting = [];
    for (const p of battingTeam?.roster || []) {
      const per = (battingRow(p) || []).find((x) => num(x.period) === meta.period);
      const sub = per?.linescores?.[0];
      if (!sub || statVal(sub, 'battingPosition') == null) continue;
      const runs = statVal(sub, 'runs');
      if (runs == null && statVal(sub, 'ballsFaced') == null) continue;
      batting.push({
        player_id: String(p.athlete?.id || ''),
        name: p.athlete?.displayName || p.athlete?.name || '',
        runs: num(runs),
        balls: num(statVal(sub, 'ballsFaced')),
        fours: num(statVal(sub, 'fours')),
        sixes: num(statVal(sub, 'sixes')),
        strike_rate: num(statVal(sub, 'strikeRate')),
        dismissal: sub?.batting?.outText || statVal(sub, 'dismissalCard') || '',
        is_batting: false,
        is_striker: false,
      });
    }

    const bowling = [];
    for (const p of bowlingTeam?.roster || []) {
      const per = (battingRow(p) || []).find((x) => num(x.period) === meta.period);
      const sub = per?.linescores?.[0];
      if (!sub) continue;
      const overs = statVal(sub, 'overs');
      if (statVal(sub, 'bowlingPosition') == null && overs == null) continue;
      if (!num(overs) && statVal(sub, 'inningsBowled') == null) continue;
      bowling.push({
        player_id: String(p.athlete?.id || ''),
        name: p.athlete?.displayName || p.athlete?.name || '',
        overs: num(overs),
        maidens: num(statVal(sub, 'maidens')),
        runs: num(statVal(sub, 'conceded')),
        wickets: num(statVal(sub, 'wickets')),
        economy: num(statVal(sub, 'economyRate')),
        dots: num(statVal(sub, 'dots')),
        wides: num(statVal(sub, 'wides')),
        no_balls: num(statVal(sub, 'noballs')),
        is_bowling: false,
      });
    }

    return {
      innings_number: meta.period || idx + 1,
      batting_team: meta.battingTeamName,
      batting_team_id: meta.battingTeamId,
      total: meta.total,
      run_rate: meta.total.overs ? +(meta.total.runs / meta.total.overs).toFixed(2) : 0,
      extras: { total: 0, byes: 0, leg_byes: 0, wides: 0, no_balls: 0, penalty: 0 },
      batting,
      bowling,
      fall_of_wickets: [],
      partnerships: [],
    };
  });

  return { innings, last_updated: new Date().toISOString() };
}

// --- commentary ------------------------------------------------------------

/** Normalize a /playbyplay response into the internal commentary array. */
export function normalizeCommentary(raw) {
  const items = raw?.commentary?.items || raw?.items || [];
  return items.map((c) => {
    const over = c?.over?.unique != null ? c.over.unique : (c?.over?.overs ?? null);
    const isWicket = !!c?.dismissal?.dismissal;
    const runs = num(c?.scoreValue ?? c?.over?.runs);
    return {
      id: String(c.id || c.sequence || ''),
      innings_number: num(c?.period ?? c?.innings?.number, 0),
      over: over != null ? Number(over) : null,
      ball: c?.over?.ball != null ? num(c.over.ball) : null,
      event: c?.playType?.description || 'ball',
      text: c.shortText || c.text || c.postText || '',
      runs,
      is_wicket: isWicket,
      is_boundary: runs === 4 || runs === 6,
      batsman: c?.batsman?.athlete?.displayName || '',
      bowler: c?.bowler?.athlete?.displayName || '',
      timestamp: Date.now(),
    };
  });
}

// --- series / points table -------------------------------------------------

/** Extract a de-duplicated series list from a scoreboard/header payload. */
export function normalizeSeriesList(raw) {
  const leagues = raw?.sports?.[0]?.leagues || raw?.leagues || [];
  const seen = new Set();
  const out = [];
  for (const l of leagues) {
    const id = String(l?.id || '');
    if (!id || seen.has(id)) continue;
    seen.add(id);
    out.push({
      series_id: id,
      name: l.name || l.shortName || '',
      season: String(l.season?.year || l.season || ''),
      start_date: iso(l.smartdates?.[0]?.date) || null,
      end_date: null,
    });
  }
  return out;
}

/** Normalize a single-series /scoreboard payload into {seriesId, seriesName, matches}. */
export function normalizeSeriesInfo(raw, seriesId) {
  const league = (raw?.leagues || [])[0] || {};
  const sId = String(league.id || seriesId || '');
  const sName = league.name || league.shortName || '';
  const matches = (raw?.events || []).map((ev) => normalizeEvent(ev, sId, sName));
  return { seriesId: sId, seriesName: sName, matches };
}

/**
 * Normalize standings from a single-series /scoreboard payload. ESPN cricket
 * league blocks rarely expose a full standings table via site.api; returns []
 * when absent (caller decides whether that warrants a sentinel).
 */
export function normalizePointsTable(raw) {
  const groups = raw?.standings?.groups || raw?.standings || [];
  const out = [];
  for (const group of Array.isArray(groups) ? groups : [groups]) {
    for (const entry of group?.standings?.entries || group?.entries || []) {
      const stats = {};
      for (const s of entry.stats || []) stats[s.name || s.type] = s.value;
      out.push({
        team_id: String(entry.team?.id || ''),
        team_name: entry.team?.displayName || entry.team?.name || '',
        team_short: entry.team?.abbreviation || '',
        position: num(stats.rank),
        played: num(stats.gamesPlayed ?? stats.played),
        won: num(stats.wins),
        lost: num(stats.losses),
        tied: num(stats.ties),
        no_result: num(stats.noResult),
        points: num(stats.points),
        nrr: num(stats.netRunRate ?? stats.nrr),
        group: group.name || '',
        qualified: false,
      });
    }
  }
  return out;
}

// --- standings / points table (from /apis/v2/.../standings) -----------------

/** Read a named stat value from an ESPN standings entry's flat stats[] list. */
function standingStat(entry, ...names) {
  const stats = entry?.stats || [];
  for (const name of names) {
    const s = stats.find((x) => x.name === name || x.type === name);
    if (s && s.value != null) return s;
  }
  return null;
}

/**
 * Normalize an ESPN /standings payload into the SAME points-table shape the
 * Cricbuzz normalizer emits: { seriesId, seriesName, groups:[{name,rows}],
 * rows:[...], source }. ESPN groups standings under `children[]` (one child per
 * group/pool), each with `standings.entries[]`. Returns a shape with empty
 * groups/rows when the payload carries no entries (caller decides sentinel).
 */
export function normalizeStandings(raw, seriesId = '') {
  const sId = String(raw?.id || seriesId || '');
  const sName = raw?.name || '';
  const children = Array.isArray(raw?.children) ? raw.children : [];

  const rowFrom = (entry, index, groupName) => {
    const team = entry?.team || {};
    const logos = team.logos || [];
    const val = (s) => (s && s.value != null ? s.value : null);
    const disp = (s) => (s && s.displayValue != null ? String(s.displayValue) : '');
    const rank = standingStat(entry, 'rank');
    const played = standingStat(entry, 'matchesPlayed', 'gamesPlayed', 'played');
    const won = standingStat(entry, 'matchesWon', 'wins');
    const lost = standingStat(entry, 'matchesLost', 'losses');
    const tied = standingStat(entry, 'matchesTied', 'ties');
    const noResult = standingStat(entry, 'noresult', 'noResult');
    const points = standingStat(entry, 'matchPoints', 'points');
    const nrr = standingStat(entry, 'netrr', 'netRunRate', 'nrr');
    const forStat = standingStat(entry, 'for');
    const againstStat = standingStat(entry, 'against');
    return {
      rank: num(val(rank), index + 1),
      teamId: String(team.id || ''),
      teamName: team.displayName || team.name || '',
      teamShortName: team.abbreviation || team.shortDisplayName || '',
      logoUrl: logos[0]?.href || '',
      imageId: null,
      matches: num(val(played)),
      won: num(val(won)),
      lost: num(val(lost)),
      tied: num(val(tied)),
      noResult: num(val(noResult)),
      matchesDrawn: 0,
      points: num(val(points)),
      nrr: nrr ? String(disp(nrr) || val(nrr)) : '',
      for: disp(forStat),
      against: disp(againstStat),
      form: [],
      qualified: false,
      qualificationStatus: '',
      groupName,
    };
  };

  const groups = [];
  const flatRows = [];
  for (const child of children) {
    const entries = child?.standings?.entries || [];
    if (!entries.length) continue;
    const groupName = child?.name || child?.standings?.displayName || 'Points Table';
    const rows = entries.map((e, i) => rowFrom(e, i, groupName));
    rows.sort((a, b) => a.rank - b.rank);
    groups.push({ name: groupName, rows });
    flatRows.push(...rows);
  }

  return {
    seriesId: sId,
    seriesName: sName,
    groups,
    rows: flatRows,
    source: 'espn-cricinfo',
  };
}

// --- full schedule (series-level date ranges from scoreboard/header) ---------

/**
 * Extract a series LIST with authoritative date ranges from a scoreboard/header
 * payload, matching the Cricbuzz getFullSchedule row shape:
 *   { series_id, name, start_date, end_date, source }
 * ESPN leagues carry calendarStartDate/calendarEndDate (season window) — the
 * closest analogue to Cricbuzz's series date range. Best-effort: returns [] when
 * no leagues are present.
 */
export function normalizeFullSchedule(raw) {
  const leagues = raw?.sports?.[0]?.leagues || raw?.leagues || [];
  const seen = new Set();
  const out = [];
  for (const l of leagues) {
    const id = String(l?.id || '');
    if (!id || seen.has(id)) continue;
    seen.add(id);
    const start =
      iso(l?.calendarStartDate) ||
      iso(l?.season?.startDate) ||
      iso(l?.smartdates?.[0]?.date) ||
      null;
    const end = iso(l?.calendarEndDate) || iso(l?.season?.endDate) || null;
    out.push({
      series_id: id,
      name: l?.name || l?.shortName || '',
      start_date: start,
      end_date: end,
      source: 'espn-cricinfo',
    });
  }
  return out;
}

// --- player / team ---------------------------------------------------------
function styleOf(athlete, type) {
  const st = (athlete?.style || []).find((s) => s.type === type);
  return st?.description || '';
}

/** Normalize a player from ESPN athlete data (as found in rosters). */
export function normalizePlayer(athlete, teamId = '') {
  const a = athlete?.athlete || athlete || {};
  return {
    player_id: String(a.id || ''),
    name: a.displayName || a.name || '',
    full_name: a.fullName || a.displayName || '',
    dob: iso(a.dateOfBirth) || null,
    nationality: a.citizenship || a.birthPlace?.country || '',
    role: athlete?.position?.name || a.position?.name || '',
    batting_style: styleOf(a, 'batting'),
    bowling_style: styleOf(a, 'bowling'),
    image_url: (a.headshot?.href) || '',
    teams: teamId ? [String(teamId)] : [],
    bio: '',
    stats: {},
    last_updated: new Date().toISOString(),
  };
}

// --- match squads (from /summary rosters) -----------------------------------

/**
 * Parse ESPN's `displayDOB` ("21/9/1993" = D/M/YYYY) into an ISO date string.
 * Returns null on any unparseable value.
 */
function parseDisplayDob(dob) {
  const s = String(dob || '').trim();
  const m = /^(\d{1,2})\/(\d{1,2})\/(\d{4})$/.exec(s);
  if (!m) return iso(s);
  const [, d, mo, y] = m;
  const dt = new Date(Date.UTC(Number(y), Number(mo) - 1, Number(d)));
  return Number.isNaN(dt.getTime()) ? null : dt.toISOString();
}

/** Read a style description from an ESPN athlete batStyle/bowlStyle array. */
function athleteStyle(arr) {
  if (!Array.isArray(arr) || !arr.length) return '';
  return arr[0]?.description || arr[0]?.shortDescription || '';
}

/**
 * Normalize a standalone v3 athlete payload (from client.getAthlete) into the
 * SAME internal player shape normalizePlayerFromRoster emits, so a route can't
 * tell whether the player came from the roster cache or a live athlete lookup.
 * Returns null when the payload has no usable athlete.
 */
export function normalizePlayerFromAthlete(raw) {
  const a = raw?.athlete || raw || {};
  if (!a || !a.id) return null;
  return {
    player_id: String(a.id || ''),
    name: a.displayName || a.fullName || a.name || '',
    full_name: a.fullName || a.displayName || '',
    dob: parseDisplayDob(a.displayDOB || a.dateOfBirth),
    nationality: a.team?.name || a.flag?.alt || a.citizenship || '',
    role: a.position?.name || '',
    batting_style: athleteStyle(a.batStyle),
    bowling_style: athleteStyle(a.bowlStyle),
    image_url: a.headshot?.href || '',
    teams: a.team?.id ? [String(a.team.id)] : [],
    bio: '',
    stats: {},
    last_updated: new Date().toISOString(),
  };
}
/**
 * Normalize match squads from /summary rosters. Returns { team1, team2 }
 * with playing_xi + bench arrays. If no roster data is present, returns null
 * so the caller can emit a sentinel.
 */
export function normalizeMatchSquads(raw) {
  const header = raw?.header || {};
  const comp = (header.competitions || [])[0] || {};
  const comps = comp.competitors || [];
  const rosters = raw?.rosters || [];
  if (!comps.length || !rosters.length) return null;

  const normRoster = (r) => {
    const t = r?.team || {};
    const logos = t.logos || [];
    return {
      team_id: String(t.id || ''),
      team_name: t.displayName || t.name || '',
      team_short: t.abbreviation || '',
      team_logo: logos[0]?.href || '',
      players: (r?.roster || []).map((p) => ({
        player_id: String(p.athlete?.id || ''),
        name: p.athlete?.displayName || p.athlete?.name || '',
        role: p.position?.name || p.athlete?.position?.name || '',
        batting_style: styleOf(p.athlete || {}, 'batting'),
        bowling_style: styleOf(p.athlete || {}, 'bowling'),
        image_url: p.athlete?.headshot?.href || '',
        is_captain: false,
        is_wicketkeeper: false,
      })),
    };
  };

  // Match rosters to competitors by team id
  const compMap = new Map(comps.map((c) => [String(c.id || c.team?.id || ''), c]));
  const result = { team1: null, team2: null };

  for (const r of rosters) {
    const tid = String(r.team?.id || '');
    if (!tid) continue;
    const normalized = normRoster(r);
    if (!result.team1) {
      result.team1 = normalized;
    } else if (!result.team2) {
      result.team2 = normalized;
    }
  }

  return result;
}

// --- match news (from /summary news.articles) --------------------------------

/**
 * Normalize match news from /summary news.articles. Returns an array of
 * story objects in the same shape the Cricbuzz news normaliser emits.
 */
export function normalizeMatchNews(raw) {
  const news = raw?.news || {};
  const articles = news?.articles || [];
  if (!Array.isArray(articles) || !articles.length) {
    return [];
  }
  return articles.map((a) => {
    const webLink = a.links?.web?.href || a.links?.web || '';
    const images = a.images || [];
    return {
      id: String(a.id || ''),
      headline: a.headline || '',
      intro: a.description || '',
      body: a.description || a.headline || '',
      context: a.type || '',
      published_time: a.published || '',
      source: a.source || 'ESPNcricinfo',
      story_type: a.type || 'News',
      image_url: images[0]?.url || images[0]?.href || '',
      story_url: typeof webLink === 'string' ? webLink : '',
      last_updated: new Date().toISOString(),
    };
  });
}

// --- series teams (from /scoreboard teams) ----------------------------------

/**
 * Normalize teams list from /scoreboard. Returns an array of team objects.
 */
export function normalizeSeriesTeams(raw, seriesId) {
  const teams = raw?.teams || [];
  if (!Array.isArray(teams) || !teams.length) return [];

  return teams
    .map((t) => {
      const team = t?.team || t || {};
      const logos = team.logos || [];
      return {
        team_id: String(team.id || ''),
        name: team.displayName || team.name || '',
        short_name: team.abbreviation || '',
        logo_url: logos[0]?.href || '',
        country: team.location || '',
        series_id: String(seriesId || ''),
      };
    })
    .filter((t) => t.name && t.name !== '?');
}

// --- match leaders/stats (from /summary leaders) ----------------------------

/**
 * Extract match leaders/top performers from /summary. Returns an object with
 * batting and bowling leader arrays.
 */
export function normalizeMatchLeaders(raw) {
  const leaders = raw?.leaders || [];
  if (!Array.isArray(leaders) || !leaders.length) return null;

  const batting = [];
  const bowling = [];

  for (const leaderGroup of leaders) {
    const categories = leaderGroup?.categories || [];
    for (const cat of categories) {
      const catLeaders = cat?.leaders || [];
      for (const entry of catLeaders) {
        const a = entry?.athlete || {};
        const item = {
          player_id: String(a.id || ''),
          name: a.displayName || a.name || '',
          value: entry?.displayValue || '',
          category: cat?.displayName || '',
          team: a.team?.displayName || a.team?.name || '',
        };
        const displayName = (cat?.displayName || '').toLowerCase();
        if (displayName.includes('bat') || displayName.includes('run')) {
          batting.push(item);
        } else if (
          displayName.includes('bowl') ||
          displayName.includes('wicket') ||
          displayName.includes('economy')
        ) {
          bowling.push(item);
        }
      }
    }
  }

  if (!batting.length && !bowling.length) return null;
  return { batting, bowling };
}

/** Normalize a team + squad from a /summary roster block. */
export function normalizeTeam(rosterBlock, teamId = '') {
  const t = rosterBlock?.team || {};
  return {
    team_id: String(t.id || teamId || ''),
    name: t.displayName || t.name || '',
    short_name: t.abbreviation || '',
    logo_url: (t.logos || [])[0]?.href || '',
    country: t.location || '',
    players: (rosterBlock?.roster || []).map((p) => ({
      player_id: String(p.athlete?.id || ''),
      name: p.athlete?.displayName || p.athlete?.name || '',
      role: p.position?.name || '',
    })),
    last_updated: new Date().toISOString(),
  };
}

/**
 * Group a scoreboard/header payload into the internal schedule shape
 * {days:[{date, series:[{seriesId, seriesName, matches:[...]}]}]}, bucketed by
 * the calendar day of each event's start time.
 */
export function normalizeSchedule(raw) {
  const leagues = raw?.sports?.[0]?.leagues || raw?.leagues || [];
  const byDay = new Map();
  for (const league of leagues) {
    const sId = String(league?.id || '');
    const sName = league?.name || league?.shortName || '';
    for (const ev of league?.events || []) {
      const m = normalizeEvent(ev, sId, sName);
      const day = m.start_time ? m.start_time.slice(0, 10) : 'unknown';
      if (!byDay.has(day)) byDay.set(day, new Map());
      const seriesMap = byDay.get(day);
      if (!seriesMap.has(sId)) {
        seriesMap.set(sId, { seriesId: sId, seriesName: sName, matches: [] });
      }
      seriesMap.get(sId).matches.push(m);
    }
  }
  const days = [...byDay.entries()]
    .sort((a, b) => a[0].localeCompare(b[0]))
    .map(([date, seriesMap]) => ({ date, series: [...seriesMap.values()] }));
  return { days };
}

// --- playbyplay-derived -------------------------------------------------------

/**
 * Build over-by-over summary from playbyplay items. Groups balls by over number,
 * computes runs, wickets, and innings details per over.
 */
export function normalizeOverByOver(raw, matchId) {
  const items = raw?.commentary?.items || raw?.items || [];
  if (!items.length) return null;

  const overMap = new Map();
  const inningsMap = new Map();

  for (const item of items) {
    const ov = item?.over || {};
    const overNum = num(ov?.number, null);
    const period = num(item?.period || ov?.period, 0);
    if (overNum == null) continue;

    const key = `${period}:${overNum}`;
    if (!overMap.has(key)) {
      overMap.set(key, { over_number: overNum, innings: period, balls: [], runs: 0, wickets: 0 });
      if (!inningsMap.has(period)) inningsMap.set(period, []);
    }
    const entry = overMap.get(key);
    const playType = item?.playType?.description || 'ball';
    const runs = num(item?.scoreValue ?? ov?.runs, 0);
    const isWkt = !!(item?.dismissal?.dismissal);

    entry.balls.push({
      ball_number: num(ov?.ball, 0),
      runs,
      event: playType,
      is_wicket: isWkt,
      is_boundary: runs === 4 || runs === 6 || playType === 'four' || playType === 'six',
      batsman: item?.batsman?.athlete?.displayName || '',
      bowler: item?.bowler?.athlete?.displayName || '',
      text: item?.shortText || item?.text || '',
    });
    entry.runs += runs;
    if (isWkt) entry.wickets++;
  }

  const innings = [];
  for (const [period, overs] of inningsMap) {
    const overList = overs
      .sort((a, b) => a - b)
      .map((on) => overMap.get(`${period}:${on}`))
      .filter(Boolean);
    innings.push({ innings_number: Number(period), overs: overList });
  }

  return {
    match_id: String(matchId || ''),
    innings,
    last_updated: new Date().toISOString(),
  };
}

/**
 * Build balls-map from playbyplay items. Returns a structured map of all balls
 * indexed by innings and over with ball-level detail suitable for wagon wheel /
 * pitch map rendering. Returns null when no structured ball data is present.
 */
export function normalizeBallsMap(raw, matchId, targetInningsId) {
  const items = raw?.commentary?.items || raw?.items || [];
  if (!items.length) return null;

  const byInnings = new Map();

  for (const item of items) {
    const period = num(item?.period || item?.over?.period, 0);
    const ov = item?.over || {};
    const overNum = num(ov?.number, null);
    const ballNum = num(ov?.ball, null);
    if (overNum == null || ballNum == null) continue;

    if (!byInnings.has(period)) byInnings.set(period, []);
    const entry = {
      innings_number: period,
      over: overNum,
      ball: ballNum,
      runs: num(item?.scoreValue ?? ov?.runs, 0),
      event: item?.playType?.description || 'ball',
      is_wicket: !!(item?.dismissal?.dismissal),
      is_boundary: false,
      batsman: item?.batsman?.athlete?.displayName || '',
      batsman_id: String(item?.batsman?.athlete?.id || ''),
      bowler: item?.bowler?.athlete?.displayName || '',
      bowler_id: String(item?.bowler?.athlete?.id || ''),
      text: item?.shortText || item?.text || '',
    };
    // Mark boundaries
    const pt = item?.playType?.description || '';
    if (pt === 'four' || pt === 'six' || entry.runs === 4 || entry.runs === 6) {
      entry.is_boundary = true;
    }
    byInnings.get(period).push(entry);
  }

  const innings = [];
  for (const [period, balls] of byInnings) {
    balls.sort((a, b) => a.over - b.over || a.ball - b.ball);
    innings.push({ innings_number: period, balls });
  }

  if (targetInningsId != null) {
    const target = innings.find((inn) => inn.innings_number === num(targetInningsId));
    if (!target) return null;
    return {
      match_id: String(matchId || ''),
      innings_number: target.innings_number,
      balls: target.balls,
      last_updated: new Date().toISOString(),
    };
  }

  return {
    match_id: String(matchId || ''),
    innings,
    last_updated: new Date().toISOString(),
  };
}

/**
 * Build match overs data from playbyplay items. Groups by innings and over,
 * returns per-over runs + wickets + ball count suitable for Manhattan chart.
 */
export function normalizeMatchOvers(raw) {
  const items = raw?.commentary?.items || raw?.items || [];
  if (!items.length) return null;

  const inningsMap = new Map();

  for (const item of items) {
    const period = num(item?.period || item?.over?.period, 0);
    const ov = item?.over || {};
    const overNum = num(ov?.number, null);
    if (overNum == null) continue;

    if (!inningsMap.has(period)) inningsMap.set(period, []);
    const overs = inningsMap.get(period);
    let overEntry = overs.find((o) => o.over_number === overNum);
    if (!overEntry) {
      overEntry = { over_number: overNum, runs: 0, wickets: 0, ball_count: 0, boundaries: 0, dots: 0 };
      overs.push(overEntry);
    }

    const runs = num(item?.scoreValue ?? ov?.runs, 0);
    const isWkt = !!(item?.dismissal?.dismissal);

    overEntry.ball_count++;
    overEntry.runs += runs;
    if (isWkt) overEntry.wickets++;
    if (runs === 4 || runs === 6) overEntry.boundaries++;
    if (runs === 0 && !isWkt) overEntry.dots++;
  }

  const innings = [];
  for (const [period, overs] of inningsMap) {
    overs.sort((a, b) => a.over_number - b.over_number);
    innings.push({ innings_number: Number(period), overs });
  }
  innings.sort((a, b) => a.innings_number - b.innings_number);

  return {
    innings,
    last_updated: new Date().toISOString(),
  };
}

/**
 * Build live-line data from playbyplay items. Extracts the latest ball,
 * current innings/over/batting context, and recent over summary.
 */
export function normalizeLiveLine(raw, matchId) {
  const items = raw?.commentary?.items || raw?.items || [];
  if (!items.length) return null;

  // Get the latest item
  const latest = items[0]; // items are reverse-chronological
  const ov = latest?.over || {};

  // Build recent-over summary (last 6 balls from latest over)
  const currentOver = ov?.number != null ? num(ov.number) : null;
  const currentPeriod = num(latest?.period || ov?.period, 0);
  const recentBalls = [];
  if (currentOver != null) {
    for (const item of items) {
      const iov = item?.over || {};
      if (num(iov?.number, null) === currentOver && num(item?.period || iov?.period, 0) === currentPeriod) {
        recentBalls.unshift({
          ball: num(iov?.ball, 0),
          runs: num(item?.scoreValue ?? iov?.runs, 0),
          event: item?.playType?.description || 'ball',
        });
      }
    }
  }

  return {
    match_id: String(matchId || ''),
    current_innings: currentPeriod,
    current_over: currentOver,
    current_ball: num(ov?.ball, 0),
    latest_ball: {
      ball: num(ov?.ball, 0),
      over: currentOver,
      runs: num(latest?.scoreValue ?? ov?.runs, 0),
      wickets: num(ov?.wickets, 0),
      runs_in_over: num(ov?.runs, 0),
      event: latest?.playType?.description || 'ball',
      is_wicket: !!(latest?.dismissal?.dismissal),
      is_boundary: false,
      batsman: latest?.batsman?.athlete?.displayName || '',
      batsman_id: String(latest?.batsman?.athlete?.id || ''),
      bowler: latest?.bowler?.athlete?.displayName || '',
      bowler_id: String(latest?.bowler?.athlete?.id || ''),
      text: latest?.shortText || latest?.text || '',
    },
    recent_over: recentBalls.slice(-6),
    last_updated: new Date().toISOString(),
  };
}

// --- team / player from roster cache ----------------------------------------

/**
 * Extract a team record from a /summary roster block. Use when the ESPN team id
 * is known (from event/match context — not from a Cricbuzz-origin team id).
 * Returns null when the roster has no team data.
 */
export function normalizeTeamFromRoster(rosterBlock) {
  if (!rosterBlock) return null;
  const t = rosterBlock?.team;
  if (!t?.displayName) return null;
  const logos = t.logos || [];
  return {
    team_id: String(t.id || ''),
    name: t.displayName || t.name || '',
    short_name: t.abbreviation || '',
    logo_url: logos[0]?.href || '',
    country: t.location || '',
    players: (rosterBlock?.roster || []).map((p) => ({
      player_id: String(p.athlete?.id || ''),
      name: p.athlete?.displayName || p.athlete?.name || '',
      role: p.position?.name || '',
    })),
    last_updated: new Date().toISOString(),
  };
}

/**
 * Extract a player record from /summary roster data. Only works for ESPN player
 * IDs that appear in recently-fetched match rosters. Returns null if not found
 * or if the roster block doesn't contain this player.
 */
export function normalizePlayerFromRoster(rosterBlock, playerId) {
  if (!rosterBlock) return null;
  const pid = String(playerId || '').trim();
  if (!pid) return null;

  for (const p of rosterBlock?.roster || []) {
    if (String(p.athlete?.id || '') === pid) {
      const a = p.athlete || {};
      return {
        player_id: String(a.id || ''),
        name: a.displayName || a.name || '',
        full_name: a.fullName || a.displayName || '',
        dob: iso(a.dateOfBirth) || null,
        nationality: a.citizenship || '',
        role: p.position?.name || a.position?.name || '',
        batting_style: styleOf(a, 'batting'),
        bowling_style: styleOf(a, 'bowling'),
        image_url: a.headshot?.href || '',
        teams: rosterBlock?.team?.id ? [String(rosterBlock.team.id)] : [],
        bio: '',
        stats: {},
        last_updated: new Date().toISOString(),
      };
    }
  }
  return null;
}
