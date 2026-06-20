# Local WebP Assets — Local-First Enforcement Report

Generated: 2026-06-16
Branch: `phase4-remote-assets-archiving`
Status: **DONE. Large static backgrounds now always load from bundled local
WebP — never from the admin/remote server. Premium originals restored from
`archived/` (PNG → optimized WebP) into the active asset paths (see §15).
`flutter analyze lib/` clean. No release build run (per instruction).**

---

## 0. Outcome (bottom line)

The large static visual assets are **already bundled locally as optimized WebP**
in their original paths — nothing had to be moved back from `archived/`. The one
real gap was the remote-asset resolver: 20 heavy stadium/hero/card/panel
background keys would load from the API **first** if an admin uploaded a URL,
which is exactly the per-user bandwidth spike you want to avoid.

Fix: added a `_localFirstKeys` denylist to `RemoteAssetsService.urlFor`. For
those keys `urlFor` now returns `null` regardless of any admin upload, so every
caller renders its bundled local WebP. Core screens (Home / Matches / Schedule /
Series / Match Details / Live Player) no longer depend on the server for their
heavy backgrounds.

---

## 1. Reports read

- `REMOTE_ASSETS_PHASE4_ARCHIVING_REPORT.md` — archived large PNG originals →
  `archived/remote-assets-replaced/`, kept compressed fallbacks in place.
- `APP_SIZE_CLEANUP_REPORT.md` — the PNG→WebP conversion + dead-screen/asset
  cleanup (267 images converted, `assets/` 7.1 MB → 3.2 MB).
- `REMOTE_ASSETS_PHASE2_REPORT.md`, `REMOTE_ASSETS_PHASE2B_FULL_WIRING_REPORT.md`,
  `REMOTE_ASSETS_PHASE2_SIZE_AUDIT.txt` — which keys were wired to `/assets`.
- `REMOTE_ASSETS_LIGHT_MODE_THEME_FIX_REPORT.md` — `universalSafe` / theme rules.
- `REMOTE_ASSETS_ROLLOUT_CHECKLIST.txt`, `REMOTE_ASSETS_ADMIN_PLAN.txt`,
  `HOME_SCREEN_IMPROVEMENT_REPORT.md`, `PROJECT_SIZE_REPORT.txt`,
  `OPTIMIZATION_PLAN.txt`.

---

## 2. Files inspected

- `pubspec.yaml` asset entries (directory globs).
- `assets/` tree (full ext + size scan).
- `lib/api_models.dart` (team-logo + flag asset maps).
- `lib/widgets/remote_or_local_image.dart` (remote-with-local-fallback loader).
- `lib/services/remote_assets_service.dart` (`urlFor` resolver).
- `lib/components.dart` (`StadiumImage`, the shared backdrop/card widget).
- `lib/main.dart` (startup load path).
- Every `remoteKey` / `assetKey` call site in `lib/` (20 keys, listed §4).

---

## 3. Current local asset strategy (verified on disk)

- `assets/` = **267 WebP + 23 SVG + 1 JSON, 0 PNG. Total 3.2 MB.**
- The compressed local fallbacks already sit in their **original paths as WebP**
  (e.g. `assets/images/stadium_live.webp`,
  `assets/images/home/futuristic_stadium_ui_backdrop.webp`,
  `assets/images/home/home_top_featured_card.webp`). **No move from `archived/`
  was needed** — the WebP conversion (later phase) already regenerated them.
- `archived/remote-assets-replaced/` and `archived/dead-assets/` hold the **old
  large PNG originals** only — history/backup, not in the build path. (pubspec
  globs `assets/...`, not `archived/...`.)
- `pubspec.yaml` uses **directory** asset entries, so every bundled WebP is
  auto-included; no per-file edit needed.
- Startup: `RemoteAssetsService.instance.load()` in `main.dart:133` is
  **fire-and-forget (not awaited)** — the app never blocks on the asset catalog.
  On failure it keeps bundled assets.

Two render chokepoints, both routed through `RemoteAssetsService.urlFor`:
- `StadiumImage` (backdrops/cards) — `components.dart:72`.
- `RemoteOrLocalImage` (match-details header, live-player surface) —
  `remote_or_local_image.dart:46`.

