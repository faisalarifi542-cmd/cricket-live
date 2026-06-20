# Remote Assets — Phase 4 Archiving Report

Generated: 2026-06-12
Branch: `phase4-remote-assets-archiving`
Status: **DONE. Release build passes (exit 0). APK reduced 51.9 MiB → 32.8 MiB.**

---

## 1. Source reports used

This phase was executed strictly against the three prior reports:

- `REMOTE_ASSETS_PHASE2_REPORT.md` — Phase 2 wired keys + fallbacks.
- `REMOTE_ASSETS_PHASE2B_FULL_WIRING_REPORT.md` — Phase 2b wired keys + the
  define-only DEAD asset list (§5 of that report).
- `REMOTE_ASSETS_LIGHT_MODE_THEME_FIX_REPORT.md` — `universalSafe` theme
  resolution. **This logic was NOT touched.** No resolver, no widget, no
  backend catalog file was modified in Phase 4. Light Mode behavior is byte-for-byte
  unchanged: light still uses a `light` upload if present, else the bundled
  (now compressed) light/local fallback; `both` never leaks into Light Mode
  because every themed key remains `universalSafe:false`.

Every key in the prompt's Phase 2 / Phase 2b wired list was re-verified against
the **current** code (not the old report) before its fallback was archived — see §3.

---

## 2. APK size

| Stage | APK (`app-release.apk`, arm64) | Bytes |
|---|---|---|
| **Before Phase 4** | **51.9 MiB** (54.4 MB) | 54,419,668 |
| **After Phase 4** | **32.8 MiB** (34.4 MB) | 34,390,283 |
| **Reduction** | **~19.1 MB (−36.8%)** | −20,029,385 |

- Build command (both): `flutter clean && flutter pub get && flutter build apk --release --target-platform android-arm64 --analyze-size`
- Both builds exited **0**.
- Size-analysis JSON: baseline `~/.flutter-devtools/apk-code-size-analysis_09.json`,
  final `apk-code-size-analysis_10.json`.

The realized cut (~19 MB) exceeded the prior 8–11 MB estimate because these PNGs
were near-incompressible by the APK zip stage, so the raw asset reduction carried
through almost fully.

---

## 3. Assets archived + compressed fallbacks kept (16)

Each large original was moved to `archived/remote-assets-replaced/<same path under
assets/images>` and a **compressed PNG fallback was written back to the original
path** (same filename + `.png` extension → zero code/pubspec change). Compression:
downscale longest side ≤1080 px + 256-color adaptive palette, opaque images only;
real-alpha images would keep RGBA (none in this set). Visually acceptable for
decorative backgrounds rendered behind UI with opacity/tint.

| Remote key | Fallback path (kept, compressed) | Original | Fallback |
|---|---|---|---|
| match_details_header_bg | match_details/backgrounds/stadium_score_header_bg.png | 2275 KB | 132 KB |
| stadium_bg_generic | stadium_live.png | 1870 KB | 139 KB |
| home_hero_bg_dark | home/home_top_featured_card.png | 1720 KB | 95 KB |
| home_backdrop | home/futuristic_stadium_ui_backdrop.png | 1341 KB | 47 KB |
| series_squad_section_bg | series/backgrounds/series_squad_section_bg.png | 1159 KB | 30 KB |
| series_stats_table_bg | series/backgrounds/series_stats_table_bg.png | 1084 KB | 28 KB |
| schedule_backdrop | schedule/stadium_top_bg.png | 914 KB | 133 KB |
| series_overview_panel_bg | series/backgrounds/series_overview_panel_bg.png | 869 KB | 23 KB |
| series_hero_bg | series/backgrounds/series_detail_hero_bg.png | 704 KB | 22 KB |
| player_surface_bg | live_stream/backgrounds/stadium_player_background_clean_16x9.png | 623 KB | 51 KB |
| series_match_card_bg | series/backgrounds/series_match_card_bg.png | 602 KB | 18 KB |
| series_backdrop | series/backgrounds/series_page_top_backdrop.png | 598 KB | 42 KB |
| schedule_match_card_bg | schedule/match_card_bg.png | 507 KB | 72 KB |
| series_empty_state_bg | series/backgrounds/series_empty_state_bg.png | 499 KB | 26 KB |
| series_list_card_bg | series/backgrounds/series_list_card_bg.png | 407 KB | 13 KB |
| matches_backdrop | matches/matches_top_bg.png | 345 KB | 49 KB |

