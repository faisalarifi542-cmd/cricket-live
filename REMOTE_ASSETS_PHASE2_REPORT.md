# Remote Assets — Phase 2 Report

Generated: 2026-06-12
Status: **Wiring complete (Phases 1–3 + 5 build). Phase 4 archiving GATED on your
visual sign-off.**

> I cannot visually test screens. Wiring + admin catalog + build are done. Asset
> archiving (the part that actually shrinks the APK) is intentionally NOT done
> yet — it must wait until you confirm each screen looks correct in both themes
> with remote ON and remote OFF. Removing assets blind would risk a blank/broken
> background. See **Phase 4 — Your turn** below.

---

## Files changed

### Flutter (wiring)
| File | Change |
|---|---|
| `lib/components.dart` | `StadiumImage` gained an optional `remoteKey`. When a URL is configured for that key (theme-aware) it renders the network image with the **identical** opacity/tint/blend treatment; on offline/404/decode it falls back to the bundled asset. Added `RemoteAssetsService` import. |
| `lib/screens/home/home_screen.dart` | Backdrop → `home_backdrop` |
| `lib/screens/home/widgets/home_hero.dart` | Hero → `home_hero_bg_dark` |
| `lib/screens/home/widgets/home_featured.dart` | Featured hero → `home_hero_bg_dark`; live card → `match_card_live_bg` |
| `lib/screens/home/widgets/home_match_cards.dart` | Live card → `match_card_live_bg` |
| `lib/screens/matches/matches_screen.dart` | Backdrop → `matches_backdrop` |
| `lib/screens/matches/widgets/matches_cards.dart` | `_MatchCardShell` gained `remoteKey`; live/upcoming/finished cards → `match_card_live_bg` / `match_card_upcoming_bg` / `match_card_finished_bg` |
| `lib/screens/series/widgets/series_detail_hero.dart` | Hero → `series_hero_bg` |
| `lib/screens/series/series_detail_screen.dart` | Backdrop → `series_backdrop` |

### Backend
| File | Change |
|---|---|
| `cricket-api/src/admin/routes/assets.routes.js` | Expanded `ASSET_KEYS` catalog (added `home_backdrop`, `matches_backdrop`, `series_hero_bg`, `series_backdrop`, deferred `match_details_header_bg` + `stadium_bg_generic`; renamed `series_hero_background`→`series_hero_bg`). Added `wired` flag per key + `UPLOAD_GUIDANCE`. `GET /admin/assets` now returns `wired` + `guidance`. |

### Admin panel
| File | Change |
|---|---|
| `admin-panel/lib/api.ts` | `AppAssetRow.wired?`, new `AppAssetGuidance` type, list returns `guidance`. |
| `admin-panel/app/assets/page.tsx` | Upload-guidance banner + "Not wired" badge on reserved keys. |

### Docs
- `REMOTE_ASSETS_PHASE2_SIZE_AUDIT.txt` (Phase 1)
- `REMOTE_ASSETS_PHASE2_REPORT.md` (this file)

---

## Remote asset keys wired

| Key | Theme | Bundled fallback (kept) |
|---|---|---|
| `home_backdrop` | both | `home/futuristic_stadium_ui_backdrop.png` |
| `home_hero_bg_dark` | dark | `home/home_top_featured_card.png` (light → bundled `light_mode/hero_stadium_bg.png`) |
| `match_card_live_bg` | both | `matches/match_card_bg_live.png` + home live card |
| `match_card_upcoming_bg` | both | `matches/match_card_bg_upcoming.png` |
| `match_card_finished_bg` | both | `matches/match_card_bg_finished.png` |
| `matches_backdrop` | both | `matches/matches_top_bg.png` |
| `series_hero_bg` | both | `series/backgrounds/series_detail_hero_bg.png` |
| `series_backdrop` | both | `series/backgrounds/series_page_top_backdrop.png` |
| `live_player_bg_dark` | dark | already wired (MVP) |

