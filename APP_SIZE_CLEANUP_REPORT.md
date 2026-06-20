# CricPro — Phase 3 Code Audit + App Size Cleanup Report

Date: 2026-06-13
Branch: phase4-remote-assets-archiving
Scope: Flutter app only (backend/admin untouched). Live-score logic, stream-player behavior, UI design, ads, notifications all left intact.

---

## 1. Files inspected

Core routing / nav:
- `lib/main.dart` — route graph, `RootShell._buildTab`, `_open*` push methods, notification deep-link handler
- `lib/screens.dart` — component export barrel
- `pubspec.yaml`, `android/app/build.gradle.kts`, `android/gradle.properties`, `android/app/proguard-rules.pro`

Asset resolution:
- `lib/api_models.dart` — team-logo + flag asset maps
- `lib/widgets/remote_or_local_image.dart` — admin-remote-with-local-fallback loader
- `lib/services/remote_assets_service.dart`

Screens / widgets / components: full `lib/**/*.dart` glob + class-name reference grep across repo.

---

## 2. Active screens / routes (KEPT)

Reachable from `main.dart` → `RootShell`:
- Bottom nav tabs: **Home, Matches, Schedule, Series, More**
- Match flow: `MatchDetailsScreen` → tabs Live / Scorecard / Commentary / Overs / Squad / Info
- `LivePlayerScreen` (stream player) — via Watch Live + notification deep-link
- `SeriesListScreen`, `SeriesDetailScreen`, `PlayerDetailScreen`, `TeamsScreen`, `TeamDetailScreen`, `RankingsScreen`
- `HighlightsScreen` (routed via More → highlights)
- `NotificationsScreen`, `SearchScreen` route? — no (see removed)
- More sub-pages: `ContactUsScreen`, `PrivacyPolicyScreen`, `TermsScreen`, `SimpleInfoScreen`
- `NewsDetailScreen` — kept (used by notification deep-link `type=news`)
- Splash: `PremiumSplashScreen`

Method to identify active vs unused: repo-wide class-name + import grep (NOT analyzer-only). A file counted as orphan only when its public class is referenced nowhere outside itself, and not reachable from any route/push/deep-link.

---

## 3. Removed screens / files (dead code)

All confirmed by grep before deletion; `flutter analyze lib/` clean before and after.

