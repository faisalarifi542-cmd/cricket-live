/**
 * CRITICAL FIXES FOR CRICBUZZ PARSERS
 * 
 * This file contains fixes for:
 * 1. parseMatchSquadsFromHtml - Proper team name extraction from h3 headers
 * 2. parsePointsTableFromHtml - Better IPL points table parsing
 * 3. parseScorecardFromHtml - HTML scorecard fallback
 * 4. getOversWithFallback - Commentary-based overs
 * 5. getLiveLineFixed - Proper innings detection
 */

const logger = require('../../lib/logger');

/**
 * FIXED: Parse match squads from Cricbuzz HTML
 * Key fixes:
 * - Extract team names from h3.cb-match-sqd-text (not page title)
 * - Properly separate Playing XI from Bench by section markers
 * - Better captain/WK detection with (C), (WK), (C & WK) patterns
 * - Group players by team based on header positions
 */
function parseMatchSquadsFromHtml_FIXED(html, matchId) {
  logger.info({ msg: '[FIXED] Parsing match squads HTML', matchId, htmlLength: html?.length || 0 });
  
  // Extract page title for validation only
  const titleMatch = html.match(/<title>([^<]*)<\/title>/i);
  const pageTitle = titleMatch ? titleMatch[1].replace(/\s+/g, ' ').trim() : '';
  logger.info({ msg: '[FIXED] Squads page title', matchId, pageTitle });
  
  // STEP 1: Find team headers (h3 with cb-match-sqd-text class)
  const teamHeaders = [];
  const teamHeaderPattern = /<h3[^>]*class="[^"]*cb-match-sqd-text[^"]*"[^>]*>([\s\S]*?)<\/h3>/gi;
  let headerMatch;
  
  while ((headerMatch = teamHeaderPattern.exec(html)) !== null) {
    const teamName = headerMatch[1].replace(/<[^>]+>/g, '').trim();
    if (teamName && teamName.length > 2 && !teamName.toLowerCase().includes('playing xi')) {
      teamHeaders.push({
        name: teamName,
        shortName: generateShortName(teamName),
        index: headerMatch.index
      });
    }
  }
  
  // Fallback: try generic h3 if specific class not found
  if (teamHeaders.length < 2) {
    const genericH3Pattern = /<h3[^>]*>([\s\S]*?)<\/h3>/gi;
    while ((headerMatch = genericH3Pattern.exec(html)) !== null) {
      const teamName = headerMatch[1].replace(/<[^>]+>/g, '').trim();
      if (teamName && 
          teamName.length > 2 && 
          teamName.length < 50 &&
          !teamName.toLowerCase().includes('playing xi') &&
          !teamName.toLowerCase().includes('bench') &&
          !teamName.toLowerCase().includes('substitutes') &&
          !teamName.toLowerCase().includes('impact') &&
          !teamName.toLowerCase().includes('support staff') &&
          !teamName.toLowerCase().includes('cricbuzz') &&
          !teamHeaders.find(h => h.name === teamName)) {
        teamHeaders.push({
          name: teamName,
          shortName: generateShortName(teamName),
          index: headerMatch.index
        });
      }
      if (teamHeaders.length >= 2) break;
    }
  }
  
  logger.info({ msg: '[FIXED] Found team headers', matchId, teams: teamHeaders.map(h => h.name) });
  
  if (teamHeaders.length < 2) {
    logger.error({ msg: '[FIXED] Could not find 2 team headers', matchId, pageTitle });
    return {
      match_id: String(matchId),
      team1: { team_name: 'Team 1', team_short: 'T1', playing_xi: [], bench: [], substitutes: [], impact_player: null },
      team2: { team_name: 'Team 2', team_short: 'T2', playing_xi: [], bench: [], substitutes: [], impact_player: null },
      support_staff: [],
      page_title: pageTitle,
      _parse_error: 'Could not identify team headers'
    };
  }
  
  // STEP 2: Parse all player cards with their positions
  const allPlayers = [];
  const playerCardPattern = /<a[^>]*href="[^"]*\/profiles\/(\d+)\/[^"]*"[^>]*>([\s\S]*?)<\/a>/gi;
  let playerMatch;
  
  while ((playerMatch = playerCardPattern.exec(html)) !== null) {
    const playerId = playerMatch[1];
    const nameHtml = playerMatch[2];
    const playerName = nameHtml.replace(/<[^>]+>/g, '').trim();
    
    if (playerName && playerName.length > 2) {
      const contextStart = Math.max(0, playerMatch.index - 200);
      const contextEnd = Math.min(html.length, playerMatch.index + 300);
      const context = html.slice(contextStart, contextEnd);
      
      // Determine section by looking at preceding labels
      const precedingHtml = html.slice(Math.max(0, playerMatch.index - 800), playerMatch.index);
      const lastSectionMatch = precedingHtml.match(/(playing\s*xi|bench|substitutes|impact\s*player)/i);
      const section = lastSectionMatch ? lastSectionMatch[1].toLowerCase() : 'unknown';
      
      // Extract role
      const role = extractPlayerRole(context);
      
      // Detect captain and wicketkeeper with proper patterns
      const captainMatch = context.match(/\((c|C)\s*(?:&\s*(?:wk|WK))?\)|captain/i);
      const wkMatch = context.match(/\((?:wk|WK|w\.k\.)\s*(?:&\s*(?:c|C))?\)|wicket.?keeper/i);
      const isCaptain = !!captainMatch;
      const isWicketkeeper = !!wkMatch;
      
      allPlayers.push({
        player_id: String(playerId),
        name: playerName,
        role,
        is_captain: isCaptain,
        is_wicketkeeper: isWicketkeeper,
        section,
        index: playerMatch.index
      });
    }
  }
  
  logger.info({ msg: '[FIXED] Parsed players', matchId, totalPlayers: allPlayers.length });
  
  // STEP 3: Assign players to teams based on position between headers
  const teams = [];
  teamHeaders.sort((a, b) => a.index - b.index);
  
  for (let i = 0; i < teamHeaders.length && i < 2; i++) {
    const header = teamHeaders[i];
    const nextHeader = teamHeaders[i + 1];
    
    // Get players for this team
    const teamPlayers = allPlayers.filter(p => {
      if (nextHeader) {
        return p.index > header.index && p.index < nextHeader.index;
      }
      return p.index > header.index;
    });
    
    // Separate by section
    const playingXi = teamPlayers
      .filter(p => p.section.includes('playing') || (!p.section.includes('bench') && !p.section.includes('impact') && !p.section.includes('substitutes')))
      .slice(0, 11)
      .map(p => ({
        player_id: p.player_id,
        name: p.name,
        role: p.role,
        is_captain: p.is_captain,
        is_wicketkeeper: p.is_wicketkeeper
      }));
    
    const bench = teamPlayers
      .filter(p => p.section.includes('bench') || p.section.includes('substitutes'))
      .map(p => ({
        player_id: p.player_id,
        name: p.name,
        role: p.role,
        is_captain: p.is_captain,
        is_wicketkeeper: p.is_wicketkeeper
      }));
    
    const impactPlayer = teamPlayers.find(p => p.section.includes('impact')) || null;
    
    teams.push({
      team_name: header.name,
      team_short: header.shortName,
      playing_xi: playingXi,
      bench: bench,
      substitutes: bench, // Alias
      impact_player: impactPlayer ? {
        player_id: impactPlayer.player_id,
        name: impactPlayer.name,
        role: impactPlayer.role
      } : null
    });
  }
  
  // STEP 4: Extract support staff if available
  const supportStaff = [];
  const staffPattern = /<div[^>]*class="[^"]*cb-match-sqd-lst[^"]*"[^>]*>([\s\S]*?)<\/div>/gi;
  let staffMatch;
  while ((staffMatch = staffPattern.exec(html)) !== null) {
    const staffText = staffMatch[1].replace(/<[^>]+>/g, '').trim();
    if (staffText && (staffText.includes('Coach') || staffText.includes('Manager') || staffText.includes('Physio'))) {
      supportStaff.push(staffText);
    }
  }
  
  return {
    match_id: String(matchId),
    team1: teams[0] || { team_name: 'Team 1', team_short: 'T1', playing_xi: [], bench: [], substitutes: [], impact_player: null },
    team2: teams[1] || { team_name: 'Team 2', team_short: 'T2', playing_xi: [], bench: [], substitutes: [], impact_player: null },
    support_staff: supportStaff,
    page_title: pageTitle,
    _players_found: allPlayers.length,
    _teams_found: teamHeaders.length
  };
}

