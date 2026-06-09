import 'package:flutter/foundation.dart';

import 'package:cricpro_flutter/models/ad_config.dart';
import 'package:cricpro_flutter/services/ads/ad_adapter.dart';
import 'package:cricpro_flutter/services/ads/native_ads_bridge.dart';

/// Meta / Facebook Audience Network adapter backed by the native SDK via
/// [NativeAdsBridge].
///
/// This adapter wires Meta's interstitial and rewarded-video full-screen
/// formats. Meta banner/native rendering needs platform views and is not wired
/// here yet, so those return empty and the [AdsManager] waterfall falls through
/// to the next enabled network (or hides the slot). Meta has no app-open
/// format.
///
/// [isDirectSupported] only becomes true after the native SDK initializes on a
/// supported platform, so a missing iOS bridge degrades gracefully to the
/// fallback network.
class MetaAdapter implements AdNetworkAdapter {
  MetaAdapter();

  AdNetworkConfig _config = AdNetworkConfig.empty(AdNetwork.meta);
  bool _testMode = kDebugMode;
  bool _initialized = false;

  bool _interstitialLoaded = false;
  String? _loadedInterstitialPlacement;
  bool _rewardedLoaded = false;
  String? _loadedRewardedPlacement;

  @override
  AdNetwork get network => AdNetwork.meta;

  @override
  bool get isDirectSupported => _initialized;

  @override
  AdNetworkStatus get status {
    if (kIsWeb) return AdNetworkStatus.notSupported;
    if (!_config.enabled) return AdNetworkStatus.disabled;
    if (_initialized) return AdNetworkStatus.active;
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

    final ok = await NativeAdsBridge.instance.metaInitialize(testMode: _testMode);
    _initialized = ok;
    if (kDebugMode) {
      debugPrint('[Ads][meta] native init ${ok ? 'OK' : 'unavailable'} '
          '(test=$_testMode)');
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
    final ok = await NativeAdsBridge.instance.metaLoadInterstitial(placement);
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
    return NativeAdsBridge.instance.metaShowInterstitial(placement);
  }

  @override
  Future<bool> loadRewarded() async {
    if (!_initialized) return false;
    final placement = _config.rewardedId;
    if (placement == null || placement.isEmpty) return false;
    if (_rewardedLoaded && _loadedRewardedPlacement == placement) return true;
    final ok = await NativeAdsBridge.instance.metaLoadRewarded(placement);
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
    return NativeAdsBridge.instance.metaShowRewarded(placement);
  }

  // Meta has no dedicated rewarded-interstitial; map to rewarded video.
  @override
  Future<bool> loadRewardedInterstitial() => loadRewarded();

  @override
  Future<bool> showRewardedInterstitial() => showRewarded();

  // Meta has no app-open format.
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
