/**
 * Normalizes raw Cricbuzz API responses into internal schema.
 * NEVER expose raw Cricbuzz data to clients.
 */

import { getCricbuzzImageUrl, getTeamLogoUrl, getMatchImageUrl } from '../../lib/image-helper.js';

/**
 * Normalize the /api/home response into categorized match lists.
 * @param {object} raw - Response from /api/home
 * @param {string} filterType - 'live', 'upcoming', or 'recent'
 */
export function normalizeHomeMatchList(raw, filterType = 'live') {
  if (!raw || !raw.matches) return [];

  const matches = [];
  for (const wrapper of raw.matches) {
    const m = wrapper.match;
    if (!m || !m.matchInfo) continue;
    const info = m.matchInfo;
    const score = m.matchScore;

    const state = normalizeHomeState(info.state);
    if (filterType === 'live' && state !== 'live' && state !== 'innings_break') continue;
    if (filterType === 'upcoming' && state !== 'upcoming') continue;
    if (filterType === 'recent' && state !== 'completed' && state !== 'abandoned' && state !== 'no_result') continue;

    matches.push(normalizeHomeMatchSummary(info, score));
  }
  return matches;
}

function normalizeHomeMatchSummary(info, score) {
  return {
    match_id: String(info.matchId || ''),
    series_id: String(info.seriesId || ''),
    series_name: info.seriesName || '',
    match_format: normalizeFormat(info.matchFormat),
    match_type: info.matchType || '',
    match_desc: info.matchDesc || '',
    status: normalizeHomeState(info.state),
    status_text: info.status || info.stateTitle || '',
    short_status: info.shortStatus || '',
    team1: normalizeTeamShort(info.team1),
    team2: normalizeTeamShort(info.team2),
    venue: buildVenue(info.venueInfo),
    start_time: info.startDate ? new Date(parseInt(info.startDate)).toISOString() : null,
    end_time: info.endDate ? new Date(parseInt(info.endDate)).toISOString() : null,
    current_innings: 0,
    curr_bat_team_id: info.currBatTeamId ? String(info.currBatTeamId) : null,
    match_image_url: getMatchImageUrl(info.matchImageId),
    is_forecast_enabled: info.isForecastEnabled || false,
    score: normalizeHomeScore(score, info.team1, info.team2),
    last_updated: new Date().toISOString(),
  };
}

function normalizeHomeState(state) {
  if (!state) return 'upcoming';
  const s = state.toLowerCase();
  if (s === 'complete') return 'completed';
  if (s === 'preview' || s === 'upcoming') return 'upcoming';
  if (s === 'abandon' || s === 'abandoned') return 'abandoned';
  if (s === 'no result') return 'no_result';
  // Stumps, In Progress, Innings Break, Drinks, Rain, etc. → live
  return 'live';
}

function normalizeHomeScore(score, team1Info, team2Info) {
  if (!score) return {};
  return {
    team1: extractHomeInnings(score.team1Score),
    team2: extractHomeInnings(score.team2Score),
  };
}

function extractHomeInnings(teamScore) {
  if (!teamScore) return [];
  const innings = [];
  for (const key of Object.keys(teamScore).sort()) {
    if (key.startsWith('inngs')) {
      const inn = teamScore[key];
      innings.push({
        runs: inn.runs || 0,
        wickets: inn.wickets || 0,
        overs: inn.overs || 0,
      });
    }
  }
  return innings;
}

export function normalizeMatchList(raw, type = 'live') {
  if (!raw) return [];

  // Cricbuzz wraps matches in typeMatches → matchList arrays
  const typeMatches = raw.typeMatches || raw.matches || [];
  const matches = [];

  for (const group of Array.isArray(typeMatches) ? typeMatches : [typeMatches]) {
    const matchList = group.seriesMatches || group.matchList || group.matches || [];
    for (const seriesGroup of Array.isArray(matchList) ? matchList : [matchList]) {
      const seriesData = seriesGroup.seriesAdWrapper || seriesGroup;
      const items = seriesData.matches || seriesData.matchList || [];
      for (const item of Array.isArray(items) ? items : [items]) {
        const m = item.matchInfo || item;
        if (m && m.matchId) {
          matches.push(normalizeMatchSummary(m, seriesData));
        }
      }
    }
  }

  return matches;
}

export function normalizeMatchSummary(m, seriesData = {}) {
  const seriesInfo = seriesData.seriesInfo || seriesData.series || {};
  // Preserve the ORIGINAL source series ID from Cricbuzz — never overwrite
  const originalSeriesId = String(m.seriesId || seriesInfo.seriesId || '');
  const originalSeriesName = m.seriesName || seriesInfo.seriesName || '';

  return {
    match_id: String(m.matchId),
    series_id: originalSeriesId,
    series_name: originalSeriesName,
    source_series_id: originalSeriesId,
    source_series_name: originalSeriesName,
    match_format: normalizeFormat(m.matchFormat),
    match_type: m.matchType || '',
    match_desc: m.matchDesc || '',
    status: normalizeStatus(m.state || m.status),
    status_text: m.status || m.stateTitle || '',
    short_status: m.shortStatus || '',
    team1: normalizeTeamShort(m.team1),
    team2: normalizeTeamShort(m.team2),
    venue: buildVenue(m.venueInfo || m),
    start_time: m.startDate ? new Date(parseInt(m.startDate)).toISOString() : null,
    end_time: m.endDate ? new Date(parseInt(m.endDate)).toISOString() : null,
    current_innings: m.currInnings || 0,
    curr_bat_team_id: m.currBatTeamId ? String(m.currBatTeamId) : null,
    match_image_url: getMatchImageUrl(m.matchImageId),
    score: normalizeQuickScore(m),
    last_updated: new Date().toISOString(),
  };
}

export function normalizeMatchDetail(raw) {
  if (!raw) return null;

  // mcenter livescore has miniscore (live data) and optionally matchHeader
  const header = raw.matchHeader || {};
  const mini = raw.miniscore || {};
  const score = mini.matchScoreDetails || raw.matchScoreDetails || {};
  const matchTeamInfo = score.matchTeamInfo || [];
  const tossResults = score.tossResults || header.tossResults || {};

  // Get matchId from multiple locations
  const matchId = header.matchId || score.matchId || raw.matchId || '';

  // Extract team info: prefer matchHeader, fallback to matchTeamInfo
  let team1Raw = header.team1;
  let team2Raw = header.team2;

  if (matchTeamInfo.length >= 1 && (!team1Raw?.teamId && !team1Raw?.id)) {
    const info = matchTeamInfo[0];
    team1Raw = { teamId: info.battingTeamId, teamSName: info.battingTeamShortName, teamName: info.battingTeamShortName };
    team2Raw = { teamId: info.bowlingTeamId, teamSName: info.bowlingTeamShortName, teamName: info.bowlingTeamShortName };
  }

  // Build team scores from inningsScoreList
  const t1Id = team1Raw?.teamId || team1Raw?.id;
  const t2Id = team2Raw?.teamId || team2Raw?.id;
  const inningsList = score.inningsScoreList || [];

  const team1ScoreData = { inngs: [] };
  const team2ScoreData = { inngs: [] };
  for (const inn of inningsList) {
    const entry = { runs: inn.score, wickets: inn.wickets, overs: inn.overs, isDeclared: inn.isDeclared, isFollowOn: inn.isFollowOn };
    if (inn.batTeamId === t1Id) {
      team1ScoreData.inngs.push(entry);
    } else {
      team2ScoreData.inngs.push(entry);
    }
  }

  // Extract current batsmen and bowler from miniscore
  const batsmanStriker = mini.batsmanStriker;
  const batsmanNonStriker = mini.batsmanNonStriker;
  const bowlerStriker = mini.bowlerStriker;

  // --- Robust live-state derivation -------------------------------------
  // Cricbuzz `state` for an in-progress match can be "Rain delay",
  // "Bad light stopped play", "Tea", "Drinks", "Stumps Day 1", "Innings
  // Break", etc. The plain string mapper falls back to "upcoming" for those,
  // which silently breaks live polling + the Live tab. If we actually have
  // live miniscore data (batters/bowler on the field or overs already
  // bowled) and the match is not finished, treat it as live.
  let derivedStatus = normalizeStatus(score.state || header.state || score.customStatus);
  const resultType = header.result?.resultType || header.result || '';
  const looksComplete = derivedStatus === 'completed'
    || derivedStatus === 'abandoned'
    || derivedStatus === 'no_result'
    || Boolean(resultType);
  const hasLiveMiniscore = Boolean(batsmanStriker || bowlerStriker)
    || inningsList.some((inn) => parseFloat(inn.overs || 0) > 0);
  if (!looksComplete && hasLiveMiniscore
      && (derivedStatus === 'upcoming' || derivedStatus === 'innings_break')) {
    derivedStatus = 'live';
  }

  return {
    match_id: String(matchId),
    series_id: String(header.seriesId || score.seriesId || ''),
    series_name: header.seriesName || header.seriesDesc || '',
    match_desc: header.matchDescription || '',
    match_format: normalizeFormat(header.matchFormat || score.matchFormat),
    match_type: header.matchType || '',
    match_number: header.matchNumber || '',
    status: derivedStatus,
    status_text: score.customStatus || mini.status || header.status || header.stateTitle || '',
    team1: normalizeTeamFull(team1Raw, team1ScoreData.inngs.length > 0 ? team1ScoreData : null),
    team2: normalizeTeamFull(team2Raw, team2ScoreData.inngs.length > 0 ? team2ScoreData : null),
    venue: buildVenue(header.venueInfo || header.venue),
    start_time: (header.startDate || header.matchStartTimestamp) ? new Date(parseInt(header.startDate || header.matchStartTimestamp)).toISOString() : null,
    end_time: (header.endDate || header.matchCompleteTimestamp) ? new Date(parseInt(header.endDate || header.matchCompleteTimestamp)).toISOString() : null,
    toss: {
      winner: tossResults.tossWinnerName || '',
      decision: tossResults.decision || '',
    },
    result: header.result?.resultType || header.result || '',
    man_of_match: header.playersOfTheMatch?.[0]?.name || '',
    current_innings: mini.inningsId || header.currInnings || 0,
    day_number: header.dayNumber || null,
    session: header.session || null,
    innings: normalizeInningsList(score),
    // Live miniscore data
    current_batsmen: batsmanStriker ? [
      normalizeLiveBatsman(batsmanStriker, true),
      ...(batsmanNonStriker ? [normalizeLiveBatsman(batsmanNonStriker, false)] : []),
    ] : [],
    current_bowler: bowlerStriker ? normalizeLiveBowler(bowlerStriker) : null,
    current_run_rate: mini.currentRunRate || 0,
    required_run_rate: mini.requiredRunRate || 0,
    partnership: mini.partnerShip ? { runs: mini.partnerShip.runs || 0, balls: mini.partnerShip.balls || 0 } : null,
    last_wicket: mini.lastWicket || '',
    recent_overs: mini.recentOvsStats || '',
    target: mini.target || null,
    rem_runs_to_win: mini.remRunsToWin ?? null,
    latest_performance: normalizeLatestPerformance(mini.latestPerformance),
    powerplay_data: normalizePowerplayData(mini.ppData),
    over_summary_list: mini.overSummaryList || [],
    match_udrs: mini.matchUdrs || null,
    player_of_match: normalizePlayerOfMatch(header.playersOfTheMatch),
    match_image_url: getMatchImageUrl(header.matchImageId || score.matchImageId),
    // Merged Live Center object — a single, clean payload the app's Live tab
    // can consume directly without stitching multiple endpoints together.
    live_center: buildLiveCenter({
      status: derivedStatus,
      statusText: score.customStatus || mini.status || header.status || header.stateTitle || '',
      mini,
      inningsList,
      batsmanStriker,
      batsmanNonStriker,
      bowlerStriker,
      playerOfMatch: normalizePlayerOfMatch(header.playersOfTheMatch),
      result: resultType,
    }),
    last_updated: new Date().toISOString(),
  };
}

