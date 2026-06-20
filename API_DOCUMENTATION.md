# Cricket API Documentation

**Base URL:** `https://api.webcrichd.co`

## Table of Contents
1. [System Routes](#system-routes)
2. [Match Routes](#match-routes)
3. [Series Routes](#series-routes)
4. [Player & Team Routes](#player--team-routes)
5. [News Routes](#news-routes)
6. [Schedule Routes](#schedule-routes)
7. [Admin Routes](#admin-routes)
8. [Important Data Models](#important-data-models)

---

## System Routes

### Health Check
- **GET** `/health`
  - Description: Basic liveness check
  - Response: System health status including Redis, MySQL, providers, and WebSocket status

### Readiness Probe
- **GET** `/health/ready`
  - Description: Kubernetes/Docker readiness probe
  - Response: Ready status

### Metrics
- **GET** `/metrics`
  - Description: Prometheus metrics endpoint
  - Response: Prometheus-formatted metrics

### Providers Status
- **GET** `/providers`
  - Description: Data provider health status
  - Response: Health status of all data providers

---

## Match Routes

### Live Matches
- **GET** `/matches/live`
  - Description: Get all currently live matches
  - Cache: 10 seconds
  - Response: Array of match objects

### Upcoming Matches
- **GET** `/matches/upcoming`
  - Description: Get upcoming matches
  - Cache: 5 minutes
  - Response: Array of match objects

### Recent/Finished Matches
- **GET** `/matches/recent`
- **GET** `/matches/finished` (alias)
  - Description: Get recently completed matches
  - Cache: 5 minutes
  - Response: Array of match objects

### Match Detail
- **GET** `/match/:id`
  - Description: Get detailed match info
  - Parameters: `id` (match ID)
  - Cache: 10 seconds for live matches
  - Response: Detailed match object with teams, scores, innings, current batsmen, etc.

### Match Scorecard
- **GET** `/match/:id/scorecard`
  - Description: Get match scorecard with batting and bowling details
  - Parameters: `id` (match ID)
  - Cache: 30 seconds
  - Response: Innings-wise batting and bowling scorecards

### Match Commentary
- **GET** `/match/:id/commentary`
  - Description: Get match commentary
  - Parameters: 
    - `id` (match ID)
    - `page` (optional, default: 1)
    - `limit` (optional, default: 50)
  - Cache: 30 seconds
  - Response: Paginated commentary entries

### Match Innings
- **GET** `/match/:id/innings`
  - Description: Get match innings summary
  - Parameters: `id` (match ID)
  - Response: Array of innings details

### Match Overs
- **GET** `/match/:id/overs`
  - Description: Get overs data including recent overs, powerplay, and latest performance
  - Parameters: `id` (match ID)
  - Cache: 20 seconds
  - Response: Overs data with run rate graph

### Match Stats
- **GET** `/match/:id/stats`
  - Description: Get match statistics
  - Parameters: `id` (match ID)
  - Cache: 1 minute
  - Response: Match statistics

### Match News
- **GET** `/match/:id/news`
  - Description: Get news stories for a match
  - Parameters: 
    - `id` (match ID)
    - `cursor` (optional, for pagination)
  - Response: News stories related to the match

### Full Commentary
- **GET** `/match/:id/full-commentary/:inningsId`
  - Description: Get full ball-by-ball commentary for an innings
  - Parameters: 
    - `id` (match ID)
    - `inningsId` (innings number)
  - Response: Complete commentary for the innings

### Match Highlights
- **GET** `/match/:id/highlights/:inningsId`
  - Description: Get match highlights (4s, 6s, wickets) for an innings
  - Parameters: 
    - `id` (match ID)
    - `inningsId` (innings number)
  - Response: Highlights for the innings

- **GET** `/match/:id/highlights`
  - Description: Get match highlights for all innings
  - Parameters: `id` (match ID)
  - Response: Combined highlights from all innings

### Balls Map
- **GET** `/match/:id/balls-map/:inningsId`
- **GET** `/match/:id/balls-map` (default innings 1)
  - Description: Get ball-by-ball map for an innings
  - Parameters: 
    - `id` (match ID)
    - `inningsId` (optional, innings number)
  - Response: Ball-by-ball data with batters and bowlers summary

### Over-by-Over
- **GET** `/match/:id/over-by-over/:inningsId`
- **GET** `/match/:id/over-by-over` (default innings 1)
  - Description: Get over-by-over updates for an innings
  - Parameters: 
    - `id` (match ID)
    - `inningsId` (optional, innings number)
  - Response: Over-by-over data

### Match Squads
- **GET** `/match/:id/squads`
  - Description: Get match squads with Playing XI, Bench, and Impact Player
  - Parameters: `id` (match ID)
  - Cache: 1 hour
  - Response: Team squads with player details

### Live Line
- **GET** `/match/:id/live-line`
  - Description: Get enhanced live line data for Fast Live Line experience
  - Parameters: `id` (match ID)
  - Cache: 5 seconds
  - Response: Real-time match data including latest ball, striker, non-striker, bowler, partnership, etc.

---

## Series Routes

### All Series
- **GET** `/series`
  - Description: Get all series
  - Cache: 1 hour
  - Response: Array of series objects

### Series Detail
- **GET** `/series/:id`
  - Description: Get series details and matches
  - Parameters: `id` (series ID)
  - Response: Series info with matches

### Series Matches
- **GET** `/series/:id/matches`
  - Description: Get only matches belonging to this series (strict filtering)
  - Parameters: 
    - `id` (series ID)
    - `status` (optional: live, upcoming, completed)
  - Response: Filtered matches for the series

### Points Table
- **GET** `/points-table/:seriesId`
- **GET** `/series/:id/points-table`
  - Description: Get points table for a series
  - Parameters: `seriesId` or `id` (series ID)
  - Cache: 5 minutes
  - Response: Points table with team standings

### Series Stats
- **GET** `/series/:id/stats`
  - Description: Get available stat types for a series (batting and bowling)
  - Parameters: `id` (series ID)
  - Response: Batting and bowling statistics

- **GET** `/series/:id/stats/:type`
  - Description: Get stat table (player rankings) for a series by stat type
  - Parameters: 
    - `id` (series ID)
    - `type` (stat type: mostRuns, mostWickets, batting, bowling, etc.)
  - Response: Player rankings for the specified stat type

### Series Schedule
- **GET** `/series/:id/schedule`
  - Description: Get app-ready series schedule
  - Parameters: `id` (series ID)
  - Response: Series schedule with match details

### Series News
- **GET** `/series/:id/news`
  - Description: Get news stories for a series
  - Parameters: 
    - `id` (series ID)
    - `cursor` (optional, for pagination)
    - `limit` (optional, default: 10)
  - Response: News stories related to the series

### Series Teams
- **GET** `/series/:id/teams`
  - Description: Get teams participating in a series
  - Parameters: `id` (series ID)
  - Cache: 1 hour
  - Response: List of teams in the series

---

## Player & Team Routes

### Player Info
- **GET** `/player/:id`
  - Description: Get player info and career stats
  - Parameters: `id` (player ID)
  - Cache: 1 day
  - Response: Player details with career statistics

### Team Info
- **GET** `/team/:id`
  - Description: Get team info and squad
  - Parameters: `id` (team ID)
  - Cache: 1 day
  - Response: Team details with squad information

---

## News Routes

### News List
- **GET** `/news`
  - Description: Get cricket news stories with pagination
  - Parameters: 
    - `cursor` (optional, for pagination)
    - `limit` (optional, default: 10, max: 50)
    - `context` (optional, filter by context like "IPL 2026")
    - `storyType` (optional, filter by type like "News", "Features")
  - Cache: 5 minutes
  - Response: Paginated news stories

### News Detail
- **GET** `/news/:id`
  - Description: Get news story detail by ID
  - Parameters: `id` (news story ID)
  - Cache: 1 hour
  - Response: News story details (summary only, full body not available from Cricbuzz)

### Videos
- **GET** `/videos`
  - Description: Get cricket video cards
  - Parameters: `limit` (optional, default: 10, max: 50)
  - Response: Video cards (URLs may not be available)

- **GET** `/videos/:id`
  - Description: Get a cricket video card by ID
  - Parameters: `id` (video ID)
  - Response: Video card details

---

## Schedule Routes

### Upcoming Schedule
- **GET** `/schedule/upcoming`
  - Description: Get upcoming match schedule (all types)
  - Parameters: `timestamp` (optional, for pagination)
  - Cache: 5 minutes
  - Response: Schedule grouped by days

- **GET** `/schedule/upcoming/:type`
  - Description: Get upcoming match schedule by type
  - Parameters: 
    - `type` (all, international, league, domestic, women)
    - `timestamp` (optional, for pagination)
  - Cache: 5 minutes
  - Response: Filtered schedule by type

---

## Admin Routes

**Prefix:** `/admin`

### Login
- **POST** `/admin/login`
  - Description: Admin login to get JWT token
  - Body: `{ username, password }`
  - Response: JWT token and user info

### Logout
- **POST** `/admin/logout`
  - Description: Admin logout (invalidate token)
  - Auth: Required
  - Response: Success message

### API Keys Management
- **POST** `/admin/api-keys`
  - Description: Generate a new API key
  - Auth: Required (Admin only)
  - Body: `{ name, email, tier, rate_limit, expires_in_days }`
  - Response: Generated API key (shown only once)

- **GET** `/admin/api-keys`
  - Description: List all API keys
  - Auth: Required (Admin only)
  - Response: Array of API keys

- **DELETE** `/admin/api-keys/:id`
  - Description: Revoke an API key
  - Auth: Required (Admin only)
  - Parameters: `id` (API key ID)
  - Response: Success message

### Provider Management
- **POST** `/admin/providers/:name/reset`
  - Description: Reset a provider health state
  - Auth: Required (Admin only)
  - Parameters: `name` (provider name)
  - Response: Success message

### Cache Management
- **POST** `/admin/cache/flush`
  - Description: Flush all cached data
  - Auth: Required (Admin only)
  - Response: Success message

### System Stats
- **GET** `/admin/stats`
  - Description: System statistics
  - Auth: Required (Admin only)
  - Response: Redis, database, providers, and system stats

---

## Important Data Models

### Match Object (ApiMatch)
```dart
{
  matchId: String,
  seriesId: String,
  seriesName: String,
  matchDesc: String,
  matchFormat: String,
  matchType: String,
  status: String, // 'live', 'upcoming', 'completed'
  statusText: String,
  team1: {
    id: String,
    name: String,
    shortName: String,
    logoUrl: String?
  },
  team2: {
    id: String,
    name: String,
    shortName: String,
    logoUrl: String?
  },
  venue: {
    name: String,
    city: String,
    country: String
  },
  startTime: DateTime?,
  endTime: DateTime?,
  score: {
    team1: [{ runs: int, wickets: int, overs: double }],
    team2: [{ runs: int, wickets: int, overs: double }]
  }
}
```

### Match Detail Object (ApiMatchDetail)
```dart
{
  matchId: String,
  seriesId: String,
  seriesName: String,
  matchDesc: String,
  matchFormat: String,
  status: String,
  statusText: String,
  result: String,
  toss: {
    winner: String,
    decision: String
  },
  team1: ApiTeam,
  team2: ApiTeam,
  venue: ApiVenue,
  innings: [ApiInningsDetail],
  currentBatsmen: [ApiCurrentBatsman],
  currentBowler: ApiCurrentBowler?,
  partnership: ApiPartnership?,
  currentRunRate: double,
  requiredRunRate: double,
  latestPerformance: [ApiLatestPerformance],
  powerplayData: [ApiPowerplayData],
  lastUpdated: DateTime
}
```

### Scorecard Object (ApiScorecard)
```dart
{
  innings: [
    {
      inningsNumber: int,
      battingTeam: String,
      battingTeamShort: String,
      batting: [
        {
          playerId: String,
          name: String,
          runs: int,
          balls: int,
          fours: int,
          sixes: int,
          strikeRate: double,
          dismissal: String,
          dismissalText: String
        }
      ],
      bowling: [
        {
          playerId: String,
          name: String,
          overs: double,
          maidens: int,
          runs: int,
          wickets: int,
          economy: double,
          dots: int,
          fours: int,
          sixes: int
        }
      ],
      extras: {
        total: int,
        byes: int,
        legByes: int,
        wides: int,
        noBalls: int,
        penalty: int
      },
      total: {
        runs: int,
        wickets: int,
        overs: double,
        runRate: double
      },
      fallOfWickets: [
        {
          wicketNumber: int,
          runs: int,
          overs: double,
          playerOut: String
        }
      ]
    }
  ]
}
```

### Series Object (ApiSeries)
```dart
{
  seriesId: String,
  name: String,
  startDate: DateTime?,
  endDate: DateTime?,
  status: String
}
```

### Points Table
```dart
{
  seriesId: String,
  seriesName: String,
  groups: [
    {
      groupName: String,
      teams: [
        {
          position: int,
          teamId: String,
          teamName: String,
          teamShort: String,
          played: int,
          won: int,
          lost: int,
          tied: int,
          noResult: int,
          nrr: double,
          points: int,
          qualified: bool,
          logoUrl: String?
        }
      ]
    }
  ]
}
```

### Player Object (ApiPlayer)
```dart
{
  playerId: String,
  name: String,
  country: String,
  role: String,
  battingStyle: String?,
  bowlingStyle: String?,
  imageUrl: String?,
  stats: {
    // Career statistics by format (Test, ODI, T20I, etc.)
  }
}
```

### News Object (NewsModel)
```dart
{
  id: String,
  headline: String,
  intro: String?,
  imageUrl: String?,
  publishedTime: DateTime,
  context: String?, // e.g., "IPL 2026"
  storyType: String?, // e.g., "News", "Features"
  content: String? // Full body not available from Cricbuzz
}
```

### Schedule Object (ApiSchedule)
```dart
{
  days: [
    {
      date: String,
      series: [
        {
          seriesId: String,
          seriesName: String,
          matches: [
            {
              matchId: String,
              matchDesc: String,
              matchFormat: String,
              status: String,
              team1: ApiScheduleTeam,
              team2: ApiScheduleTeam,
              venue: ApiScheduleVenue,
              startTime: DateTime?
            }
          ]
        }
      ]
    }
  ]
}
```

### Live Line Object
```dart
{
  matchId: String,
  status: String,
  innings: int,
  battingTeam: {
    name: String,
    score: String,
    overs: double
  },
  bowlingTeam: {
    name: String
  },
  target: int?,
  runsNeeded: int?,
  ballsRemaining: int?,
  crr: double,
  rrr: double?,
  latestBall: {
    over: double,
    ball: int,
    result: String,
    runs: int,
    isWicket: bool,
    commentary: String
  },
  recentBalls: [String],
  currentOverBalls: [String],
  striker: {
    name: String,
    runs: int,
    balls: int,
    fours: int,
    sixes: int,
    strikeRate: double
  },
  nonStriker: {
    name: String,
    runs: int,
    balls: int
  },
  bowler: {
    name: String,
    overs: double,
    maidens: int,
    runs: int,
    wickets: int,
    economy: double
  },
  partnership: {
    runs: int,
    balls: int
  }?,
  lastWicket: {
    playerName: String,
    runs: int,
    overs: double
  }?,
  winProbability: {
    team1: double,
    team2: double
  }?
}
```

---

## Cache TTL (Time To Live)

- **Live Scores:** 10 seconds
- **Scorecard:** 30 seconds
- **Commentary:** 30 seconds
- **Match Overs:** 20 seconds
- **Match Stats:** 1 minute
- **Live Line:** 5 seconds
- **Squads:** 1 hour
- **Points Table:** 5 minutes
- **Series:** 1 hour
- **Player/Team:** 1 day
- **News:** 5 minutes
- **Schedule:** 5 minutes

---

## Rate Limiting

- Default: 100 requests per time window
- Configurable per API key tier (free, pro, enterprise)
- Rate limit headers included in responses

---

## Authentication

- **Public Access:** Most endpoints are publicly accessible
- **API Key:** Optional, provides higher rate limits
- **JWT Token:** Required for admin routes
- **Header:** `X-API-Key` for API key authentication

---

## WebSocket

- **Endpoint:** `ws://api.webcrichd.co/ws`
- **Purpose:** Real-time match updates
- **Events:** Live score updates, ball-by-ball commentary

---

## Error Responses

All error responses follow this format:
```json
{
  "success": false,
  "error": "Error message",
  "statusCode": 400
}
```

Common status codes:
- **200:** Success
- **400:** Bad Request
- **401:** Unauthorized
- **404:** Not Found
- **429:** Rate Limit Exceeded
- **500:** Internal Server Error
- **503:** Service Unavailable

---

## Notes

1. **Data Source:** All data is scraped from Cricbuzz
2. **Caching:** Aggressive caching is used to reduce load on source
3. **Fallbacks:** Multiple fallback mechanisms ensure data availability
4. **Validation:** Payload validation prevents caching of invalid data
5. **Series Filtering:** Strict filtering ensures matches belong to correct series
6. **No Full Article Body:** News endpoints return summaries only (Cricbuzz limitation)
7. **Video URLs:** Video playback URLs may not be available from current source

---

## Flutter App Integration

The Flutter app uses the `CricketApiService` class to interact with all these endpoints. Key features:

1. **Type-safe models:** All responses are parsed into Dart models
2. **Error handling:** Comprehensive error handling with `ApiException`
3. **Caching:** Client-side caching for better performance
4. **Pagination:** Support for paginated endpoints (news, commentary)
5. **Real-time updates:** WebSocket integration for live matches

---

## Deployment

- **Production URL:** https://api.webcrichd.co
- **Server:** Node.js with Fastify framework
- **Database:** MySQL for persistent data
- **Cache:** Redis for high-performance caching
- **Process Manager:** PM2 for production deployment
- **Web Server:** Nginx as reverse proxy
