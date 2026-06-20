# Cricket API - Quick Reference Guide

**Base URL:** `https://api.webcrichd.co`

---

## 🏏 Most Used Endpoints

### Matches
```
GET  /matches/live              # Live matches
GET  /matches/upcoming          # Upcoming matches  
GET  /matches/recent            # Recent/finished matches
GET  /match/:id                 # Match details
GET  /match/:id/live-line       # Real-time live data (5s cache)
GET  /match/:id/scorecard       # Full scorecard
GET  /match/:id/commentary      # Ball-by-ball commentary
GET  /match/:id/squads          # Playing XI & bench
GET  /match/:id/highlights      # Match highlights (4s, 6s, wickets)
```

### Series/Tournaments
```
GET  /series                    # All series
GET  /series/:id/matches        # Series matches (with ?status=live|upcoming|completed)
GET  /points-table/:seriesId    # Points table/standings
GET  /series/:id/stats          # Top performers (batting & bowling)
```

### Schedule
```
GET  /schedule/upcoming         # All upcoming matches
GET  /schedule/upcoming/league  # League matches only
GET  /schedule/upcoming/international  # International matches
```

### News
```
GET  /news                      # Latest news (with ?limit=10&cursor=...)
GET  /match/:id/news            # Match-specific news
GET  /series/:id/news           # Series-specific news
```

### Players & Teams
```
GET  /player/:id                # Player profile & stats
GET  /team/:id                  # Team info & squad
```

---

## 🔥 Real-Time Data Endpoints

### For Live Match Updates (Poll every 5-10 seconds)
```
GET  /match/:id/live-line       # Fastest - Current ball, batsmen, bowler
GET  /match/:id                 # Match status & basic info
```

### For Detailed Updates (Poll every 30-60 seconds)
```
GET  /match/:id/scorecard       # Full batting/bowling scorecard
GET  /match/:id/commentary      # Latest commentary
GET  /match/:id/overs           # Over-by-over data
```

---

## 📊 Response Format

All successful responses follow this format:
```json
{
  "success": true,
  "data": { ... },
  "message": null
}
```

Error responses:
```json
{
  "success": false,
  "error": "Error message",
  "statusCode": 400
}
```

---

## 🎯 Common Query Parameters

### Pagination
```
?page=1&limit=50                # For commentary
?cursor=story_id&limit=10       # For news
?timestamp=...                  # For schedule
```

### Filtering
```
?status=live                    # For series matches
?status=upcoming                # For series matches
?status=completed               # For series matches
?context=IPL 2026               # For news
?storyType=News                 # For news
```

---

## 🚀 Quick Start Examples

### Get Live Matches
```bash
curl https://api.webcrichd.co/matches/live
```

### Get Match Details
```bash
curl https://api.webcrichd.co/match/152241
```

### Get Live Line (Real-time)
```bash
curl https://api.webcrichd.co/match/152241/live-line
```

### Get Scorecard
```bash
curl https://api.webcrichd.co/match/152241/scorecard
```

### Get Points Table
```bash
curl https://api.webcrichd.co/points-table/9241
```

### Get Series Stats
```bash
curl https://api.webcrichd.co/series/9241/stats
```

### Get Schedule
```bash
curl https://api.webcrichd.co/schedule/upcoming/league
```

### Get News
```bash
curl https://api.webcrichd.co/news?limit=10
```

---

## 🔐 Authentication (Optional)

Add API key header for higher rate limits:
```
X-API-Key: your_api_key_here
```

---

## ⚡ Cache Headers

Check if response is from cache:
```
X-Cache: HIT   # Served from cache
X-Cache: MISS  # Fresh from source
```

---

## 🎨 Flutter Integration

### Using CricketApiService
```dart
final apiService = CricketApiService();

// Get live matches
final liveMatches = await apiService.getLiveMatches();

// Get match details
final matchDetail = await apiService.getMatchDetail('152241');

// Get scorecard
final scorecard = await apiService.getMatchScorecard('152241');

// Get points table
final pointsTable = await apiService.getPointsTable('9241');

// Get series stats
final stats = await apiService.getSeriesStatsTypes('9241');

// Get news
final news = await apiService.getNews(limit: 10);
```