/**
 * Builds the merged "Live Center" object from the miniscore. Each section is
 * included only when it carries real data, so the app never renders empty or
 * fake rows. Recent balls are parsed from `recentOvsStats`.
 */
function buildLiveCenter({
  status,
  statusText,
  mini,
  inningsList,
  batsmanStriker,
  batsmanNonStriker,
  bowlerStriker,
  playerOfMatch,
  result,
}) {
  const isFinished = status === 'completed'
    || status === 'abandoned'
    || status === 'no_result';

  // Current batters — only real, named batters (drop empty placeholders).
  const currentBatters = [];
  if (batsmanStriker && (batsmanStriker.batName || batsmanStriker.batId)) {
    currentBatters.push(normalizeLiveBatsman(batsmanStriker, true));
  }
  if (batsmanNonStriker && (batsmanNonStriker.batName || batsmanNonStriker.batId)) {
    currentBatters.push(normalizeLiveBatsman(batsmanNonStriker, false));
  }

  // Current bowler — only when it has a real name (never "Player 0 0 0 0").
  const currentBowler = bowlerStriker && (bowlerStriker.bowlName || bowlerStriker.bowlId)
    ? normalizeLiveBowler(bowlerStriker)
    : null;

  // Partnership.
  const partnership = mini.partnerShip && (mini.partnerShip.runs || mini.partnerShip.balls)
    ? {
        runs: mini.partnerShip.runs || 0,
        balls: mini.partnerShip.balls || 0,
        overs: oversFromBalls(mini.partnerShip.balls || 0),
      }
    : null;

  // Last wicket — keep the raw Cricbuzz string; the app parses it.
  const lastWicket = mini.lastWicket || '';

  // Recent balls parsed from recentOvsStats ("1 4 0 W 2 | 6 1 .").
  const recentBalls = parseRecentBalls(mini.recentOvsStats || '');

  // Latest score line from the current innings.
  const currentInn = inningsList.length
    ? inningsList[inningsList.length - 1]
    : null;
  const score = currentInn
    ? `${currentInn.score || 0}/${currentInn.wickets || 0}`
    : '';
  const overs = currentInn ? String(currentInn.overs || '') : '';

  return {
    match_state: isFinished ? 'finished' : (status === 'upcoming' ? 'upcoming' : 'live'),
    status,
    status_text: statusText,
    score,
    overs,
    current_run_rate: mini.currentRunRate || 0,
    required_run_rate: mini.requiredRunRate || 0,
    target: mini.target || null,
    current_batters: currentBatters,
    current_bowler: currentBowler,
    partnership,
    last_wicket: lastWicket,
    recent_balls: recentBalls,
    player_of_match: isFinished ? playerOfMatch : null,
    result: result || '',
    updated_at: new Date().toISOString(),
  };
}

function oversFromBalls(balls) {
  const n = parseInt(balls, 10);
  if (!n || n <= 0) return '';
  return `${Math.floor(n / 6)}.${n % 6}`;
}

/**
 * Parses Cricbuzz `recentOvsStats` into normalized ball pills. The string uses
 * spaces between balls and `|` between overs, e.g. "1 4 0 W 2 | 6 1 .".
 * Returns the most recent balls first (max 6).
 */
function parseRecentBalls(recentStr) {
  if (!recentStr || typeof recentStr !== 'string') return [];
  const tokens = recentStr.split(/\s+/).filter((t) => t && t !== '|');
  const balls = tokens.map((raw) => {
    const value = String(raw).trim();
    const upper = value.toUpperCase();
    let type = 'run';
    if (upper.includes('W')) type = 'wicket';
    else if (value === '4') type = 'four';
    else if (value === '6') type = 'six';
    else if (value === '0' || value === '.') type = 'dot';
    else if (upper.includes('NB') || upper.includes('WD')) type = 'extra';
    return { value: value === '.' ? '0' : value, type };
  });
  // Most recent last in Cricbuzz; take the final 6 for "recent over".
  return balls.slice(-6);
}

function normalizeLatestPerformance(perf) {
  if (!perf || !Array.isArray(perf)) return [];
  return perf.map((p) => ({
    runs: p.runs || 0,
    wickets: p.wkts || 0,
    label: p.label || '',
  }));
}

function normalizePowerplayData(ppData) {
  if (!ppData || typeof ppData !== 'object') return [];
  return Object.values(ppData).map((pp) => ({
    id: pp.ppId || 0,
    overs_from: pp.ppOversFrom || 0,
    overs_to: pp.ppOversTo || 0,
    type: pp.ppType || '',
    runs_scored: pp.runsScored || 0,
  }));
}

function normalizePlayerOfMatch(players) {
  if (!players || !Array.isArray(players) || players.length === 0) return null;
  const p = players[0];
  const imageId = p.faceImageId || p.imageId || null;
  return {
    id: String(p.id || p.playerId || ''),
    name: p.name || p.fullName || '',
    image_id: imageId ? String(imageId) : null,
    image_url: getCricbuzzImageUrl(imageId, 'i2'),
  };
}

function normalizeLiveBatsman(b, isStriker) {
  return {
    player_id: String(b.batId || ''),
    name: b.batName || '',
    runs: b.batRuns ?? 0,
    balls: b.batBalls ?? 0,
    fours: b.batFours ?? 0,
    sixes: b.batSixes ?? 0,
    strike_rate: b.batStrikeRate ?? 0,
    is_batting: true,
    is_striker: isStriker,
  };
}

function normalizeLiveBowler(b) {
  return {
    player_id: String(b.bowlId || ''),
    name: b.bowlName || '',
    overs: b.bowlOvs ?? 0,
    maidens: b.bowlMaidens ?? 0,
    runs: b.bowlRuns ?? 0,
    wickets: b.bowlWkts ?? 0,
    economy: b.bowlEcon ?? 0,
    wides: b.bowlWides ?? 0,
    no_balls: b.bowlNoballs ?? 0,
    is_bowling: true,
  };
}

export function normalizeScorecard(raw) {
  if (!raw) return null;

  const innings = raw.scoreCard || raw.innings || [];
  return {
    innings: innings.map((inn, idx) => ({
      innings_number: idx + 1,
      batting_team: inn.batTeamDetails?.batTeamName || inn.batTeamName || '',
      batting_team_id: String(inn.batTeamDetails?.batTeamId || ''),
      total: {
        runs: inn.scoreDetails?.runs || inn.score || 0,
        wickets: inn.scoreDetails?.wickets || inn.wickets || 0,
        overs: inn.scoreDetails?.overs || inn.overs || 0,
      },
      run_rate: inn.scoreDetails?.runRate || inn.runRate || 0,
      extras: normalizeExtras(inn.extrasData || inn.extras),
      batting: normalizeBattingCard(inn.batTeamDetails?.batsmenData || inn.batsmen || {}),
      bowling: normalizeBowlingCard(inn.bowlTeamDetails?.bowlersData || inn.bowlers || {}),
      fall_of_wickets: normalizeFOW(inn.wicketsData || inn.fallOfWickets || {}),
      partnerships: normalizePartnerships(inn.partnershipsData || {}),
    })),
    last_updated: new Date().toISOString(),
  };
}

