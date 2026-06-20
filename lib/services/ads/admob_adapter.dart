import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'package:cricpro_flutter/models/ad_config.dart';
import 'package:cricpro_flutter/services/ads/ad_adapter.dart';

/// Direct Google ads adapter.
///
/// Supports both normal AdMob unit IDs (`ca-app-pub-.../...`) and Google Ad
/// Manager unit paths (`/.../...`) because the live admin config currently uses
/// GAM paths for banner/interstitial/rewarded-interstitial placements.
class AdMobAdapter implements AdNetworkAdapter {
  AdMobAdapter();

  static const _loadTimeout = Duration(seconds: 8);

  // Google sample/test unit IDs. These are used only when admin testMode=true.
  static const _testBannerAndroid = 'ca-app-pub-3940256099942544/6300978111';
  static const _testBannerIos = 'ca-app-pub-3940256099942544/2934735716';
  static const _testInterstitialAndroid =
      'ca-app-pub-3940256099942544/1033173712';
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
  bool _testMode = false;
  bool _initialized = false;

  InterstitialAd? _interstitial;
  AdManagerInterstitialAd? _adManagerInterstitial;
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
  Future<void> initialize(
    AdNetworkConfig config, {
    required bool testMode,
  }) async {
    _config = config;
    _testMode = testMode || config.testMode;
    if (kIsWeb || _initialized) return;
    await MobileAds.instance.initialize();
    _initialized = true;
    debugPrint('ADS_INIT: network=admob initialized testMode=$_testMode '
        'appId=${_mask(_config.appId)}');
  }

  bool _isAdManagerUnit(String value) => value.trim().startsWith('/');

  bool _isGoogleSampleUnit(String value) =>
      value.contains('ca-app-pub-3940256099942544/');

  String _mask(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'empty';
    if (text.length <= 12) return '***';
    return '${text.substring(0, 10)}...${text.substring(text.length - 6)}';
  }

  void _log(String message) => debugPrint('ADS_ADMOB: $message');

  void _logLoadStart(String placement, String format, String unitId) {
    _log('placement=$placement format=$format unit=${_mask(unitId)} '
        'source=${_isAdManagerUnit(unitId) ? 'ad_manager' : 'admob'} '
        'testMode=$_testMode');
  }

  void _logLoadFail(String placement, String format, LoadAdError error) {
    _log('placement=$placement format=$format failed '
        'code=${error.code} domain=${error.domain} message="${error.message}"');
  }

  String? _unitOrNull(String? value, String placement, String format) {
    final unit = value?.trim();
    if (unit == null || unit.isEmpty) {
      _log(
          'placement=$placement format=$format skipped reason=missing_unit_id');
      return null;
    }
    if (!_testMode && _isGoogleSampleUnit(unit)) {
      _log('placement=$placement format=$format skipped '
          'reason=google_sample_unit_in_real_mode unit=${_mask(unit)}');
      return null;
    }
    return unit;
  }

  String? _configuredBannerUnit(String placement) {
    final raw = _testMode
        ? (Platform.isIOS ? _testBannerIos : _testBannerAndroid)
        : _config.bannerId;
    return _unitOrNull(raw, placement, 'banner');
  }

  String? _configuredInterstitialUnit(String placement) {
    final raw = _testMode
        ? (Platform.isIOS ? _testInterstitialIos : _testInterstitialAndroid)
        : _config.interstitialId;
    return _unitOrNull(raw, placement, 'interstitial');
  }

  String? _configuredRewardedUnit(String placement) {
    final raw = _testMode
        ? (Platform.isIOS ? _testRewardedIos : _testRewardedAndroid)
        : _config.rewardedId;
    return _unitOrNull(raw, placement, 'rewarded');
  }

  String? _configuredRewardedInterstitialUnit(String placement) {
    final raw = _testMode
        ? (Platform.isIOS
            ? _testRewardedInterstitialIos
            : _testRewardedInterstitialAndroid)
        : _config.rewardedInterstitialId;
    return _unitOrNull(raw, placement, 'rewarded_interstitial');
  }

  String? _configuredNativeUnit(String placement) {
    final raw = _testMode
        ? (Platform.isIOS ? _testNativeIos : _testNativeAndroid)
        : _config.nativeId;
    return _unitOrNull(raw, placement, 'native');
  }

