# Cricket App - Important Data Requirements

## Overview
This document outlines the critical data structures and API endpoints that the Cricket Live app depends on.

---

## Core App Features & Required Data

### 1. Home Screen
**Primary Data Needed:**
- Live matches with real-time scores
- Upcoming matches
- Recent/finished matches
- Featured news stories

**API Endpoints:**
- `GET /matches/live` - Live matches list
- `GET /matches/upcoming` - Upcoming matches
- `GET /matches/recent` - Recent matches
- `GET /news?limit=5` - Top news stories

**Key Data Fields:**
```dart
Match {
  matchId, seriesName, matchDesc,
  team1: { name, shortName, logoUrl },
  team2: { name, shortName, logoUrl },
  status, statusText,
  score: { team1: [runs/wickets/overs], team2: [runs/wickets/overs] },
  venue: { name, city }
}
```

---

### 2. Live Match Details
**Primary Data Needed:**
- Real-time match status
- Current score and run rate
- Current batsmen and bowler
- Recent balls and overs
- Partnership details
- Latest performance (last 5 overs)

**API Endpoints:**
- `GET /match/:id` - Match detail
- `GET /match/:id/live-line` - Fast live updates (5s cache)
- `GET /match/:id/overs` - Overs data
- `GET /match/:id/scorecard` - Full scorecard

**Key Data Fields:**
```dart
LiveLine {
  battingTeam: { name, score, overs },
  bowlingTeam: { name },
  striker: { name, runs, balls, fours, sixes, strikeRate },
  nonStriker: { name, runs, balls },
  bowler: { name, overs, runs, wickets, economy },
  latestBall: { over, ball, result, runs, isWicket },
  recentBalls: [String],
  partnership: { runs, balls },
  crr, rrr, target, runsNeeded, ballsRemaining
}
```

---

### 3. Scorecard
**Primary Data Needed:**
- Innings-wise batting details
- Innings-wise bowling details
- Fall of wickets
- Extras breakdown
- Partnership details

**API Endpoints:**
- `GET /match/:id/scorecard`

**Key Data Fields:**
```dart
Scorecard {
  innings: [
    {
      inningsNumber, battingTeam,
      batting: [
        { name, runs, balls, fours, sixes, strikeRate, dismissal }
      ],
      bowling: [
        { name, overs, maidens, runs, wickets, economy }
      ],
      extras: { total, byes, legByes, wides, noBalls },
      total: { runs, wickets, overs, runRate },
      fallOfWickets: [{ wicketNumber, runs, overs, playerOut }]
    }
  ]
}
```

---

### 4. Commentary
**Primary Data Needed:**
- Ball-by-ball commentary
- Over summaries
- Key events (wickets, boundaries)

**API Endpoints:**
- `GET /match/:id/commentary?page=1&limit=50` - Paginated commentary
- `GET /match/:id/full-commentary/:inningsId` - Full innings commentary

**Key Data Fields:**
```dart
CommentaryEntry {
  inningsId, overNumber, ballNumber,
  commentary, timestamp,
  batsman: { name, runs, balls },
  bowler: { name, overs, runs, wickets },
  runs, isWicket, isBoundary
}
```

---

### 5. Match Highlights
**Primary Data Needed:**
- Boundaries (4s and 6s)
- Wickets
- Key moments

**API Endpoints:**
- `GET /match/:id/highlights` - All innings highlights
- `GET /match/:id/highlights/:inningsId` - Specific innings

**Key Data Fields:**
```dart
HighlightEntry {
  overNumber, ballNumber,
  type, // 'four', 'six', 'wicket'
  batsman, bowler,
  runs, commentary
}
```

---

### 6. Series/Tournament
**Primary Data Needed:**
- Series information
- Points table/standings
- Series matches
- Top performers (batting/bowling stats)

**API Endpoints:**
- `GET /series/:id` - Series details
- `GET /series/:id/matches?status=live` - Series matches (filtered)
- `GET /points-table/:seriesId` - Points table
- `GET /series/:id/stats` - Top performers (batting & bowling)