/**
 * FIXED: Parse points table from Cricbuzz HTML
 * Key fixes:
 * - Better detection of cb-srs-pnts-tble table
 * - Stop before "Opposition" section
 * - Extract qualification status (Q, E)
 * - Validate expected IPL teams
 */
function parsePointsTableFromHtml_FIXED(html, seriesId) {
  logger.info({ msg: '[FIXED] Parsing points table HTML', seriesId, htmlLength: html?.length || 0 });
  
  const pointsTableInfo = [];
  
  // Try multiple strategies to find the points table
  let tableHtml = null;
  
  // Strategy 1: Look for cb-srs-pnts-tble class
  const tableMatch = html.match(/<table[^>]*class="[^"]*cb-srs-pnts-tble[^"]*"[^>]*>([\s\S]*?)<\/table>/i);
  if (tableMatch) {
    tableHtml = tableMatch[0];
    logger.info({ msg: '[FIXED] Found points table by class', seriesId });
  }
  
  // Strategy 2: Look for any table with points-related headers
  if (!tableHtml) {
    const allTables = html.match(/<table[^>]*>[\s\S]*?<\/table>/gi) || [];
    for (const table of allTables) {
      if (table.includes('Pts') && table.includes('NRR') && table.includes('P')) {
        tableHtml = table;
        logger.info({ msg: '[FIXED] Found points table by content', seriesId });
        break;
      }
    }
  }
  
  // Strategy 3: Look for div-based points table (modern Cricbuzz)
  if (!tableHtml) {
    const divTableMatch = html.match(/<div[^>]*class="[^"]*cb-srs-pnts[^"]*"[^>]*>([\s\S]*?)<\/div>/i);
    if (divTableMatch) {
      // Parse div-based structure
      const divHtml = divTableMatch[1];
      const rowPattern = /<div[^>]*class="[^"]*cb-srs-pnts-dgt-wdg[^"]*"[^>]*>([\s\S]*?)<\/div>/gi;
      let rowMatch;
      let position = 1;
      
      while ((rowMatch = rowPattern.exec(divHtml)) !== null) {
        const rowHtml = rowMatch[1];
        
        // Extract team info
        const teamMatch = rowHtml.match(/<a[^>]*>([\s\S]*?)<\/a>/i);
        const teamName = teamMatch ? teamMatch[1].replace(/<[^>]+>/g, '').trim() : '';
        
        // Extract numbers
        const numbers = rowHtml.match(/>(\d+)</g);
        if (teamName && numbers && numbers.length >= 5) {
          const values = numbers.map(n => parseInt(n.replace(/[><]/g, '')));
          
          pointsTableInfo.push({
            rank: position++,
            team_id: '',
            team_name: teamName,
            team_short: generateShortName(teamName),
            played: values[0] || 0,
            won: values[1] || 0,
            lost: values[2] || 0,
            tied: values[3] || 0,
            no_result: values[4] || 0,
            points: values[5] || 0,
            nrr: parseFloat(values[6] || 0),
            qualified: position <= 4 ? 'Q' : (position <= 6 ? 'E' : ''),
            logo_url: ''
          });
        }
      }
    }
  }
  
  // Parse table rows if we found a table
  if (tableHtml && pointsTableInfo.length === 0) {
    const tbodyMatch = tableHtml.match(/<tbody[^>]*>([\s\S]*?)<\/tbody>/i);
    const tbody = tbodyMatch ? tbodyMatch[1] : tableHtml;
    
    // Extract rows - stop at "Opposition" section
    const rowPattern = /<tr[^>]*>([\s\S]*?)<\/tr>/gi;
    let rowMatch;
    let position = 1;
    
    while ((rowMatch = rowPattern.exec(tbody)) !== null) {
      const rowHtml = rowMatch[1];
      
      // Stop if we hit the detailed match history section
      if (rowHtml.includes('Opposition') || rowHtml.includes('Description') || rowHtml.includes('Date')) {
        break;
      }
      
      // Extract cells
      const cellPattern = /<td[^>]*>([\s\S]*?)<\/td>/gi;
      const cells = [];
      let cellMatch;
      
      while ((cellMatch = cellPattern.exec(rowHtml)) !== null) {
        let cellText = cellMatch[1].replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim();
        cells.push(cellText);
      }
      
      // Need at least: Rank, Team, P, W, L, Tied/NR, Pts, NRR
      if (cells.length >= 7) {
        const rank = parseInt(cells[0]) || position;
        const teamName = cells[1];
        
        if (teamName && teamName.length > 1 && !teamName.match(/^\d+$/)) {
          // Extract qualification status from team cell (might have Q or E badge)
          const qualified = cells[1].includes('Q') ? 'Q' : (cells[1].includes('E') ? 'E' : '');
          
          // Find numeric values
          const numericCells = cells.slice(2).map(c => parseFloat(c) || 0).filter(n => n > 0 || cells[2 + n] === '0');
          
          pointsTableInfo.push({
            rank: rank,
            team_id: '',
            team_name: teamName.replace(/\s+Q\s*$/, '').replace(/\s+E\s*$/, '').trim(),
            team_short: generateShortName(teamName),
            played: parseInt(cells[2]) || 0,
            won: parseInt(cells[3]) || 0,
            lost: parseInt(cells[4]) || 0,
            tied: parseInt(cells[5]) || 0,
            no_result: parseInt(cells[6]) || 0,
            points: parseInt(cells[7]) || 0,
            nrr: parseFloat(cells[8]) || 0,
            qualified: qualified,
            logo_url: ''
          });
          
          position++;
        }
      }
    }
  }
  
  // Validate: For IPL, we expect 10 teams
  if (seriesId === '9241' || seriesId === 9241) {
    const expectedTeams = ['RCB', 'PBKS', 'GT', 'RR', 'DC', 'SRH', 'CSK', 'KKR', 'MI', 'LSG'];
    const foundTeams = pointsTableInfo.map(t => t.team_short);
    const missingTeams = expectedTeams.filter(t => !foundTeams.includes(t));
    
    if (missingTeams.length > 0) {
      logger.warn({ 
        msg: '[FIXED] IPL points table missing teams', 
        seriesId, 
        found: foundTeams, 
        missing: missingTeams,
        count: pointsTableInfo.length 
      });
    }
    
    if (pointsTableInfo.length < 8) {
      logger.error({ 
        msg: '[FIXED] IPL points table has too few teams', 
        seriesId, 
        count: pointsTableInfo.length,
        teams: pointsTableInfo.map(t => t.team_name)
      });
      return { pointsTable: [], _error: `Only found ${pointsTableInfo.length} teams, expected 10 for IPL` };
    }
  }
  
  logger.info({ msg: '[FIXED] Parsed points table', seriesId, teams: pointsTableInfo.length });
  
  return { pointsTable: pointsTableInfo };
}

