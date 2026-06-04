import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'package:cricpro_flutter/models/ad_config.dart';
import 'package:cricpro_flutter/services/ads/ad_adapter.dart';

/// Direct Google AdMob adapter built on the `google_mobile_ads` plugin.
class AdMobAdapter implements AdNetworkAdapter {
  AdMobAdapter();

  static const _loadTimeout = Duration(seconds: 8);

  // Google sample/test unit IDs — never serve real ads, safe for QA.
  static const _testBannerAndroid = 'ca-app-pub-3940256099942544/6300978111';
  static const _testBannerIos = 'ca-app-pub-3940256099942544/2934735716';
  static const _testInterstitialAndroid = 'ca-app-pub-3940256099942544/1033173712';
  static const _testInterstitialIos = 'ca-app-pub-3940256099942544/4411468910';
  static const _testRewardedAndroid = 'ca-app-pub-3940256099942544/5224354917';
  static const _testRewardedIos = 'ca-app-pub-3940256099942544/1712485313';
  static const _testRewardedInterstitialAndroid =
      'ca-app-pub-3940256099942544/5354046379';
  static const _testRewardedInterstitialIos =
      'ca-app-pub-3940256099942544/6978759866';
  static const _testNativeAndroid = 'ca-app-pub-3940256099942544/2247696110';
  static const _testNativeIos = 'ca-app-pub-3940256099942544/3986624511';
  static const _testAppOpenAndroid = 'ca-app-pub-3940256099942544/9257395921';
  static const _testAppOpenIos = 'ca-app-pub-3940256099942544/5575463023';

  AdNetworkConfig _config = AdNetworkConfig.empty(AdNetwork.admob);
  bool _testMode = kDebugMode;
  bool _initialized = false;

  InterstitialAd? _interstitial;
  RewardedAd? _rewarded;
  RewardedInterstitialAd? _rewardedInterstitial;
  AppOpenAd? _appOpen;

  @override
  AdNetwork get network => AdNetwork.admob;

  @override
  bool get isDirectSupported => !kIsWeb;

  @override
  AdNetworkStatus get status {
    if (kIsWeb) return AdNetworkStatus.notSupported;
    if (!_config.enabled) return AdNetworkStatus.disabled;
    return AdNetworkStatus.active;
  }

  @override
  bool get isReady => _initialized;

  @override
  Future<void> initialize(AdNetworkConfig config, {required bool testMode}) async {
    _config = config;
    _testMode = testMode || config.testMode;
    if (kIsWeb || _initialized) return;
    await MobileAds.instance.initialize();
    _initialized = true;
    if (kDebugMode) debugPrint('[Ads][admob] initialized (test=$_testMode)');
  }

  String? get _bannerUnit {
    if (_testMode) return Platform.isIOS ? _testBannerIos : _testBannerAndroid;
    return _config.bannerId;
  }

  String? get _interstitialUnit {
    if (_testMode) {
      return Platform.isIOS ? _testInterstitialIos : _testInterstitialAndroid;
    }
    return _config.interstitialId;
  }

  String? get _rewardedUnit {
    if (_testMode) {
      return Platform.isIOS ? _testRewardedIos : _testRewardedAndroid;
    }
    return _config.rewardedId;
  }

  String? get _nativeUnit {
    if (_testMode) return Platform.isIOS ? _testNativeIos : _testNativeAndroid;
    return _config.nativeId;
  }

  String? get _rewardedInterstitialUnit {
    if (_testMode) {
      return Platform.isIOS
          ? _testRewardedInterstitialIos
          : _testRewardedInterstitialAndroid;
    }
    return _config.rewardedInterstitialId;
  }

  String? get _appOpenUnit {
    if (_testMode) {
      return Platform.isIOS ? _testAppOpenIos : _testAppOpenAndroid;    }
    return _config.appOpenId;
  }