**Key Data Fields:**
```dart
PointsTable {
  seriesId, seriesName,
  groups: [
    {
      groupName,
      teams: [
        {
          position, teamName, teamShort,
          played, won, lost, tied, noResult,
          nrr, points, qualified
        }
      ]
    }
  ]
}

SeriesStats {
  batting: {
    type: 'batting',
    rows: [
      {
        rank, playerName, team,
        matches, innings, runs, average, strikeRate,
        highestScore, fours, sixes, hundreds, fifties
      }
    ]
  },
  bowling: {
    type: 'bowling',
    rows: [
      {
        rank, playerName, team,
        matches, innings, overs, wickets,
        economy, average, bestBowling,
        fourWickets, fiveWickets
      }
    ]
  }
}
```

---

### 7. Schedule
**Primary Data Needed:**
- Upcoming matches by date
- Matches by type (international, league, domestic, women)
- Match timing and venue

**API Endpoints:**
- `GET /schedule/upcoming` - All upcoming matches
- `GET /schedule/upcoming/league` - League matches only
- `GET /schedule/upcoming/international` - International matches

**Key Data Fields:**
```dart
Schedule {
  days: [
    {
      date,
      series: [
        {
          seriesId, seriesName,
          matches: [
            {
              matchId, matchDesc, matchFormat,
              team1, team2, venue,
              startTime, status
            }
          ]
        }
      ]
    }
  ]
}
```

---

### 8. News & Updates
**Primary Data Needed:**
- Latest cricket news
- Match-specific news
- Series-specific news
- News categories

**API Endpoints:**
- `GET /news?limit=10&cursor=...` - General news (paginated)
- `GET /match/:id/news` - Match news
- `GET /series/:id/news` - Series news
- `GET /news/:id` - News detail

**Key Data Fields:**
```dart
NewsStory {
  id, headline, intro,
  imageUrl, publishedTime,
  context, // e.g., "IPL 2026"
  storyType // e.g., "News", "Features"
}
```

---

### 9. Player Profile
**Primary Data Needed:**
- Player information
- Career statistics
- Recent performances

**API Endpoints:**
- `GET /player/:id` - Player details

**Key Data Fields:**
```dart
Player {
  playerId, name, country, role,
  battingStyle, bowlingStyle, imageUrl,
  stats: {
    // Format-wise (Test, ODI, T20I)
    matches, innings, runs, average, strikeRate,
    wickets, economy, bestBowling
  }
}
```

---

### 10. Team Profile
**Primary Data Needed:**
- Team information
- Squad/roster
- Team statistics

**API Endpoints:**
- `GET /team/:id` - Team details
- `GET /match/:id/squads` - Match squads (Playing XI, Bench)

**Key Data Fields:**
```dart
Team {
  teamId, name, shortName, logoUrl,
  squad: [
    {
      playerId, name, role,
      battingStyle, bowlingStyle
    }
  ]
}

MatchSquads {
  teams: [
    {
      teamName, teamShort,
      playingXI: [{ name, role, playerId }],
      bench: [{ name, role, playerId }],
      impactPlayer: { name, role, playerId }?
    }
  ]
}
```

---

## Critical Real-Time Data (Requires Frequent Updates)

### High Priority (5-10 second updates)
1. **Live Match Score** - `/match/:id/live-line`
2. **Current Batsmen Stats** - `/match/:id/live-line`
3. **Current Bowler Stats** - `/match/:id/live-line`
4. **Latest Ball Result** - `/match/:id/live-line`
5. **Recent Balls** - `/match/:id/live-line`

### Medium Priority (30-60 second updates)
1. **Full Scorecard** - `/match/:id/scorecard`
2. **Commentary** - `/match/:id/commentary`
3. **Match Stats** - `/match/:id/stats`
4. **Overs Data** - `/match/:id/overs`

### Low Priority (5+ minute updates)
1. **Points Table** - `/points-table/:seriesId`
2. **Series Stats** - `/series/:id/stats`
3. **News** - `/news`
4. **Schedule** - `/schedule/upcoming`