export function normalizeCommentary(raw) {
  if (!raw) return [];

  // mcenter /comm endpoint returns matchCommentary as object keyed by timestamp
  // mcenter /livescore endpoint returns commentaryList as array
  let comms = raw.commentaryList || raw.commentary || raw.comms || null;

  // matchCommentary is an object keyed by timestamp — convert to array
  if ((!comms || (Array.isArray(comms) && comms.length === 0)) && raw.matchCommentary) {
    comms = Object.values(raw.matchCommentary);
  }

  if (!Array.isArray(comms)) comms = [];

  return comms
    .filter((c) => c.commText || c.commentary)
    .map((c) => {
      // event can be string or array e.g. ["FOUR","all"] or "FOUR"
      const eventArr = Array.isArray(c.event) ? c.event : [c.event || ''];
      const eventStr = eventArr.join(' ').toUpperCase();
      const isFour = eventStr.includes('FOUR') || c.runs === 4;
      const isSix = eventStr.includes('SIX') || c.runs === 6;
      const isWicket = !!(c.wicketData || c.isWicket || eventStr.includes('WICKET'));

      // Extract batsman/bowler from multiple sources
      let batsman = c.batsmanDetails?.playerName || c.batStrikerName || '';
      let bowler = c.bowlerDetails?.playerName || c.bowlStrikerName || '';
      let commText = c.commText || c.commentary || '';

      // Parse Cricbuzz formatting tokens like B0$, B1$ into their values
      if (c.commentaryFormats?.bold?.formatId && c.commentaryFormats?.bold?.formatValue) {
        const { formatId, formatValue } = c.commentaryFormats.bold;
        for (let fi = 0; fi < formatId.length; fi++) {
          if (formatId[fi] && formatValue[fi]) {
            commText = commText.replace(formatId[fi], formatValue[fi]);
          }
        }
      }

      // Fallback: parse from commText "Bowler to Batsman, ..."
      if ((!batsman || !bowler) && commText.includes(' to ')) {
        const parts = commText.split(',')[0];
        const toBits = parts.split(' to ');
        if (toBits.length >= 2) {
          bowler = bowler || toBits[0].trim();
          batsman = batsman || toBits[1].trim();
        }
      }

      // Parse runs from commText if not in data
      let runs = c.runs ?? 0;
      if (runs === 0 && !isWicket) {
        const runsMatch = commText.match(/(\d+)\s+run/i);
        if (runsMatch) runs = parseInt(runsMatch[1]);
      }
      if (isFour) runs = Math.max(runs, 4);
      if (isSix) runs = Math.max(runs, 6);

      // ballMetric is like 6.2 = over 6, ball 2
      const ballMetric = c.ballMetric ?? c.overNumber ?? c.overs ?? null;
      const overNum = ballMetric != null ? Math.floor(ballMetric) : null;
      const ballNum = ballMetric != null ? Math.round((ballMetric % 1) * 10) : (c.ballNbr ?? c.ballNumber ?? null);

      return {
        id: String(c.timestamp || c.id || Date.now()),
        innings_number: c.inningsId || 0,
        over: overNum ?? ballMetric,
        ball: ballNum,
        event: normalizeCommentaryEvent(c),
        text: commText.replace(/<[^>]*>/g, ''),
        runs,
        is_wicket: isWicket,
        is_four: isFour,
        is_six: isSix,
        is_boundary: isFour || isSix,
        batsman,
        bowler,
        timestamp: c.timestamp || Date.now(),
      };
    })
    .sort((a, b) => b.timestamp - a.timestamp);
}

export function normalizeSeriesList(raw) {
  if (!raw) return [];
  const collections = raw.seriesMapProto || raw.series || [];
  const result = [];

  for (const group of Array.isArray(collections) ? collections : [collections]) {
    const items = group.series || group.seriesList || [];
    for (const s of Array.isArray(items) ? items : [items]) {
      result.push({
        series_id: String(s.seriesId || s.id || ''),
        name: s.seriesName || s.name || '',
        season: s.season || '',
        start_date: s.startDt ? new Date(parseInt(s.startDt)).toISOString() : null,
        end_date: s.endDt ? new Date(parseInt(s.endDt)).toISOString() : null,
      });
    }
  }

  return result;
}

export function normalizePointsTable(raw) {
  if (!raw) {
    return {
      seriesId: '',
      seriesName: '',
      groups: [],
      rows: [],
      source: 'cricbuzz',
      message: 'Points table is not available for this series yet.',
    };
  }

  const tables = Array.isArray(raw.groups)
    ? raw.groups
    : Array.isArray(raw.pointsTable)
      ? raw.pointsTable
      : Array.isArray(raw.standings)
        ? raw.standings
        : Array.isArray(raw)
          ? raw
          : [];

  const normalizeRow = (entry, index, groupName = '') => {
    const teamId = String(
      entry.teamId || entry.team_id || entry.teamID || entry.id || '',
    );
    const imageId = entry.teamImageId || entry.imageId || entry.image_id || null;
    const teamShortName = entry.teamShortName || entry.team_short || entry.teamShort || entry.teamName || '';
    const teamName = entry.teamFullName || entry.teamName || entry.team_name || '';
    const rawForm = entry.form || entry.teamForm || [];
    const form = Array.isArray(rawForm)
      ? rawForm.map((item) => String(item)).filter(Boolean)
      : typeof rawForm === 'string'
        ? rawForm.split(/[,\s]+/).map((item) => item.trim()).filter(Boolean)
        : [];

    return {
      rank: toNumber(entry.position || entry.rank || index + 1, index + 1),
      teamId,
      teamName,
      teamShortName,
      logoUrl: entry.logoUrl || entry.logo_url || (imageId ? getTeamLogoUrl(imageId) : ''),
      imageId: imageId ? String(imageId) : null,
      matches: toNumber(entry.matchesPlayed || entry.matches || entry.played || entry.Mat, 0),
      won: toNumber(entry.matchesWon || entry.won || entry.W || 0, 0),
      lost: toNumber(entry.matchesLost || entry.lost || entry.L || 0, 0),
      tied: toNumber(entry.matchesTied || entry.tied || entry.T || 0, 0),
      noResult: toNumber(entry.noRes || entry.noResult || entry.no_result || entry.NR || 0, 0),
      matchesDrawn: toNumber(entry.matchesDrawn || entry.drawn || entry.D || 0, 0),
      points: toNumber(entry.points || entry.Pts || entry.pointsTotal || 0, 0),
      nrr: String(entry.nrr ?? entry.NRR ?? ''),
      for: entry.for || entry.runsFor || '',
      against: entry.against || entry.runsAgainst || '',
      form,
      qualified: !!(entry.teamQualifyStatus || entry.isQualified || entry.qualified),
      qualificationStatus: entry.teamQualifyStatus || '',
      groupName,
    };
  };

  const groups = [];
  for (const table of tables) {
    if (!table) continue;
    const entries = Array.isArray(table.pointsTableInfo)
      ? table.pointsTableInfo
      : Array.isArray(table.rows)
        ? table.rows
        : Array.isArray(table.teams)
          ? table.teams
          : Array.isArray(table.entries)
            ? table.entries
            : [];

    const rows = entries.map((entry, index) => normalizeRow(entry, index, table.groupName || table.name || 'Points Table'));
    groups.push({
      name: table.groupName || table.name || 'Points Table',
      rows,
    });
  }

  const rows = groups.flatMap((group) => group.rows);

  return {
    seriesId: String(raw.seriesId || ''),
    seriesName: raw.seriesName || '',
    matchType: raw.match_type || raw.matchType || '',
    lastUpdated: raw.lastUpdated || new Date().toISOString(),
    source: raw.source || 'cricbuzz',
    groups,
    rows,
    message: groups.length === 0 ? 'Points table is not available for this series yet.' : null,
  };
}

function toNumber(value, fallback = 0) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

export function normalizeMatchSquads(raw, matchId) {
  if (!raw) return { team1: null, team2: null };

  const cleanPlayerName = (name = '') => String(name)
    .replace(/\((C|c|WK|wk|Wk)(?:\s*&\s*(?:C|c|WK|wk|Wk))?\)/g, '')
    .replace(/\b(WK-?Batter|Batter|Bowler|All-?rounder|Wicketkeeper|WK)\b/gi, '')
    .replace(/\s+/g, ' ')
    .trim();

  const cleanRole = (player) => {
    const rawRole = player.role || '';
    if (rawRole) return rawRole.replace(/^WK\s+Batter$/i, 'WK-Batter').trim();
    const name = String(player.name || '');
    if (/WK-?Batter|Wicketkeeper/i.test(name)) return 'WK-Batter';
    if (/All-?rounder/i.test(name)) return 'All-rounder';
    if (/Bowler/i.test(name)) return 'Bowler';
    if (/Batter|Batsman/i.test(name)) return 'Batter';
    return '';
  };

  const cleanTeamName = (team, fallback) => {
    const name = String(team?.teamName || team?.team_name || fallback || '').trim();
    if (!name || /cricket match squads/i.test(name)) return fallback || '';
    return name.replace(/^.*\|\s*/, '').replace(/,\s*\d+(st|nd|rd|th).*$/i, '').trim();
  };

  const normalizeTeam = (team) => {
    if (!team) return null;

    const teamId = String(team.teamId || team.team_id || '');
    const teamName = cleanTeamName(team, team.teamShort || team.team_short || '');
    const teamShort = team.teamShort || team.team_short || '';

    // Attach a player's face image ONLY by their own identity (playerId /
    // profile link). A missing image stays null so the client renders a
    // neutral initials avatar — never another player's face. Never mapped by
    // list index.
    const normalizePlayer = (player) => {
      const realImage = player.imageUrl || player.image_url || '';
      const profileUrl = player.profileUrl || player.profile_url
        || (player.playerId || player.player_id
          ? `https://www.cricbuzz.com/profiles/${player.playerId || player.player_id}`
          : '');
      return {
        player_id: String(player.playerId || player.player_id || ''),
        name: cleanPlayerName(player.name),
        role: cleanRole(player),
        team_id: teamId,
        team_name: teamName,
        profile_url: profileUrl,
        is_captain: player.isCaptain || player.is_captain || /\((C|c)\)/.test(player.name || ''),
        is_wicketkeeper: player.isWicketkeeper || player.is_wicketkeeper || /\((WK|wk|Wk)\)|WK-?Batter/i.test(player.name || ''),
        is_impact_player: player.isImpactPlayer || false,
        is_substitute: player.isSubstitute || false,
        image_url: realImage || null,
        image_source: realImage ? 'cricbuzz' : 'none',
      };
    };

    const playingXI = (team.playingXi || team.playing_xi || []).map(normalizePlayer);
    const bench = (team.bench || []).map((p) => ({ ...normalizePlayer(p), is_substitute: true }));
    const impactPlayers = [team.impactPlayer || team.impact_player].filter(Boolean).map((p) => ({
      ...normalizePlayer(p),
      is_impact_player: true,
    }));

    const toCamel = (p) => ({
      playerId: p.player_id,
      name: p.name,
      role: p.role,
      teamId: p.team_id,
      teamName: p.team_name,
      profileUrl: p.profile_url,
      imageUrl: p.image_url,
      imageSource: p.image_source,
      isCaptain: p.is_captain,
      isWicketKeeper: p.is_wicketkeeper,
      isImpactPlayer: p.is_impact_player,
      isSubstitute: p.is_substitute,
    });

    return {
      team_name: teamName,
      team_short: teamShort,
      playing_xi: playingXI,
      bench,
      impact_player: impactPlayers[0] || null,
      substitutes: bench,
      teamId,
      teamName,
      teamShort,
      logoUrl: team.logoUrl || team.logo_url || '',
      playingXI: playingXI.map(toCamel),
      impactPlayers: impactPlayers.map(toCamel),
    };
  };

  const team1 = normalizeTeam(raw.team1);
  const team2 = normalizeTeam(raw.team2);

  return {
    match_id: String(matchId),
    team1,
    team2,
    matchId: String(matchId),
    teams: [team1, team2].filter(Boolean),
    updated_at: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
    page_title: raw.page_title || '',
    _players_found: raw._players_found || 0,
    _teams_found: raw._teams_found || 0,
    _parse_error: raw._parse_error || null,
  };
}

