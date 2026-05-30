# Quick Testing Guide

## Run the App

```bash
flutter run -d chrome
```

## What to Test

### 1. Team Logos (2 minutes)
1. Open the app
2. Look at the home screen hero card - **should show team logos** (not just initials)
3. Scroll down to match cards - **should show team logos**
4. Tap any match to open details - **should show team logos in hero card**
5. Go back, tap "More" → "Series" → tap any series → **should show team logos in matches**

**Expected:** Team logos load from URLs like `https://static.cricbuzz.com/a/img/v1/i1/c860055/i.jpg`  
**Fallback:** If image fails, shows initials (RR, GT, etc.)

---

### 2. Commentary Tab (1 minute)
1. From home, tap match ID **155398** (RR vs GT)
2. Tap **Commentary** tab
3. **Should see timeline cards** with commentary text
4. Try filters: All, Wickets, Boundaries, Key Events

**Expected:** 20 commentary items displayed  
**If empty:** Check browser console (F12) for debug output

---

### 3. Series Screens (2 minutes)
1. Tap "More" → "Series"
2. **Should see real series:** IPL 2026, India Women Tour, etc.
3. Tap "Indian Premier League 2026"
4. **Overview tab:** Should show series details
5. **Matches tab:** Should show real matches
6. **Squads tab:** Should show real teams
7. **Stats tab:** Should show points table/stats
8. Tap any match → **should open Match Details with real data**

**Expected:** No "demo data" labels anywhere  
**Expected:** All navigation uses real IDs

---

### 4. Scorecard Tab (30 seconds)
1. Open match 155398
2. Tap **Scorecard** tab
3. **Should show empty state:** "Scorecard is not available from the provider yet"

**Expected:** Empty state message (this is a backend limitation)  
**Expected:** No crashes or errors

---

## Quick Verification Checklist

- [ ] Team logos visible on home screen
- [ ] Team logos visible in match details
- [ ] Commentary tab shows timeline cards (match 155398)
- [ ] Series list shows real series (no mock data)
- [ ] Series detail shows real matches
- [ ] Tapping series match opens Match Details
- [ ] Scorecard shows proper empty state
- [ ] No "demo data" labels visible
- [ ] No crashes or errors

---

## If Something Doesn't Work

### Logos Not Loading
1. Open browser console (F12)
2. Check for network errors
3. Verify URL format: `https://static.cricbuzz.com/a/img/v1/i1/c{imageId}/i.jpg`
4. Check if initials fallback appears

### Commentary Empty
1. Open browser console (F12)
2. Look for debug output: "Commentary data keys: ..."
3. Check if API returns data: `curl "https://api.webcrichd.co/match/155398/commentary?page=1&limit=50"`

### Series Shows Mock Data
1. This should NOT happen - series screens use real API only
2. If you see mock data, report which screen and what data

---

## Backend Testing (Optional)

```bash
# Test recent matches (should show logo_url)
curl https://api.webcrichd.co/matches/recent

# Test commentary (should return 20 items)
curl "https://api.webcrichd.co/match/155398/commentary?page=1&limit=50"

# Test scorecard (will return empty - known issue)
curl https://api.webcrichd.co/match/155398/scorecard

# Test series (should return 9 series)
curl https://api.webcrichd.co/series
```

---

## Report Results

After testing, report:
1. ✅ or ❌ for each checklist item
2. Any errors in browser console
3. Screenshots of issues (if any)
4. Which match IDs you tested

---

## Expected Outcome

**Working:**
- ✅ Team logos display correctly
- ✅ Commentary shows timeline cards
- ✅ Series uses real API data
- ✅ No mock/demo data visible

**Known Limitation:**
- ⚠️ Scorecard returns empty (backend provider issue)
- ⚠️ This is NOT a Flutter bug
- ⚠️ Proper empty state message shown
