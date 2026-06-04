import 'package:flutter/widgets.dart';

import 'package:cricpro_flutter/models/ad_config.dart';

/// Result of a banner load attempt. [widget] is null when no ad was filled.
class BannerLoadResult {
  const BannerLoadResult({this.widget, this.height, this.dispose});

  final Widget? widget;
  final double? height;

  /// Releases the underlying native ad. Call when the host widget is disposed.
  final VoidCallback? dispose;

  bool get loaded => widget != null;

  static const empty = BannerLoadResult();
}

/// Result of a native ad load attempt. [widget] is null when no ad was filled.
class NativeLoadResult {
  const NativeLoadResult({this.widget, this.dispose});

  final Widget? widget;

  /// Releases the underlying native ad. Call when the host widget is disposed.
  final VoidCallback? dispose;

  bool get loaded => widget != null;

  static const empty = NativeLoadResult();
}

/// Honest runtime status of an ad-network adapter, for diagnostics/admin.
enum AdNetworkStatus {
  /// SDK is implemented and the adapter can serve.
  active,

  /// Admin enabled it and IDs may be set, but no direct SDK/plugin is wired in.
  pending,

  /// Disabled by admin config.
  disabled,

  /// Not supported on this platform (e.g. web).
  notSupported,
}

/// Common interface every direct ad-network adapter implements. The
/// [AdsManager] waterfall talks only to this interface, so screens never call a
/// network SDK directly.
abstract class AdNetworkAdapter {
  AdNetwork get network;

  /// Whether a working direct integration exists for this network on this
  /// platform. Adapters with no real SDK return false so the waterfall skips
  /// them instead of pretending to serve ads.
  bool get isDirectSupported;

  /// Honest status for diagnostics/admin display.
  AdNetworkStatus get status;

  /// True once [initialize] has completed and the adapter can serve.
  bool get isReady;

  Future<void> initialize(AdNetworkConfig config, {required bool testMode});

  /// Attempts to load a banner for [placement]. Returns an empty result if the
  /// network has no fill, times out, or is unsupported.
  Future<BannerLoadResult> loadBanner(AdPlacement placement);

  /// Attempts to load a native ad for [placement]. Returns an empty result if
  /// the network has no fill, no native factory, times out, or is unsupported.
  Future<NativeLoadResult> loadNative(AdPlacement placement);

  /// Preloads an interstitial. Returns true when one is ready to show.
  Future<bool> loadInterstitial();

  /// Shows a previously loaded interstitial. Returns true if it was shown.
  Future<bool> showInterstitial();

  /// Preloads a rewarded ad. Returns true when one is ready to show.
  Future<bool> loadRewarded();

  /// Shows a rewarded ad. Returns true only if the user earned the reward.
  Future<bool> showRewarded();

  /// Preloads a rewarded interstitial. Returns true when one is ready.
  Future<bool> loadRewardedInterstitial();

  /// Shows a rewarded interstitial. Returns true only if the reward is earned.
  Future<bool> showRewardedInterstitial();

  /// Preloads an app open ad. Returns true when one is ready to show.
  Future<bool> loadAppOpen();

  /// Shows a previously loaded app open ad. Returns true if it was shown.
  Future<bool> showAppOpen();

  /// Releases any cached full-screen ads held by this adapter.
  void dispose();
}
