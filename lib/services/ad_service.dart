import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'package:cricpro_flutter/models/ad_config.dart';

class AdService {
  AdService._();

  static final AdService instance = AdService._();

  AdConfig _config = AdConfig.empty;
  bool _initialized = false;

  AdConfig get config => _config;

  Future<void> initialize(AdConfig config) async {
    _config = config;
    if (!_config.enabled || !_config.admobEnabled || kIsWeb) return;
    if (!_initialized) {
      await MobileAds.instance.initialize();
      _initialized = true;
    }
  }

  Future<void> updateConfig(AdConfig config) => initialize(config);

  String? bannerUnitId() {
    if (!_config.enabled || !_config.admobEnabled) return null;
    if (_config.testMode) {
      if (Platform.isAndroid) return 'ca-app-pub-3940256099942544/6300978111';
      if (Platform.isIOS) return 'ca-app-pub-3940256099942544/2934735716';
    }
    if (Platform.isAndroid) return _config.androidBannerId;
    if (Platform.isIOS) return _config.iosBannerId;
    return null;
  }

  String? nativeUnitId() {
    if (!_config.enabled || !_config.admobEnabled) return null;
    if (_config.testMode) {
      if (Platform.isAndroid) return 'ca-app-pub-3940256099942544/2247696110';
      if (Platform.isIOS) return 'ca-app-pub-3940256099942544/3986624511';
    }
    if (Platform.isAndroid) return _config.androidNativeId;
    if (Platform.isIOS) return _config.iosNativeId;
    return null;
  }

  String? interstitialUnitId() {
    if (!_config.enabled || !_config.admobEnabled) return null;
    if (_config.testMode) {
      if (Platform.isAndroid) return 'ca-app-pub-3940256099942544/1033173712';
      if (Platform.isIOS) return 'ca-app-pub-3940256099942544/4411468910';
    }
    if (Platform.isAndroid) return _config.androidInterstitialId;
    if (Platform.isIOS) return _config.iosInterstitialId;
    return null;
  }

  String? rewardedUnitId() {
    if (!_config.enabled || !_config.admobEnabled) return null;
    if (_config.testMode) {
      if (Platform.isAndroid) return 'ca-app-pub-3940256099942544/5224354917';
      if (Platform.isIOS) return 'ca-app-pub-3940256099942544/1712485313';
    }
    if (Platform.isAndroid) return _config.androidRewardedId;
    if (Platform.isIOS) return _config.iosRewardedId;
    return null;
  }
}