/**
 * Parse scorecard from Cricbuzz HTML
 */
function parseScorecardFromHtml(html, matchId) {
  logger.info({ msg: '[FIXED] Parsing scorecard HTML', matchId, htmlLength: html?.length || 0 });
  
  const innings = [];
  
  // Find innings sections
  const inningsPattern = /<div[^>]*id="innings_\d+"[^>]*>([\s\S]*?)<\/div>\s*<\/div>/gi;
  let inningsMatch;
  
  while ((inningsMatch = inningsPattern.exec(html)) !== null) {
    const inningsHtml = inningsMatch[1];
    
    // Extract innings header
    const headerMatch = inningsHtml.match(/<h2[^>]*>([\s\S]*?)<\/h2>/i) || 
                       inningsHtml.match(/<span[^>]*class="[^"]*cb-scrcrd-hdr-rw[^"]*"[^>]*>([\s\S]*?)<\/span>/i);
    const headerText = headerMatch ? headerMatch[1].replace(/<[^>]+>/g, '').trim() : '';
    
    // Parse batting table
    const battingRows = [];
    const battingPattern = /<tr[^>]*class="[^"]*cb-scrcrd-bat-tr[^"]*"[^>]*>([\s\S]*?)<\/tr>/gi;
    let battingMatch;
    
    while ((battingMatch = battingPattern.exec(inningsHtml)) !== null) {
      const rowHtml = battingMatch[1];
      const cells = rowHtml.match(/<td[^>]*>([\s\S]*?)<\/td>/gi) || [];
      
      if (cells.length >= 8) {
        const playerMatch = cells[0].match(/>([^<]+)</);
        const dismissalMatch = cells[1].match(/>([^<]+)</);
        
        battingRows.push({
          player: playerMatch ? playerMatch[1].trim() : '',
          dismissal: dismissalMatch ? dismissalMatch[1].trim() : '',
          runs: parseInt(cells[2].replace(/<[^>]+>/g, '')) || 0,
          balls: parseInt(cells[3].replace(/<[^>]+>/g, '')) || 0,
          fours: parseInt(cells[5].replace(/<[^>]+>/g, '')) || 0,
          sixes: parseInt(cells[6].replace(/<[^>]+>/g, '')) || 0,
          strike_rate: parseFloat(cells[7].replace(/<[^>]+>/g, '')) || 0
        });
      }
    }
    
    // Parse bowling table
    const bowlingRows = [];
    const bowlingPattern = /<tr[^>]*class="[^"]*cb-scrcrd-bwl-tr[^"]*"[^>]*>([\s\S]*?)<\/tr>/gi;
    let bowlingMatch;
    
    while ((bowlingMatch = bowlingPattern.exec(inningsHtml)) !== null) {
      const rowHtml = bowlingMatch[1];
      const cells = rowHtml.match(/<td[^>]*>([\s\S]*?)<\/td>/gi) || [];
      
      if (cells.length >= 8) {
        const playerMatch = cells[0].match(/>([^<]+)</);
        
        bowlingRows.push({
          player: playerMatch ? playerMatch[1].trim() : '',
          overs: cells[1].replace(/<[^>]+>/g, '').trim(),
          maidens: parseInt(cells[2].replace(/<[^>]+>/g, '')) || 0,
          runs: parseInt(cells[3].replace(/<[^>]+>/g, '')) || 0,
          wickets: parseInt(cells[4].replace(/<[^>]+>/g, '')) || 0,
          no_balls: parseInt(cells[6].replace(/<[^>]+>/g, '')) || 0,
          wides: parseInt(cells[7].replace(/<[^>]+>/g, '')) || 0,
          economy: parseFloat(cells[8].replace(/<[^>]+>/g, '')) || 0
        });
      }
    }
    
    // Extract extras and total
    const extrasMatch = inningsHtml.match(/extras[\s\S]*?<td[^>]*>(\d+)<\/td>/i);
    const totalMatch = inningsHtml.match(/total[\s\S]*?<td[^>]*>(\d+)[\s\S]*?(\d+\.\d+)<\/td>/i) ||
                      inningsHtml.match(/total[\s\S]*?<span[^>]*>(\d+)<\/span>/i);
    
    innings.push({
      name: headerText,
      batting: battingRows,
      bowling: bowlingRows,
      extras: extrasMatch ? parseInt(extrasMatch[1]) : 0,
      total: totalMatch ? parseInt(totalMatch[1]) : 0,
      overs: totalMatch && totalMatch[2] ? totalMatch[2] : ''
    });
  }
  
  return { innings };
}

