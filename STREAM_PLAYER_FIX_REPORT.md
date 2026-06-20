# Stream Player Fix Report — Phase 2

Date: 2026-06-13
Branch: phase4-remote-assets-archiving
Scope: Live Stream Player robustness only. No UI redesign, no ads/score/cast/minimizer changes.

## 1. Root cause found

The player wiring was already largely correct — `video_player` received `httpHeaders`,
parsed HLS master playlists into quality tiers, disposed/recreated controllers safely,
and offered a Retry button. The "stream not playable" failures came from gaps, not a
single broken path:

1. **No initialization timeout.** A dead or hanging link left `controller.initialize()`
   pending forever, so the player spun indefinitely and never surfaced an error.
2. **Backup URL was never tried.** The model and backend both carried `backupUrl`, but
   `_loadStream` only ever played the primary URL.
3. **One generic error message.** Every failure (403, expired token, network drop,
   unsupported codec) collapsed to a single "Unable to play this stream" string, so users
   and logs couldn't tell transient from permanent failures.
4. **No automatic retry.** Transient network/token hiccups required a manual tap.
5. **Backend `/:id/test` was HEAD-only.** It checked HTTP status but never inspected
   content-type or payload, so it could not detect an HTML error page, a DASH/MPD stream,
   or whether headers were required.

## 2. Files inspected

- `pubspec.yaml`
- `lib/screens/live/live_player_screen.dart`
- `lib/screens/live/widgets/live_player_surface.dart`
- `lib/screens/live/widgets/live_player_streams.dart`
- `lib/api_models.dart` (`StreamSource`)
- `cricket-api/src/lib/public-app-state.js` (`publicStreamDto`, `fetchActiveStreamsForMatch`, `publicHeaders`, `publicDrm`)
- `cricket-api/src/routes/app.js` (stream summary + `/app/match/:id/streams`)
- `cricket-api/src/admin/routes/streams.routes.js`

## 3. Files changed

- `lib/screens/live/live_player_screen.dart`
- `lib/screens/live/widgets/live_player_surface.dart`
- `cricket-api/src/admin/routes/streams.routes.js`

## 4. Backend changes

`cricket-api/src/admin/routes/streams.routes.js`:

- Added `validateStreamUrl(url, headers)` helper. It:
  - Sends a GET with `Range: bytes=0-65535` and `maxContentLength: 512KB` so only the
    first chunk is buffered (no full-video download).
  - Follows up to 5 redirects, 9s timeout, `validateStatus: () => true`.
  - Returns `{ playable, type, status, statusCode, finalUrl, needsHeaders, reason, variants, latencyMs }`.
  - Classifies: 401/403 → `needsHeaders`/expired; 404/410 → expired; 5xx → slow;
    `#EXTM3U`/`mpegurl`/`.m3u8` → HLS playable (and extracts master-playlist variants);
    `<MPD>`/`dash+xml`/`.mpd` → DASH, marked not playable (app is HLS-only);
    `text/html` or `<!doctype/<html` → HTML error page; otherwise unverified.
  - Maps connection errors (timeout, SSL/cert, DNS) to clear reasons.
- `/:id/test` now calls `validateStreamUrl` (passing UA/Referer/Origin), persists the same
  `status`/`http_status`/`latency_ms`/`error_message` health-check row as before, and adds
  `playable`, `type`, `final_url`, `needs_headers`, `reason`, `variants` to the response.

No public app endpoint changed — `publicStreamDto` already returned `url`, `backupUrl`,
`type`, `quality`, `headers`, `drm`, `priority`, `status`, premium/reward/login flags.

## 5. Flutter changes

`lib/screens/live/live_player_screen.dart` — `_loadStream`:

- New `_initTimeout = 12s`. Each source init is wrapped in `.timeout(_initTimeout)`.
- Builds a candidate list `[playUrl, backupUrl]` (backup only when present and different)
  and tries them in order, disposing the failed controller before the next.
- Added `isRetry` param: when every candidate fails and this isn't already a retry, waits
  1.5s and re-runs the whole chain once (guarded by `_selectedStream?.id` so a stream
  change cancels it). Second failure surfaces the error.