**Deferred to Phase 2b (higher risk, not wired):**
- `match_details_header_bg` — biggest single asset (2.27 MB) but dark branch uses
  raw `Image.asset` with a special `errorBuilder`; wire + test in isolation.
- `stadium_bg_generic` — `stadium_live.png`/`stadium_light.png` rendered without
  an `isDark` guard in `match_details_components.dart:93`.

---

## How the fallback guarantee works (why no blank/broken UI)

`StadiumImage` resolves `urlFor(key, isDark)`:
- No URL configured → renders bundled asset directly. (Today's behavior. Nothing changes until you set a URL in admin.)
- URL configured → `Image.network` with `frameBuilder` showing the bundled asset
  while loading and `errorBuilder` falling back to it on **any** failure
  (offline, 404, decode). Same fit/alignment/tint/opacity as before.
- Theme safety: a dark request never resolves to a light row and vice-versa
  (`dark → both`, `light → both`, never cross).

---

## Phase 4 — Your turn (archiving = the actual size win)

Nothing is archived yet, so the APK is still ~baseline. To realize the size cut,
**after** you visually verify, do this per asset:

1. In admin `/assets`, upload a compressed (WebP/JPG, ≤300 KB, 1080px wide) image
   for the key and toggle Active.
2. Open the app, confirm the screen looks right in **light AND dark**.
3. Toggle Active OFF (or airplane mode) → confirm bundled fallback still looks right.
4. Only then: move the large original to `archived/remote-assets-replaced/` and
   replace the in-bundle fallback with a **compressed** version (never zero fallback).
5. Update `pubspec.yaml` only if a whole directory is emptied.

Largest originals to target first (raw KB): `stadium_score_header_bg` 2275,
`home_top_featured_card` 1720, `futuristic_stadium_ui_backdrop` 1341,
`schedule/stadium_top_bg` 914, `series_detail_hero_bg` 704,
`series_page_top_backdrop` 598, `series_match_card_bg` 602, `matches_top_bg` 345,
`match_card_bg_*` ~220 each. Est. APK reduction once done: **~8–10 MB** (51 → ~41–43).

---

## Screens to visually test (both light + dark)

- [ ] Home — backdrop + hero + live card
- [ ] Matches — backdrop + live/upcoming/finished cards
- [ ] Schedule — header + cards (StadiumImage; not yet keyed — verify unchanged)
- [ ] Match Details — header (deferred key; verify unchanged)
- [ ] Series Detail — hero + backdrop
- [ ] Live Player — already remote (regression check)
- [ ] Offline mode — every screen shows bundled fallback, no blank
- [ ] Slow network / remote 404 — set a bad URL, confirm fallback kicks in

---

## Admin setup steps

1. Deploy backend (`cricket-api`) + admin panel with these changes.
2. Open admin `/assets`. New keys appear with a **Not wired**/theme badge and the
   upload-guidance banner.
3. For each key you want remote: **Edit → Upload image (≤2 MB, WebP/JPG, 1080px) → Save** (auto-actives), or paste a CDN URL.
4. Toggle Active to enable; **Revert** (trash) removes the URL → app uses bundled fallback.

---

## APK / AAB size

- Before: **51 MB** (baseline, per your report).
- After wiring (no archiving yet): **51.9 MB** measured (`flutter build apk --release --target-platform android-arm64 --analyze-size`, exit 0). Confirms wiring alone removes nothing — the override path is enabled but every bundled fallback is still shipped. Build did NOT break.
- After Phase 4 archiving: _to be measured once you sign off and archive. AAB build deferred to the same point (no size change before archiving)._

## Risks

- `StadiumImage` is shared — one widget change touches home/matches/series/schedule.
  Mitigated: identical render path when no remote URL; analyzer clean.
- Light mode keeps small bundled `light_mode/*` art (these are the light fallback —
  do **not** archive them).
- Deferred keys (`match_details_header_bg`, `stadium_bg_generic`) untouched on purpose.