export function normalizePlayerInfo(raw) {
  if (!raw) return null;
  const p = raw.player || raw;
  const battingStats = Array.isArray(p.battingStats) ? p.battingStats : [];
  const bowlingStats = Array.isArray(p.bowlingStats) ? p.bowlingStats : [];
  const careerSummary = Array.isArray(p.careerSummary) ? p.careerSummary : [];
  const recentForm = Array.isArray(p.recentForm) ? p.recentForm : Array.isArray(p.recent) ? p.recent : [];
  const achievements = Array.isArray(p.achievements) ? p.achievements : [];
  const teams = Array.isArray(p.teams) ? p.teams : [];

  return {
    player_id: String(p.id || p.playerId || ''),
    name: p.name || p.fullName || p.longName || '',
    full_name: p.fullName || p.longName || p.name || '',
    country: p.country || p.nationality || '',
    country_code: p.countryCode || p.country_code || '',
    dob: p.dateOfBirth || p.DoB || p.dob || null,
    birth_place: p.birthPlace || p.birth_place || '',
    nationality: p.nationality || p.country || '',
    role: p.role || p.playingRole || '',
    batting_style: p.battingStyle || p.bat || '',
    bowling_style: p.bowlingStyle || p.bowl || '',
    jersey_number: p.jerseyNumber || p.jersey_number || '',
    image_id: p.imageId || p.image_id || '',
    image_url: p.imageUrl || p.image || '',
    rankings: p.rankings || raw.rankings || null,
    teams,
    bio: p.bio || '',
    career_summary: careerSummary,
    batting_stats: battingStats,
    bowling_stats: bowlingStats,
    recent_form: recentForm,
    achievements,
    stats: normalizePlayerStats(raw.stats || p.stats || raw.career || p.career || {}),
    career: raw.career || p.career || {},
    last_updated: new Date().toISOString(),
  };
}

// --- Helpers ---

function normalizeFormat(fmt) {
  if (!fmt) return 'unknown';
  const f = String(fmt).toLowerCase();
  if (f.includes('test')) return 'test';
  if (f.includes('odi') || f.includes('one')) return 'odi';
  if (f.includes('t20') || f.includes('twenty')) return 't20';
  if (f.includes('t10')) return 't10';
  return f;
}

function normalizeStatus(state) {
  if (!state) return 'upcoming';
  const s = String(state).toLowerCase();
  if (s.includes('live') || s.includes('progress') || s === 'in progress') return 'live';
  if (s.includes('innings') || s.includes('break')) return 'innings_break';
  if (s.includes('complete') || s.includes('result') || s.includes('won') || s.includes('drawn')) return 'completed';
  if (s.includes('abandon')) return 'abandoned';
  if (s.includes('no result') || s.includes('no_result')) return 'no_result';
  if (s.includes('toss') || s.includes('preview') || s.includes('upcoming')) return 'upcoming';
  return 'upcoming';
}

function normalizeTeamShort(team) {
  if (!team) return { id: '', name: '', short_name: '', image_id: null, logo_url: null };
  const imageId = team.imageId || team.image_id || null;
  return {
    id: String(team.teamId || team.id || ''),
    name: team.teamName || team.name || '',
    short_name: team.teamSName || team.shortName || '',
    image_id: imageId ? String(imageId) : null,
    logo_url: getTeamLogoUrl(imageId),
  };
}

function normalizeTeamFull(team, scoreData) {
  const base = normalizeTeamShort(team);
  const innings = [];

  if (scoreData) {
    const innsArr = scoreData.inngs || (scoreData.runs !== undefined ? [scoreData] : []);
    for (const inn of Array.isArray(innsArr) ? innsArr : [innsArr]) {
      innings.push({
        runs: inn.runs || inn.score || 0,
        wickets: inn.wickets || 0,
        overs: inn.overs || 0,
        declared: inn.isDeclared || false,
        follow_on: inn.isFollowOn || false,
      });
    }
  }

  return { ...base, innings };
}

function normalizeQuickScore(m) {
  const score = {};
  if (m.team1Score) {
    score.team1 = extractInningsScore(m.team1Score);
  }
  if (m.team2Score) {
    score.team2 = extractInningsScore(m.team2Score);
  }
  return score;
}

function extractInningsScore(teamScore) {
  if (!teamScore) return [];
  const inngs = teamScore.inngs || (teamScore.runs !== undefined ? [teamScore] : []);
  return (Array.isArray(inngs) ? inngs : [inngs]).map((i) => ({
    runs: i.runs || i.score || 0,
    wickets: i.wickets || 0,
    overs: i.overs || 0,
  }));
}

function normalizeInningsList(score) {
  if (!score) return [];
  const list = score.inningsScoreList || [];
  return list.map((inn, idx) => ({
    innings_number: idx + 1,
    batting_team_id: String(inn.batTeamId || ''),
    batting_team: inn.batTeamName || '',
    runs: inn.score || inn.runs || 0,
    wickets: inn.wickets || 0,
    overs: inn.overs || 0,
    run_rate: inn.runRate || 0,
    target: inn.target || null,
    required_rate: inn.requiredRunRate || null,
    declared: inn.isDeclared || false,
    follow_on: inn.isFollowOn || false,
  }));
}

function buildVenue(info) {
  if (!info) return { name: '', city: '', country: '' };
  return {
    name: info.ground || info.name || info.venueName || '',
    city: info.city || '',
    country: info.country || '',
  };
}

/**
 * Find innings data for a team from mcenter's inningsScoreList.
 */
function findTeamInnings(score, team) {
  if (!score?.inningsScoreList || !team) return null;
  const teamId = team.id || team.teamId;
  if (!teamId) return null;
  const innings = score.inningsScoreList.filter((i) => i.batTeamId === teamId);
  if (innings.length === 0) return null;
  return { inngs: innings.map((i) => ({ runs: i.score, wickets: i.wickets, overs: i.overs, isDeclared: i.isDeclared, isFollowOn: i.isFollowOn })) };
}

function normalizeExtras(extras) {
  if (!extras) return { total: 0, byes: 0, leg_byes: 0, wides: 0, no_balls: 0, penalty: 0 };
  return {
    total: extras.total || extras.t || 0,
    byes: extras.byes || extras.b || 0,
    leg_byes: extras.legByes || extras.lb || 0,
    wides: extras.wides || extras.w || 0,
    no_balls: extras.noBalls || extras.nb || 0,
    penalty: extras.penalty || extras.p || 0,
  };
}

function normalizeBattingCard(batsmenData) {
  if (!batsmenData) return [];
  const batsmen = Object.values(batsmenData);
  return batsmen
    .filter((b) => b.batName || b.name)
    .map((b) => ({
      player_id: String(b.batId || b.playerId || ''),
      name: b.batName || b.name || '',
      runs: b.runs ?? 0,
      balls: b.balls ?? 0,
      fours: b.fours ?? 0,
      sixes: b.sixes ?? 0,
      strike_rate: b.strikeRate ?? 0,
      dismissal: b.outDesc || b.dismissal || (b.wicketCode === '' ? 'not out' : ''),
      is_batting: b.isBatting || false,
      is_striker: b.isStriker || false,
      position: b.position || 0,
    }));
}

function normalizeBowlingCard(bowlersData) {
  if (!bowlersData) return [];
  const bowlers = Object.values(bowlersData);
  return bowlers
    .filter((b) => b.bowlName || b.name)
    .map((b) => ({
      player_id: String(b.bowlId || b.playerId || ''),
      name: b.bowlName || b.name || '',
      overs: b.overs ?? 0,
      maidens: b.maidens ?? 0,
      runs: b.runs ?? 0,
      wickets: b.wickets ?? 0,
      economy: b.economy ?? 0,
      dots: b.dots ?? 0,
      wides: b.wides ?? 0,
      no_balls: b.noBalls ?? 0,
      is_bowling: b.isBowling || false,
    }));
}

function normalizeFOW(fowData) {
  if (!fowData) return [];
  const entries = Object.values(fowData);
  return entries.map((f) => ({
    wicket_number: f.wktNbr || 0,
    runs: f.wktRuns || 0,
    overs: f.wktOver || 0,
    player: f.batName || '',
  }));
}

function normalizePartnerships(data) {
  if (!data) return [];
  const entries = Object.values(data);
  return entries.map((p) => ({
    runs: p.totalRuns || 0,
    balls: p.totalBalls || 0,
    bat1: { name: p.bat1Name || '', runs: p.bat1Runs || 0 },
    bat2: { name: p.bat2Name || '', runs: p.bat2Runs || 0 },
  }));
}