---

## 📱 WebSocket (Real-time Updates)

Connect to WebSocket for instant updates:
```
ws://api.webcrichd.co/ws
```

Subscribe to match updates:
```json
{
  "action": "subscribe",
  "matchId": "152241"
}
```

---

## ⏱️ Cache TTL Reference

| Endpoint | Cache Duration |
|----------|---------------|
| `/match/:id/live-line` | 5 seconds |
| `/matches/live` | 10 seconds |
| `/match/:id` | 10 seconds |
| `/match/:id/overs` | 20 seconds |
| `/match/:id/scorecard` | 30 seconds |
| `/match/:id/commentary` | 30 seconds |
| `/match/:id/stats` | 1 minute |
| `/points-table/:id` | 5 minutes |
| `/matches/upcoming` | 5 minutes |
| `/matches/recent` | 5 minutes |
| `/news` | 5 minutes |
| `/schedule/upcoming` | 5 minutes |
| `/match/:id/squads` | 1 hour |
| `/series` | 1 hour |
| `/player/:id` | 1 day |
| `/team/:id` | 1 day |

---

## 🛠️ System Endpoints

```
GET  /health                    # Health check
GET  /health/ready              # Readiness probe
GET  /metrics                   # Prometheus metrics
GET  /providers                 # Data provider status
GET  /docs                      # Swagger API documentation
```

---

## ❌ Common Error Codes

| Code | Meaning | Solution |
|------|---------|----------|
| 400 | Bad Request | Check request parameters |
| 401 | Unauthorized | Add valid API key |
| 404 | Not Found | Verify match/series/player ID |
| 429 | Rate Limit Exceeded | Wait and retry, or upgrade API key |
| 500 | Internal Server Error | Retry after a moment |
| 503 | Service Unavailable | API is down, check /health |

---

## 💡 Pro Tips

1. **Use `/match/:id/live-line` for fastest live updates** (5s cache)
2. **Implement WebSocket for real-time updates** (no polling needed)
3. **Cache player/team data locally** (changes rarely)
4. **Use pagination for commentary and news** (better performance)
5. **Check X-Cache header** to verify cache hits
6. **Handle graceful degradation** when data is not available
7. **Use ?status filter** for series matches to reduce payload
8. **Batch requests** where possible to reduce API calls
9. **Implement retry logic** for failed requests
10. **Show cached data** with "Last updated" timestamp

---

## 🔍 Debugging

### Check API Health
```bash
curl https://api.webcrichd.co/health
```

### Check Provider Status
```bash
curl https://api.webcrichd.co/providers
```

### View API Documentation
```
https://api.webcrichd.co/docs
```

### Test with Sample IDs
- Get live match IDs: `/matches/live`
- Get series IDs: `/series`
- Use these IDs to test other endpoints

---

## 📞 Support

- **Full Documentation:** `API_DOCUMENTATION.md`
- **Data Requirements:** `APP_DATA_REQUIREMENTS.md`
- **Swagger UI:** https://api.webcrichd.co/docs
- **Health Status:** https://api.webcrichd.co/health

---

## 🎯 Recommended Update Frequencies

### Live Match Screen
- **Live Line:** Every 5 seconds
- **Scorecard:** Every 30 seconds
- **Commentary:** Every 30 seconds
- **Stats:** Every 60 seconds

### Home Screen
- **Live Matches:** Every 10 seconds
- **Upcoming Matches:** Every 5 minutes
- **News:** Every 5 minutes

### Series Screen
- **Points Table:** Every 5 minutes
- **Stats:** Every 5 minutes
- **Matches:** Every 5 minutes

### Schedule Screen
- **Schedule:** Every 5 minutes

---

## 🌐 Production URL

```
https://api.webcrichd.co
```

All endpoints are relative to this base URL.

---

## 📝 Notes

- All IDs (match, series, player, team) are **strings**, not integers
- Timestamps are in **ISO 8601 format**
- Scores can be **null** for upcoming matches
- Full news article body is **not available** (Cricbuzz limitation)
- Video playback URLs may **not be available**
- Points table may **not be available** for all series
- Always check `success` field in response
- Handle `null` values gracefully
- Implement proper error handling
- Use loading states for better UX