Fixing `urlFor` therefore enforces the policy in **one** place for both widgets.

---

## 4. Large remote-asset usages found (the 20 keys now forced local)

All currently-wired keys are large static decorative backgrounds — none is small
or genuinely dynamic. All are now in `_localFirstKeys`:

| Key | Where used |
|---|---|
| stadium_bg_generic | Match Details hero stadium fill |
| home_backdrop | Home backdrop |
| home_hero_bg_dark | Home hero / featured hero |
| match_card_live_bg | Home + Matches live cards |
| match_card_upcoming_bg | Matches upcoming cards |
| match_card_finished_bg | Matches finished cards |
| matches_backdrop | Matches backdrop |
| live_player_bg_dark | Live Player background |
| player_surface_bg | Live Player video poster |
| match_details_header_bg | Match Details score header |
| schedule_backdrop | Schedule top header |
| schedule_match_card_bg | Schedule match cards |
| series_backdrop | Series detail backdrop |
| series_hero_bg | Series detail hero |
| series_list_card_bg | Series list cards |
| series_match_card_bg | Series overview + squads cards |
| series_overview_panel_bg | Series overview panel |
| series_squad_section_bg | Series squads section |
| series_stats_table_bg | Series stats + points tables |
| series_empty_state_bg | Series empty state |

(`home_hero_bg_light`, `home_featured_card_bg`, `live_player_bg_light` are also
in the set as a guard — reserved/light variants of the same heavy backgrounds.)

---

## 5. Changes made

1. `lib/services/remote_assets_service.dart`
   - Added `static const Set<String> _localFirstKeys` (the 20 heavy keys + 3
     reserved light/variant guards) with a doc comment explaining the bandwidth
     rationale.
   - `urlFor` now early-returns `null` when `key` is in `_localFirstKeys`, before
     any remote lookup → always renders the bundled local WebP for these keys.
   - Remote infrastructure left intact for any **future** genuinely-dynamic key
     not in the set.
2. `lib/api_models.dart`
   - Cosmetic: doc comment `<team>.png` → `<team>.webp` (the only `.png` text
     remaining in `lib/`; code already used `.webp`).

No widget files changed. No pubspec change. No asset files moved. No backend /
admin change. Fully reversible (remove a key from the set to re-enable remote).

---

## 6. WebP verification result

- `assets/` extension scan: **267 webp, 23 svg, 1 json, 0 png.**
- All **87 unique literal** `assets/...webp` paths referenced in `lib/` **exist
  on disk** (0 missing).
- Team-logo map + 76-entry rounded-flag map: all `.webp`; `assets/flags/` on disk
  = 76 webp + 1 json (0 png). Dynamic flag/team paths resolve.
- Light + dark backgrounds resolve to bundled WebP (light-mode clean art under
  `light_mode/*` untouched).
- Team / flag / logo fallbacks resolve.

---

## 7. Missing asset references

**None.** 0 missing literal refs; 0 missing flag/team-map refs.

---

## 8. Remaining PNG references in `lib/`

**None.** Before: 1 (`.png` in a doc comment, now fixed). Code references: 0.
(Android launcher icons under `android/app/src/main/res/mipmap-*` stay PNG —
native Android resources, not Flutter assets, out of scope.)

---

## 9. Assets intentionally left untouched

- `archived/**` — old PNG originals kept as reversible backup; not in build path.
- `light_mode/*` clean light art — the light-mode fallback; must stay bundled.
- Team / player / flag placeholders, app icon, splash, fonts.
- The `RemoteOrLocalImage` / `StadiumImage` widgets and the remote catalog
  load/parse logic — kept so future small dynamic keys can still use remote with
  a local fallback. Only the resolution result for the 20 heavy keys changed.

---

## 10. Why local WebP is better for server load

- **No bandwidth spike on app open:** heavy stadium/hero/card backgrounds are not
  fetched from the API per user; they paint from the bundle.
- **Faster first paint / works on poor network / offline:** local WebP renders
  immediately; no wait on a remote download for core UI.
- **No blank backgrounds:** a server failure can't blank a core screen — the
  bundled WebP is the source of truth for these keys.
- **No startup block:** the remote catalog load stays best-effort and
  fire-and-forget; UI never waits on admin assets.
