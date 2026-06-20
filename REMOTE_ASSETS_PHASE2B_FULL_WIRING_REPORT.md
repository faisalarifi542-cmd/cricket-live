# Remote Assets — Phase 2b Full Wiring Report

Generated: 2026-06-12
Scope: wire all remaining large decorative/background assets to Admin `/assets`
with safe bundled fallback. **No asset deleted/archived.** Build passes.

> Caveman note: wiring ≠ smaller APK. APK shrinks only in **Phase 4 archiving**
> (later, gated on your visual sign-off). This task makes every big background
> *uploadable + overridable* from Admin, safely.

---

## 1. New keys added (11 wired this round)

| Key | Category | Theme | Where used | Fallback (bundled) |
|---|---|---|---|---|
| `match_details_header_bg` | Match Details | both | Score header (light+dark) | match_details/backgrounds/stadium_score_header_bg.png (2.27MB) |
| `stadium_bg_generic` | Match Details | both | Hero card stadium fill | stadium_live.png (1.87MB) |
| `schedule_backdrop` | Schedule | both | Schedule top stadium header | schedule/stadium_top_bg.png (914KB) |
| `schedule_match_card_bg` | Schedule | both | Schedule match cards | schedule/match_card_bg.png (507KB) |
| `series_match_card_bg` | Series | both | Series overview + squads cards | series/backgrounds/series_match_card_bg.png (602KB) |
| `series_squad_section_bg` | Series | both | Squads section panel | series/backgrounds/series_squad_section_bg.png (1.16MB) |
| `series_stats_table_bg` | Series | both | Stats + points table panels | series/backgrounds/series_stats_table_bg.png (1.08MB) |
| `series_overview_panel_bg` | Series | both | Overview info panel | series/backgrounds/series_overview_panel_bg.png (869KB) |
| `series_list_card_bg` | Series | both | Series list cards | series/backgrounds/series_list_card_bg.png (407KB) |
| `series_empty_state_bg` | Series | both | Empty state panel | series/backgrounds/series_empty_state_bg.png (499KB) |
| `player_surface_bg` | Live Player | both | Video poster before playback | live_stream/backgrounds/stadium_player_background_clean_16x9.png (623KB) |

Already wired (Phase 2, untouched): home_backdrop, home_hero_bg_dark,
match_card_live/upcoming/finished_bg, matches_backdrop, series_hero_bg,
series_backdrop, live_player_bg_dark.

Reserved keys kept `wired:false` (no real Flutter render site, so NOT faked):
live_player_bg_light, home_hero_bg_light, home_featured_card_bg.

---

## 2. Flutter files changed

| File | Change |
|---|---|
| `lib/screens/series/series_premium.dart` | Added `bgRemoteKey` to `PremiumGlassPanel` + `PremiumSectionPanel`, threaded to `StadiumImage.remoteKey`. Wired `series_empty_state_bg`. |
| `lib/screens/series/widgets/series_detail_overview.dart` | `series_overview_panel_bg`, `series_match_card_bg` |
| `lib/screens/series/widgets/series_detail_squads.dart` | `series_match_card_bg`, `series_squad_section_bg` |
| `lib/screens/series/widgets/series_detail_stats.dart` | `series_stats_table_bg` (×2) |
| `lib/screens/series/series_components.dart` | `series_list_card_bg` |
| `lib/screens/schedule/schedule_screen.dart` | `schedule_backdrop` |
| `lib/screens/schedule/widgets/schedule_cards.dart` | `schedule_match_card_bg` |
| `lib/screens/match_details/widgets/match_details_ui.dart` | dark `Image.asset`→`RemoteOrLocalImage`, light `StadiumImage.remoteKey`; key `match_details_header_bg`. Added import. |
| `lib/components/match_details_components.dart` | hero stadium `Image.asset`→`RemoteOrLocalImage` key `stadium_bg_generic`. Added import. |
| `lib/screens/live/widgets/live_player_surface.dart` | poster `Image.asset`→`RemoteOrLocalImage` key `player_surface_bg`. |

No new widget needed — reused existing `StadiumImage.remoteKey` (Phase 2) and
`RemoteOrLocalImage`. No duplicated remote-loading logic.

## 3. Backend files changed

- `cricket-api/src/admin/routes/assets.routes.js` — `ASSET_KEYS` expanded to 23
  entries with `category`, `where`, `dimensions`, `fallback`, `large`, `wired`.
  Flipped `match_details_header_bg` + `stadium_bg_generic` to `wired:true`.
  GET `/admin/assets` now returns those fields + existing `guidance`. Existing
  keys/names unchanged (backward compatible). No DB rows touched.

