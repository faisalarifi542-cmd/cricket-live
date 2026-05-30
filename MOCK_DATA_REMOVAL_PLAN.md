# Mock Data Removal - Complete Fix Plan

**Date:** May 30, 2026  
**Priority:** CRITICAL - User reports mock data still visible in running app

---

## Problem Statement

User manually tested the app and found:
1. ❌ Series Details shows "India vs Australia" mock data
2. ❌ Team logos not loading correctly
3. ❌ Commentary tab not showing real data
4. ❌ Scorecard tab not showing real data

---

## Root Cause Analysis

### 1. Series Detail Screen Issues

**File:** `lib/screens/series/series_detail_screen.dart`

**Problems:**
- Line 102: `const SeriesHeroCard()` - ALWAYS shows hardcoded "India Tour of Australia 2024-25"
- Lines 127-136: When `_seriesId.isEmpty`, shows mock components:
  - `SeriesOverviewTab` - hardcoded India vs Australia
  - `SeriesMatchesTab` - hardcoded match rows
  - `SeriesStatsTab` - hardcoded stats

**Why it happens:**
- Hero card is not conditional on API data
- Fallback components use `AppData` mock data from `lib/models.dart`

### 2. Series Components Using Mock Data

**File:** `lib/components/series_components.dart`

**Problems:**
- `SeriesHeroCard` (line 18): Hardcoded "India Tour of Australia"
- `SeriesOverviewTab` (line 223): Uses `AppData.seriesOverviewStats`
- `SeriesMatchesTab` (line 791): Uses `AppData.seriesUpcomingRows`
- `SeriesMatchesTab` (line 801): Uses `AppData.seriesCompletedRows`

### 3. Home Screen Mock Data

**File:** `lib/screens/home/home_screen.dart`

**Problems:**
- Line 230: Uses `AppData.upcomingSeries` for upcoming series cards

### 4. Other Mock Data Sources

**Files:**
- `lib/models.dart` - Contains `AppData` class with all mock data
- `lib/data/mock_data.dart` - Exports mock data
- `lib/data/mock_matches.dart` - Contains `MockMatches` class
- `lib/widgets/live_match_mini_card.dart` - Default values "NZ vs WI"
- `lib/screens/rankings/rankings_screen.dart` - Hardcoded player rankings

---

## API Endpoint Analysis

### Available Endpoints

1. ✅ `/series` - Returns list of series
2. ✅ `/series/:id/matches` - Returns matches for series (but endpoint is `/series/:id`)
3. ✅ `/series/:id/teams` - Returns teams
4. ⚠️ `/series/:id` - Returns MATCHES, not series metadata
5. ❌ No endpoint for series details (name, dates, format, venues)

### Solution for Series Details

Since there's no dedicated series detail endpoint, we must:
1. Extract series info from the first match in `/series/:id` response
2. All matches have: `series_id`, `series_name`, `match_format`
3. Calculate date range from match `start_time` fields
4. Get teams from `/series/:id/teams`

---

## Fix Strategy

### Phase 1: Remove All Mock Data from Production Path ✅

1. **Series Hero Card** - Make it API-driven or remove it
2. **Series Overview Tab** - Use real API data or show empty state
3. **Series Matches Tab** - Use real API matches only
4. **Series Stats Tab** - Use real API stats or show empty state
5. **Home Upcoming Series** - Use real API or remove section
6. **Live Match Mini Card** - Remove default "NZ vs WI"

### Phase 2: Fix Logo Parsing ✅

Already done in previous task, but verify it works in running app.

### Phase 3: Fix Commentary Parsing ✅

Already done in previous task, but verify it works in running app.

### Phase 4: Verify Scorecard Empty State ✅

Already correct - shows proper empty state when backend returns empty.

---

## Implementation Plan

### Step 1: Create API-Driven Series Hero Card

**New Component:** `_SeriesApiHeroCard`

```dart
class _SeriesApiHeroCard extends StatelessWidget {
  final Map<String, dynamic> seriesData;
  final List<dynamic> teams;
  
  // Extract from first match:
  // - series_name
  // - match_format
  // Calculate date range from all matches
  // Show first 2 teams from teams list
}
```