- **Smaller + already optimized:** continues the prior PNG→WebP direction
  (`assets/` 7.1 MB → 3.2 MB).

---

## 11. Checks run

- `flutter analyze lib/` → **No issues found! (ran in 5.0s)**
- Disk asset scans + reference cross-checks (§6) — all resolve.
- **Not run** (per instruction): release APK, appbundle.

---

## 12. Previously completed work (carried forward, unchanged)

- **PNG → WebP** conversion of all Flutter image assets (prior app-size phase) —
  `assets/` reduced ~55% (7.1 MB → 3.2 MB). This task keeps that direction.
- **Dead screens / dead assets removed**; APK trimmed (33.1 → 28.2 MB arm64).
- Remote-asset wiring + `universalSafe` light-mode theme fix — kept intact; this
  task only changes whether the **heavy** keys consult remote at all.

---

## 13. What was intentionally left unchanged

Per task scope — **not touched**: ads flow, live-score polling, floating score
overlay, Match Details polling, stream player (HLS), backend / admin-panel,
release signing, Play Store config, the remote-asset widget/loader architecture,
and all bundled fallback assets.

---

## 14. Risks / unverified

- Visual fidelity of the heavy backgrounds is now whatever the **bundled
  compressed WebP** looks like (no remote high-res override for these keys). The
  prior phase already judged these acceptable as decorative backgrounds; on-device
  light+dark spot-check recommended before release.
- On-device verification (live device) not possible here; analyzer + disk checks
  pass. Recommend a quick visual pass on Home / Matches / Schedule / Series /
  Match Details / Live Player, both themes.

---

## 15. Archived PNG recovery + active WebP placement (2026-06-16, second pass)

### 1. Why this pass was needed

The first pass enforced local-first but the active WebPs in `assets/images` were
the **Phase-4 compressed fallbacks** (256-color, downscaled ≤1080px) — generic,
low-fidelity art, not the premium originals. The full-quality originals existed
only in `archived/remote-assets-replaced/` as large PNG. With remote-first now
disabled for these keys, the app would render the weak fallbacks forever. This
pass restores the premium originals as optimized WebP into the active paths.

### 2. Heavy local-first keys checked

All 16 keys that had an archived original were checked (the 20 `_localFirstKeys`
minus `match_card_live_bg` / `match_card_upcoming_bg` / `match_card_finished_bg`,
which were never archived — Phase 4 kept their small originals as-is — and the 3
reserved light/variant guards with no distinct asset). Each archived PNG maps
1:1 to its active path `assets/images/<same rel path>.webp`, and every active
path is referenced by code (refs ≥ 1), confirming they are the real runtime
fallbacks (not orphans).

### 3. Archived PNGs found (premium originals, `archived/remote-assets-replaced/`)

16 originals, 353 KB – 2.33 MB each (~15.2 MB total): `stadium_score_header_bg`,
`stadium_live`, `home_top_featured_card`, `futuristic_stadium_ui_backdrop`,
`series_squad_section_bg`, `series_stats_table_bg`, `schedule/stadium_top_bg`,
`series_overview_panel_bg`, `series_detail_hero_bg`,
`stadium_player_background_clean_16x9`, `series_match_card_bg`,
`series_page_top_backdrop`, `schedule/match_card_bg`, `series_empty_state_bg`,
`series_list_card_bg`, `matches/matches_top_bg`.

### 4. Assets converted to WebP

All 16 PNG → WebP via `restore_premium_webp.py` (Pillow 12.2.0). Settings:
**quality 85** (premium 82–88 range), **method 6**, longest side capped at
**1600px** (aspect ratio preserved), opaque → RGB. Command:

```
python restore_premium_webp.py
```

Result (active WebP size before → after this pass):

