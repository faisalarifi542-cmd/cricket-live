import 'package:flutter/foundation.dart';

import 'package:cricpro_flutter/models/ad_config.dart';
import 'package:cricpro_flutter/services/ads/ad_adapter.dart';

/// Unity Ads adapter.
///
/// NOTE: A direct Unity Ads SDK integration is NOT wired in yet — there is no
/// Unity Ads Flutter plugin in `pubspec.yaml`. This adapter is intentionally
/// honest: it reports [isDirectSupported] = false and never fabricates a fill,
/// so the [AdsManager] waterfall simply skips Unity and moves to the next
/// enabled network.
///
/// To make Unity ads serve directly, add a maintained Unity Ads Flutter plugin
/// (or a native bridge) and implement the load/show methods below using the
/// game IDs and placement IDs already provided in [AdNetworkConfig].
class UnityAdapter implements AdNetworkAdapter {
  UnityAdapter();

  AdNetworkConfig _config = AdNetworkConfig.empty(AdNetwork.unity);

  @override
  AdNetwork get network => AdNetwork.unity;

  @override
  bool get isDirectSupported => false;

  @override
  AdNetworkStatus get status =>
      _config.enabled ? AdNetworkStatus.pending : AdNetworkStatus.disabled;

  @override
  bool get isReady => false;

  /// True when the admin has configured Unity but the app can't serve it yet.
  bool get configuredButInactive => _config.enabled;

  @override
  Future<void> initialize(AdNetworkConfig config, {required bool testMode}) async {
    _config = config;
    if (kDebugMode && config.enabled) {
      debugPrint(
        '[Ads][unity] enabled in config but no direct Unity SDK is wired in; '
        'skipping (gameId=${config.gameId ?? '—'}).',
      );
    }
  }

  @override
  Future<BannerLoadResult> loadBanner(AdPlacement placement) async =>
      BannerLoadResult.empty;

  @override
  Future<NativeLoadResult> loadNative(AdPlacement placement) async =>
      NativeLoadResult.empty;

  @override
  Future<bool> loadInterstitial() async => false;

  @override
  Future<bool> showInterstitial() async => false;

  @override
  Future<bool> loadRewarded() async => false;

  @override
  Future<bool> showRewarded() async => false;

  @override
  Future<bool> loadRewardedInterstitial() async => false;

  @override
  Future<bool> showRewardedInterstitial() async => false;

  @override
  Future<bool> loadAppOpen() async => false;

  @override
  Future<bool> showAppOpen() async => false;

  @override
  void dispose() {}
}
