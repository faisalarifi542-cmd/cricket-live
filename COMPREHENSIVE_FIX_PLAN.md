# Comprehensive Real Data Fix Plan

## Executive Summary

The app has **backend data scraping issues**, not frontend problems. Cricbuzz pages contain real data, but the backend isn't parsing it correctly. This document outlines all required fixes.

---

## ✅ COMPLETED: Backend Scorecard Fix

### Status: DEPLOYED AND WORKING ✅

The scorecard endpoint is now returning complete batting and bowling data!

**Test Result**:
```bash
curl "https://api.webcrichd.co/match/155398/scorecard"
```

**Returns**:
- ✅ Both innings (RR and GT)
- ✅ Complete batting statistics (runs, balls, fours, sixes, strike rate, dismissals)
- ✅ Complete bowling figures (overs, runs, wickets, economy)
- ✅ Fall of wickets
- ✅ Partnerships
- ✅ Extras breakdown

### Changes Made
**File**: `cricket-api/src/providers/cricbuzz/client.js`

1. **Enhanced `getScorecard()` with multiple slug strategies**
   - Strategy 1: Fetch match info to build proper slug (e.g., `gt-vs-rr-qualifier-2-indian-premier-league-2026`)
   - Strategy 2: Use provided matchInfo if available
   - Strategy 3: Generic fallback

2. **Fixed JSON validation logic**
   - Check for `batTeamDetails.batsmenData` and `bowlTeamDetails.bowlersData`
   - Validate that innings have actual data, not just empty arrays
   - Return data in format normalizer expects: `{ scoreCard: innings }`

3. **Completely rewritten `parseScorecardFromHtml()` (fallback)**
   - Strategy 1: Extract from Next.js JSON payloads (`self.__next_f.push()`)
   - Strategy 2: Traditional HTML parsing (fallback)
   - Strategy 3: Meta tag extraction (last resort)

### Commits
- `c84a508` - Initial scorecard parser rewrite
- `90fdcae` - Fixed JSON validation logic

### Next Step: Flutter Integration
Verify the Flutter app can parse and display this data in the Scorecard tab.

---

## ✅ VERIFIED: Commentary Endpoint Works

### Current Status
```bash
curl "https://api.webcrichd.co/match/155398/commentary"
```

**Result**: ✅ Returns data correctly
```json
{
  "success": true,
  "data": [
    {
      "id": "...",
      "innings_number": 2,
      "over": "18",
      "ball": "4",
      "event": "six",
      "text": "...",
      "runs": 6,
      "is_wicket": false,
      "batsman": "Rahul Tewatia",
      "bowler": "Brijesh Sharma"
    }
  ],
  "cache": true
}
```

**Flutter Support**: Already handles this structure in `match_details_screen.dart`:
```dart
final source = apiList(widget.data['data'] ?? 
                      widget.data['items'] ??
                      widget.data['commentary']);
```

**Action**: No backend fix needed. If Flutter shows "Commentary not available", it's a UI bug, not backend.

---

## 🔴 TODO: Series Details Navigation Fix

### Problem
1. Series list shows real series
2. Tapping a series opens Series Details
3. Series Details says "Please select a series to view details"

### Root Cause
The `seriesId` is not being passed correctly from Series List to Series Detail screen.

### Files to Inspect
```
lib/screens/series/series_list_screen.dart
lib/screens/series/series_detail_screen.dart
lib/main.dart (route definitions)
lib/repositories/cricket_repository.dart
lib/services/cricket_api_service.dart
lib/models/api_models.dart
```

### Required Fix
1. **Verify series card tap handler**
   ```dart
   // In series_list_screen.dart
   onTap: () {
     if (kDebugMode) {
       debugPrint('Series tapped: id=$seriesId, name=$seriesName');
     }
     Navigator.pushNamed(
       context,
       '/series-detail',
       arguments: seriesId, // Must pass seriesId
     );
   }
   ```

2. **Verify Series Detail receives ID**
   ```dart
   // In series_detail_screen.dart
   @override
   void didChangeDependencies() {
     super.didChangeDependencies();
     final routeArg = ModalRoute.of(context)?.settings.arguments;
     if (routeArg is String && routeArg.isNotEmpty) {
       _seriesId = routeArg;
       if (kDebugMode) {
         debugPrint('SeriesDetail opened with seriesId=$_seriesId');
       }
       // Load series data
       _loadSeriesData();
     }
   }
   ```

3. **Remove any mock fallback data**
   - Search for "India vs Australia", "Australia Tour Of Pakistan" in series_detail_screen.dart
   - Replace with empty state or loading skeleton

---

## 🔴 TODO: Backend Series Endpoints

### Required Endpoints

#### 1. GET /series/:id
**Current**: May return empty or incomplete data
**Required**: Full series info
```json
{
  "success": true,
  "data": {
    "seriesId": "9241",
    "seriesName": "Indian Premier League 2026",
    "startDate": "2026-03-28",
    "endDate": "2026-05-31",
    "category": "League"
  }
}
```