| Active path | dims out | before | after |
|---|---|---|---|
| match_details/backgrounds/stadium_score_header_bg.webp | 1600x533 | 87.5 KB | 141 KB |
| stadium_live.webp | 1600x900 | 73.4 KB | 105 KB |
| home/home_top_featured_card.webp | 1600x618 | 51.9 KB | 82 KB |
| schedule/stadium_top_bg.webp | 1440x760 | 66.3 KB | 70 KB |
| matches/matches_top_bg.webp | 1080x650 | 33.9 KB | 34 KB |
| schedule/match_card_bg.webp | 1200x620 | 32.6 KB | 32 KB |
| series/backgrounds/series_squad_section_bg.webp | 1600x933 | 18.4 KB | 30 KB |
| series/backgrounds/series_stats_table_bg.webp | 1600x871 | 17.6 KB | 29 KB |
| series/backgrounds/series_overview_panel_bg.webp | 1600x693 | 16.0 KB | 27 KB |
| series/backgrounds/series_empty_state_bg.webp | 1400x520 | 18.2 KB | 25 KB |
| series/backgrounds/series_detail_hero_bg.webp | 1600x472 | 14.8 KB | 24 KB |
| series/backgrounds/series_page_top_backdrop.webp | 1080x1200 | 20.5 KB | 22 KB |
| series/backgrounds/series_match_card_bg.webp | 1600x462 | 14.2 KB | 22 KB |
| series/backgrounds/series_list_card_bg.webp | 1600x311 | 11.2 KB | 17 KB |
| live_stream/backgrounds/stadium_player_background_clean_16x9.webp | 1280x720 | 18.1 KB | 17 KB |
| home/futuristic_stadium_ui_backdrop.webp | 1600x728 | 11.6 KB | 14 KB |

Total active WebP for these 16: **506 KB → 691 KB (+185 KB)**. Premium fidelity,
each file still small (max 141 KB) — no multi-MB WebP. (15.2 MB of PNG originals
collapse to 691 KB of WebP.)

### 5. Final active WebP paths

The 16 paths in the table above (under `assets/images/`). All are `.webp`, all
exist, all referenced by code. Originals remain in
`archived/remote-assets-replaced/` as backup (not deleted, per instruction).

### 6. Assets left unchanged and why

- `match_card_live_bg`, `match_card_upcoming_bg`, `match_card_finished_bg` — no
  archived original; Phase 4 kept their small in-place originals. Already good.
- Reserved guards `home_hero_bg_light`, `home_featured_card_bg`,
  `live_player_bg_dark`, `live_player_bg_light` — no distinct heavy asset to
  restore; they fall back to existing bundled art.
- `archived/dead-assets/**`, `archived/unused-assets/**` — dead/unused, not
  runtime; left as backup.
- `light_mode/*` clean light art, team/player/flag placeholders, splash, fonts,
  Android launcher PNGs — untouched.

### 7. Keys still missing a good local asset

**None.** Every heavy local-first key that previously had a premium original now
serves it as optimized WebP. The match-card keys and light guards intentionally
use their existing bundled art.

### 8. Total asset folder size before/after this pass

`assets/` **3.2 MB → 3.4 MB** (+~0.18 MB). Still 267 WebP + 23 SVG + 1 JSON,
**0 PNG**.

### 9. Confirmation: large backgrounds remain local-first

Unchanged from §5/§10. `_localFirstKeys` still forces `urlFor` → `null` for these
keys; no remote/admin URL is consulted. This pass only upgraded the *bytes* of
the bundled WebP, not the resolution path. Startup still fire-and-forget; no
remote dependency for core visuals.

### 10. Confirmation: no runtime `.png` refs in `lib/`

`grep -rnE "\.png['\"]" lib/` → **0**. `grep -rn "\.png" lib/` → **0** (the prior
doc-comment was fixed in pass 1). Android launcher PNGs untouched (native, not
Flutter assets).

### 11. Checks run

- `python restore_premium_webp.py` → 16 files converted, table above.
- `flutter analyze lib/` → **No issues found! (ran in 2.4s)**
- `find assets -type f` ext scan → 267 webp / 23 svg / 1 json / **0 png**.
- 16 archived-original → active-path map verified 1:1; each active path
  referenced by code (refs ≥ 1).
- **Not run** (per instruction): release APK, appbundle.

### Files added this pass
- `restore_premium_webp.py` (conversion script, repo root).
- 16 active `.webp` files overwritten with premium content (paths in §4 table).
- `LOCAL_WEBP_ASSETS_REPORT.md` (this section).

No Dart code changed this pass (paths already correct). No backend/admin/ads/
polling/stream change.