| File | Reason |
|------|--------|
| `lib/data/mock_data.dart` | self-only; header says "DO NOT use in production" |
| `lib/data/mock_matches.dart` | self-only mock fixtures |
| `lib/screens/news/news_screen.dart` | `NewsScreen` list — not routed anywhere (only `NewsDetailScreen` is, via deep-link) |
| `lib/screens/common/search_screen.dart` | `SearchScreen` — not routed |
| `lib/screens/highlights/highlights_player_screen.dart` | not routed; `HighlightsScreen` never pushes it |
| `lib/screens/highlights/highlight_detail_screen.dart` | not routed |
| `lib/components/highlights_components.dart` | imported only by the (also-dead) highlights player; hardcoded fake storyboard |
| `lib/widgets/live_match_mini_card.dart` | `LiveMatchMiniCard` — referenced only in its own file |
| `lib/widgets/home_hero_card.dart` | duplicate `HomeHeroCard`; the live one lives in `components/home_components.dart` (that's what `test/widget_test.dart` and the home screen use) |

Also removed: temporary Phase 2 `CricProDiag` `print(...)` diagnostic in `lib/screens/live/live_player_screen.dart` (`_loadStream`). No other temp diagnostics found. `debugPrint` watch-live/ad logs kept (operational, not noisy print).

---

## 4. Removed dependencies

| Package | Reason |
|---------|--------|
| `cupertino_icons` | zero `CupertinoIcons`/`Cupertino*` usage in `lib/` |

All other deps confirmed imported and active: `http`, `flutter_svg`, `video_player`, `google_mobile_ads`, `onesignal_flutter`, `package_info_plus`, `wakelock_plus`, `shared_preferences`. No webview/carousel/charts/old-player bloat present — pubspec already lean.

---

## 5. Removed assets

None deleted this phase. (You converted all PNG→WebP yourself; originals already replaced on disk — see section 6.) Dead demo assets identified but **not deleted** — see section 7.

---

## 6. WebP conversion — DONE (by user) + code references updated

All 267 image assets were converted PNG → WebP on disk (0 PNG remaining in `assets/`). I updated **all** code references accordingly:
- Replaced every quoted `.png` asset string → `.webp` across 17 `lib/` files (api_models flag/team maps, all `_base`/`_bg`/`_fx`/`_icon`/`_venue`/`_balls`/`_logos` prefix paths, `stadium_live`, light_mode `${dir}` paths, splash).
- Verified: every literal `assets/...webp` path referenced in code exists on disk (0 missing).
- Verified: prefix-var dirs (balls, series backgrounds, venues, etc.) all hold `.webp`.
- `pubspec.yaml` uses directory asset entries → WebP auto-included; no per-file edits needed.

Result: `assets/` folder **7.1 MB → 3.2 MB (−55%)**.

Android launcher icons (`android/app/src/main/res/mipmap-*/ic_launcher.png`) intentionally left PNG — native Android resources, not Flutter assets.

---

## 7. Assets NOT safe to delete yet (dead demo — your call)

No code reference, runtime loads team/player images via network `image_id` with `stadium_live.webp` fallback. Likely old demo data. Flagged, **not deleted**:
- Team demos: `team_dcp`, `team_cgr`, `team_dv`, `team_wa`, `team_vic`, `team_brt`, `team_qld`, `team_ire` (`.webp`)
- Player demos: `player_harry_brook`, `player_joe_root`, `player_rohit_sharma`, `player_kane_williamson`, `player_steven_smith`, `player_yashasvi_jaiswal`, `player_ibrahim_zadran`, `player_daryl_mitchell`, `player_kamindu_mendis` (`.webp`)
- `team_placeholder.webp`, `player_placeholder.webp` — verify no admin/runtime fallback key first

Kept (mapped/used): `team_nz/wi/sa/ban` (in `kTeamLogoAssets`), all `flags/rounded/*` (in `kFlagAssets`), `stadium_live`, all venue/icon/badge/ball/overlay/logo assets.

---

## 8. APK size before / after

| Build | Size |
|-------|------|
| Reported Phase 2 universal APK | 67.9 MB |
| Earlier arm64-only release | 33.1 MB |
| **This phase, arm64-only release** | **28.2 MB** |

Cause of 67.9 MB confirmed = **universal APK** (bundles all ABIs arm64-v8a + armeabi-v7a + x86_64) plus three ad-network native SDKs (google_mobile_ads + Unity 4.12.5 + Meta 6.16.0). Not a config regression — `build.gradle.kts` already had `isMinifyEnabled=true`, `isShrinkResources=true`, R8 `proguard-android-optimize`. The 33.1→28.2 drop comes from dead-code removal + WebP.

## 9. AAB size

`app-release.aab` = **56.8 MB** (contains all ABIs; Play delivers per-device split, ~28 MB arm64 install).

---

## 10. Build commands run

```
flutter pub get
flutter analyze lib/
flutter test
flutter build apk --release --target-platform android-arm64     # 28.2 MB
flutter build appbundle --release                                # 56.8 MB
```

Recommended going forward:
- Play Store: `flutter build appbundle --release` (Play splits ABIs per device)
- Smaller test APK: `flutter build apk --release --target-platform android-arm64`
- Avoid plain `flutter build apk --release` (universal, ~68 MB — this was the regression).

---

## 11. Analyze / test results

- `flutter analyze lib/` → **No issues found** (before and after every cleanup batch).
- `flutter test` → **All tests passed** (38 checks across 8 test files, incl. team-logo fallback, home hero, live-tab layout).

---

## 12. Risks / unknowns

- Dead demo team/player WebPs (section 7) — left in place per your delete-only-when-certain rule. Safe to delete after you confirm no admin asset-key maps to them.
- `team_placeholder`/`player_placeholder` — verify no remote-asset fallback key before deleting.
- `cricket-api/lib/**/*.dart` — old Flutter screens living inside the Node backend dir. NOT shipped (Flutter `source = ../..`, root only). Out of Phase-3 scope. Junk `cricket-api/src22.zip` / `src333.zip` also there — backend cleanup, separate phase.
- Build VM-service ABI: only arm64 APK verified building. armeabi-v7a/x86_64 covered by AAB but not separately smoke-tested.

---

## 13. Intentionally left unchanged

- Live-score polling / innings-break logic (Phase 1)
- Stream-player behavior (Phase 2) — only the temp `CricProDiag` print removed
- UI / theme / premium design
- Ads system, OneSignal notifications, consent flow
- `applicationId = com.cric.pro` (published Play id) vs `namespace = com.cricpro.app` — left as-is
- Android launcher PNG icons
- All backend / admin-panel code

---

## 14. Next-phase recommendation

1. After you OK it: delete the dead demo team/player WebPs (section 7) — small extra trim.
2. Backend hygiene (separate phase): remove `cricket-api/lib/` orphan Flutter screens + `src22.zip`/`src333.zip`.
3. Optional: bump `google_mobile_ads` 8→9 and other pinned deps in a controlled pass with full regression (14 packages have newer majors held by constraints).
4. Consider `--analyze-size` snapshot stored in CI to catch future universal-APK regressions.