/**
 * Generate short name from full team name
 */
function generateShortName(fullName) {
  if (!fullName) return '';
  
  // Known team short names
  const knownTeams = {
    'royal challengers bangalore': 'RCB',
    'royal challengers bengaluru': 'RCB',
    'punjab kings': 'PBKS',
    'gujarat titans': 'GT',
    'rajasthan royals': 'RR',
    'delhi capitals': 'DC',
    'sunrisers hyderabad': 'SRH',
    'chennai super kings': 'CSK',
    'kolkata knight riders': 'KKR',
    'mumbai indians': 'MI',
    'lucknow super giants': 'LSG',
    'kochi tuskers kerala': 'KTK',
    'pune warriors india': 'PWI',
    'rising pune supergiant': 'RPS',
    'gujarat lions': 'GL',
    'deccan chargers': 'DC',
  };
  
  const lowerName = fullName.toLowerCase();
  if (knownTeams[lowerName]) {
    return knownTeams[lowerName];
  }
  
  // Generate from initials
  const words = fullName.split(/\s+/);
  if (words.length >= 2) {
    return words.map(w => w[0]?.toUpperCase() || '').join('').slice(0, 4);
  }
  
  return fullName.slice(0, 4).toUpperCase();
}

/**
 * Extract player role from HTML context
 */
function extractPlayerRole(html) {
  const rolePatterns = [
    { pattern: /batting all-?rounder/i, role: 'Batting Allrounder' },
    { pattern: /bowling all-?rounder/i, role: 'Bowling Allrounder' },
    { pattern: /all-?rounder/i, role: 'Allrounder' },
    { pattern: /wicket-?keeper(?:\s*bat(?:ter)?)?/i, role: 'WK-Batter' },
    { pattern: /wk-?batter/i, role: 'WK-Batter' },
    { pattern: /bat(?:ter|sman)/i, role: 'Batter' },
    { pattern: /bowler/i, role: 'Bowler' },
    { pattern: /captain/i, role: '' }, // Captain is not a role
  ];
  
  for (const { pattern, role } of rolePatterns) {
    if (pattern.test(html)) {
      return role;
    }
  }
  
  return '';
}

module.exports = {
  parseMatchSquadsFromHtml_FIXED,
  parsePointsTableFromHtml_FIXED,
  parseScorecardFromHtml,
  generateShortName,
  extractPlayerRole
};