#### 2. GET /series/:id/matches
**Cricbuzz Source**: `https://www.cricbuzz.com/cricket-series/9241/indian-premier-league-2026/matches`

**Strategy**:
1. Try JSON API first
2. Parse HTML page if JSON fails
3. Extract match list from Next.js RSC payload
4. Return normalized match array

**Required Response**:
```json
{
  "success": true,
  "data": [
    {
      "matchId": "155398",
      "seriesId": "9241",
      "seriesName": "Indian Premier League 2026",
      "matchDesc": "Qualifier 2",
      "team1": {
        "teamId": "64",
        "teamName": "Rajasthan Royals",
        "teamShortName": "RR"
      },
      "team2": {
        "teamId": "971",
        "teamName": "Gujarat Titans",
        "teamShortName": "GT"
      },
      "venue": {
        "name": "Maharaja Yadavindra Singh International Cricket Stadium"
      },
      "startTime": "2026-05-29T14:00:00.000Z",
      "state": "complete",
      "status": "Gujarat Titans won by 7 wkts"
    }
  ]
}
```

#### 3. GET /series/:id/teams (Squads)
**Cricbuzz Source**: `https://www.cricbuzz.com/cricket-series/9241/indian-premier-league-2026/squads`

**Required Response**:
```json
{
  "success": true,
  "data": [
    {
      "teamId": "971",
      "teamName": "Gujarat Titans",
      "teamShortName": "GT",
      "logoUrl": "https://static.cricbuzz.com/a/img/v1/0x0/i1/c860066/gujarat-titans.jpg",
      "players": [
        {
          "playerId": "11808",
          "name": "Shubman Gill",
          "role": "Batsman",
          "isCaptain": true
        }
      ]
    }
  ]
}
```

#### 4. GET /points-table/:seriesId
**Cricbuzz Source**: `https://www.cricbuzz.com/cricket-series/9241/indian-premier-league-2026/points-table`

**Current Status**: May have parser issues
**Required Response**:
```json
{
  "success": true,
  "data": {
    "seriesId": "9241",
    "groups": [
      {
        "name": "Points Table",
        "rows": [
          {
            "teamName": "Gujarat Titans",
            "matches": 14,
            "won": 9,
            "lost": 5,
            "points": 18,
            "nrr": "+0.123"
          }
        ]
      }
    ]
  }
}
```

#### 5. GET /series/:id/stats
**Cricbuzz API**: 
```
https://www.cricbuzz.com/api/cricket-series/series-stats/9241?statsType=mostRuns&seasonSeriesId=9241&matchFormat=3
```

**Stat Types**:
- `mostRuns`
- `highestScore`
- `highestAvg`
- `highestSr`
- `mostHundreds`
- `mostWickets`
- `lowestAvg`
- `bestBowlingInnings`

**Required Response**:
```json
{
  "success": true,
  "data": {
    "seriesId": "9241",
    "statsType": "mostRuns",
    "items": [
      {
        "rank": 1,
        "playerId": "11808",
        "playerName": "Shubman Gill",
        "teamName": "Gujarat Titans",
        "teamShortName": "GT",
        "imageId": "11808",
        "imageUrl": "https://static.cricbuzz.com/a/img/v1/i1/c11808/shubman-gill.jpg",
        "value": "851 runs"
      }
    ]
  }
}
```

### Implementation Files
```
cricket-api/src/providers/cricbuzz/client.js
cricket-api/src/providers/cricbuzz/normalizer.js
cricket-api/src/routes/series.js
```

---

## 🔴 TODO: Team Logo/Image Handling

### Problem
Team logos and player images not displaying correctly.

### Cricbuzz Image Formats

**Team Logo**:
```
https://static.cricbuzz.com/a/img/v1/0x0/i1/c860066/sunrisers-hyderabad.jpg
```

**Player Image**:
```
https://static.cricbuzz.com/a/img/v1/i1/c781069/ruturaj-gaikwad.jpg?d=low&p=gthumb
```

**Generic Format**:
```
https://static.cricbuzz.com/a/img/v1/i1/c{imageId}/i.jpg
```

### Backend Normalization Required
```javascript
// In normalizer.js
{
  "imageId": "860066",
  "logoUrl": "https://static.cricbuzz.com/a/img/v1/0x0/i1/c860066/team-slug.jpg",
  "imageUrl": "https://static.cricbuzz.com/a/img/v1/i1/c860066/i.jpg"
}
```

### Flutter Handling
```dart
// Use logoUrl if available
if (team.logoUrl != null && team.logoUrl!.isNotEmpty) {
  return CachedNetworkImage(imageUrl: team.logoUrl!);
}
// Build from imageId if only ID exists
else if (team.imageId != null) {
  final url = 'https://static.cricbuzz.com/a/img/v1/i1/c${team.imageId}/i.jpg';
  return CachedNetworkImage(imageUrl: url);
}
// Fallback to initials
else {
  return CircleAvatar(child: Text(team.teamShortName));
}
```

