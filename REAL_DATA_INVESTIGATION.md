# Real Data Investigation Report

## Executive Summary

**Date:** May 30, 2026  
**Investigation:** Backend data availability for Scorecard and Commentary endpoints  
**Status:** ⚠️ **BACKEND ISSUE CONFIRMED**

---

## Test Results

### Match Tested
- **Match ID:** 155398
- **Teams:** Rajasthan Royals vs Gujarat Titans
- **Series:** Indian Premier League 2026
- **Status:** Completed
- **Result:** Gujarat Titans won by 7 wickets

### Endpoint Test Results

#### 1. ✅ Match Detail (`/match/155398`)
**Status:** Working  
**Data:** Returns full match info with scores, teams, venue, etc.

#### 2. ❌ Scorecard (`/match/155398/scorecard`)
**Status:** **FAILING - Backend returns empty**  
**Response:**
```json
{
  "success": true,
  "data": {
    "innings": [],
    "scorecard_available": false
  },
  "fromCache": false,
  "message": "Scorecard not available for this match"
}
```

**Root Cause:** Backend Cricbuzz provider is failing to fetch scorecard data. Both JSON API and HTML fallback are returning empty.

**Backend File:** `cricket-api/src/providers/cricbuzz/client.js` (line 260-298)

**What's Happening:**
1. Backend tries Cricbuzz JSON API: `/scorecard/${matchId}` - **FAILS**
2. Backend tries HTML fallback: `/live-cricket-scorecard/${matchId}/${slug}` - **FAILS**
3. Backend returns empty: `{ innings: [], _error: 'Scorecard not available' }`

#### 3. ✅ Commentary (`/match/155398/commentary?page=1&limit=10`)
**Status:** **WORKING**  
**Response:**
```json
{
  "success": true,
  "data": [
    {
      "id": "1780079009866",
      "innings_number": 2,
      "over": null,
      "ball": null,
      "event": "ball",
      "text": "And then there were two. The IPL 2026 final is set...",
      "runs": 0,
      "is_wicket": false,
      "is_four": false,
      "is_six": false,
      "is_boundary": false,
      "batsman": "",
      "bowler": "",
      "timestamp": 1780079009866
    }
    // ... more items
  ],
  "pagination": {
    "page": 1,
    "limit": 10,
    "total": 20,
    "pages": 2
  }
}
```

**Backend File:** `cricket-api/src/providers/cricbuzz/client.js` (line 300)  
**Method:** `getCommentary(matchId)` - calls `/comm/${matchId}` - **WORKING**

---

## Problem Classification

### Scorecard Issue
**Classification:** **Case B - Backend provider/scraper incomplete**

The backend endpoint `/match/:id/scorecard` is correctly implemented in the route handler (`cricket-api/src/routes/matches.js` line 336), but the Cricbuzz provider's `getScorecard` method is failing to fetch data from Cricbuzz.

**Possible Reasons:**
1. Cricbuzz JSON API endpoint changed or requires authentication
2. Cricbuzz HTML structure changed, breaking the HTML parser
3. Match ID format mismatch between our system and Cricbuzz
4. Cricbuzz rate limiting or blocking requests
5. Scorecard genuinely not available for this specific match on Cricbuzz

### Commentary Issue  
**Classification:** **Case D - Commentary endpoint returns real data**

Commentary is working perfectly. The backend successfully fetches data from Cricbuzz `/comm/${matchId}` endpoint.

**Flutter Issue:** The Flutter UI was looking for `data['items']` or `data['commentary']`, but the API returns the array directly in `data`. This has been fixed in the Flutter code.

---

## Backend Code Analysis

### Scorecard Implementation

**File:** `cricket-api/src/providers/cricbuzz/client.js`

```javascript
async getScorecard(matchId, matchInfo = null) {
  // Try JSON API first
  let jsonData = null;
  try {
    jsonData = await request(mcenterClient, `/scorecard/${matchId}`);
    
    // Validate JSON response
    if (jsonData && jsonData.innings && jsonData.innings.length > 0) {
      logger.info({ msg: 'Scorecard JSON data found', matchId, innings: jsonData.innings.length });
      return jsonData;
    }
  } catch (jsonErr) {
    logger.warn({ msg: 'JSON scorecard failed, trying HTML fallback', matchId, error: jsonErr.message });
  }
  
  // JSON failed or empty, try HTML fallback
  try {
    // Build slug from match info if available
    let slug = 'scorecard';
    if (matchInfo && matchInfo.title) {
      slug = matchInfo.title.toLowerCase()
        .replace(/[^a-z0-9\s]/g, '')
        .replace(/\s+/g, '-')
        .slice(0, 50);
    }
    
    const html = await request(htmlClient, `/live-cricket-scorecard/${matchId}/${slug}`, { responseType: 'text' });
    const htmlData = parseScorecardFromHtml(html, matchId);
    
    if (htmlData.innings && htmlData.innings.length > 0) {
      logger.info({ msg: '[FIXED] Scorecard HTML data found', matchId, innings: htmlData.innings.length });
      return htmlData;
    }
  } catch (htmlErr) {
    logger.error({ msg: 'HTML scorecard fallback also failed', matchId, error: htmlErr.message });
  }
  
  // Both failed
  return { innings: [], _error: 'Scorecard not available' };
}
```

**Issues:**
1. No logging of actual error details from Cricbuzz
2. No retry mechanism
3. No alternative data sources
4. `matchInfo` parameter is not being passed from route handler

### Route Handler

**File:** `cricket-api/src/routes/matches.js` (line 336)

