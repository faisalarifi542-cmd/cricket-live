# Remote Assets — Light Mode Theme Fix Report

Generated: 2026-06-12
Scope: stop dark `theme=both` remote uploads from bleeding into Light Mode.
**No asset deleted/archived. No bundled asset removed. Dark Mode unchanged.**
Follow-up to `REMOTE_ASSETS_PHASE2B_FULL_WIRING_REPORT.md`.

---

## 1. Root cause

Card/panel/background remote keys are registered in the backend catalog as a
single `theme: both` entry. The Flutter resolver `urlFor(key, isDark)` resolved:

- dark request → `dark` ?? `both`
- light request → `light` ?? **`both`**  ← bug

Since these keys only ever had a `both` row, and operators uploaded a **dark**
image into `both`, **Light Mode received that dark image**. Result: dark
backgrounds/cards under match cards and panels in Light Mode.

`StadiumImage` (light branch) still resolved a remote URL for `isDark:false` and
painted it over the clean light asset, so even purpose-built light artwork was
covered by the dark remote `both` image.

---

## 2. The fix (how theme resolution works NOW)

New rule: **Light Mode never uses a `both` asset unless the catalog explicitly
marks the key universal-safe.** A new `universalSafe` flag (default `false` for
every key) gates this. Dark Mode is untouched.

`urlFor(key, {required bool isDark})`:

| Request | Resolution |
|---|---|
| **Dark** | `dark` URL → else `both` URL → else `null` (unchanged from before) |
| **Light** | `light` URL → else (`universalSafe == true` ? `both` URL : skip) → else `null` |

`null` → caller (`StadiumImage` / `RemoteOrLocalImage`) renders the **bundled
light/local fallback**. No dark remote image can appear in Light Mode for any
card/panel/background key, because all of them are `universalSafe: false`.

Dark `both` uploads still serve Dark Mode exactly as before.

---

## 3. Files changed

| File | Change |
|---|---|
| `lib/services/remote_assets_service.dart` | `RemoteAsset` gained `universalSafe`. Loader parses `universalSafe` per asset, tracks `_universalSafe` per key. **`urlFor` rewritten**: dark = `dark`→`both` (unchanged); light = `light`→(`both` only if universalSafe)→`null`. |
| `cricket-api/src/admin/routes/assets.routes.js` | Added `THEMED_BG_KEYS` (15 keys), `universalSafeFor()` (returns `false` by default), `expandedAssetCatalog()` (emits dark/light/both upload slots for themed keys). Admin `GET /admin/assets` now returns `themed` + `universalSafe` per entry. Existing keys/rows untouched. |
| `cricket-api/src/routes/app.js` | Public `GET /app/assets` now returns `universalSafe` per asset (additive, backward compatible). Imports `universalSafeFor`. |
| `admin-panel/lib/api.ts` | `AppAssetRow` gained `themed?` + `universalSafe?`. |
| `admin-panel/app/assets/page.tsx` | Theme badges relabeled (**Dark only / Light only / Universal·Both**; themed `both` → `Both · dark-only`). Per-card hint for themed keys recommending separate Light + Dark uploads. Edit modal shows ⚠ warning when editing a `both` slot. |

No Flutter widget files needed edits — every card/panel/background routes through
`StadiumImage` or `RemoteOrLocalImage`, both of which call `urlFor`. The central
resolver fix covers Home / Matches / Schedule / Series cards, Series panels, and
Match Details header/hero in one place. `frameBuilder` / `errorBuilder` / opacity
/ tint / border radius / blend mode / fit / alignment all preserved.

---

## 4. Keys affected (now support separate Dark / Light / Both uploads)

`THEMED_BG_KEYS` (all `universalSafe: false` → light = bundled fallback until a
`light` asset is uploaded):