## 4. Admin panel files changed

- `admin-panel/lib/api.ts` — `AppAssetRow` gained `category/where/fallback/large`.
- `admin-panel/app/assets/page.tsx` — category sections; badges Theme / Wired /
  Not wired / Large / Safe-to-upload; **Copy key** button; **Where used** line.
  Upload/active-toggle/revert unchanged.

---

## 5. Wired vs not wired

**Wired (uploadable + live fallback):** 20 keys total (9 prior + 11 new) — see §1.

**Not wired (reserved, shown with amber badge):**
- `live_player_bg_light`, `home_hero_bg_light` — light mode already uses small
  bundled clean art; no separate render hook. Wire later if desired.
- `home_featured_card_bg` — no distinct render site (home hero covers it).

**Define-only DEAD assets (declared in Dart but never rendered — NOT wired,
direct-archive candidates in Phase 4, ~3.3MB pure waste):**
`series_screen_background.png` (583KB), `series_featured_carousel_bg.png` (924KB),
`series/effects/glass_noise_overlay.png` (1.03MB), `match_details/.../stadium_card_bg.png`
(133KB), `match_details/.../glass_panel_bg.png` (38KB),
`stadium_score_header_b.png` (216KB), `stadium_light.png` (1.87MB — not referenced
by string), `stadium_player_background_clean_native.png` (382KB),
`match_header_card_background_no_logos.png` (69KB). These can be deleted outright
in Phase 4 (no render site = zero risk), independent of remote upload.

---

## 6. Safe to upload now (Admin `/assets`) — recommended order (biggest win first)

1. `match_details_header_bg` (2.27MB original)
2. `stadium_bg_generic` (1.87MB)
3. `series_squad_section_bg` (1.16MB)
4. `series_stats_table_bg` (1.08MB)
5. `series_overview_panel_bg` (869KB)
6. `schedule_backdrop` (914KB)
7. `home_backdrop` / `home_hero_bg_dark` (1.34MB / 1.72MB) — already wired
8. `player_surface_bg` (623KB)
9. `series_match_card_bg` (602KB)
10. `series_empty_state_bg`, `series_list_card_bg`, `schedule_match_card_bg`
11. `match_card_*`, `series_hero_bg`, `series_backdrop`, `matches_backdrop`

Per upload: WebP/JPG, ~1080px wide, target <300KB, max 2MB, no text/logos/names.

---

## 7. Screens to test (light + dark)

- [ ] Match Details — score header (dark = RemoteOrLocalImage path; light = StadiumImage). Score text/logos/tabs/commentary intact.
- [ ] Match Details hero card — generic stadium fill.
- [ ] Schedule — header + match cards.
- [ ] Series — overview panel, match cards, squads section, stats/points table, list cards, empty state.
- [ ] Live Player — video poster before playback + existing dark bg.
- [ ] Home / Matches — regression (Phase 2 keys).
- [ ] Offline — every screen shows bundled fallback, no blank.
- [ ] Bad URL / inactive — fallback kicks in.

Theme safety: `urlFor(key, isDark)` resolves `dark→both` / `light→both`, never
crosses. Dark never shows light asset; light never shows dark.

---

## 8. APK / AAB size

- Before (baseline): **51 MB** (51.9 MB measured arm64 release after Phase 2).
- After Phase 2b wiring: **51.9 MB** measured (arm64 release, `--analyze-size`, exit 0). Identical — confirms wiring removes nothing, build not broken.
- After Phase 4 archiving: TBD once you sign off.

Analysis JSON: `~/.flutter-devtools/apk-code-size-analysis_08.json`.

**Reminder: wiring alone does NOT reduce APK.** Every bundled fallback still
ships. Size drops only in Phase 4.

---

## 9. Phase 4 archiving plan (LATER — do NOT execute now)

1. Upload compressed remote for a key, toggle Active.
2. Verify screen light+dark, then verify fallback (toggle off / airplane mode).
3. Move large original → `archived/remote-assets-replaced/` + drop a **compressed**
   (~300KB) fallback in bundle (never zero fallback).
4. Dead define-only assets (§5) → delete outright, no remote needed (~3.3MB free).
5. Update `pubspec.yaml` only if a whole asset dir is emptied.
6. Rebuild `--analyze-size`, record before/after.

Est. total reduction when Phases 2+2b+dead-asset cleanup archived:
**~12–16MB raw → ~8–11MB APK** (51 → ~40–43MB).
