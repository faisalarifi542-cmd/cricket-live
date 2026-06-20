# Flutter Release Size Guide — CricPro / cricket-live

Generated: 2026-06-11
Goal: smallest, cleanest release builds without breaking UI/design or removing
required cricket assets.

---

## 1. Build commands

### Clean + deps (always first)
```bash
flutter clean
flutter pub get
```

### Play Store — App Bundle (RECOMMENDED for store)
```bash
flutter build appbundle --release --analyze-size
```
Google Play generates per-device APKs from the AAB, so users download only the
ABI + density they need. Smallest user-facing download. Use this for the store.

### Direct APK distribution — split per ABI
```bash
flutter build apk --release --split-per-abi --analyze-size
```
Produces separate arm64-v8a / armeabi-v7a / x86_64 APKs. Use ONLY when shipping
APKs outside Play (website, sideload). Ship arm64-v8a to most modern phones.

### Single ABI APK (CI / quick size check)
```bash
flutter build apk --release --target-platform android-arm64 --analyze-size
```
Fastest size check during optimization work. arm64 only.

`--analyze-size` opens a breakdown (code vs assets vs native libs) so you can see
exactly where bytes go.

---

## 2. Recommendations (priority order)

1. **Use App Bundle for Play Store.** Never upload a fat universal APK.
2. **Use split-per-abi APK only for direct distribution.** A universal APK bundles
   all ABIs and is 2-3x larger than needed per device.
3. **Tree-shake icons** (on by default in release for `Icons.*` from icon fonts).
   Do NOT pass `--no-tree-shake-icons` unless you use dynamic IconData (this app
   does not appear to). Keep tree-shaking ON.
4. **Ship no unused assets.** This repo declares whole directories in
   `pubspec.yaml` (`assets/images/home/` etc), so Flutter bundles EVERY file in
   them. Archived-out files stop shipping automatically. See section 3.
5. **Keep debug/test/demo assets out of release.** QA screenshots already moved to
   `docs/archive/`. Keep them out of `assets/`.
6. **R8/resource shrinking** (Android): ensure `android/app/build.gradle` release
   buildType has `minifyEnabled true` + `shrinkResources true`. (Verify on device
   build — `android/` is gitignored locally.)

---

## 3. Asset hygiene (already applied / pending)

DONE this pass:
- 22 unused `assets/images/home/*` files (~18MB) archived to
  `archived/unused-assets/home/`. home dir: 22MB -> 3.3MB.
- 53 QA screenshots + stray backend PNG moved to `docs/archive/`.

PENDING (review before removing — see PROJECT_SIZE_REPORT.txt §3B):
- ~48 grep-unused assets in series/match_details/matches/live_stream/light_mode
  (~1MB). Several look like runtime fallbacks (`*_fallback`, `status_*`,
  `role_*_badge`, `*_placeholder`) — verify they are not built via dynamic paths
  before archiving. Archive into `archived/unused-assets/<dir>/` first, never
  hard-delete.

Re-audit command (lists assets in a dir not referenced in lib/):
```bash
for f in $(find assets/images/<dir> -type f | xargs -n1 basename | sort -u); do
  grep -rq "$f" lib/ || echo "UNUSED $f"
done
```

---

## 4. Image compression (deferred, manual — needs visual QA)

Oversized PNGs are the biggest remaining asset cost. WebP is typically 50-70%
smaller at equal quality:

| File | Size |
|------|------|
| match_details/backgrounds/stadium_score_header_bg.png | 2.3M |
| stadium_live.png | 1.9M |
| stadium_light.png | 1.9M |
| home/home_top_featured_card.png | 1.7M |
| home/futuristic_stadium_ui_backdrop.png | 1.3M |
| series/backgrounds/series_squad_section_bg.png | 1.2M |

Convert (lossy q80 keeps backgrounds clean):
```bash
cwebp -q 80 input.png -o output.webp
```
Then update the `.png` references in `lib/` and `pubspec.yaml` to `.webp`.
Flutter supports WebP natively on Android/iOS. DO THIS WITH VISUAL QA — light/dark
stadium overlays in this app are alpha-sensitive (see AI_PROJECT_INDEX.md). Not
auto-applied here.

---

## 5. After any asset/code change — verify
```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release --target-platform android-arm64 --analyze-size
```
Compare the `--analyze-size` asset total before/after. Do an on-device visual
pass on home, match details (light + dark), and live player to confirm no missing
backgrounds.
