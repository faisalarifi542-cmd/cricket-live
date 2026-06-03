import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'package:cricpro_flutter/services/ad_service.dart';

class InterstitialManager {
  InterstitialManager._();

  static final InterstitialManager instance = InterstitialManager._();

  InterstitialAd? _ad;
  DateTime? _lastShownAt;
  int _shownInWindow = 0;

  void preload() {
    if (kIsWeb || !AdService.instance.config.canShowInterstitial || _ad != null) return;
    final unitId = AdService.instance.interstitialUnitId();
    if (unitId == null || unitId.isEmpty) return;
    InterstitialAd.load(
      adUnitId: unitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _ad = ad,
        onAdFailedToLoad: (_) => _ad = null,
      ),
    );
  }

  bool get _allowedByFrequency {
    final config = AdService.instance.config;
    if (_shownInWindow >= config.interstitialFrequencyCap) return false;
    final last = _lastShownAt;
    if (last == null) return true;
    return DateTime.now().difference(last).inSeconds >=
        config.minimumInterstitialSeconds;
  }

  void showIfReady() {
    if (kIsWeb || !AdService.instance.config.canShowInterstitial) return;
    if (!_allowedByFrequency) return;
    final ad = _ad;
    if (ad == null) {
      preload();
      return;
    }
    _ad = null;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        preload();
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose();
        preload();
      },
    );
    _lastShownAt = DateTime.now();
    _shownInWindow += 1;
    ad.show();
  }

  void dispose() {
    _ad?.dispose();
    _ad = null;
  }
}
