# Ads Real Mode Fix Report

Date: 2026-06-13

## Summary

Inspected the ads path from Admin Panel -> Backend `/app/config` -> Flutter
`AdConfig` -> `AdsManager` -> AdMob adapter -> placements.

Flutter now uses admin real-mode config in debug and release builds. It no
longer forces Google sample ad units just because the app is running in debug.
The AdMob adapter now also supports Google Ad Manager unit paths for banner,
interstitial, rewarded, and rewarded-interstitial placements.

## Root Cause: Pre-roll Showing Test Ads

Two causes were found:

1. Flutter forced test mode in debug:
   `AdConfig.fromAppConfig()` used `kDebugMode || ads.testMode`, so debug builds
   loaded Google sample IDs even when Admin had `testMode=false`.

2. Live `/app/config` currently still returns a Google sample rewarded unit:
   `androidRewarded = ca-app-pub-3940256099942544/...354917`.
   Since live pre-roll is configured as `rewarded_video`, that is the unit used
   for Watch Live pre-roll.

Fix:
- Removed the `kDebugMode` force. Admin `ads.testMode` is now the source of
  truth.
- In real mode, the AdMob adapter refuses Google sample unit IDs and logs:
  `reason=google_sample_unit_in_real_mode`.
- Watch Live logs now include selected pre-roll format and a masked unit ID.

Remaining admin step:
- Replace Android rewarded unit in Admin Panel with the real production rewarded
  unit, or change pre-roll type to interstitial/rewarded-interstitial if those
  are the intended production formats.

## Root Cause: Banner Not Loading

Two causes were found:

1. The app rendered banner widgets before `/app/config` had loaded. They tried
   once with `AdConfig.empty`, then did not retry after real config arrived.

2. Live banner ID is a Google Ad Manager path (`/.../Banner`), but the app used
   AdMob `BannerAd` only. GAM paths require `AdManagerBannerAd`.

Fix:
- `AdsManager` exposes `configRevision`.
- `BannerAdWidget` and `StickyBannerBar` listen for config changes and reload
  after real config arrives.
- AdMob adapter detects `/...` unit paths and uses `AdManagerBannerAd`.
- Banner load logs now include placement, network, masked unit, source
  (`admob` or `ad_manager`), success/failure, and error code/message.

## Root Cause: Interstitial Not Loading

Live interstitial ID is also a Google Ad Manager path (`/.../Interstitial`), but
the app used AdMob `InterstitialAd` only.

Fix:
- AdMob adapter detects `/...` unit paths and uses `AdManagerInterstitialAd`.
- Preload and show failures now log AdMob/Ad Manager code, domain, and message.
- Existing frequency caps and placement toggles are unchanged.

## Android Configuration

Checked:
- `AndroidManifest.xml` has production AdMob app id:
  `ca-app-pub-5604905670303331~7374966285`.
- Added explicit `INTERNET` and `ACCESS_NETWORK_STATE` permissions.
- `MobileAds.instance.initialize()` is called before loading ads.
- Release build with R8/minify completed successfully.
- Android package is `com.cricpro.app`.

Note:
- Live `/app/config` currently returns missing Android AdMob app ID in the ads
  JSON, but Google Mobile Ads app id is a native manifest value, not something
  Flutter can change at runtime. The manifest value is the one Android uses.

## Live `/app/config` Verification

Command:

```bash
curl https://api.webcrichd.co/app/config
```

Observed masked values:

- `enabled`: true
- `testMode`: false
- `primaryNetwork`: admob
- `fallbackOrder`: admob > unity > meta
- `bannerEnabled`: true
- `interstitialEnabled`: true
- `rewardedEnabled`: true
- `liveStreamPreRollAdType`: rewarded_video
- Android banner: `/219023649...Banner` (Google Ad Manager path)
- Android interstitial: `/219023649...titial` (Google Ad Manager path)
- Android rewarded: `ca-app-pub...354917` (Google sample rewarded unit)
- Android rewarded interstitial: `/219023649...warded` (Google Ad Manager path)
- Home banner placement: true
- Match details banner placement: true
- Live player rewarded placement: true

## Flutter Logs To Verify

Use `flutter logs` or logcat and filter for:

- `ADS_CONFIG:` config loaded from API.
- `ADS_INIT:` AdMob initialization and test mode.
- `ADS_LOAD:` placement load attempts and waterfall result.
- `ADS_ADMOB:` masked unit id, source (`admob` or `ad_manager`), load success,
  failure code/domain/message.
- `AD_WATERFALL:` Watch Live pre-roll load/show waterfall.
- `WATCH_LIVE_AD:` selected pre-roll type and masked unit.

Expected real-mode behavior:

- `ADS_CONFIG: ... testMode=false ...`
- Banner/interstitial GAM paths show `source=ad_manager`.
- Pre-roll rewarded-video will be skipped until Admin replaces the Google sample
  rewarded unit with a real production unit.

## Files Changed

- `lib/models/ad_config.dart`
  - Admin `testMode` is now the source of truth; debug no longer forces tests.
- `lib/services/ads/admob_adapter.dart`
  - Added Ad Manager path support.
  - Added sample-unit guard in real mode.
  - Added masked unit and error logs.
- `lib/services/ads/ads_manager.dart`
  - Added `configRevision` for ad widgets to reload after config arrives.
  - Added config/load diagnostics.
- `lib/widgets/ads/banner_ad_widget.dart`
  - Reloads banners when ads config updates.
- `lib/main.dart`
  - Watch Live pre-roll logs masked unit ID.
- `android/app/src/main/AndroidManifest.xml`
  - Added network permissions.
- `admin-panel/components/forms/AdsSettingsForm.tsx`
  - Warns if Google sample units are saved while Test mode is off.

## Commands Run

- `curl https://api.webcrichd.co/app/config` - verified live ads config.
- `flutter analyze lib/models/ad_config.dart lib/services/ads lib/widgets/ads lib/main.dart` - passed.
- `flutter test` - 38 tests passed.
- `npm run lint` in `admin-panel` - passed.
- `node --check cricket-api/src/lib/public-app-state.js` - passed.
- `node --check cricket-api/src/admin/index.js` - passed.
- `flutter build apk --debug` - passed.
- `flutter build apk --release` - passed, APK built at
  `build/app/outputs/flutter-apk/app-release.apk`.

## Remaining Manual Steps

1. In Admin Panel -> Ads, replace Android rewarded unit with a real production
   rewarded ad unit, because live config still has a Google sample rewarded ID.
2. If the intended pre-roll is interstitial or rewarded-interstitial, change
   `live_stream_pre_roll_ad_type` accordingly in Admin Panel.
3. Save ads settings and confirm `/app/config` no longer contains
   `ca-app-pub-3940256099942544` in any real-mode unit field.
4. Run the app and watch logs:
   - if AdMob returns `no fill`, the code is correct and the issue is account,
     inventory, approval, policy, app-ads.txt, or placement availability.
   - if a unit is missing/sample, the logs now identify the exact placement.
