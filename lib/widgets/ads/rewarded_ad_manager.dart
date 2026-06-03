import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'package:cricpro_flutter/services/ad_service.dart';

class RewardedAdManager {
  RewardedAdManager._();

  static final RewardedAdManager instance = RewardedAdManager._();

  RewardedAd? _ad;
  bool _loading = false;

  Future<void> preload() async {
    if (kIsWeb || !AdService.instance.config.canShowRewarded || _ad != null || _loading) {
      return;
    }
    final unitId = AdService.instance.rewardedUnitId();
    if (unitId == null || unitId.isEmpty) return;
    _loading = true;
    final completer = Completer<void>();
    RewardedAd.load(
      adUnitId: unitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _ad = ad;
          _loading = false;
          completer.complete();
        },
        onAdFailedToLoad: (_) {
          _ad = null;
          _loading = false;
          completer.complete();
        },
      ),
    );
    return completer.future;
  }

  Future<bool> showForUnlock() async {
    if (kIsWeb || !AdService.instance.config.canShowRewarded) return false;
    await preload();
    final ad = _ad;
    if (ad == null) return false;
    _ad = null;
    final completer = Completer<bool>();
    var earned = false;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        preload();
        if (!completer.isCompleted) completer.complete(earned);
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose();
        preload();
        if (!completer.isCompleted) completer.complete(false);
      },
    );
    ad.show(onUserEarnedReward: (_, __) {
      earned = true;
    });
    return completer.future;
  }

  void dispose() {
    _ad?.dispose();
    _ad = null;
  }
}
