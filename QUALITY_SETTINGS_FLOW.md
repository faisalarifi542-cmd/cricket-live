# Live Player Quality Settings - Flow Diagram

## User Interaction Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    Live Player Screen                        │
│                                                              │
│  ┌────────────────────────────────────────────────────┐    │
│  │              Match Info Card                        │    │
│  │  [LIVE]  IND vs AUS - T20 World Cup                │    │
│  │  IND 180/5 (18.2)  VS  AUS 165/8 (20.0)           │    │
│  └────────────────────────────────────────────────────┘    │
│                                                              │
│  ┌────────────────────────────────────────────────────┐    │
│  │                                                     │    │
│  │         [LIVE]  Video Player  [HD] 💬 📊 🔗       │    │
│  │                                                     │    │
│  │                                                     │    │
│  │         ▶️ ⏪ ⏩  [00:45 / 02:30]  🔊 ⚙️ ⛶        │    │
│  │         ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━      │    │
│  └────────────────────────────────────────────────────┘    │
│                          ↓ Tap ⚙️                           │
│  ┌────────────────────────────────────────────────────┐    │
│  │  Quality: [AUTO] [FHD] [HD] [SD]                   │    │
│  └────────────────────────────────────────────────────┘    │
│                                                              │
│  ┌────────────────────────────────────────────────────┐    │
│  │  Server: 🖥️ Server 1 ✓                             │    │
│  └────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

## Settings Bottom Sheet

```
┌─────────────────────────────────────────────────────────────┐
│                                                              │
│  ┌────────────────────────────────────────────────────┐    │
│  │  ⚙️  Stream Settings                          ✕    │    │
│  ├────────────────────────────────────────────────────┤    │
│  │                                                     │    │
│  │  📺 Stream Quality                                  │    │
│  │                                                     │    │
│  │  ┌──────────────────────────────────────────────┐ │    │
│  │  │ [AUTO]  Auto          Adaptive          ✓   │ │    │
│  │  └──────────────────────────────────────────────┘ │    │
│  │                                                     │    │
│  │  ┌──────────────────────────────────────────────┐ │    │
│  │  │ [FHD]   Full HD       1080p             ○   │ │    │
│  │  └──────────────────────────────────────────────┘ │    │
│  │                                                     │    │
│  │  ┌──────────────────────────────────────────────┐ │    │
│  │  │ [HD]    HD            720p              ○   │ │    │
│  │  └──────────────────────────────────────────────┘ │    │
│  │                                                     │    │
│  │  ┌──────────────────────────────────────────────┐ │    │
│  │  │ [SD]    SD            480p              ○   │ │    │
│  │  └──────────────────────────────────────────────┘ │    │
│  │                                                     │    │
│  │  ┌──────────────────────────────────────────────┐ │    │
│  │  │ 🖥️  Current Server                           │ │    │
│  │  │     Server 1                            ✓   │ │    │
│  │  └──────────────────────────────────────────────┘ │    │
│  │                                                     │    │
│  └────────────────────────────────────────────────────┘    │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Technical Flow

### 1. Stream Selection Flow
```
User taps "Watch Live"
        ↓
_selectStream(stream)
        ↓
Reset quality state
        ↓
_loadStream(stream)
        ↓
Is HLS stream? ──No──→ Load directly
        ↓ Yes
_parseHlsQualities(url)
        ↓
Fetch master playlist
        ↓
Parse #EXT-X-STREAM-INF
        ↓
Extract resolutions
        ↓
Create HlsQuality objects
        ↓
Sort by rank
        ↓
Add AUTO option
        ↓
Update state
        ↓
Load stream with AUTO quality
```

### 2. HLS Parsing Flow
```
_parseHlsQualities(masterUrl)
        ↓
http.get(masterUrl) with 5s timeout
        ↓
Success? ──No──→ Silent fail → Fallback qualities
        ↓ Yes
Parse response.body
        ↓