  @override
  Future<BannerLoadResult> loadBanner(AdPlacement placement) async {
    if (!isReady) return BannerLoadResult.empty;
    final unitId = _bannerUnit;
    if (unitId == null || unitId.isEmpty) return BannerLoadResult.empty;

    final completer = Completer<BannerLoadResult>();
    late final BannerAd ad;
    ad = BannerAd(
      adUnitId: unitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (loadedAd) {
          if (completer.isCompleted) {
            loadedAd.dispose();
            return;
          }
          final banner = loadedAd as BannerAd;
          completer.complete(BannerLoadResult(
            height: banner.size.height.toDouble(),
            dispose: banner.dispose,
            widget: SizedBox(
              width: banner.size.width.toDouble(),
              height: banner.size.height.toDouble(),
              child: AdWidget(ad: banner),
            ),
          ));
        },
        onAdFailedToLoad: (failedAd, error) {
          failedAd.dispose();
          if (kDebugMode) {
            debugPrint('[Ads][admob] banner no-fill: ${error.message}');
          }
          if (!completer.isCompleted) completer.complete(BannerLoadResult.empty);
        },
      ),
    );
    unawaited(ad.load());
    return completer.future.timeout(_loadTimeout, onTimeout: () {
      ad.dispose();
      return BannerLoadResult.empty;
    });
  }

  @override
  Future<NativeLoadResult> loadNative(AdPlacement placement) async {
    if (!isReady) return NativeLoadResult.empty;
    // Native rendering needs the platform-registered factory. Only Android has
    // the "cricproNative" factory registered, so skip elsewhere.
    if (!Platform.isAndroid) return NativeLoadResult.empty;
    final unitId = _nativeUnit;
    if (unitId == null || unitId.isEmpty) return NativeLoadResult.empty;

    final completer = Completer<NativeLoadResult>();
    late final NativeAd ad;
    ad = NativeAd(
      adUnitId: unitId,
      factoryId: 'cricproNative',
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (loadedAd) {
          if (completer.isCompleted) {
            loadedAd.dispose();
            return;
          }
          completer.complete(NativeLoadResult(
            dispose: loadedAd.dispose,
            widget: SizedBox(
              height: 300,
              child: AdWidget(ad: loadedAd as NativeAd),
            ),
          ));
        },
        onAdFailedToLoad: (failedAd, error) {
          failedAd.dispose();
          if (kDebugMode) {
            debugPrint('[Ads][admob] native no-fill: ${error.message}');
          }
          if (!completer.isCompleted) completer.complete(NativeLoadResult.empty);
        },
      ),
    );
    unawaited(ad.load());
    return completer.future.timeout(_loadTimeout, onTimeout: () {
      ad.dispose();
      return NativeLoadResult.empty;
    });
  }

  @override
  Future<bool> loadInterstitial() async {
    if (!isReady || _interstitial != null) return _interstitial != null;
    final unitId = _interstitialUnit;
    if (unitId == null || unitId.isEmpty) return false;
    final completer = Completer<bool>();
    InterstitialAd.load(
      adUnitId: unitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitial = ad;
          if (!completer.isCompleted) completer.complete(true);
        },
        onAdFailedToLoad: (error) {
          _interstitial = null;
          if (kDebugMode) {
            debugPrint('[Ads][admob] interstitial no-fill: ${error.message}');
          }
          if (!completer.isCompleted) completer.complete(false);
        },
      ),
    );
    return completer.future.timeout(_loadTimeout, onTimeout: () => false);
  }

  @override
  Future<bool> showInterstitial() async {
    final ad = _interstitial;
    if (ad == null) return false;
    _interstitial = null;
    final completer = Completer<bool>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        if (!completer.isCompleted) completer.complete(true);
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose();
        if (!completer.isCompleted) completer.complete(false);
      },
    );
    await ad.show();
    return completer.future;
  }

  @override
  Future<bool> loadRewarded() async {
    if (!isReady || _rewarded != null) return _rewarded != null;
    final unitId = _rewardedUnit;
    if (unitId == null || unitId.isEmpty) return false;
    final completer = Completer<bool>();
    RewardedAd.load(
      adUnitId: unitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewarded = ad;
          if (!completer.isCompleted) completer.complete(true);
        },
        onAdFailedToLoad: (error) {
          _rewarded = null;
          if (kDebugMode) {
            debugPrint('[Ads][admob] rewarded no-fill: ${error.message}');
          }
          if (!completer.isCompleted) completer.complete(false);
        },
      ),
    );
    return completer.future.timeout(_loadTimeout, onTimeout: () => false);
  }

  @override
  Future<bool> showRewarded() async {
    final ad = _rewarded;
    if (ad == null) return false;
    _rewarded = null;
    final completer = Completer<bool>();
    var earned = false;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        if (!completer.isCompleted) completer.complete(earned);
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose();
        if (!completer.isCompleted) completer.complete(false);
      },
    );
    await ad.show(onUserEarnedReward: (_, __) => earned = true);
    return completer.future;
  }

  @override
  Future<bool> loadRewardedInterstitial() async {
    if (!isReady || _rewardedInterstitial != null) {
      return _rewardedInterstitial != null;
    }
    final unitId = _rewardedInterstitialUnit;
    if (unitId == null || unitId.isEmpty) return false;
    final completer = Completer<bool>();
    RewardedInterstitialAd.load(
      adUnitId: unitId,
      request: const AdRequest(),
      rewardedInterstitialAdLoadCallback: RewardedInterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _rewardedInterstitial = ad;
          if (!completer.isCompleted) completer.complete(true);
        },
        onAdFailedToLoad: (error) {
          _rewardedInterstitial = null;
          if (kDebugMode) {
            debugPrint(
                '[Ads][admob] rewarded-interstitial no-fill: ${error.message}');
          }
          if (!completer.isCompleted) completer.complete(false);
        },
      ),
    );
    return completer.future.timeout(_loadTimeout, onTimeout: () => false);
  }

  @override
  Future<bool> showRewardedInterstitial() async {
    final ad = _rewardedInterstitial;
    if (ad == null) return false;
    _rewardedInterstitial = null;
    final completer = Completer<bool>();
    var earned = false;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        if (!completer.isCompleted) completer.complete(earned);
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose();
        if (!completer.isCompleted) completer.complete(false);
      },
    );
    await ad.show(onUserEarnedReward: (_, __) => earned = true);
    return completer.future;
  }

  @override
  Future<bool> loadAppOpen() async {
    if (!isReady || _appOpen != null) return _appOpen != null;
    final unitId = _appOpenUnit;
    if (unitId == null || unitId.isEmpty) return false;
    final completer = Completer<bool>();
    AppOpenAd.load(
      adUnitId: unitId,
      request: const AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) {
          _appOpen = ad;
          if (!completer.isCompleted) completer.complete(true);
        },
        onAdFailedToLoad: (error) {
          _appOpen = null;
          if (kDebugMode) {
            debugPrint('[Ads][admob] app-open no-fill: ${error.message}');
          }
          if (!completer.isCompleted) completer.complete(false);
        },
      ),
    );
    return completer.future.timeout(_loadTimeout, onTimeout: () => false);
  }

  @override
  Future<bool> showAppOpen() async {
    final ad = _appOpen;
    if (ad == null) return false;
    _appOpen = null;
    final completer = Completer<bool>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        if (!completer.isCompleted) completer.complete(true);
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose();
        if (!completer.isCompleted) completer.complete(false);
      },
    );
    ad.show();
    return completer.future;
  }

  @override
  void dispose() {
    _interstitial?.dispose();
    _interstitial = null;
    _rewarded?.dispose();
    _rewarded = null;
    _rewardedInterstitial?.dispose();
    _rewardedInterstitial = null;
    _appOpen?.dispose();
    _appOpen = null;
  }
}
