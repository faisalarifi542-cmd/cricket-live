import 'package:cricpro_flutter/services/ads/ads_manager.dart';

/// Backwards-compatible facade for interstitials. All logic (waterfall +
/// frequency caps) now lives in [AdsManager]; screens may keep calling this.
class InterstitialManager {
  InterstitialManager._();

  static final InterstitialManager instance = InterstitialManager._();

  void preload() {
    // Fire-and-forget; AdsManager guards web/enabled/frequency internally.
    AdsManager.instance.preloadInterstitial();
  }

  void showIfReady() {
    AdsManager.instance.maybeShowInterstitial();
  }

  void dispose() {}
}