function normalizeCommentaryEvent(c) {
  if (c.wicketData || c.isWicket) return 'wicket';
  // event can be array like ["FOUR","all"] or string
  const evts = Array.isArray(c.event) ? c.event.map(e => String(e).toUpperCase()) : [String(c.event || '').toUpperCase()];
  if (evts.includes('WICKET')) return 'wicket';
  if (evts.includes('SIX') || c.runs === 6) return 'six';
  if (evts.includes('FOUR') || c.runs === 4) return 'four';
  if (c.overSeparator || c.overSep) return 'over_end';
  if (evts.includes('WIDE')) return 'wide';
  if (evts.includes('NO-BALL') || evts.includes('NOBALL')) return 'noball';
  if (c.eventType) return String(c.eventType).toLowerCase();
  return 'ball';
}

function normalizePlayerStats(stats) {
  if (!stats || typeof stats !== 'object') return {};
  const result = {};

  for (const [format, data] of Object.entries(stats)) {
    if (!data || typeof data !== 'object') continue;
    result[format] = {
      batting: {
        matches: data.matchesPlayed || data.batting?.matches || 0,
        innings: data.battingInnings || data.batting?.innings || 0,
        runs: data.battingRuns || data.batting?.runs || 0,
        highest: data.highestScore || data.batting?.highest || '',
        average: data.battingAverage || data.batting?.average || 0,
        strike_rate: data.battingStrikeRate || data.batting?.strikeRate || 0,
        centuries: data.centuries || data.batting?.hundreds || 0,
        fifties: data.fifties || data.batting?.fifties || 0,
        fours: data.batting?.fours || 0,
        sixes: data.batting?.sixes || 0,
        not_outs: data.notOuts || data.batting?.notOuts || 0,
      },
      bowling: {
        matches: data.matchesPlayed || data.bowling?.matches || 0,
        innings: data.bowlingInnings || data.bowling?.innings || 0,
        wickets: data.bowlingWickets || data.bowling?.wickets || 0,
        best: data.bestBowling || data.bowling?.best || '',
        average: data.bowlingAverage || data.bowling?.average || 0,
        economy: data.bowlingEconomy || data.bowling?.economy || 0,
        strike_rate: data.bowlingStrikeRate || data.bowling?.strikeRate || 0,
        five_wickets: data.fiveWickets || data.bowling?.fiveWickets || 0,
      },
    };
  }

  return result;
}

/**
 * Build match stats from livescore data.
 * Used by GET /match/:id/stats
 */
export function normalizeMatchStats(raw) {
  if (!raw) return null;

  const mini = raw.miniscore || {};
  const score = mini.matchScoreDetails || raw.matchScoreDetails || {};
  const inningsList = score.inningsScoreList || [];

  // Build per-team summary — inningsScoreList[0] is typically the latest innings
  const team1Inn = inningsList.find((i) => i.inningsId === 1) || null;
  const team2Inn = inningsList.find((i) => i.inningsId === 2) || null;

  const summary = {
    team1_runs: team1Inn?.score ?? null,
    team1_wickets: team1Inn?.wickets ?? null,
    team1_overs: team1Inn?.overs ?? null,
    team2_runs: team2Inn?.score ?? null,
    team2_wickets: team2Inn?.wickets ?? null,
    team2_overs: team2Inn?.overs ?? null,
    current_run_rate: mini.currentRunRate || 0,
    required_run_rate: mini.requiredRunRate || 0,
    target: mini.target || null,
    last_wicket: mini.lastWicket || '',
    rem_runs_to_win: mini.remRunsToWin ?? null,
  };

  return {
    summary,
    powerplay: normalizePowerplayData(mini.ppData),
    latest_performance: normalizeLatestPerformance(mini.latestPerformance),
    boundaries: {
      team1_fours: null,
      team1_sixes: null,
      team2_fours: null,
      team2_sixes: null,
    },
    top_batters: [],
    top_bowlers: [],
    recent_overs: mini.recentOvsStats || '',
    innings: normalizeInningsList(score),
  };
}

/**
 * Build overs data from livescore data.
 * Used by GET /match/:id/overs — never return 404.
 */
// --- News normalizers ---

function makeNewsSlug(value = '') {
  return String(value || '')
    .toLowerCase()
    .replace(/&amp;/g, 'and')
    .replace(/&/g, 'and')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 120);
}

