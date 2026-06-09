# iOS Ads — Unity + Meta Native Bridge TODO

Android has a complete native bridge for Unity Ads and Meta Audience Network
(interstitial + rewarded). iOS currently has **no** native bridge, so on iOS:

- AdMob works fully (official `google_mobile_ads` plugin, all formats).
- Unity / Meta calls hit the platform channel, get `MissingPluginException`,
  are caught by `NativeAdsBridge._invoke`, and resolve to `false`. The
  `AdsManager` waterfall then **skips Unity/Meta and falls back to AdMob**.

So iOS is safe and functional today — it just never serves Unity/Meta. This doc
is the spec to bring iOS to parity with Android.

## Channel contract (must match Android exactly)

Channel name: `cricpro/ads_bridge` (MethodChannel).

| Method                   | Args                                   | Returns (bool) |
|--------------------------|----------------------------------------|----------------|
| `unityInitialize`        | `gameId: String`, `testMode: Bool`     | init success   |
| `unityLoadInterstitial`  | `placementId: String`                  | loaded         |
| `unityShowInterstitial`  | `placementId: String`                  | shown          |
| `unityLoadRewarded`      | `placementId: String`                  | loaded         |
| `unityShowRewarded`      | `placementId: String`                  | reward earned  |
| `metaInitialize`         | `testMode: Bool`                       | init success   |
| `metaLoadInterstitial`   | `placementId: String`                  | loaded         |
| `metaShowInterstitial`   | `placementId: String`                  | shown          |
| `metaLoadRewarded`       | `placementId: String`                  | loaded         |
| `metaShowRewarded`       | `placementId: String`                  | reward earned  |

Rules (same as Android):
- Each call must reply to the `FlutterResult` **exactly once**, on the main thread.
- Rewarded `show*` returns `true` ONLY when the reward is earned (completed),
  `false` on skip/close/error.
- Interstitial `show*` returns `true` once displayed/dismissed, `false` on error.
- No SDK object may be hardcoded in Dart; placement/game IDs come from the
  backend ad config (already wired in `unity_adapter.dart` / `meta_adapter.dart`).

## CocoaPods dependencies (`ios/Podfile`)

Add to the `Runner` target:

```ruby
pod 'UnityAds', '~> 4.12'
pod 'FBAudienceNetwork', '~> 6.16'
```

Then `cd ios && pod install`. Set `platform :ios, '13.0'` or higher (both SDKs
require modern minimums). Meta also requires `-ObjC` and `SKAdNetworkItems` in
`Info.plist` (see Meta docs) plus AdMob/Meta `GADApplicationIdentifier` already
present for AdMob.

## Swift files to add (mirror the Kotlin classes)

Under `ios/Runner/Ads/`:

- `AdsBridge.swift` — registers the channel in `AppDelegate`, routes methods to
  the two bridges (mirror of `AdsBridge.kt`).
- `UnityAdsBridge.swift` — uses `UnityAds` (`UnityAds.initialize`,
  `UnityAds.load(_:loadDelegate:)`, `UnityAds.show(_:placementId:showDelegate:)`).
  Rewarded earned == `UnityAdsShowCompletionState.completed`.
- `MetaAdsBridge.swift` — uses `FBInterstitialAd` and `FBRewardedVideoAd`.
  Rewarded earned tracked via `rewardedVideoAdVideoComplete`, resolve result on
  `rewardedVideoAdDidClose`.
- `SafeResult.swift` — wraps `FlutterResult` so it fires once on main thread.

### AppDelegate registration

```swift
override func application(_ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: ...) -> Bool {
  GeneratedPluginRegistrant.register(with: self)
  let controller = window?.rootViewController as! FlutterViewController
  adsBridge = AdsBridge(messenger: controller.binaryMessenger,
                        viewControllerProvider: { [weak self] in self?.window?.rootViewController })
  return super.application(application, didFinishLaunchingWithOptions: launchOptions)
}
```

Unity/Meta `show` on iOS needs a presenting `UIViewController` — pass the root
view controller via the provider closure (Android passes the Activity the same way).

## Logging parity

Mirror Android's logcat tags using `os_log` / `print`:
- `UNITY_AD: requested / loaded / failed / shown / completed / rewardGranted`
- `META_AD: requested / loaded / failed / shown / completed / rewardGranted`

## Formats NOT implemented on either platform (by design)

- App-open: **AdMob only** (Unity/Meta have no app-open format). Do not add.
- Unity/Meta banner + native: not wired (need platform views). Waterfall falls
  through to AdMob or hides the slot.
- No AdMob mediation anywhere — Unity/Meta are independent, backend-controlled
  networks.

## Acceptance

iOS is at parity when, with Unity/Meta enabled and valid iOS IDs in the admin
panel, a forced AdMob no-fill falls through to Unity then Meta for interstitial
and rewarded, with rewards granted only on completion — matching Android.