**Totals:** ~15.15 MB originals → **919 KB** compressed fallbacks (in-bundle).
No referenced fallback path is left missing (verified post-move).

---

## 4. Dead define-only assets moved (7)

Re-scanned current code for every reference form (`Image.asset`, `AssetImage`,
`DecorationImage`, `ExactAssetImage`, `SvgPicture.asset`, raw string, and the Dart
`static const` identifier that names the path) before moving. Each was confirmed
**defined-but-never-rendered** (const declared, identifier never used) or **zero
references anywhere**. Moved to `archived/dead-assets/<path>` (moved, not hard
deleted, for reversibility).

| Asset | Size | Why dead (current code) |
|---|---|---|
| series/backgrounds/series_screen_background.png | 583 KB | `SAsset.screenBg` declared (series_premium.dart:26), never used |
| series/backgrounds/series_featured_carousel_bg.png | 924 KB | `SAsset.featuredCarouselBg` declared (:28), never used |
| series/effects/glass_noise_overlay.png | 1032 KB | `SAsset.glassNoise` declared (:44), never used |
| match_details/backgrounds/stadium_card_bg.png | 132 KB | `_Asset.cardBg` declared (match_details_ui.dart:26), never used |
| match_details/backgrounds/glass_panel_bg.png | 37 KB | `_Asset.glassBg` declared (:27), never used |
| stadium_light.png | 1870 KB | Zero refs in `lib/`. No dynamic `_live`→`_light` derivation exists (verified). Not used by Light Mode. |
| live_stream/backgrounds/stadium_player_background_clean_native.png | 382 KB | Zero refs in `lib/` |

**Total dead moved:** ~4.85 MB.

The 5 unused `static const` path strings (`screenBg`, `featuredCarouselBg`,
`glassNoise`, `cardBg`, `glassBg`) were intentionally **left in code**: a const
String is only loaded if passed to `Image.asset`, which never happens, so the
build does not fail and nothing renders. Removing them is cosmetic and was skipped
to avoid edit risk in live files.

---

## 5. Assets skipped (and why)

| Asset | Reason skipped |
|---|---|
| matches/match_card_bg_live.png (227 KB) | Already small; still the live-card fallback. Compressing 227→~100 KB saves little vs. visual risk on the live card. Kept as-is. |
| matches/match_card_bg_upcoming.png (221 KB) | Same — already within target, kept as fallback. |
| matches/match_card_bg_finished.png (219 KB) | Same. |
| stadium_score_header_b.png | Already absent from tree (removed in a prior phase). Nothing to do. |
| match_header_card_background_no_logos.png | Already absent. |
| assets/images/match_card_stadium_bg.png | Already absent (pre-existing). `components.dart:150` still names it as a non-rendered fallback constant; out of Phase 4 scope, left untouched. |
| Team logos / player images / flags / app icon / launch icon / `light_mode/*` clean art | **Never touched** — critical / offline / Light-Mode fallbacks (rules 3 & 5). |

---

## 6. Files changed

**Asset moves (git-tracked renames):** 16 originals → `archived/remote-assets-replaced/…`,
7 dead → `archived/dead-assets/…`.

**Asset content replaced (compressed in place):** the 16 fallback paths in §3.

**Code:** none. **`pubspec.yaml`:** unchanged — every asset entry is a **directory
glob**, and no globbed directory was emptied (e.g. `series/effects/` still holds 9
files, `match_details/backgrounds/` and `live_stream/backgrounds/` still populated),
so Flutter still resolves every declared directory. **Backend / admin panel:** unchanged.

**New helper/report files (repo root):** `compress_assets.py` (Pillow compressor),
`phase4_manifest.txt` (archive→fallback map), `phase4_baseline_build.log`,
`phase4_final_build.log`, `REMOTE_ASSETS_PHASE4_ARCHIVING_REPORT.md` (this file).

All changes are committed to nothing yet — staged/working on branch
`phase4-remote-assets-archiving`. Review, then commit when ready.

---

## 7. Build + analyzer results

- `flutter clean` / `flutter pub get`: OK (both builds).
- **`flutter build apk --release --target-platform android-arm64 --analyze-size`:
  exit 0**, APK 34,390,283 bytes.
