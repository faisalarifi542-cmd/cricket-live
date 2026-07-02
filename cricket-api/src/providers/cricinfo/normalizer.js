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
  return {
    match_id: String(ev?.id || ev?.competitionId || ''),
    series_id: String(seriesId || ''),
    series_name: seriesName || '',
    match_format: mapFormat(ev?.class?.eventType || ev?.eventType),
    match_type: ev?.class?.generalClassCard || ev?.class?.name || '',
    match_desc: ev?.title || ev?.name || '',
    status: mapState(status, statusText),
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

  return {
    match_id: String(header.id || comp.id || ''),
    series_id: String(league.id || ''),
    series_name: league.name || header.league?.name || '',
    match_format: mapFormat(comp?.class?.eventType || comp?.class?.name),
    match_type: comp?.class?.generalClassCard || comp?.class?.name || '',
    match_desc: header.title || header.name || '',
    status: mapState(status, statusText),
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