  String? _configuredAppOpenUnit(String placement) {
    final raw = _testMode
        ? (Platform.isIOS ? _testAppOpenIos : _testAppOpenAndroid)
        : _config.appOpenId;
    return _unitOrNull(raw, placement, 'app_open');
  }

  @override
  Future<BannerLoadResult> loadBanner(AdPlacement placement) async {
    final placementName = placement.name;
    if (!isReady) return BannerLoadResult.empty;
    final unitId = _configuredBannerUnit(placementName);
    if (unitId == null) return BannerLoadResult.empty;
    _logLoadStart(placementName, 'banner', unitId);

    if (_isAdManagerUnit(unitId)) {
      return _loadAdManagerBanner(placementName, unitId);
    }
    return _loadAdMobBanner(placementName, unitId);
  }

  Future<BannerLoadResult> _loadAdMobBanner(
    String placement,
    String unitId,
  ) async {
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
          _log('placement=$placement format=banner loaded '
              'size=${banner.size.width}x${banner.size.height}');
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
          _logLoadFail(placement, 'banner', error);
          if (!completer.isCompleted) {
            completer.complete(BannerLoadResult.empty);
          }
        },
      ),
    );
    unawaited(ad.load());
    return completer.future.timeout(_loadTimeout, onTimeout: () {
      ad.dispose();
      _log('placement=$placement format=banner failed reason=timeout');
      return BannerLoadResult.empty;
    });
  }

  Future<BannerLoadResult> _loadAdManagerBanner(
    String placement,
    String unitId,
  ) async {
    final completer = Completer<BannerLoadResult>();
    late final AdManagerBannerAd ad;
    ad = AdManagerBannerAd(
      adUnitId: unitId,
      sizes: const [AdSize.banner],
      request: const AdManagerAdRequest(),
      listener: AdManagerBannerAdListener(
        onAdLoaded: (loadedAd) async {
          if (completer.isCompleted) {
            loadedAd.dispose();
            return;
          }
          final banner = loadedAd as AdManagerBannerAd;
          final size = await banner.getPlatformAdSize() ?? AdSize.banner;
          _log('placement=$placement format=banner loaded '
              'size=${size.width}x${size.height}');
          completer.complete(BannerLoadResult(
            height: size.height.toDouble(),
            dispose: banner.dispose,
            widget: SizedBox(
              width: size.width.toDouble(),
              height: size.height.toDouble(),
              child: AdWidget(ad: banner),
            ),
          ));
        },
        onAdFailedToLoad: (failedAd, error) {
          failedAd.dispose();
          _logLoadFail(placement, 'banner', error);
          if (!completer.isCompleted) {
            completer.complete(BannerLoadResult.empty);
          }
        },
      ),
    );
    unawaited(ad.load());
    return completer.future.timeout(_loadTimeout, onTimeout: () {
      ad.dispose();
      _log('placement=$placement format=banner failed reason=timeout');
      return BannerLoadResult.empty;
    });
  }

  @override
  Future<NativeLoadResult> loadNative(AdPlacement placement) async {
    final placementName = placement.name;
    if (!isReady || !Platform.isAndroid) return NativeLoadResult.empty;
    final unitId = _configuredNativeUnit(placementName);
    if (unitId == null) return NativeLoadResult.empty;
    _logLoadStart(placementName, 'native', unitId);

    final completer = Completer<NativeLoadResult>();
    late final NativeAd ad;
    final listener = NativeAdListener(
      onAdLoaded: (loadedAd) {
        if (completer.isCompleted) {
          loadedAd.dispose();
          return;
        }
        _log('placement=$placementName format=native loaded');
        completer.complete(NativeLoadResult(
          dispose: loadedAd.dispose,
          widget:
              SizedBox(height: 300, child: AdWidget(ad: loadedAd as NativeAd)),
        ));
      },
      onAdFailedToLoad: (failedAd, error) {
        failedAd.dispose();
        _logLoadFail(placementName, 'native', error);
        if (!completer.isCompleted) completer.complete(NativeLoadResult.empty);
      },
    );
    ad = _isAdManagerUnit(unitId)
        ? NativeAd.fromAdManagerRequest(
            adUnitId: unitId,
            factoryId: 'cricproNative',
            listener: listener,
            adManagerRequest: const AdManagerAdRequest(),
          )
        : NativeAd(
            adUnitId: unitId,
            factoryId: 'cricproNative',
            request: const AdRequest(),
            listener: listener,
          );
    unawaited(ad.load());
    return completer.future.timeout(_loadTimeout, onTimeout: () {
      ad.dispose();
      _log('placement=$placementName format=native failed reason=timeout');
      return NativeLoadResult.empty;
    });
  }

  @override
  Future<bool> loadInterstitial() async {
    if (!isReady || _interstitial != null || _adManagerInterstitial != null) {
      return _interstitial != null || _adManagerInterstitial != null;
    }
    final unitId = _configuredInterstitialUnit('interstitial');
    if (unitId == null) return false;
    _logLoadStart('interstitial', 'interstitial', unitId);
    return _isAdManagerUnit(unitId)
        ? _loadAdManagerInterstitial(unitId)
        : _loadAdMobInterstitial(unitId);
  }

  Future<bool> _loadAdMobInterstitial(String unitId) async {
    final completer = Completer<bool>();
    InterstitialAd.load(
      adUnitId: unitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _interstitial = ad;
          _log('placement=interstitial format=interstitial loaded');
          if (!completer.isCompleted) completer.complete(true);
        },
        onAdFailedToLoad: (error) {
          _interstitial = null;
          _logLoadFail('interstitial', 'interstitial', error);
          if (!completer.isCompleted) completer.complete(false);
        },
      ),
    );
    return completer.future.timeout(_loadTimeout, onTimeout: () {
      _log('placement=interstitial format=interstitial failed reason=timeout');
      return false;
    });
  }

  Future<bool> _loadAdManagerInterstitial(String unitId) async {
    final completer = Completer<bool>();
    AdManagerInterstitialAd.load(
      adUnitId: unitId,
      request: const AdManagerAdRequest(),
      adLoadCallback: AdManagerInterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _adManagerInterstitial = ad;
          _log('placement=interstitial format=interstitial loaded');
          if (!completer.isCompleted) completer.complete(true);
        },
        onAdFailedToLoad: (error) {
          _adManagerInterstitial = null;
          _logLoadFail('interstitial', 'interstitial', error);
          if (!completer.isCompleted) completer.complete(false);
        },
      ),
    );
    return completer.future.timeout(_loadTimeout, onTimeout: () {
      _log('placement=interstitial format=interstitial failed reason=timeout');
      return false;
    });
  }

  @override
  Future<bool> showInterstitial() async {
    final managerAd = _adManagerInterstitial;
    if (managerAd != null) {
      _adManagerInterstitial = null;
      final completer = Completer<bool>();
      managerAd.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (ad) {
          ad.dispose();
          if (!completer.isCompleted) completer.complete(true);
        },
        onAdFailedToShowFullScreenContent: (ad, error) {
          ad.dispose();
          _log('placement=interstitial format=interstitial show_failed '
              'code=${error.code} message="${error.message}"');
          if (!completer.isCompleted) completer.complete(false);
        },
      );
      await managerAd.show();
      return completer.future;
    }

    final ad = _interstitial;
    if (ad == null) return false;
    _interstitial = null;
    final completer = Completer<bool>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        if (!completer.isCompleted) completer.complete(true);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _log('placement=interstitial format=interstitial show_failed '
            'code=${error.code} message="${error.message}"');
        if (!completer.isCompleted) completer.complete(false);
      },
    );
    await ad.show();
    return completer.future;
  }

  @override
  Future<bool> loadRewarded() async {
    if (!isReady || _rewarded != null) return _rewarded != null;
    final unitId = _configuredRewardedUnit('live_player_preroll');
    if (unitId == null) return false;
    _logLoadStart('live_player_preroll', 'rewarded', unitId);
    final completer = Completer<bool>();
    final callback = RewardedAdLoadCallback(
      onAdLoaded: (ad) {
        _rewarded = ad;
        _log('placement=live_player_preroll format=rewarded loaded');
        if (!completer.isCompleted) completer.complete(true);
      },
      onAdFailedToLoad: (error) {
        _rewarded = null;
        _logLoadFail('live_player_preroll', 'rewarded', error);
        if (!completer.isCompleted) completer.complete(false);
      },
    );
    if (_isAdManagerUnit(unitId)) {
      RewardedAd.loadWithAdManagerAdRequest(
        adUnitId: unitId,
        adManagerRequest: const AdManagerAdRequest(),
        rewardedAdLoadCallback: callback,
      );
    } else {
      RewardedAd.load(
        adUnitId: unitId,
        request: const AdRequest(),
        rewardedAdLoadCallback: callback,
      );
    }
    return completer.future.timeout(_loadTimeout, onTimeout: () {
      _log(
          'placement=live_player_preroll format=rewarded failed reason=timeout');
      return false;
    });
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
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _log('placement=live_player_preroll format=rewarded show_failed '
            'code=${error.code} message="${error.message}"');
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
    final unitId = _configuredRewardedInterstitialUnit('live_player_preroll');
    if (unitId == null) return false;
    _logLoadStart('live_player_preroll', 'rewarded_interstitial', unitId);
    final completer = Completer<bool>();
    final callback = RewardedInterstitialAdLoadCallback(
      onAdLoaded: (ad) {
        _rewardedInterstitial = ad;
        _log(
            'placement=live_player_preroll format=rewarded_interstitial loaded');
        if (!completer.isCompleted) completer.complete(true);
      },
      onAdFailedToLoad: (error) {
        _rewardedInterstitial = null;
        _logLoadFail('live_player_preroll', 'rewarded_interstitial', error);
        if (!completer.isCompleted) completer.complete(false);
      },
    );
    if (_isAdManagerUnit(unitId)) {
      RewardedInterstitialAd.loadWithAdManagerAdRequest(
        adUnitId: unitId,
        adManagerRequest: const AdManagerAdRequest(),
        rewardedInterstitialAdLoadCallback: callback,
      );
    } else {
      RewardedInterstitialAd.load(
        adUnitId: unitId,
        request: const AdRequest(),
        rewardedInterstitialAdLoadCallback: callback,
      );
    }
    return completer.future.timeout(_loadTimeout, onTimeout: () {
      _log('placement=live_player_preroll format=rewarded_interstitial failed '
          'reason=timeout');
      return false;
    });
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
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _log('placement=live_player_preroll format=rewarded_interstitial '
            'show_failed code=${error.code} message="${error.message}"');
        if (!completer.isCompleted) completer.complete(false);
      },
    );
    await ad.show(onUserEarnedReward: (_, __) => earned = true);
    return completer.future;
  }

  @override
  Future<bool> loadAppOpen() async {
    if (!isReady || _appOpen != null) return _appOpen != null;
    final unitId = _configuredAppOpenUnit('app_open');
    if (unitId == null) return false;
    if (_isAdManagerUnit(unitId)) {
      _log('placement=app_open format=app_open skipped '
          'reason=ad_manager_app_open_not_supported unit=${_mask(unitId)}');
      return false;
    }
    _logLoadStart('app_open', 'app_open', unitId);
    final completer = Completer<bool>();
    AppOpenAd.load(
      adUnitId: unitId,
      request: const AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) {
          _appOpen = ad;
          _log('placement=app_open format=app_open loaded');
          if (!completer.isCompleted) completer.complete(true);
        },
        onAdFailedToLoad: (error) {
          _appOpen = null;
          _logLoadFail('app_open', 'app_open', error);
          if (!completer.isCompleted) completer.complete(false);
        },
      ),
    );
    return completer.future.timeout(_loadTimeout, onTimeout: () {
      _log('placement=app_open format=app_open failed reason=timeout');
      return false;
    });
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
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _log('placement=app_open format=app_open show_failed '
            'code=${error.code} message="${error.message}"');
        if (!completer.isCompleted) completer.complete(false);
      },
    );
    await ad.show();
    return completer.future;
  }

  @override
  void dispose() {
    _interstitial?.dispose();
    _interstitial = null;
    _adManagerInterstitial?.dispose();
    _adManagerInterstitial = null;
    _rewarded?.dispose();
    _rewarded = null;
    _rewardedInterstitial?.dispose();
    _rewardedInterstitial = null;
    _appOpen?.dispose();
    _appOpen = null;
  }
}
