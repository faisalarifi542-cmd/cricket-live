import 'package:flutter/foundation.dart';

import 'package:cricpro_flutter/models/ad_config.dart';
import 'package:cricpro_flutter/services/ads/ad_adapter.dart';

/// Meta / Facebook Audience Network adapter.
///
/// NOTE: A direct Meta Audience Network SDK integration is NOT wired in yet.
/// There is no maintained, reliable FAN Flutter plugin in `pubspec.yaml`, so
/// this adapter is intentionally honest: it reports [isDirectSupported] = false
/// and never fabricates a fill. The admin panel can still store Meta IDs, but
/// the app will not claim Meta ads are active until a real adapter ships
/// (either via a maintained plugin or an Android/iOS native bridge).
///
/// When implementing: use the placement IDs from [AdNetworkConfig] and only
/// flip [isDirectSupported] to true once load/show actually work on-device.
class MetaAdapter implements AdNetworkAdapter {
  MetaAdapter();

  AdNetworkConfig _config = AdNetworkConfig.empty(AdNetwork.meta);

  @override
  AdNetwork get network => AdNetwork.meta;

  @override
  bool get isDirectSupported => false;

  @override
  AdNetworkStatus get status =>
      _config.enabled ? AdNetworkStatus.pending : AdNetworkStatus.disabled;

  @override
  bool get isReady => false;

  /// True when the admin has configured Meta but the app can't serve it yet.
  bool get configuredButInactive => _config.enabled;

  @override
  Future<void> initialize(AdNetworkConfig config, {required bool testMode}) async {
    _config = config;
    if (kDebugMode && config.enabled) {
      debugPrint(
        '[Ads][meta] enabled in config but no direct Meta/FAN SDK is wired in; '
        'skipping (treated as not available on this platform).',
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
