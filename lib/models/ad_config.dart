import 'package:flutter/foundation.dart';

import 'package:cricpro_flutter/api_models.dart';

enum AdPlacement {
  home,
  matches,
  matchDetails,
  news,
  series,
  more,
  livePlayer,
}

class AdConfig {
  const AdConfig({
    required this.enabled,
    required this.testMode,
    required this.admobEnabled,
    required this.unityEnabled,
    required this.metaEnabled,
    required this.bannerEnabled,
    required this.nativeEnabled,
    required this.interstitialEnabled,
    required this.rewardedEnabled,
    required this.rewardedRequiredForPremiumStreams,
    required this.androidBannerId,
    required this.androidNativeId,
    required this.androidInterstitialId,
    required this.androidRewardedId,
    required this.iosBannerId,
    required this.iosNativeId,
    required this.iosInterstitialId,
    required this.iosRewardedId,
    required this.placements,
    required this.frequency,
  });

  final bool enabled;
  final bool testMode;
  final bool admobEnabled;
  final bool unityEnabled;
  final bool metaEnabled;
  final bool bannerEnabled;
  final bool nativeEnabled;
  final bool interstitialEnabled;
  final bool rewardedEnabled;
  final bool rewardedRequiredForPremiumStreams;
  final String? androidBannerId;
  final String? androidNativeId;
  final String? androidInterstitialId;
  final String? androidRewardedId;
  final String? iosBannerId;
  final String? iosNativeId;
  final String? iosInterstitialId;
  final String? iosRewardedId;
  final Map<String, dynamic> placements;
  final Map<String, dynamic> frequency;

  static const empty = AdConfig(
    enabled: false,
    testMode: true,
    admobEnabled: true,
    unityEnabled: false,
    metaEnabled: false,
    bannerEnabled: false,
    nativeEnabled: false,
    interstitialEnabled: false,
    rewardedEnabled: false,
    rewardedRequiredForPremiumStreams: false,
    androidBannerId: null,
    androidNativeId: null,
    androidInterstitialId: null,
    androidRewardedId: null,
    iosBannerId: null,
    iosNativeId: null,
    iosInterstitialId: null,
    iosRewardedId: null,
    placements: {},
    frequency: {},
  );

  factory AdConfig.fromAppConfig(dynamic value) {
    final root = apiMap(value);
    final ads = apiMap(root['ads']);
    final android = apiMap(ads['android'] ?? ads['units']?['android']);
    final ios = apiMap(ads['ios'] ?? ads['units']?['ios']);
    final placements = apiMap(ads['placements'] ?? ads['placementConfig']);
    final frequency = apiMap(ads['frequency'] ?? ads['frequencyConfig']);

    final enabled = apiBool(
      ads['enabled'] ?? root['enableAds'] ?? root['features']?['adsEnabled'],
      false,
    );
    final testMode = kDebugMode || apiBool(ads['testMode'] ?? ads['test_mode'], false);

    return AdConfig(
      enabled: enabled,
      testMode: testMode,
      admobEnabled: apiBool(ads['admobEnabled'] ?? ads['admob_enabled'], true),
      unityEnabled: apiBool(ads['unityEnabled'] ?? ads['unity_enabled'], false),
      metaEnabled: apiBool(ads['metaEnabled'] ?? ads['meta_enabled'], false),
      bannerEnabled: apiBool(ads['bannerEnabled'] ?? ads['banner_enabled'], true),
      nativeEnabled: apiBool(ads['nativeEnabled'] ?? ads['native_enabled'], true),
      interstitialEnabled:
          apiBool(ads['interstitialEnabled'] ?? ads['interstitial_enabled'], true),
      rewardedEnabled: apiBool(ads['rewardedEnabled'] ?? ads['rewarded_enabled'], false),
      rewardedRequiredForPremiumStreams: apiBool(
        ads['rewardedRequiredForPremiumStreams'] ??
            ads['rewarded_required_for_premium_streams'],
        false,
      ),
      androidBannerId:
          _text(android['bannerId'] ?? android['banner_id'] ?? ads['android_banner_id']),
      androidNativeId:
          _text(android['nativeId'] ?? android['native_id'] ?? ads['android_native_id']),
      androidInterstitialId: _text(android['interstitialId'] ??
          android['interstitial_id'] ??
          ads['android_interstitial_id']),
      androidRewardedId: _text(
          android['rewardedId'] ?? android['rewarded_id'] ?? ads['android_rewarded_id']),
      iosBannerId: _text(ios['bannerId'] ?? ios['banner_id'] ?? ads['ios_banner_id']),
      iosNativeId: _text(ios['nativeId'] ?? ios['native_id'] ?? ads['ios_native_id']),
      iosInterstitialId:
          _text(ios['interstitialId'] ?? ios['interstitial_id'] ?? ads['ios_interstitial_id']),
      iosRewardedId:
          _text(ios['rewardedId'] ?? ios['rewarded_id'] ?? ads['ios_rewarded_id']),
      placements: placements,
      frequency: frequency,
    );
  }

  int get minimumInterstitialSeconds =>
      apiInt(frequency['minimumSecondsBetweenInterstitials']) ??
      apiInt(frequency['minimum_seconds_between_interstitials']) ??
      apiInt(frequency['minSeconds']) ??
      ((apiInt(frequency['frequencyMinutes']) ??
              apiInt(frequency['frequency_minutes']) ??
              5) *
          60);

  int get interstitialFrequencyCap =>
      apiInt(frequency['interstitialFrequencyCap']) ??
      apiInt(frequency['interstitial_frequency_cap']) ??
      apiInt(frequency['frequencyCap']) ??
      1;

  bool bannerFor(AdPlacement placement) {
    if (!enabled || !admobEnabled || !bannerEnabled) return false;
    return _placementBool(placement, 'bannerEnabled', true);
  }

  bool nativeFor(AdPlacement placement) {
    // Native ads stay off until Android/iOS native factories are implemented.
    if (!nativeFactoryAvailable) return false;
    if (!enabled || !admobEnabled || !nativeEnabled) return false;
    return _placementBool(placement, 'nativeEnabled', true);
  }

  static bool get nativeFactoryAvailable => false;

  bool get canShowInterstitial =>
      enabled && admobEnabled && interstitialEnabled;

  bool get canShowRewarded => enabled && admobEnabled && rewardedEnabled;

  bool _placementBool(AdPlacement placement, String key, bool fallback) {
    final raw = apiMap(placements[_placementKey(placement)]);
    return apiBool(raw[key] ?? raw[_snake(key)], fallback);
  }

  static String _placementKey(AdPlacement placement) {
    return switch (placement) {
      AdPlacement.home => 'home',
      AdPlacement.matches => 'matches',
      AdPlacement.matchDetails => 'matchDetails',
      AdPlacement.news => 'news',
      AdPlacement.series => 'series',
      AdPlacement.more => 'more',
      AdPlacement.livePlayer => 'livePlayer',
    };
  }

  static String _snake(String value) => value
      .replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m.group(0)!.toLowerCase()}');

  static String? _text(dynamic value) {
    final text = apiString(value);
    return text.isEmpty ? null : text;
  }
}