### Step 2: Update Series Detail Screen

**Changes to `lib/screens/series/series_detail_screen.dart`:**

1. Remove `const SeriesHeroCard()` on line 102
2. Add conditional hero based on API data:
   ```dart
   if (_seriesId.isNotEmpty && _seriesData != null)
     _SeriesApiHeroCard(data: _seriesData, teams: _teams)
   else
     _EmptySeriesHero()
   ```

3. Remove fallback to mock components (lines 127-136)
4. Always show `_SeriesApiPanel` when `_seriesId.isNotEmpty`
5. Show error/empty state when `_seriesId.isEmpty`

### Step 3: Update Series Overview API Panel

**Changes to `_SeriesOverviewApiPanel`:**

1. Extract series info from matches
2. Show real match count, format, dates
3. Remove hardcoded venues, form, insights
4. Show only what API provides

### Step 4: Remove Mock Data from Home Screen

**Changes to `lib/screens/home/home_screen.dart`:**

1. Remove `AppData.upcomingSeries` usage (line 230)
2. Either:
   - Fetch upcoming series from API
   - Or remove "Upcoming Series" section entirely

### Step 5: Clean Up Mock Data Files

**Do NOT delete files** (may break imports), but:
1. Add warning comments at top of each mock file
2. Ensure no production code path uses them
3. Only allow usage in:
   - Debug/demo mode with `kDebugMode` guard
   - Storybook/preview components
   - Tests

---

## Testing Checklist

### Manual Testing Required

1. **Series List**
   - [ ] Shows real series from API
   - [ ] No mock data visible

2. **Series Detail - IPL 2026**
   - [ ] Hero card shows "Indian Premier League 2026" (from API)
   - [ ] Overview tab shows real match count
   - [ ] Matches tab shows real matches (RR vs GT, etc.)
   - [ ] Teams tab shows real teams (10 IPL teams)
   - [ ] Stats tab shows real stats or proper empty state
   - [ ] NO "India vs Australia" anywhere
   - [ ] NO "Border-Gavaskar Trophy"
   - [ ] NO hardcoded venues

3. **Home Screen**
   - [ ] No "India vs England" upcoming series cards
   - [ ] Only real API data visible

4. **Match Details - 155398**
   - [ ] Team logos load (RR and GT)
   - [ ] Commentary tab shows 20 items
   - [ ] Scorecard shows proper empty state

5. **Logos Everywhere**
   - [ ] Home hero card
   - [ ] Match cards
   - [ ] Series matches
   - [ ] Team details

---

## Files to Modify

### Critical (Must Fix)
1. `lib/screens/series/series_detail_screen.dart` - Remove mock hero, fix fallbacks
2. `lib/components/series_components.dart` - Make hero API-driven or remove
3. `lib/screens/home/home_screen.dart` - Remove upcoming series mock data

### Important (Should Fix)
4. `lib/widgets/live_match_mini_card.dart` - Remove "NZ vs WI" defaults
5. `lib/models.dart` - Add warning comments to `AppData` class

### Optional (Nice to Have)
6. `lib/screens/rankings/rankings_screen.dart` - Note that rankings are mock
7. `lib/data/mock_data.dart` - Add warning comment
8. `lib/data/mock_matches.dart` - Add warning comment

---

## Success Criteria

✅ **Production Ready When:**
1. Series Detail shows ONLY real API data for IPL 2026
2. No "India vs Australia" visible anywhere
3. No "Border-Gavaskar Trophy" visible
4. Team logos load from `logo_url` fields
5. Commentary shows 20 items for match 155398
6. Scorecard shows proper empty state
7. Home screen shows no mock upcoming series
8. Flutter analyze passes
9. User manually verifies in Chrome

❌ **NOT Production Ready If:**
- Any hardcoded match/series/team names visible
- Any mock data in production UI path
- Logos don't load
- Commentary empty when API has data

---

## Next Steps

1. Implement fixes in order listed above
2. Test each fix individually
3. Run `flutter analyze`
4. Run `flutter run -d chrome`
5. Manual verification by user
6. Create final report with proof