---

## Data Caching Strategy

### Client-Side Caching Recommendations

**Cache Forever (until app restart):**
- Player profiles
- Team profiles
- Series information (name, dates)

**Cache for 1 hour:**
- Points tables
- Series stats
- Match squads
- Schedule

**Cache for 5 minutes:**
- News stories
- Upcoming matches
- Recent matches

**Cache for 30 seconds:**
- Scorecard
- Commentary
- Match stats

**Cache for 10 seconds:**
- Live match details
- Match list (live/upcoming/recent)

**Cache for 5 seconds:**
- Live line data (real-time updates)

**Never Cache:**
- WebSocket live updates

---

## WebSocket Integration

For real-time updates, the app should connect to:
- **WebSocket URL:** `ws://api.webcrichd.co/ws`

**Subscribe to:**
- Match updates by match ID
- Live score updates
- Ball-by-ball updates

**Benefits:**
- Instant updates without polling
- Reduced API calls
- Better battery life
- Lower bandwidth usage

---

## Offline Support

### Essential Data to Cache for Offline:
1. Last viewed match details
2. Recent scorecard
3. Points table
4. Schedule (next 7 days)
5. Favorite team/player profiles

### Graceful Degradation:
- Show cached data with "Last updated" timestamp
- Display "Offline" indicator
- Queue actions for when connection returns
- Show placeholder for images that failed to load

---

## Performance Optimization

### Image Loading:
- Use CDN URLs for team logos and player images
- Implement lazy loading for lists
- Cache images locally
- Use placeholder images while loading

### List Optimization:
- Implement pagination for long lists (commentary, news)
- Use virtual scrolling for large datasets
- Load initial data quickly, fetch details on demand

### API Call Optimization:
- Batch requests where possible
- Use conditional requests (If-Modified-Since)
- Implement request debouncing
- Cancel pending requests on navigation

---

## Error Handling

### Common Scenarios:
1. **Match not started yet** - Show "Match details will be available closer to start time"
2. **Scorecard not available** - Show "Scorecard not available for this match"
3. **Commentary not available** - Show "Commentary not available"
4. **Network error** - Show cached data with retry option
5. **Rate limit exceeded** - Show "Too many requests, please try again later"

### User-Friendly Messages:
- Avoid technical error messages
- Provide actionable solutions
- Show retry buttons where appropriate
- Display loading states clearly

---

## Data Validation

### Client-Side Checks:
1. Validate match IDs before API calls
2. Check for null/empty responses
3. Validate date formats
4. Ensure numeric fields are valid
5. Handle missing optional fields gracefully

### Fallback Values:
- Use "TBD" for missing team names
- Use "0" for missing scores
- Use "Unknown" for missing venue
- Use placeholder images for missing logos

---

## Important Notes

1. **API Base URL:** `https://api.webcrichd.co`
2. **All timestamps are in ISO 8601 format**
3. **Match IDs are strings, not integers**
4. **Series IDs are strings, not integers**
5. **Player/Team IDs are strings**
6. **Scores can be null for upcoming matches**
7. **Full news article body is NOT available** (Cricbuzz limitation)
8. **Video playback URLs may not be available**
9. **Points table may not be available for all series**
10. **Stats may not be available for ongoing series**

---

## Testing Endpoints

### Sample Match IDs (for testing):
- Check `/matches/live` for current live match IDs
- Check `/matches/upcoming` for upcoming match IDs
- Check `/matches/recent` for recent match IDs

### Sample Series IDs:
- Check `/series` for available series IDs
- IPL series typically have IDs like "9241"

### Health Check:
- `GET /health` - Verify API is running
- `GET /providers` - Check data provider status

---

## Support & Documentation

- **API Documentation:** See `API_DOCUMENTATION.md`
- **Swagger UI:** `https://api.webcrichd.co/docs`
- **Health Status:** `https://api.webcrichd.co/health`
- **Metrics:** `https://api.webcrichd.co/metrics`
