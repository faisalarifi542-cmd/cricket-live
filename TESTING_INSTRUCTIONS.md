# Live Player Quality Settings - Testing Instructions

## Quick Start

### 1. Run the App
```bash
cd "c:\Users\Faisal Arifi\Downloads\cricket-live-wip\cricket-live"
flutter run -d chrome
```

### 2. Navigate to Live Player
1. Open the app in Chrome
2. Go to **Matches** tab
3. Find match ID **129497** (or any live match)
4. Tap **Watch Live** button
5. Player screen opens

### 3. Test Settings Button
1. Wait for player to load
2. Look for **settings gear icon** in bottom control bar (right side)
3. Tap the settings icon
4. **Premium bottom sheet** should slide up from bottom

### 4. Verify Settings UI
Check that the bottom sheet shows:
- ✅ Header with "Stream Settings" title
- ✅ Settings icon in gradient circle
- ✅ Close button (X) in top-right
- ✅ "Stream Quality" section with icon
- ✅ Quality options: Auto, Full HD, HD, SD
- ✅ Each quality shows:
  - Quality code badge (AUTO, FHD, HD, SD)
  - Quality label (Auto, Full HD, HD, SD)
  - Resolution (Adaptive, 1080p, 720p, 480p)
  - Checkmark on selected quality (cyan color)
- ✅ "Current Server" section at bottom
- ✅ Server name displayed
- ✅ Dark glass background with cyan accents

### 5. Test Quality Switching
1. Tap a different quality option (e.g., HD)
2. Bottom sheet should close
3. Player should show loading indicator
4. Stream should reload with new quality
5. Quality badge in top-right should update
6. Open settings again - checkmark should be on selected quality

### 6. Test HLS Parsing
**Test Stream:** `https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8`

This stream should:
- Parse as HLS master playlist
- Detect multiple quality variants
- Show real quality options in settings

**To verify HLS parsing:**
1. Open browser DevTools (F12)
2. Go to Console tab
3. Look for any HLS parsing logs
4. Check Network tab for .m3u8 requests
5. If variants detected: settings will show real qualities
6. If parsing fails: settings will show fallback qualities (all same URL)

### 7. Test Single Server Layout
If the match has only one server:
- ✅ Should show compact server card below quality options
- ✅ No large "Server" section
- ✅ Compact card shows server icon, name, and checkmark
- ✅ Minimal vertical space used

If the match has multiple servers:
- ✅ Should show full "Server" section header
- ✅ List of server cards
- ✅ Each server shows quality, language, type
- ✅ Selected server has checkmark

### 8. Test Error Handling
**Test scenarios:**
1. **No stream URL**: Should show error message
2. **Invalid stream URL**: Should show retry button
3. **CORS blocked HLS**: Should fall back to quality buttons
4. **Network timeout**: Should continue with fallback
5. **Unsupported stream type**: Should show unsupported message

None of these should crash the app.

## Expected Behavior Summary

### Settings Button
- ✅ Opens premium bottom sheet
- ✅ Shows quality options
- ✅ Shows current server
- ✅ Smooth animation
- ✅ Can be closed by tapping X or outside

### HLS Parsing
- ✅ Automatically detects HLS master playlists
- ✅ Parses resolution and bandwidth
- ✅ Creates quality options from variants
- ✅ Resolves relative URLs
- ✅ Falls back gracefully if parsing fails
- ✅ 5 second timeout prevents hanging

### Quality Switching
- ✅ Disposes old controller safely
- ✅ Initializes new controller with quality URL
- ✅ Shows loading overlay
- ✅ Updates quality badge
- ✅ Updates checkmark in settings
- ✅ Preserves match info card

### Server Section
- ✅ Compact when single server
- ✅ Full list when multiple servers
- ✅ No wasted space
- ✅ Clean design

### Error Handling
- ✅ No crashes
- ✅ No blank screens
- ✅ Clear error messages
- ✅ Retry options when applicable
- ✅ Graceful fallbacks

## Known Limitations

1. **Web CORS**: HLS parsing may fail on web due to CORS restrictions. This is expected and handled gracefully.

2. **Fallback Qualities**: When HLS variants cannot be detected, all quality buttons use the same URL. This is intentional.

3. **Native Adaptive**: AUTO quality relies on the video player's native adaptive streaming logic.

## Troubleshooting

### Settings button does nothing
- Check browser console for errors
- Verify `onSettings` callback is wired correctly
- Check if `_selectedStream` is not null

### Bottom sheet doesn't show
- Check if modal bottom sheet is blocked
- Verify context is valid
- Check for overlay conflicts

### Quality switching fails
- Check network connectivity
- Verify stream URL is valid
- Check browser console for errors
- Try different quality option

### HLS parsing not working
- Check if stream is actually HLS (.m3u8)
- Verify network request succeeds
- Check for CORS errors in console
- Fallback should still work

### Player shows error
- Check stream URL validity
- Verify stream type is supported
- Check network connectivity
- Try different server/quality

## Success Criteria

All of these should work:
- ✅ Settings button opens bottom sheet
- ✅ Quality options are displayed
- ✅ Selected quality is highlighted
- ✅ Tapping quality switches stream
- ✅ Quality badge updates
- ✅ Server section is compact for single server
- ✅ HLS parsing works or falls back gracefully
- ✅ No crashes or blank screens
- ✅ Premium UI maintained
- ✅ Smooth user experience

## Manual Testing Checklist

- [ ] Run app on Chrome
- [ ] Navigate to live match
- [ ] Tap Watch Live
- [ ] Player loads successfully
- [ ] Tap settings gear icon
- [ ] Bottom sheet opens
- [ ] Quality options visible
- [ ] Current quality checked
- [ ] Server info shown
- [ ] Tap different quality
- [ ] Bottom sheet closes
- [ ] Stream switches
- [ ] Quality badge updates
- [ ] Open settings again
- [ ] New quality is checked
- [ ] Test with test stream URL
- [ ] Verify HLS parsing or fallback
- [ ] Test single server layout
- [ ] Test multiple server layout
- [ ] Test error scenarios
- [ ] Verify no crashes

## Report Template

After testing, report:

**Settings Gear:**
- Opens quality menu: YES/NO
- Bottom sheet appears: YES/NO
- UI looks premium: YES/NO

**HLS Variants:**
- Test stream parsed: YES/NO
- Qualities detected: [list them]
- Fallback works: YES/NO

**Quality Switching:**
- Switches successfully: YES/NO
- Badge updates: YES/NO
- Checkmark moves: YES/NO

**Server Layout:**
- Single server compact: YES/NO
- Multiple servers full: YES/NO

**Errors:**
- Any crashes: YES/NO
- Any blank screens: YES/NO
- Error messages clear: YES/NO

**Files Changed:**
- lib/screens/live/live_player_screen.dart

**Flutter Analyze:**
- Result: No issues found!

**Limitations:**
- [List any issues encountered]