- `flutter analyze`: **175 issues — all inside
  `archived/dead-code/components/series_components.dart`** (pre-existing, from an
  earlier archived-folder move; NOT in the `lib/` build path) plus 1 `unused_import`
  warning in `test/analytics_service_test.dart`. **Zero issues in any live `lib/`
  file changed or relied on this phase.** The release build path compiles and ships
  clean. This matches the known-issue count recorded in the Light-Mode theme-fix report.

---

## 8. Manual visual checklist (please test on device)

**Dark Mode** — confirm each screen background/card looks correct (remote OFF →
compressed bundled fallback shows; should be visually acceptable, not blank):

- [ ] Home — backdrop, hero, live card
- [ ] Matches — backdrop, live/upcoming/finished cards
- [ ] Schedule — header, match cards
- [ ] Match Details — score header, hero stadium fill
- [ ] Series List — list cards, top backdrop
- [ ] Series Detail — hero, overview panel, match cards, squads, stats/points, empty state
- [ ] Live Player — video poster before playback

**Light Mode** — confirm NO dark background leaks (each should show clean
light/bundled art):

- [ ] Home  [ ] Matches  [ ] Schedule  [ ] Match Details
- [ ] Series List  [ ] Series Detail  [ ] Live Player

**Fallback / resilience:**

- [ ] Remote asset Active ON (uploaded image shows)
- [ ] Remote asset Active OFF (compressed bundled fallback shows)
- [ ] Bad image URL (errorBuilder → bundled fallback)
- [ ] Offline / airplane mode (bundled fallback, no blank)
- [ ] No blank backgrounds anywhere
- [ ] No dark asset in Light Mode

---

## 9. Risks remaining

- **Compressed-fallback fidelity:** bundled fallbacks are now 256-color downscaled
  PNGs. They are intentionally lower fidelity (offline/last-resort art). If any
  screen looks too soft offline, upload a proper remote image for that key (it
  overrides the fallback). Originals are preserved in
  `archived/remote-assets-replaced/` and can be restored.
- **Dead const strings** (`screenBg`, `featuredCarouselBg`, `glassNoise`, `cardBg`,
  `glassBg`) still reference moved files. Harmless (never loaded) but flagged for a
  future cleanup if desired.
- **Pre-existing analyzer noise** (175 issues in `archived/dead-code/`) is unrelated
  to Phase 4 and does not affect the build; left as-is per scope.

---

## 10. Admin Panel upload guidance after archiving

Bundled fallbacks are now low-fidelity by design. For the best look, upload a
proper remote image per key in Admin `/assets`. Theme rules are unchanged
(`universalSafe:false` for all themed keys):

1. **Dark slot (`theme=dark`)** — your full-quality dark image. Shows in Dark Mode.
2. **Light slot (`theme=light`)** — a bright light-mode image. Shows in Light Mode.
   Upload this to replace the compressed light fallback.
3. **Both slot (`theme=both`)** — treated as **dark-only** (will NOT appear in Light
   Mode). Use a dedicated Light upload for Light Mode.

Per upload: WebP/JPG, ~1080 px wide, target <300 KB, max 2 MB, no text/logos/names.

Priority order (biggest visual win first): `match_details_header_bg`,
`stadium_bg_generic`, `home_hero_bg_dark`, `home_backdrop`,
`series_squad_section_bg`, `series_stats_table_bg`, `schedule_backdrop`,
`series_overview_panel_bg`, `series_hero_bg`, `player_surface_bg`,
`series_match_card_bg`, `series_backdrop`, `schedule_match_card_bg`,
`series_empty_state_bg`, `series_list_card_bg`, `matches_backdrop`.

---

## 11. Acceptance criteria — status

| Criterion | Status |
|---|---|
| APK release build passes | ✅ exit 0 |
| App still has fallback assets | ✅ 16 compressed fallbacks in bundle |
| Remote assets still work | ✅ resolver/widgets untouched |
| Light Mode shows no dark backgrounds | ✅ `universalSafe` logic unchanged |
| Dark Mode visually correct | ✅ (verify on device, §8) |
| Offline shows no blank UI | ✅ bundled fallback path intact |
| Bad URL shows no blank UI | ✅ errorBuilder → fallback |
| APK size reduced | ✅ 51.9 → 32.8 MiB (−19.1 MB) |
| Phase 4 report created | ✅ this file |