For each line:
  Is #EXT-X-STREAM-INF? ──No──→ Continue
        ↓ Yes
  Extract RESOLUTION=WxH
        ↓
  Extract BANDWIDTH=N
        ↓
  Get next line (variant URL)
        ↓
  Resolve relative URL
        ↓
  Map resolution to quality
        ↓
  Create HlsQuality object
        ↓
Add to qualities list
        ↓
Sort by rank (0=Auto, 1=FHD, 2=HD, 3=SD)
        ↓
Insert AUTO at beginning
        ↓
Update _hlsQualities state
```

### 3. Quality Selection Flow
```
User taps settings gear
        ↓
_openSettings()
        ↓
Show modal bottom sheet
        ↓
Display _SettingsBottomSheet
        ↓
Show quality options:
  - HLS qualities if available
  - Fallback qualities if not
        ↓
User taps quality option
        ↓
onQualitySelected(quality)
        ↓
Close bottom sheet
        ↓
_loadStream(stream, quality: quality)
        ↓
Dispose old controller
        ↓
Create new controller with quality.url
        ↓
Initialize and play
        ↓
Update _selectedQuality state
        ↓
Quality badge updates
        ↓
Checkmark moves in settings
```

### 4. URL Resolution Flow
```
_resolveUrl(baseUrl, relativePath)
        ↓
Is absolute URL? ──Yes──→ Return as-is
        ↓ No
Parse baseUrl to URI
        ↓
Extract base path (directory)
        ↓
Append relative path
        ↓
Construct full URL:
  scheme://host:port/basePath/relativePath
        ↓
Return resolved URL
```

## State Management

### State Variables
```
_selectedStream: StreamSource?
  ↓ Current stream being played

_videoController: VideoPlayerController?
  ↓ Video player instance

_hlsQualities: List<HlsQuality>
  ↓ Parsed quality options from HLS

_selectedQuality: HlsQuality?
  ↓ Currently selected quality

_playerError: String?
  ↓ Error message if any
```

### State Updates
```
Stream Selection:
  _selectedStream = stream
  _hlsQualities = []
  _selectedQuality = null
  _playerError = null

HLS Parsing Complete:
  _hlsQualities = [parsed qualities]
  _selectedQuality = qualities.first (AUTO)

Quality Selection:
  _selectedQuality = selected quality
  _videoController = new controller
  _playerError = null (or error message)

Error Occurred:
  _playerError = error message
  _videoController = null
```

## Component Hierarchy

```
LivePlayerScreen
├── _LivePlayerHeader
├── _MatchInfoSection
│   ├── _MatchInfoCard
│   ├── _MatchInfoSkeleton
│   └── _MatchInfoUnavailable
├── _PlayerSurface
│   ├── VideoPlayer
│   ├── _PlayerPill (LIVE badge)
│   ├── _PlayerPill (Quality badge)
│   ├── _PlayerMiniIcon (controls)
│   └── VideoProgressIndicator
└── _StreamsSection
    ├── _QualityCard (for each quality)
    ├── _CompactServerCard (single server)
    ├── _StreamOption (multiple servers)
    ├── _StreamInfoRow
    └── _SecureStreamCard

Settings Bottom Sheet:
_SettingsBottomSheet
├── Header (title + close)
├── Quality Section
│   └── _QualityOption (for each quality)
└── Server Info Section
```

## Data Models

### HlsQuality
```
class HlsQuality {
  label: String       // "Full HD", "HD", "SD", "Auto"
  code: String        // "FHD", "HD", "SD", "AUTO"
  resolution: String  // "1080p", "720p", "480p", "Adaptive"
  url: String         // Variant playlist URL or master URL
  rank: int           // 0=Auto, 1=FHD, 2=HD, 3=SD, 4=Low
  bandwidth: int?     // Optional bandwidth in bps
}
```

### StreamSource (existing)
```
class StreamSource {
  id: String
  name: String
  url: String
  quality: String?
  label: String?
  language: String?
  streamType: String?
  isPremium: bool
  priority: int?
  status: String?
  