export function normalizeNewsStories(raw) {
  if (!raw || !raw.paginatedData) return { stories: [], nextCursor: null, nextPaginationURL: null };

  const stories = raw.paginatedData
    .filter((s) => s.id && s.headline)
    .map((s) => {
      const imageId = s.imageDetails?.imageId || null;
      const storyUrl =
        s.appIndex?.webURL ||
        s.webURL ||
        s.url ||
        s.storyUrl ||
        (s.id && s.headline ? `/cricket-news/${s.id}/${makeNewsSlug(s.headline)}` : '');
      return {
        id: String(s.id),
        context: s.context || '',
        headline: s.headline || '',
        intro: s.intro || '',
        publishedTime: s.publishedTime || '',
        storyType: s.storyType || '',
        isPremium: !!(s.isCbPlusContent && !s.isPremiumFree),
        imageId: imageId ? String(imageId) : null,
        imageUrl: getCricbuzzImageUrl(imageId, 'i3'),
        storyUrl,
        isNewsPage: s.isNewsPage || false,
      };
    });

  // Extract next cursor from nextPaginationURL e.g. "/api/cricket-news/138837/all-stories"
  let nextCursor = null;
  const nextUrl = raw.nextPaginationURL || null;
  if (nextUrl) {
    const match = nextUrl.match(/\/cricket-news\/(\d+)\//);
    if (match) nextCursor = match[1];
  }

  return { stories, nextCursor, nextPaginationURL: nextUrl };
}

export function normalizeNewsDetail(raw, fallbackStory = null) {
  if (!raw && !fallbackStory) return null;
  const detail = raw || {};
  const fallback = fallbackStory || {};
  const paragraphs = [];
  const paragraphInput = Array.isArray(detail.paragraphs) ? detail.paragraphs : [];
  for (const paragraph of paragraphInput) {
    const clean = String(paragraph || '').trim();
    if (clean) paragraphs.push(clean);
  }
  const body = paragraphs.length
    ? paragraphs.join('\n\n')
    : String(detail.body || detail.content || fallback.body || '').trim();
  const imageId = detail.imageId || detail.image_id || fallback.imageId || fallback.image_id || null;
  const imageUrl = detail.imageUrl || detail.image_url || fallback.imageUrl || fallback.image_url || getCricbuzzImageUrl(imageId, 'i3');
  const relatedStories = Array.isArray(detail.relatedStories)
    ? detail.relatedStories.map((story) => {
        const relatedImageId = story.imageId || story.image_id || null;
        return {
          id: String(story.id || ''),
          headline: story.headline || story.hline || '',
          intro: story.intro || '',
          context: story.context || '',
          publishedTime: story.publishedTime || story.pubTime || '',
          imageId: relatedImageId ? String(relatedImageId) : null,
          imageUrl: story.imageUrl || story.image_url || getCricbuzzImageUrl(relatedImageId, 'i3'),
        };
      })
    : [];

  return {
    id: String(detail.id || fallback.id || ''),
    headline: detail.headline || fallback.headline || '',
    intro: detail.intro || fallback.intro || '',
    body: body || null,
    paragraphs,
    source: detail.source || fallback.source || 'Cricbuzz',
    context: detail.context || fallback.context || '',
    publishedTime: detail.publishedTime || fallback.publishedTime || '',
    storyType: detail.storyType || fallback.storyType || 'News',
    imageId: imageId ? String(imageId) : null,
    imageUrl,
    storyUrl: detail.storyUrl || fallback.storyUrl || '',
    relatedStories,
  };
}

// --- Series stats normalizers ---

export function normalizeSeriesStatsTypes(raw) {
  if (!raw || !raw.types) return { types: [], appIndex: null };

  const types = raw.types
    .filter((t) => t.value) // skip header-only entries (no value)
    .map((t) => ({
      value: t.value,
      header: t.header || '',
      category: t.category || '',
    }));

  return { types, appIndex: raw.appIndex || null };
}

export function normalizeSeriesStatsTable(raw, statType) {
  if (!raw) return { header: statType, category: '', players: [], headers: [], filters: null };

  // Find the stats list — key varies by format (t20StatsList, odiStatsList, testStatsList)
  const statsKey = Object.keys(raw).find((k) => k.endsWith('StatsList') || k.toLowerCase().includes('statslist'));
  const statsList = statsKey ? raw[statsKey] : null;

  if (!statsList || !statsList.values) {
    return { header: statType, category: '', players: [], headers: [], filters: null };
  }

  const headers = statsList.headers || [];
  const teamMap = {};
  if (raw.filter?.team) {
    for (const t of raw.filter.team) {
      teamMap[String(t.id)] = t.teamShortName || '';
    }
  }

  const players = statsList.values.map((row) => {
    const vals = row.values || [];
    // First value is always playerId, second is playerName
    const playerId = vals[0] || '';
    const playerName = vals[1] || '';

    // Map remaining values to headers (headers[0] = "PLAYER", so data starts at vals[2] for headers[1])
    const stats = {};
    for (let i = 1; i < headers.length; i++) {
      const key = headers[i];
      const val = vals[i + 1]; // +1 because vals[0] = playerId (not in headers)
      stats[key] = val !== undefined ? val : null;
    }

    return {
      playerId: String(playerId),
      playerName,
      imageUrl: '',
      ...stats,
    };
  });

  return {
    header: statType,
    category: '',
    players,
    headers,
    filters: raw.filter || null,
  };
}

// --- Series News normalizer ---

export function normalizeSeriesNews(raw) {
  if (!raw || !raw.storyList) return { stories: [], nextCursor: null };

  const stories = raw.storyList
    .filter((item) => item.story && item.story.id)
    .map((item) => {
      const s = item.story;
      const imageId = s.coverImage?.id || s.imageId || null;
      return {
        id: String(s.id),
        headline: s.hline || '',
        intro: s.intro || '',
        publishedTime: s.pubTime || '',
        source: s.source || '',
        storyType: s.storyType || '',
        context: s.context || '',
        imageId: imageId ? String(imageId) : null,
        imageUrl: getCricbuzzImageUrl(imageId, 'i1'),
        coverCaption: s.coverImage?.caption || '',
        coverSource: s.coverImage?.source || '',
        seoHeadline: s.seoHeadline || '',
      };
    });

  // Infer nextCursor from last story ID
  let nextCursor = null;
  if (stories.length > 0) {
    const lastId = parseInt(stories[stories.length - 1].id, 10);
    if (!isNaN(lastId)) nextCursor = String(lastId);
  }

  return { stories, nextCursor };
}

// --- Match News normalizer ---

export function normalizeMatchNews(raw) {
  if (!raw || !raw.paginatedData) return { stories: [], nextCursor: null, nextPaginationURL: null };

  const stories = raw.paginatedData
    .filter((s) => s.id && s.headline)
    .map((s) => {
      const imageId = s.imageDetails?.imageId || null;
      return {
        id: String(s.id),
        headline: s.headline || '',
        intro: s.intro || '',
        publishedTime: s.publishedTime || '',
        storyType: s.storyType || '',
        context: s.context || '',
        imageId: imageId ? String(imageId) : null,
        imageUrl: getCricbuzzImageUrl(imageId, 'i1'),
        isPremium: !!(s.isCbPlusContent && !s.isPremiumFree),
        isNewsPage: s.isNewsPage || false,
      };
    });

  let nextCursor = null;
  const nextUrl = raw.nextPaginationURL || null;
  if (nextUrl) {
    const match = nextUrl.match(/\/(\d+)$/);
    if (match) nextCursor = match[1];
  }

  return { stories, nextCursor, nextPaginationURL: nextUrl };
}

// --- Full Commentary normalizer ---

function replaceFormatTokens(text, formats) {
  if (!text || !formats) return text || '';
  let result = text;
  const bold = formats.bold;
  if (bold && bold.formatId && bold.formatValue) {
    for (let i = 0; i < bold.formatId.length; i++) {
      const token = bold.formatId[i];
      const value = bold.formatValue[i] || '';
      result = result.replace(token, value);
    }
  }
  return result;
}

export function normalizeFullCommentary(raw, requestedInningsId) {
  if (!raw || !raw.commentary || !raw.commentary.length) {
    return { matchId: raw?.matchId || null, inningsId: requestedInningsId, commentary: [] };
  }

  const inningsData = raw.commentary[0];
  const inningsId = inningsData.inningsId || requestedInningsId;
  const list = inningsData.commentaryList || [];

  const commentary = list.map((entry) => {
    const isWicket = (entry.event || '').includes('WICKET');
    const isFour = entry.event === 'FOUR';
    const isSix = entry.event === 'SIX';
    const isOverBreak = (entry.event || '').includes('over-break');

    const bat = entry.batsmanStriker || {};
    const bowl = entry.bowlerStriker || {};
    const overSep = entry.overSeparator || null;

    return {
      inningsId: entry.inningsId || inningsId,
      overNumber: entry.overNumber || 0,
      ballNumber: entry.ballNbr || 0,
      event: entry.event || 'NONE',
      text: replaceFormatTokens(entry.commText, entry.commentaryFormats),
      rawText: entry.commText || '',
      timestamp: entry.timestamp || 0,
      batTeamName: entry.batTeamName || '',
      batsman: bat.batId ? {
        id: String(bat.batId),
        name: bat.batName || '',
        runs: bat.batRuns || 0,
        balls: bat.batBalls || 0,
        fours: bat.batFours || 0,
        sixes: bat.batSixes || 0,
        strikeRate: bat.batStrikeRate || 0,
      } : null,
      bowler: bowl.bowlId ? {
        id: String(bowl.bowlId),
        name: bowl.bowlName || '',
        overs: bowl.bowlOvs || 0,
        runs: bowl.bowlRuns || 0,
        wickets: bowl.bowlWkts || 0,
        economy: bowl.bowlEcon || 0,
      } : null,
      runs: {
        legal: entry.legalRuns || 0,
        total: entry.totalRuns || 0,
      },
      score: overSep ? {
        runs: overSep.score || 0,
        wickets: overSep.wickets || 0,
      } : { runs: entry.batTeamScore || 0, wickets: 0 },
      isWicket,
      isFour,
      isSix,
      isOverBreak,
      overSummary: overSep?.o_summary?.trim() || null,
    };
  });

  return { matchId: raw.matchId || null, inningsId, commentary };
}

// --- Match Highlights normalizer ---

export function normalizeHighlights(raw, matchId, inningsId) {
  if (!raw || !raw.commentaryList || !raw.commentaryList.length) {
    return { highlights: [] };
  }

  const highlights = raw.commentaryList.map((entry) => {
    const isWicket = (entry.event || '').includes('WICKET');
    const isFour = entry.event === 'FOUR';
    const isSix = entry.event === 'SIX';
    const bat = entry.batsmanStriker || {};
    const bowl = entry.bowlerStriker || {};

    return {
      overNumber: entry.overNumber || 0,
      ballNumber: entry.ballNbr || 0,
      event: entry.event || 'NONE',
      type: isWicket ? 'wicket' : isSix ? 'six' : isFour ? 'four' : 'other',
      text: replaceFormatTokens(entry.commText, entry.commentaryFormats),
      timestamp: entry.timestamp || 0,
      batTeamName: entry.batTeamName || '',
      batsman: bat.batName || '',
      batsmanId: bat.batId ? String(bat.batId) : null,
      bowler: bowl.bowlName || '',
      bowlerId: bowl.bowlId ? String(bowl.bowlId) : null,
      isWicket,
      isFour,
      isSix,
      score: entry.overSeparator ? {
        runs: entry.overSeparator.score || 0,
        wickets: entry.overSeparator.wickets || 0,
      } : null,
    };
  });

  return { highlights };
}

// --- Combined, app-ready commentary feed ---------------------------------
//
// Takes the per-innings results of `normalizeFullCommentary` and produces a
// single, de-duplicated, newest-first feed where every item is explicitly
// classified. The Flutter app trusts these fields directly and never guesses
// event types from text.
//
// Item shape:
//   { id, innings, over, team, teamShort, score, type, label, title, text,
//     isBall, isWicket, isBoundary, runs, timestamp }

function _abbrevTeam(name = '') {
  const n = String(name || '').trim();
  if (!n) return '';
  // Use an existing short code if the name already looks like one.
  if (/^[A-Z]{2,4}$/.test(n)) return n;
  const words = n.split(/\s+/).filter(Boolean);
  if (words.length === 1) return words[0].slice(0, 3).toUpperCase();
  return words.map((w) => w[0]).join('').slice(0, 3).toUpperCase();
}

function _formatOver(overNumber) {
  const n = Number(overNumber);
  if (!Number.isFinite(n) || n <= 0) return null;
  return Number.isInteger(n) ? String(n) : n.toFixed(1);
}

function _noteLabel(text = '') {
  const t = String(text || '').toLowerCase();
  if (/innings break|end of innings/.test(t)) return 'INNINGS BREAK';
  if (/\bdrinks\b/.test(t)) return 'DRINKS';
  if (/man of the (match|series)|player of the (match|series)|\bpotm\b|\bpom\b/.test(t)) {
    return 'PRESENTATION';
  }
  if (/presentation|trophy|won the|lifts the|collects the|won by/.test(t)) return 'PRESENTATION';
  if (/rain|delay|\btea\b|lunch|stumps|strategic|review|\bdrs\b/.test(t)) return 'UPDATE';
  if (/comes to the crease|into the attack|back into the attack|on strike|open the attack/.test(t)) {
    return 'INFO';
  }
  return 'COMMENTARY';
}

// Event flags that are NOT the delivery outcome (they decorate a ball).
const _NON_OUTCOME_FLAGS = new Set([
  'OVER-BREAK', 'HIGHSCORING_OVER', 'MAIDEN_OVER', 'NONE', '',
  'FIFTY', 'HUNDRED', 'TEAM_FIFTY', 'TEAM_HUNDRED', 'TEAM_FIFTY_RUNS',
  'TEAM_HUNDRED_RUNS', 'TEAM_TWO_HUNDRED', 'PARTNERSHIP',
]);

function _eventFlags(event) {
  return String(event || '')
    .toUpperCase()
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean);
}

/// True for notes that are genuine "key events" (innings break, drinks, rain,
/// presentation, result …) — but NOT routine "X comes to the crease" lines.
function _noteIsKeyEvent(text = '') {
  const t = String(text || '').toLowerCase();
  return /innings break|end of innings|drinks|rain|delay|\btea\b|lunch|stumps|strategic|presentation|trophy|won the|player of the (match|series)|man of the (match|series)|\bpotm\b|review|\bdrs\b|won by|match tied|no result/.test(t);
}

/**
 * Classifies a normalized full-commentary entry into an app feed item.
 * Real deliveries are detected by a positive ball number (notes are ballNbr 0).
 * The `over-break` flag merely marks the last ball of an over; such entries are
 * still real deliveries and must be classified by their true outcome.
 */
function classifyCommentaryItem(entry, inningsId, teamName, scoreLine) {
  const flags = _eventFlags(entry.event);
  const text = String(entry.text || entry.rawText || '').replace(/<[^>]*>/g, '').trim();
  const ballNbr = entry.ballNumber || 0;
  const over = _formatOver(entry.overNumber);
  const isBall = ballNbr > 0 && over !== null;

  if (!isBall) {
    return {
      innings: inningsId,
      over: null,
      team: null,
      teamShort: null,
      score: null,
      type: 'note',
      label: _noteLabel(text),
      title: null,
      text,
      isBall: false,
      isWicket: false,
      isBoundary: false,
      isKeyEvent: _noteIsKeyEvent(text),
      runs: null,
      ballNbr,
      timestamp: entry.timestamp || 0,
    };
  }

  const team = teamName || entry.batTeamName || '';
  const teamShort = _abbrevTeam(team);
  const totalRuns = Number((entry.runs && entry.runs.total) ?? 0);

  const isWicket = !!entry.isWicket || flags.includes('WICKET');
  const isSix = !!entry.isSix || flags.includes('SIX');
  const isFour = !!entry.isFour || flags.includes('FOUR');
  const hasMilestone = flags.some((f) =>
    f === 'FIFTY' || f === 'HUNDRED' || f.startsWith('TEAM_'));

  let type;
  let label;
  if (isWicket) {
    type = 'wicket';
    label = 'WICKET';
  } else if (isSix) {
    type = 'six';
    label = 'SIX';
  } else if (isFour) {
    type = 'four';
    label = 'FOUR';
  } else if (totalRuns === 0) {
    type = 'dot';
    label = 'DOT BALL';
  } else {
    type = 'run';
    label = `${totalRuns} RUN${totalRuns === 1 ? '' : 'S'}`;
  }

  return {
    innings: inningsId,
    over,
    team,
    teamShort,
    score: scoreLine || null,
    type,
    label,
    title: null,
    text,
    isBall: true,
    isWicket,
    isBoundary: isFour || isSix,
    isKeyEvent: isWicket || isFour || isSix || hasMilestone,
    runs: totalRuns,
    ballNbr,
    timestamp: entry.timestamp || 0,
  };
}