- match_card_live_bg
- match_card_upcoming_bg
- match_card_finished_bg
- schedule_match_card_bg
- series_match_card_bg
- series_list_card_bg
- series_overview_panel_bg
- series_squad_section_bg
- series_stats_table_bg
- series_empty_state_bg
- match_details_header_bg
- stadium_bg_generic
- schedule_backdrop
- series_backdrop
- home_backdrop

Other `both` keys (matches_backdrop, series_hero_bg, player_surface_bg, etc.)
are also `universalSafe: false`, so they too fall back to bundled in Light Mode —
no dark remote leak anywhere.

---

## 5. What you need to upload for Light Mode

In Admin `/assets`, each themed key now shows **three slots** — Dark / Light /
Both:

1. **Dark slot (`theme=dark`)** — your existing dark image. Shows in Dark Mode.
2. **Light slot (`theme=light`)** — a bright, light-mode image. Shows in Light
   Mode. **Upload this to replace the bundled light fallback.**
3. **Both slot (`theme=both`)** — use **only** if the same image genuinely looks
   correct in both themes. Currently treated as **dark-only** (universalSafe is
   false), so a `both` upload will NOT appear in Light Mode.

Recommended: upload a dedicated **Light** asset for each card/panel key. Until
then, Light Mode safely uses the bundled clean light artwork.

Per-upload guidance unchanged: WebP/JPG, ~1080px wide, target <300 KB, max 2 MB,
no text/logos/names.

To later make a single image serve both themes: flip that key to `true` inside
`universalSafeFor()` in `assets.routes.js` after visually verifying it.

---

## 6. Backward compatibility & safety

- DB schema unchanged. No rows touched/deleted. Existing `both` uploads keep
  serving **Dark Mode** exactly as before.
- `universalSafe` and `themed` are additive JSON fields. Older app builds that
  ignore them keep their prior behavior; the shipped app reads `universalSafe`
  and defaults it to `false` when absent.
- All fallback paths intact: remote off / inactive / bad URL / offline → bundled
  asset via `frameBuilder` + `errorBuilder`. Never blank.

---

## 7. Testing

**Static analysis**

- `flutter analyze` on changed live files (`remote_assets_service.dart`,
  `remote_or_local_image.dart`, `components.dart`): **No issues found.**
- Full `flutter analyze`: 175 issues — **all in `archived/dead-code/
  series_components.dart`** (pre-existing, from the archived-folder move; not in
  the build path under `lib/`). Zero issues in any changed/live file.
- Backend `node --check` on `assets.routes.js` and `app.js`: **OK.**

**Release build**

- `flutter build apk --release --target-platform android-arm64`: **not run this
  session** (skipped at operator request). Re-run before shipping. No code in the
  build path changed signatures; the resolver edit is internal to a method body.

**Manual verification checklist (run on device, light + dark):**

| # | Check | Expected |
|---|---|---|
| 1 | Dark Mode overall | Identical to before — remote dark/both assets still load |
| 2 | Light Mode match cards | No dark background — bundled clean light art |
| 3 | Home match cards (light) | Light/clean |
| 4 | Matches screen cards (light) | Light/clean |
| 5 | Schedule cards + backdrop (light) | Light/clean |
| 6 | Series cards + panels (light) | Light/clean (overview/squads/stats/empty/list) |
| 7 | Match Details header/hero (light) | Light/clean |
| 8 | Remote OFF (toggle inactive) | Bundled fallback, both themes |
| 9 | Bad URL | `errorBuilder` → bundled fallback |
| 10 | Offline | Bundled fallback, no blank |
| 11 | No blank backgrounds anywhere | Pass |

---

## 8. Net effect

- **Dark Mode:** unchanged.
- **Light Mode:** dark remote `both` images can no longer appear. Light uses a
  dedicated `light` upload if present, otherwise the bundled light design.
- **Admin:** clear Dark / Light / Both slots, a warning on `Both`, and a
  recommendation to upload separate Light + Dark versions for cards & panels.
