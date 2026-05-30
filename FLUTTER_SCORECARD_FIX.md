# Flutter Scorecard Display Fix

## Problem

The backend was returning complete scorecard data, but the Flutter app was showing "Scorecard is not available from the provider yet."

## Root Cause

The Flutter scorecard panel was checking for `scorecard_available == false` field, which the backend no longer includes in the response. This caused the app to show an error message even when valid innings data was present.

**Old validation logic**:
```dart
if (widget.data['scorecard_available'] == false || innings.isEmpty) {
  return _MatchDataStateCard(
    text: 'Scorecard is not available from the provider yet.',
  );
}
```

## The Fix

**File**: `lib/screens/match_details/match_details_screen.dart`

Changed the validation to check if innings actually contain batting/bowling data:

```dart
final innings = apiList(widget.data['innings']);

// Check if innings data is actually empty (no batting/bowling data)
final hasData = innings.isNotEmpty && innings.any((inn) {
  final inningsMap = apiMap(inn);
  final batting = apiList(inningsMap['batting'] ?? inningsMap['batters'] ?? inningsMap['batsmen']);
  final bowling = apiList(inningsMap['bowling'] ?? inningsMap['bowlers']);
  return batting.isNotEmpty || bowling.isNotEmpty;
});

if (!hasData) {
  // Show error message
}
```

## Backend Response Structure

The backend returns scorecard data in this format:

```json
{
  "success": true,
  "data": {
    "innings": [
      {
        "innings_number": 1,
        "batting_team": "Rajasthan Royals",
        "batting_team_id": "64",
        "total": {
          "runs": 214,
          "wickets": 6,
          "overs": 20
        },
        "run_rate": 10.7,
        "extras": {
          "total": 6,
          "byes": 0,
          "leg_byes": 0,
          "wides": 6,
          "no_balls": 0,
          "penalty": 0
        },
        "batting": [
          {
            "player_id": "13940",
            "name": "Yashasvi Jaiswal",
            "runs": 1,
            "balls": 2,
            "fours": 0,
            "sixes": 0,
            "strike_rate": 50,
            "dismissal": "c Prasidh Krishna b Mohammed Siraj",
            "is_batting": false,
            "is_striker": false,
            "position": 0
          }
          // ... more batsmen
        ],
        "bowling": [
          {
            "player_id": "",
            "name": "Mohammed Siraj",
            "overs": 4,
            "maidens": 0,
            "runs": 42,
            "wickets": 1,
            "economy": 10.5,
            "dots": 0,
            "wides": 5,
            "no_balls": 0,
            "is_bowling": false
          }
          // ... more bowlers
        ],
        "fall_of_wickets": [
          {
            "wicket_number": 1,
            "runs": 2,
            "overs": 0.4,
            "player": "Yashasvi Jaiswal"
          }
          // ... more wickets
        ],
        "partnerships": [
          {
            "runs": 127,
            "balls": 65,
            "bat1": { "name": "Ravindra Jadeja", "runs": 41 },
            "bat2": { "name": "Vaibhav Sooryavanshi", "runs": 80 }
          }
          // ... more partnerships
        ]
      },
      {
        "innings_number": 2,
        "batting_team": "Gujarat Titans",
        // ... second innings data
      }
    ],
    "last_updated": "2026-05-30T01:46:28.535Z"
  },
  "fromCache": false
}
```

## Field Mapping

The Flutter code already supports both camelCase and snake_case fields:

### Innings Level
- `innings_number` / `inningsNumber`
- `batting_team` / `battingTeam` / `teamName`
- `batting_team_id` / `battingTeamId`
- `run_rate` / `runRate`
- `fall_of_wickets` / `fallOfWickets` / `fow`

### Batting Stats
- `player_id` / `playerId`
- `name` / `player_name` / `batsman`
- `runs`
- `balls`
- `fours`
- `sixes`
- `strike_rate` / `strikeRate`
- `dismissal`
- `is_batting` / `isBatting`
- `is_striker` / `isStriker`

### Bowling Stats
- `player_id` / `playerId`
- `name` / `player_name` / `bowler`
- `overs`
- `maidens`
- `runs` / `runs_conceded`
- `wickets`
- `economy`
- `dots`
- `wides`
- `no_balls` / `noBalls`
- `is_bowling` / `isBowling`

## Testing

### Backend Verification
```bash
curl "https://api.webcrichd.co/match/155398/scorecard"
```

**Result**: ✅ Returns complete innings data with batting and bowling statistics

### Flutter Analysis
```bash
flutter analyze
```

**Result**: ✅ No issues found

### Manual Testing Required

Run the Flutter app and verify:

1. **Match 155398 Scorecard Tab**:
   - [ ] Opens without "not available" error
   - [ ] Shows innings selector (RR vs GT)
   - [ ] Displays batting table with player names, runs, balls, fours, sixes, SR
   - [ ] Displays bowling table with bowler names, overs, runs, wickets, economy
   - [ ] Shows extras and total
   - [ ] Shows fall of wickets
   - [ ] Shows partnerships

2. **Commentary Tab**:
   - [ ] Displays commentary items (already has debug logging)
   - [ ] Shows batsman and bowler names
   - [ ] Shows runs and event types

3. **Team Logos**:
   - [ ] Team logos display from `logo_url` field
   - [ ] Fallback to initials if logo fails

## Changes Made

### Files Modified
- `lib/screens/match_details/match_details_screen.dart`
  - Removed `scorecard_available` check
  - Added validation for actual batting/bowling data
  - Changed error message from "not available from the provider" to "not available yet"

### Commits
- `83196e8` - fix: Remove scorecard_available check, validate actual innings data instead

## Next Steps

1. **Run the app**: `flutter run -d chrome`
2. **Navigate to match 155398**
3. **Open Scorecard tab**
4. **Verify data displays correctly**
5. **Test Commentary tab**
6. **Test other completed matches**

## Expected Behavior

### Before Fix
- Scorecard tab shows: "Scorecard is not available from the provider yet."
- Even though backend returns complete data

### After Fix
- Scorecard tab displays:
  - Innings selector tabs
  - Batting table with all statistics
  - Bowling table with all figures
  - Extras and totals
  - Fall of wickets
  - Partnerships

## Remaining Tasks

1. ✅ Backend scorecard fix (COMPLETE)
2. ✅ Flutter scorecard validation fix (COMPLETE)
3. ⏳ Manual testing in Chrome
4. ⏳ Series Details navigation fix
5. ⏳ Team logo display fix
6. ⏳ Remove mock data from production

## Success Criteria

✅ Backend returns non-empty innings for match 155398
✅ Flutter validates innings data correctly
✅ Flutter analyze passes with no issues
⏳ Scorecard tab displays batting/bowling tables
⏳ Commentary tab displays timeline items
⏳ Team logos load from logo_url
⏳ No "not available from provider" when data exists

---

**Status**: Code fix complete, awaiting manual testing
**Priority**: HIGH - Unblocks scorecard feature
**Impact**: Fixes scorecard display for all completed matches

