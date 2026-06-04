import 'package:cricpro_flutter/services/ads/ads_manager.dart';

/// Backwards-compatible facade for rewarded ads. The waterfall + reward
/// callback handling now live in [AdsManager].
class RewardedAdManager {
  RewardedAdManager._();

  static final RewardedAdManager instance = RewardedAdManager._();

  Future<void> preload() => AdsManager.instance.preloadRewarded();

  /// User-initiated unlock. Returns true only when the reward is earned.
  Future<bool> showForUnlock() => AdsManager.instance.showRewardedForUnlock();

  void dispose() {}
}
