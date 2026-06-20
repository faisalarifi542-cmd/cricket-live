import 'package:flutter/foundation.dart';

import 'package:cricpro_flutter/models/ad_config.dart';
import 'package:cricpro_flutter/services/ads/ad_adapter.dart';
import 'package:cricpro_flutter/services/ads/native_ads_bridge.dart';

/// Unity Ads adapter backed by the native SDK via [NativeAdsBridge].
///
/// Unity Ads supports interstitial and rewarded full-screen formats. It does
/// NOT provide native ads or app-open ads, and we do not render Unity banners
/// here — for those formats this adapter returns empty so the [AdsManager]
/// waterfall falls through to the next enabled network (or hides the slot).
///
/// The adapter only reports [isDirectSupported] = true once the native SDK has
/// actually initialized with a valid game id on a supported platform, so a
/// missing iOS bridge or an unconfigured game id transparently degrades to the
/// fallback network.
class UnityAdapter implements AdNetworkAdapter {
  UnityAdapter();

  AdNetworkConfig _config = AdNetworkConfig.empty(AdNetwork.unity);
  bool _testMode = kDebugMode;
  bool _initialized = false;

  bool _interstitialLoaded = false;
  String? _loadedInterstitialPlacement;
  bool _rewardedLoaded = false;
  String? _loadedRewardedPlacement;

  @override
  AdNetwork get network => AdNetwork.unity;

  @override
  bool get isDirectSupported => _initialized;

  @override
  AdNetworkStatus get status {
    if (kIsWeb) return AdNetworkStatus.notSupported;
    if (!_config.enabled) return AdNetworkStatus.disabled;
    if (_initialized) return AdNetworkStatus.active;
    // Admin enabled it but SDK init has not completed (e.g. no game id, or
    // the native bridge is unavailable on this platform).
    return AdNetworkStatus.pending;
  }

  @override
  bool get isReady => _initialized;

  @override
  Future<void> initialize(AdNetworkConfig config, {required bool testMode}) async {
    _config = config;
    _testMode = testMode || config.testMode;
    _initialized = false;
    if (kIsWeb || !config.enabled) return;

    final gameId = config.gameId;
    if (gameId == null || gameId.isEmpty) {
      if (kDebugMode) {
        debugPrint('[Ads][unity] enabled but no game id configured; skipping');
      }
      return;
    }

    final ok = await NativeAdsBridge.instance
        .unityInitialize(gameId: gameId, testMode: _testMode);
    _initialized = ok;
    if (kDebugMode) {
      debugPrint('[Ads][unity] native init ${ok ? 'OK' : 'unavailable'} '
          '(gameId=$gameId test=$_testMode)');
    }
  }

  @override
  Future<BannerLoadResult> loadBanner(AdPlacement placement) async =>
      BannerLoadResult.empty;

  @override
  Future<NativeLoadResult> loadNative(AdPlacement placement) async =>
      NativeLoadResult.empty;

  @override
  Future<bool> loadInterstitial() async {
    if (!_initialized) return false;
    final placement = _config.interstitialId;
    if (placement == null || placement.isEmpty) return false;
    if (_interstitialLoaded && _loadedInterstitialPlacement == placement) {
      return true;
    }
    final ok = await NativeAdsBridge.instance.unityLoadInterstitial(placement);
    _interstitialLoaded = ok;
    _loadedInterstitialPlacement = ok ? placement : null;
    return ok;
  }

  @override
  Future<bool> showInterstitial() async {
    if (!_initialized || !_interstitialLoaded) return false;
    final placement = _loadedInterstitialPlacement;
    if (placement == null) return false;
    _interstitialLoaded = false;
    _loadedInterstitialPlacement = null;
    return NativeAdsBridge.instance.unityShowInterstitial(placement);
  }

  @override
  Future<bool> loadRewarded() async {
    if (!_initialized) return false;
    final placement = _config.rewardedId;
    if (placement == null || placement.isEmpty) return false;
    if (_rewardedLoaded && _loadedRewardedPlacement == placement) return true;
    final ok = await NativeAdsBridge.instance.unityLoadRewarded(placement);
    _rewardedLoaded = ok;
    _loadedRewardedPlacement = ok ? placement : null;
    return ok;
  }

  @override
  Future<bool> showRewarded() async {
    if (!_initialized || !_rewardedLoaded) return false;
    final placement = _loadedRewardedPlacement;
    if (placement == null) return false;
    _rewardedLoaded = false;
    _loadedRewardedPlacement = null;
    return NativeAdsBridge.instance.unityShowRewarded(placement);
  }

  // Unity Ads has no rewarded-interstitial format — map to rewarded so the
  // waterfall can still satisfy a rewarded-interstitial request via Unity.
  @override
  Future<bool> loadRewardedInterstitial() => loadRewarded();

  @override
  Future<bool> showRewardedInterstitial() => showRewarded();

  // Unity Ads has no app-open format.
  @override
  Future<bool> loadAppOpen() async => false;

  @override
  Future<bool> showAppOpen() async => false;

  @override
  void dispose() {
    _interstitialLoaded = false;
    _rewardedLoaded = false;
    _loadedInterstitialPlacement = null;
    _loadedRewardedPlacement = null;
  }
}