/// Detects the redundant "THATS OUT!!" echo fragment that Cricbuzz emits with
/// ballNbr 0 right after the real wicket delivery — we drop it to avoid dupes.
function _isWicketEcho(entry) {
  if ((entry.ballNumber || 0) !== 0) return false;
  const t = String(entry.text || entry.rawText || '').toUpperCase();
  return t.includes('THATS OUT') || t.includes("THAT'S OUT");
}

/**
 * Builds the combined commentary feed from per-innings normalized commentary.
 * @param {string} matchId
 * @param {Array<{inningsId:number, teamName?:string, commentary:Array}>} inningsList
 *        Each `commentary` is the array returned by `normalizeFullCommentary`
 *        (newest-first).
 */
export function buildCommentaryFeed(matchId, inningsList = []) {
  const innings = [];
  const flat = [];
  const seen = new Set();

  // Highest innings first so the newest content (incl. post-match notes which
  // sit at the top of the latest innings) leads the feed.
  const ordered = [...inningsList]
    .filter((inn) => inn && Array.isArray(inn.commentary) && inn.commentary.length)
    .sort((a, b) => Number(b.inningsId || 0) - Number(a.inningsId || 0));

  for (const inn of ordered) {
    const inningsId = Number(inn.inningsId || 0);
    const list = inn.commentary; // newest-first
    const teamName = inn.teamName || (list[0] && list[0].batTeamName) || '';

    // Forward pass (oldest-first) to compute the cumulative wicket count so we
    // can show an accurate "runs/wkts" score on every delivery.
    const scoreByIndex = new Array(list.length).fill(null);
    let wkts = 0;
    for (let i = list.length - 1; i >= 0; i--) {
      const e = list[i];
      const isBall = (e.ballNumber || 0) > 0;
      if (!isBall) continue;
      if (_eventFlags(e.event).includes('WICKET') || e.isWicket) wkts += 1;
      scoreByIndex[i] = `${e.batTeamScore || 0}/${wkts}`;
    }

    const items = [];
    for (let i = 0; i < list.length; i++) {
      const entry = list[i];
      if (_isWicketEcho(entry)) continue; // drop redundant "THATS OUT!!" echo

      const item = classifyCommentaryItem(entry, inningsId, teamName, scoreByIndex[i]);
      const text = item.text || '';
      if (!item.isBall && !text) continue; // skip empty notes

      // Stable dedupe key. Balls include the timestamp so a no-ball + the
      // re-bowled delivery (same ballNbr) are both kept, while exact resends
      // collapse. Notes dedupe on normalized text.
      const key = item.isBall
        ? `b:${inningsId}:${item.ballNbr}:${item.timestamp}`
        : `n:${inningsId}:${text.toLowerCase().replace(/\s+/g, ' ').slice(0, 80)}`;

      if (seen.has(key)) {
        const existing = flat.find((x) => x._key === key);
        if (existing && text.length > (existing.text || '').length) existing.text = text;
        continue;
      }
      seen.add(key);

      const id = item.isBall
        ? `${matchId}-${inningsId}-${item.over}-${item.ballNbr}-${item.timestamp}`
        : `${matchId}-${inningsId}-note-${flat.length}`;
      const enriched = { id, _key: key, ...item };
      items.push(enriched);
      flat.push(enriched);
    }

    innings.push({ inningsNumber: inningsId, teamName, team: _abbrevTeam(teamName), items });
  }

  const clean = flat.map(({ _key, ...rest }) => rest);
  for (const inn of innings) {
    inn.items = inn.items.map(({ _key, ...rest }) => rest);
  }

  return { matchId: matchId || null, innings, items: clean };
}

// --- Ball-by-ball Map normalizer ---

export function normalizeBallsMap(raw, matchId, inningsId) {
  if (!raw || !raw.balls) {
    return { balls: [], batters: [], bowlers: [], scoreDetails: null, summary: { dots: 0, ones: 0, twos: 0, threes: 0, fours: 0, sixes: 0, wickets: 0 } };
  }

  const balls = (raw.balls || []).map((b) => ({
    timestamp: b.timestamp || 0,
    ballNumber: b.ballNbr || 0,
    overNumber: b.overNum || 0,
    inningsId: b.inningsId || inningsId,
    event: b.event || 'NONE',
    totalRuns: b.totalRuns || 0,
    batsmanId: b.batsmanStrikerId ? String(b.batsmanStrikerId) : null,
    bowlerId: b.bowlerStrikerId ? String(b.bowlerStrikerId) : null,
    ballLabel: b.ballLabel || '',
  }));

  const batters = (raw.batters || []).map((b) => ({
    id: String(b.batId || ''),
    name: b.batName || '',
    runs: b.runs || 0,
    balls: b.balls || 0,
    dots: b.dots || 0,
    fours: b.fours || 0,
    sixes: b.sixes || 0,
    strikeRate: b.strikeRate || 0,
  }));

  const bowlers = (raw.bowlers || []).map((b) => ({
    id: String(b.bowlerId || ''),
    name: b.bowlName || '',
    overs: b.overs || 0,
    maidens: b.maidens || 0,
    runs: b.runs || 0,
    wickets: b.wickets || 0,
    economy: b.economy || 0,
    noBalls: b.no_balls || 0,
    wides: b.wides || 0,
  }));

  const sd = raw.scoreDetails || {};
  const scoreDetails = {
    ballNumber: sd.ballNbr || 0,
    overs: sd.overs || 0,
    runRate: sd.runRate || 0,
    runs: sd.runs || 0,
    wickets: sd.wickets || 0,
  };

  // Compute summary
  let dots = 0, ones = 0, twos = 0, threes = 0, fours = 0, sixes = 0, wickets = 0;
  for (const b of balls) {
    if (b.event === 'WICKET') wickets++;
    if (b.event === 'FOUR') fours++;
    else if (b.event === 'SIX') sixes++;
    else if (b.totalRuns === 0 && b.event !== 'WICKET') dots++;
    else if (b.totalRuns === 1) ones++;
    else if (b.totalRuns === 2) twos++;
    else if (b.totalRuns === 3) threes++;
  }

  return {
    balls,
    batters,
    bowlers,
    scoreDetails,
    summary: { dots, ones, twos, threes, fours, sixes, wickets },
  };
}

// --- Over-by-over normalizer ---

export function normalizeOverByOver(raw, matchId, inningsId) {
  if (!raw || !raw.paginatedData) return { overs: [], nextTimestamp: null };

  const overs = raw.paginatedData.map((o) => ({
    inningsId: o.inningsId || inningsId,
    overNumber: o.overs || 0,
    summary: (o.ovrSummary || '').trim(),
    runs: o.runs || 0,
    wickets: (o.ovrSummary || '').split('W').length - 1,
    score: `${o.score || 0}/${o.wickets || 0}`,
    totalScore: o.score || 0,
    totalWickets: o.wickets || 0,
    batTeamName: o.batTeamName || '',
    timestamp: o.timestamp || 0,
    bowlerName: o.bowlNames?.[0] || '',
    bowlerId: o.bowlIds?.[0] ? String(o.bowlIds[0]) : null,
    bowlerOvers: o.bowlOvers || 0,
    bowlerRuns: o.bowlRuns || 0,
    bowlerWickets: o.bowlWickets || 0,
    bowlerMaidens: o.bowlMaidens || 0,
    batsmanNames: o.batStrikerNames || [],
    event: o.event || '',
  }));

  let nextTimestamp = null;
  const nextUrl = raw.nextPaginationURL || '';
  if (nextUrl) {
    const match = nextUrl.match(/\/(\d+)$/);
    if (match) nextTimestamp = match[1];
  }

  return { overs, nextTimestamp };
}

// --- Upcoming Schedule normalizer ---

export function normalizeUpcomingSchedule(raw, type) {
  if (!raw) return { days: [] };

  const days = [];
  const keys = Object.keys(raw).sort((a, b) => Number(a) - Number(b));

  for (const key of keys) {
    const wrapper = raw[key]?.scheduleAdWrapper;
    if (!wrapper) continue;

    const dateStr = wrapper.date || '';
    const seriesList = (wrapper.matchScheduleList || []).map((sched) => {
      const matches = (sched.matchInfo || []).map((m) => ({
        matchId: String(m.matchId || ''),
        seriesId: String(m.seriesId || ''),
        matchDesc: (m.matchDesc || '').trim(),
        matchFormat: m.matchFormat || '',
        startTime: m.startDate || '',
        endTime: m.endDate || '',
        venue: m.venueInfo ? {
          name: m.venueInfo.ground || '',
          city: m.venueInfo.city || '',
          country: m.venueInfo.country || '',
          timezone: m.venueInfo.timezone || '',
        } : null,
        team1: m.team1 ? {
          id: String(m.team1.teamId || ''),
          name: m.team1.teamName || '',
          shortName: m.team1.teamSName || '',
          imageId: m.team1.imageId ? String(m.team1.imageId) : null,
          logoUrl: getCricbuzzImageUrl(m.team1.imageId, 'i2'),
        } : null,
        team2: m.team2 ? {
          id: String(m.team2.teamId || ''),
          name: m.team2.teamName || '',
          shortName: m.team2.teamSName || '',
          imageId: m.team2.imageId ? String(m.team2.imageId) : null,
          logoUrl: getCricbuzzImageUrl(m.team2.imageId, 'i2'),
        } : null,
      }));

      return {
        seriesId: String(sched.seriesId || ''),
        seriesName: sched.seriesName || '',
        category: sched.seriesCategory || '',
        matches,
      };
    });

    days.push({ date: dateStr, series: seriesList });
  }

  return { days };
}