  // Computed properties:
  qualityLabel: String
  qualityCode: String
  type: String
  isHls: bool
  isDash: bool
  isExternal: bool
  isPlayable: bool
  isWorking: bool
  qualityRank: int
}
```

## Error Handling

### Error Scenarios
```
1. HLS Fetch Timeout (5s)
   ↓
   Silent fail
   ↓
   Use fallback qualities
   ↓
   Continue playback

2. Network Error
   ↓
   Catch exception
   ↓
   Use fallback qualities
   ↓
   Continue playback

3. CORS Error (Web)
   ↓
   Fetch fails
   ↓
   Use fallback qualities
   ↓
   Continue playback

4. Malformed Playlist
   ↓
   Parse fails
   ↓
   Use fallback qualities
   ↓
   Continue playback

5. Invalid Stream URL
   ↓
   Controller init fails
   ↓
   Show error message
   ↓
   Offer retry button

6. Unsupported Stream Type
   ↓
   Detect before loading
   ↓
   Show unsupported message
   ↓
   Suggest another server
```

## Quality Priority Logic

```
┌─────────────────────────────────────────┐
│  Quality Source Priority                │
├─────────────────────────────────────────┤
│                                          │
│  1. Admin Streams (API)                 │
│     ↓ Different URLs for each quality   │
│     ↓ Explicit quality field            │
│                                          │
│  2. HLS Master Playlist Variants        │
│     ↓ Parsed from .m3u8                 │
│     ↓ Real quality URLs                 │
│                                          │
│  3. Fallback Quality Buttons            │
│     ↓ Same URL for all                  │
│     ↓ Visual selection only             │
│                                          │
└─────────────────────────────────────────┘
```

## Server Layout Logic

```
┌─────────────────────────────────────────┐
│  Server Count Check                     │
├─────────────────────────────────────────┤
│                                          │
│  serverStreams.length > 1?              │
│         ↓ Yes          ↓ No             │
│         ↓              ↓                 │
│  Full Server List   Compact Card        │
│         ↓              ↓                 │
│  ┌──────────────┐  ┌──────────────┐    │
│  │ Server 1  ✓ │  │ 🖥️ Server 1 ✓│    │
│  ├──────────────┤  └──────────────┘    │
│  │ Server 2  ○ │                        │
│  ├──────────────┤                        │
│  │ Server 3  ○ │                        │
│  └──────────────┘                        │
│                                          │
└─────────────────────────────────────────┘
```

## Performance Considerations

### Async Operations
```
HLS Parsing:
  - Runs asynchronously
  - Doesn't block UI
  - 5 second timeout
  - Silent failure

Controller Disposal:
  - Awaits disposal
  - Prevents memory leaks
  - Cleans up resources

Stream Switching:
  - Shows loading overlay
  - Smooth transition
  - Error recovery
```

### Memory Management
```
Old Controller:
  - Disposed before new one
  - Listeners removed
  - Resources freed

State Updates:
  - Minimal rebuilds
  - Efficient setState calls
  - No unnecessary updates
```

## Testing Checklist

```
✓ Settings button opens bottom sheet
✓ Bottom sheet shows quality options
✓ Quality options are clickable
✓ Selected quality has checkmark
✓ Tapping quality closes sheet
✓ Stream switches to new quality
✓ Quality badge updates
✓ HLS parsing works (or falls back)
✓ Fallback qualities work
✓ Single server shows compact
✓ Multiple servers show full list
✓ Error handling works
✓ No crashes
✓ No blank screens
✓ Premium UI maintained
```

## Summary

This implementation provides:
- ✅ Premium settings UI
- ✅ HLS quality parsing
- ✅ Graceful fallbacks
- ✅ Smooth quality switching
- ✅ Compact server layout
- ✅ Robust error handling
- ✅ No breaking changes
- ✅ Maintained premium design

All requirements met without compromising existing functionality.