- New `_classifyPlayerError(error, triedBackup)` maps the failure to a safe message
  (timeout / expired-or-403 / not-found / SSL / format / network / both-failed / generic).
  Never logs or shows URLs, tokens, or header values; debug logs include only matchId,
  streamId, primary/backup, and retry flag.

`lib/screens/live/widgets/live_player_surface.dart`:

- `_PlayerErrorOverlay` now takes a `message` string and renders it (was a hardcoded line).
  Existing compact/`maxLines`/`ellipsis`/`SingleChildScrollView` layout preserved — no
  overflow, no giant panel, Retry button unchanged.

## 6. Player package limitations

Only `video_player: ^2.9.2`. It plays HLS and accepts `httpHeaders`. It does **not**
support DASH/MPD or DRM. DASH/external/iframe streams are short-circuited with a safe
"not supported on this device" message (existing behavior, kept). DRM is exposed by the
backend but not consumed by the player yet.

## 7. Header support status

Fully wired. Admin stores `user_agent_header`, `referer_header`, `origin_header`, and a
free-form `headers_json`. `publicStreamDto` → `publicHeaders` merges them into a single
`headers` map. Flutter `StreamSource` parses `headers`/`headers_json`, and `_loadStream`
passes them both to the HLS master fetch and to `VideoPlayerController.networkUrl`.
Header values are never logged.

## 8. Backup URL behavior

`backupUrl` is now attempted automatically when the primary URL fails to initialize
(or times out), before any error is shown. If both fail, the auto-retry re-runs the full
chain once. Which source failed is logged in debug only; the UI shows a single calm
message ("Primary and backup streams both failed…"), never a noisy per-attempt log.

## 9. Quality detection behavior

Unchanged and already correct: the HLS master playlist is parsed into FHD/HD/SD tiers
(720p+/480p/240–360p) plus an Auto/adaptive option, deduped to the best variant per tier.
When no variants are present it falls back to the admin-configured `quality`. The backend
validator additionally returns the raw master-playlist variants for admin visibility.

## 10. Test commands run

- `flutter analyze lib/screens/live/` → **No issues found!**
- `node --check cricket-api/src/admin/routes/streams.routes.js` → **NODE_OK**

## 11. Manual test checklist

- [ ] Valid HLS URL plays.
- [ ] HLS URL needing User-Agent/Referer plays (headers passed).
- [ ] Invalid URL → clean classified error, no crash.
- [ ] Expired/403 URL → "expired or needs authorization" message.
- [ ] Primary fails, backup configured → backup plays automatically.
- [ ] Both fail → "both failed" message after one auto-retry.
- [ ] Retry button reloads the stream.
- [ ] Fullscreen still works.
- [ ] Leaving the player disposes the controller (wakelock released).
- [ ] Switching streams/quality does not reuse the old controller.
- [ ] No overflow on a small Android screen (error overlay scrolls/clamps).
- [ ] Admin → Test stream returns `playable/type/needs_headers/reason/variants`.

## 12. Intentionally left unchanged

- HLS quality parsing/tiers, fullscreen page, quality sheet — already working.
- Public stream endpoints — already return all needed metadata.
- Live score polling, ads, onboarding, home redesign, cast, minimizer.
- No new player package added (DASH/DRM deferred — would need ExoPlayer/VLC backend).

## 13. Play Store policy safety notes