```javascript
fastify.get('/match/:id/scorecard', {
  // ... schema ...
  preHandler: cacheMiddleware((req) => KEYS.matchScorecard(req.params.id), TTL.SCORECARD),
}, async (request, reply) => {
  const { id } = request.params;
  try {
    // [FIXED] Validate data before caching - don't cache empty failures
    let data = await cacheGet(KEYS.matchScorecard(id));
    let fromCache = !!data;
    
    if (!data) {
      const result = await providerManager.execute('getScorecard', id);
      data = result?.data || null;
      
      // [FIXED] Only cache if we have valid scorecard data
      if (data && data.innings && data.innings.length > 0) {
        await cacheSet(KEYS.matchScorecard(id), data, TTL.SCORECARD);
      } else {
        logger.warn({ msg: '[FIXED] Not caching empty scorecard', matchId: id, innings: data?.innings?.length });
        fromCache = false;
      }
    }

    reply.header('X-Cache', fromCache ? 'HIT' : 'MISS');
    
    if (data && data.innings && data.innings.length > 0) {
      return { success: true, data, fromCache };
    }
  } catch (err) { 
    logger.error({ msg: '[FIXED] Scorecard fetch failed', matchId: id, error: err.message });
  }

  // Scorecard not available — return empty but valid response (never 404)
  return {
    success: true,
    data: { innings: [], scorecard_available: false },
    fromCache: false,
    message: 'Scorecard not available for this match',
  };
});
```

**Issue:** Route handler doesn't pass match info to `getScorecard`, so HTML fallback uses generic slug.

---

## Flutter Code Status

### Home Screen
**Status:** ✅ Fixed  
**Changes Made:**
- Removed hardcoded `_liveHero` with NZ vs WI data
- Removed `_heroForTab()` method that returned hardcoded heroes
- Updated `_heroFromMatches()` to return empty hero when no matches
- Hero card now only shows when real API data exists
- No fake live matches shown when `/matches/live` is empty

**Files Changed:**
- `lib/screens/home/home_screen.dart`

### Commentary Tab
**Status:** ✅ Fixed (pending verification)  
**Changes Made:**
- Updated commentary panel to look for array directly in `data` field
- Added debug logging to verify data structure
- Added import for `kDebugMode`

**Files Changed:**
- `lib/screens/match_details/match_details_screen.dart`

### Scorecard Tab
**Status:** ⚠️ Correct (shows proper empty state)  
**Current Behavior:** Shows "Scorecard is not available from the provider yet" for finished matches  
**This is CORRECT** because backend genuinely returns empty data.

---

## Required Fixes

### Priority 1: Fix Backend Scorecard Fetching

**Option A: Debug Cricbuzz API**
1. Add detailed logging to see actual Cricbuzz responses
2. Check if Cricbuzz API endpoint changed
3. Verify match ID format
4. Check for authentication requirements
5. Test with different match IDs

**Option B: Alternative Data Source**
1. Check if Cricbuzz website has scorecard for match 155398
2. If yes, update HTML parser
3. If no, find alternative cricket data API

**Option C: Manual Verification**
Visit: `https://www.cricbuzz.com/live-cricket-scorecard/155398`  
Check if scorecard exists on Cricbuzz website.

### Priority 2: Verify Flutter Commentary Fix

Run the app and navigate to match 155398 commentary tab to verify:
1. Commentary items load
2. No "not available" message
3. Filters work
4. Pagination works

---

## Testing Commands

### Backend Testing
```bash
# Test scorecard endpoint
curl.exe https://api.webcrichd.co/match/155398/scorecard

# Test commentary endpoint  
curl.exe "https://api.webcrichd.co/match/155398/commentary?page=1&limit=10"

# Test with different match
curl.exe https://api.webcrichd.co/match/150964/scorecard
```

### Backend Logs
```bash
cd cricket-api
npm run dev
# Watch logs for scorecard fetch attempts
```

### Flutter Testing
```bash
flutter pub get
flutter analyze
flutter run -d chrome
# Navigate to match 155398
# Check Commentary tab
# Check Scorecard tab
```

---

## Conclusion

### What's Working
✅ Home screen now uses real API data only  
✅ Commentary endpoint returns data  
✅ Flutter commentary parser fixed  
✅ No hardcoded mock data in production  

### What's Not Working
❌ Backend scorecard fetching from Cricbuzz  
❌ Scorecard tab shows empty (correct behavior given backend issue)  

### Next Steps
1. **Investigate Cricbuzz scorecard availability** - Check if data exists on Cricbuzz website
2. **Add detailed backend logging** - See exact Cricbuzz API responses
3. **Test with multiple matches** - Verify if issue is match-specific or systemic
4. **Consider alternative data sources** - If Cricbuzz doesn't provide scorecards
5. **Verify Flutter commentary fix** - Run app and test commentary tab

### Important Note
**DO NOT** say "production ready" until scorecard data is proven to work OR we confirm that Cricbuzz genuinely doesn't provide scorecard data for these matches and document this limitation clearly.

---

## Files Modified

### Flutter
1. `lib/screens/home/home_screen.dart` - Removed hardcoded hero data
2. `lib/screens/match_details/match_details_screen.dart` - Fixed commentary parsing

### Backend
No backend files modified yet - investigation phase only.

---

## Recommendations

1. **Immediate:** Check if Cricbuzz website has scorecard for match 155398
2. **Short-term:** Add detailed error logging to Cricbuzz client
3. **Medium-term:** Implement alternative scorecard data source if Cricbuzz fails
4. **Long-term:** Add health checks for all data providers