---

## 🔴 TODO: Match Details Hero Card

### Problem
- Series title shows "Cricket Match" instead of real series name
- Hero shows only one score instead of both innings
- Result text incomplete

### Required Data Mapping
```dart
// From /match/:id endpoint
final match = CricketMatch.fromJson(data);

// Hero should show:
- match.seriesName (not "Cricket Match")
- match.team1.score (e.g., "RR 214/6 (20.0)")
- match.team2.score (e.g., "GT 219/3 (18.4)")
- match.result (e.g., "Gujarat Titans won by 7 wkts")
```

### Files to Fix
```
lib/components/match_components.dart (MatchDetailHeroCard)
lib/models/cricket_match.dart (CricketMatch model)
lib/repositories/cricket_repository.dart (matchDetail method)
```

---

## 🔴 TODO: Match Details Tab Row Clipping

### Problem
Tab labels clipped: "Scorecard" → "ecard", "Squads" → "Sq"

### Fix
```dart
// In match_details_screen.dart
ScrollableSegmentedTabs(
  items: const [
    'Scorecard',
    'Commentary',
    'Overs',
    'Info',
    'Squads'
  ],
  selected: tab,
  onChanged: _setTab,
  height: 52,
  // Ensure horizontal scrolling enabled
  // Ensure initial scroll position is left
  // Ensure selected tab remains visible
)
```

---

## 🔴 TODO: Remove All Production Mock Data

### Search Commands
```bash
# PowerShell
Select-String -Path lib/**/*.dart,cricket-api/src/**/*.js -Pattern "mock","demo","sample","dummy","hardcoded","India vs Australia","Australia Tour Of Pakistan","India Tour Of Australia","New Zealand Tour","Williamson","Ravindra","fake","static"
```

### Decision Matrix
| Pattern | Action |
|---------|--------|
| `kDebugMode` guarded | ✅ Keep (debug only) |
| Image fallback / initials | ✅ Keep (valid fallback) |
| Fake match/series/player data | ❌ Remove |
| Fake fallback when API fails | ❌ Remove |

### Replace With
- Loading skeleton
- Empty state with message
- Retry/error state
- **Never** mock data in production paths

---

## Deployment Checklist

### Backend
- [ ] Commit scorecard parser changes
- [ ] Implement series endpoints
- [ ] Fix points table parser
- [ ] Add series stats endpoints
- [ ] Normalize image URLs
- [ ] Run `npm run lint`
- [ ] Deploy to production
- [ ] Restart backend service

### Backend Testing
```bash
# Scorecard
curl "https://api.webcrichd.co/match/155398/scorecard"

# Commentary (already works)
curl "https://api.webcrichd.co/match/155398/commentary"

# Series
curl "https://api.webcrichd.co/series/9241"
curl "https://api.webcrichd.co/series/9241/matches"
curl "https://api.webcrichd.co/series/9241/teams"
curl "https://api.webcrichd.co/points-table/9241"
curl "https://api.webcrichd.co/series/9241/stats?type=mostRuns"
```

### Flutter
- [ ] Fix Series Detail navigation
- [ ] Remove production mock data
- [ ] Fix Match Details hero card
- [ ] Fix tab row clipping
- [ ] Improve image/logo handling
- [ ] Run `flutter analyze`
- [ ] Test on Chrome

### Manual Verification
- [ ] Match 155398 scorecard displays
- [ ] Commentary tab shows real items
- [ ] Series Detail opens with correct ID
- [ ] No "Please select a series" after tapping
- [ ] Team logos display
- [ ] Player images display
- [ ] No mock "India vs Australia" data
- [ ] Tabs not clipped

---

## Success Criteria

✅ **Backend**:
- Scorecard returns non-empty innings for match 155398
- Commentary returns items (already works)
- Series endpoints return real data
- Points table returns team standings
- Series stats return player stats

✅ **Flutter**:
- Series Detail opens with correct seriesId
- Match Details shows real series name
- Scorecard tab displays batting/bowling tables
- Commentary tab displays real commentary
- Squads tab shows player names
- Team logos and player images display
- No mock/fake data in production

✅ **User Experience**:
- No "unavailable" messages when data exists
- No mock India vs Australia data
- Clean empty states when data doesn't exist
- Proper error states with retry option

---

## Priority Order

1. **HIGH**: Deploy backend scorecard fix (code complete)
2. **HIGH**: Fix Series Detail navigation (Flutter)
3. **MEDIUM**: Implement series endpoints (Backend)
4. **MEDIUM**: Fix Match Details hero card (Flutter)
5. **LOW**: Fix tab clipping (Flutter)
6. **LOW**: Improve image handling (Backend + Flutter)
7. **CLEANUP**: Remove all mock data (Flutter)

---

**Status**: Backend scorecard fix complete, awaiting deployment and testing
**Next Step**: Deploy backend changes, then fix Flutter Series Detail navigation