- No "free TV", "server TV", "illegal stream", or similar wording added.
- Error messages are neutral and user-safe ("temporarily unavailable", "try another
  server", "expired").
- No URLs, tokens, or header values are shown to users or written to release logs
  (technical detail is debug-only / admin-only).
- DASH/DRM streams are declined gracefully rather than attempting an unsupported decode.

---

## Follow-up fix — "stream type not supported" on a valid .m3u8 master

Date: 2026-06-13

### Problem

A confirmed-valid HLS master (`#EXTM3U` / `#EXT-X-DYNAMICALLY-GENERATED` /
`#EXT-X-STREAM-INF` → `dynamic_delta.m3u8`, served from a pscp.tv VPS) was rejected
**before playback** with "This stream type is not supported on this device." Root cause:
the unsupported branch trusted the stored/forwarded `type`. When the type was
missing/unknown/`live`/`external`/`iframe`/`mpd`/`dash`, the `.m3u8` URL was ignored and
the stream never reached the player.

### Fix — the `.m3u8` URL path is now authoritative HLS evidence

1. **`StreamSource` (`lib/api_models.dart`)** — `type` collapses HLS aliases (`hls`,
   `m3u8`, `mpegurl`, `x-mpegurl`, `application/x-mpegurl`,
   `application/vnd.apple.mpegurl`, `vnd.apple.mpegurl`) to `hls`. New `_urlIsM3u8`
   checks `Uri.parse(url).path` (query/token stripped) for `.m3u8`. `isHls` is true when
   type is hls **or** the URL is `.m3u8`; `isDash`/`isExternal` return false for any
   `.m3u8` URL, so a wrong stored type can no longer mark it unsupported.

2. **`live_player_screen.dart`** — the unsupported branch still keys off
   `stream.isDash || stream.isExternal` (now `.m3u8`-aware), so a valid master is
   attempted. Added safe debug log right before rejection: `matchId`, `streamId`,
   `rawType`, `normalizedType`, URL extension only (`.m3u8`/`.mpd`/`none`), `hasHeaders`.
   No full URL, token, or header values logged.

3. **Relative variant URLs** — `_resolveUrl` rewritten to RFC-3986 `Uri.resolve`. An
   origin-absolute variant like `/Transcoding/a/dynamic_delta.m3u8` now resolves against
   the master origin (e.g. `https://prod-fastly-eu-central-1.video.pscp.tv/Transcoding/a/dynamic_delta.m3u8`).
   The old string concat broke on leading-slash paths and could hand a relative URL to
   `video_player`.

4. **Admin write normalization (`streams.routes.js` `normalisePayload`)** — when
   `stream_url` path contains `.m3u8` and `stream_type` isn't already `hls`, it is forced
   to `hls` on create/update. Real `.mpd` is untouched.

5. **Public DTO (`public-app-state.js` `normalizeStreamType`)** — now URL-aware: a
   `.m3u8` path returns `hls` even for pre-existing DB rows with a bad type, and HLS
   content-type aliases collapse to `hls`. So existing records serve `type: hls` without a
   data migration.

6. **Backend validator (`streams.routes.js` `validateStreamUrl`)** — DASH branch now
   guarded `if (looksDash && !looksHls)`, so HLS always wins. HLS master returns
   `reason: 'hls_master_playlist'` (media playlist → `hls_media_playlist`). Verified on
   the exact test playlist: `playable:true`, `type:hls`, `variants:4`,
   `reason:hls_master_playlist`, DASH branch skipped, `/Transcoding/...` resolved to origin.

### Playlist compatibility note (`#EXT-X-DYNAMICALLY-GENERATED`)

This tag and `dynamic_delta.m3u8` (LL-HLS delta) are non-standard/low-latency hints.
ExoPlayer (Android `video_player`) may or may not fully support the delta child playlist.
The fix ensures the stream is now **attempted as HLS**; if the child playlist is
incompatible, initialization fails and `_classifyPlayerError` reports a
network/format/playlist message ("format is not supported on this device. Please try
another server") **after** trying — never the pre-flight "stream type not supported".

### Files changed (follow-up)

- `lib/api_models.dart`
- `lib/screens/live/live_player_screen.dart`
- `cricket-api/src/admin/routes/streams.routes.js`
- `cricket-api/src/lib/public-app-state.js`

### Checks (follow-up)

- `flutter analyze lib/screens/live/ lib/api_models.dart` → No issues found.
- `node --check` on both backend files → OK.
- Validator simulation on the exact master → `looksHls=true`, `dashBranch=false`,
  `variants=4`, `reason=hls_master_playlist`, relative variant resolved to pscp.tv origin.