export function normalizeMatchOvers(raw) {
  if (!raw) {
    return {
      recent_overs: [],
      over_summary_list: [],
      latest_performance: [],
      powerplays: [],
      innings: [],
    };
  }

  const mini = raw.miniscore || {};
  const score = mini.matchScoreDetails || raw.matchScoreDetails || {};

  // Parse recentOvsStats — it's a string like "6" or "1 4 0 W 2 | 6 1 2"
  let recentOvers = [];
  const recentStr = mini.recentOvsStats || '';
  if (recentStr) {
    recentOvers = recentStr.split(/\s+/).filter((s) => s && s !== '|');
  }

  return {
    recent_overs: recentOvers,
    over_summary_list: mini.overSummaryList || [],
    latest_performance: normalizeLatestPerformance(mini.latestPerformance),
    powerplays: normalizePowerplayData(mini.ppData),
    innings: normalizeInningsList(score),
  };
}

export function normalizeMatchInfoDetailed(raw, matchId) {
  if (!raw) {
    return {
      matchId: String(matchId),
      series: { id: '', name: '' },
      date: { start: null, end: null },
      venue: '',
      city: '',
      toss: null,
      result: null,
      playerOfMatch: [],
      officials: { umpires: [], tvUmpire: null, matchReferee: null },
      venueDetails: { name: '', city: '', country: '', established: null, capacity: null, ends: null, floodlights: null },
      weather: { temperature: null, condition: null, humidity: null, windSpeed: null, windDirection: null },
      pitchReport: { type: null, description: null, avgFirstInningsScore: null, chaseSuccess: null },
      keyMoments: [],
      updatedAt: new Date().toISOString(),
    };
  }
  
  const header = raw.matchHeader || {};
  const venue = header.venue || header.venueInfo || {};
  const officials = raw.officials || {};
  const toss = header.tossResults || raw.tossResults || null;
  const playersOfMatch = header.playersOfTheMatch || raw.playersOfTheMatch || [];
  
  return {
    match_id: String(matchId),
    matchId: String(matchId),
    match_title: header.matchDescription || '',
    series: {
      id: String(header.seriesId || ''),
      name: header.seriesName || '',
    },
    date: {
      start: header.matchStartTimestamp ? new Date(header.matchStartTimestamp).toISOString() : null,
      end: header.matchCompleteTimestamp ? new Date(header.matchCompleteTimestamp).toISOString() : null,
    },
    toss,
    result: header.result || null,
    player_of_match: playersOfMatch.map(p => ({
      id: String(p.id || ''),
      name: p.name || '',
      team: p.teamName || '',
    })) || [],
    playerOfMatch: playersOfMatch.map(p => ({
      id: String(p.id || ''),
      name: p.name || '',
      team: p.teamName || '',
    })) || [],
    officials: {
      umpires: officials.umpires || [],
      tv_umpire: officials.tvUmpire || null,
      match_referee: officials.matchReferee || null,
      tvUmpire: officials.tvUmpire || null,
      matchReferee: officials.matchReferee || null,
    },
    venue: venue.name || venue.ground || '',
    city: venue.city || '',
    venueDetails: {
      name: venue.name || venue.ground || '',
      city: venue.city || '',
      country: venue.country || '',
      established: venue.established || null,
      capacity: venue.capacity || null,
      ends: venue.ends || null,
      floodlights: venue.floodlights ?? null,
    },
    weather: { temperature: null, condition: null, humidity: null, windSpeed: null, windDirection: null },
    pitch_report: null,
    pitchReport: { type: null, description: null, avgFirstInningsScore: null, chaseSuccess: null },
    key_moments: [],
    keyMoments: [],
    updated_at: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
  };
}

/**
 * Normalizes a single Cricbuzz series-squad JSON response into a clean,
 * role-grouped player list. The raw `player` array interleaves section
 * headers ({name, isHeader:true}) with player objects that carry id, name,
 * role, captain/keeper flags, and imageId. Support staff (coaches/managers)
 * are excluded from the player list and returned separately.
 */
export function normalizeSeriesSquad(raw, seriesId, squadId) {
  const list = Array.isArray(raw?.player) ? raw.player : [];
  const players = [];
  const supportStaff = [];

  const supportPattern = /\b(?:head\s+coach|assistant\s+coach|batting\s+coach|bowling\s+coach|fielding\s+coach|fitness\s+coach|support\s+staff|team\s+manager|manager|physio(?:therapist)?|analyst|selector|mentor|trainer|coach)\b/i;

  // Maps a Cricbuzz role string to a compact UI role code + category.
  const classify = (role = '', keeper = false) => {
    const r = String(role).toLowerCase();
    if (keeper || /wk|keeper|wicket/.test(r)) {
      return { code: 'WK', category: 'wicketkeepers' };
    }
    if (/all\s*-?rounder|allrounder/.test(r)) {
      return { code: 'AR', category: 'allRounders' };
    }
    if (/bowler|bowl/.test(r)) {
      return { code: 'BOWL', category: 'bowlers' };
    }
    // Batsman / Batter / Top order etc.
    return { code: 'BAT', category: 'batters' };
  };

  let currentSection = '';
  for (const entry of list) {
    if (!entry || typeof entry !== 'object') continue;
    if (entry.isHeader) {
      currentSection = String(entry.name || '').trim();
      continue;
    }
    const name = String(entry.name || '').trim();
    if (!name) continue;

    const role = String(entry.role || '').trim();
    // Skip support staff from the player squad.
    if (supportPattern.test(role) || supportPattern.test(currentSection)) {
      supportStaff.push({
        playerId: String(entry.id || ''),
        name,
        role: role || currentSection,
        imageUrl: entry.imageId ? getCricbuzzImageUrl(entry.imageId, 'i1') : null,
      });
      continue;
    }

    const keeper = entry.keeper === true;
    const captain = entry.captain === true;
    const viceCaptain = entry.viceCaptain === true || entry.vicecaptain === true;
    const { code, category } = classify(role, keeper);

    players.push({
      playerId: String(entry.id || ''),
      name,
      role,
      roleCode: code,
      category,
      isCaptain: captain,
      isViceCaptain: viceCaptain,
      isWicketKeeper: keeper || code === 'WK',
      battingStyle: String(entry.battingStyle || ''),
      bowlingStyle: String(entry.bowlingStyle || ''),
      // Face image strictly by the player's own imageId — never reused.
      imageId: entry.imageId ? String(entry.imageId) : null,
      imageUrl: entry.imageId ? getCricbuzzImageUrl(entry.imageId, 'i1') : null,
      imageSource: entry.imageId ? 'cricbuzz' : 'none',
    });
  }

  return {
    seriesId: String(seriesId || ''),
    squadId: String(squadId || ''),
    players,
    supportStaff,
    playerCount: players.length,
  };
}

export function normalizeSeriesTeams(raw, seriesId) {
  if (!raw) return { teams: [] };
  
  // If raw already has teams array, normalize it
  if (raw.teams && Array.isArray(raw.teams)) {
    return {
      series_id: String(seriesId),
      teams: raw.teams.map(team => ({
        team_id: String(team.teamId || team.id || ''),
        team_name: team.teamName || team.name || '',
        team_short: team.teamSName || team.shortName || '',
        logo_url: team.imageId ? getCricbuzzImageUrl(team.imageId, 't') : '',
        matches_played: team.matchesPlayed || 0,
        wins: team.matchesWon || 0,
        losses: team.matchesLost || 0,
      })),
      updated_at: new Date().toISOString(),
    };
  }
  
  // Try to extract from matches data
  const matches = [...(raw.matches || raw.matchList || [])];
  const typeMatches = raw.typeMatches || [];
  for (const group of Array.isArray(typeMatches) ? typeMatches : [typeMatches]) {
    const seriesMatches = group.seriesMatches || [];
    for (const seriesGroup of Array.isArray(seriesMatches) ? seriesMatches : [seriesMatches]) {
      const wrapper = seriesGroup.seriesAdWrapper || seriesGroup;
      if (Array.isArray(wrapper.matches)) matches.push(...wrapper.matches);
    }
  }
  const teamMap = new Map();
  
  for (const match of matches) {
    const matchData = match.match || match;
    const team1 = matchData?.matchInfo?.team1 || matchData?.team1;
    const team2 = matchData?.matchInfo?.team2 || matchData?.team2;
    
    if (team1 && !teamMap.has(String(team1.id || team1.teamId))) {
      teamMap.set(String(team1.id || team1.teamId), {
        team_id: String(team1.id || team1.teamId || ''),
        team_name: team1.name || team1.teamName || '',
        team_short: team1.shortName || team1.teamSName || '',
        logo_url: team1.imageId ? getCricbuzzImageUrl(team1.imageId, 't') : '',
        matches_played: 0,
        wins: 0,
        losses: 0,
      });
    }
    
    if (team2 && !teamMap.has(String(team2.id || team2.teamId))) {
      teamMap.set(String(team2.id || team2.teamId), {
        team_id: String(team2.id || team2.teamId || ''),
        team_name: team2.name || team2.teamName || '',
        team_short: team2.shortName || team2.teamSName || '',
        logo_url: team2.imageId ? getCricbuzzImageUrl(team2.imageId, 't') : '',
        matches_played: 0,
        wins: 0,
        losses: 0,
      });
    }
  }
  
  return {
    series_id: String(seriesId),
    teams: Array.from(teamMap.values()),
    updated_at: new Date().toISOString(),
  };
}
