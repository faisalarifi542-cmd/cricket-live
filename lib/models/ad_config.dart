import 'package:flutter/foundation.dart';

import 'package:cricpro_flutter/api_models.dart';

/// Web-safe iOS check. Avoids importing `dart:io` (which is unavailable on web)
/// so [AdConfig.fromAppConfig] can run on every platform during startup.
bool get _isIos => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

enum AdPlacement {
  home,
  matches,
  schedule,
  matchDetails,
  news,
  series,
  more,
  livePlayer,
}

/// The independent ad networks CricPro can serve through.
enum AdNetwork { admob, unity, meta }

AdNetwork? adNetworkFromString(String value) {
  switch (value.trim().toLowerCase()) {
    case 'admob':
      return AdNetwork.admob;
    case 'unity':
      return AdNetwork.unity;
    case 'meta':
    case 'facebook':
    case 'fan':
      return AdNetwork.meta;
  }
  return null;
}

String adNetworkName(AdNetwork network) {
  switch (network) {
    case AdNetwork.admob:
      return 'admob';
    case AdNetwork.unity:
      return 'unity';
    case AdNetwork.meta:
      return 'meta';
  }
}

/// The ad type shown between tapping Watch Live and opening the stream.
enum StreamPreRollAdType {
  none,
  interstitial,
  rewardedInterstitial,
  rewardedVideo
}

StreamPreRollAdType streamPreRollFromString(String value) {
  switch (value.trim().toLowerCase()) {
    case 'interstitial':
      return StreamPreRollAdType.interstitial;
    case 'rewarded_interstitial':
    case 'rewardedinterstitial':
      return StreamPreRollAdType.rewardedInterstitial;
    case 'rewarded_video':
    case 'rewardedvideo':
    case 'rewarded':
      return StreamPreRollAdType.rewardedVideo;
    case 'none':
      return StreamPreRollAdType.none;
  }
  return StreamPreRollAdType.rewardedVideo;
}

/// Per-network unit / placement IDs resolved for the current platform.
class AdNetworkConfig {
  const AdNetworkConfig({
    required this.network,
    required this.enabled,
    required this.testMode,
    required this.appId,
    required this.gameId,
    required this.bannerId,
    required this.nativeId,
    required this.interstitialId,
    required this.rewardedId,
    required this.rewardedInterstitialId,
    required this.appOpenId,
    required this.directSupported,
  });

  final AdNetwork network;
  final bool enabled;
  final bool testMode;

  /// AdMob/Meta app id, or Unity game id depending on the network.
  final String? appId;
  final String? gameId;
  final String? bannerId;
  final String? nativeId;
  final String? interstitialId;
  final String? rewardedId;
  final String? rewardedInterstitialId;
  final String? appOpenId;

  /// Whether the Flutter client has a working direct adapter for this network.
  final bool directSupported;

  static AdNetworkConfig empty(AdNetwork network) => AdNetworkConfig(
        network: network,
        enabled: false,
        testMode: kDebugMode,
        appId: null,
        gameId: null,
        bannerId: null,
        nativeId: null,
        interstitialId: null,
        rewardedId: null,
        rewardedInterstitialId: null,
        appOpenId: null,
        directSupported: network == AdNetwork.admob,
      );
}

class AdConfig {
  const AdConfig({
    required this.enabled,
    required this.testMode,
    required this.consentRequired,
    required this.primaryNetwork,
    required this.fallbackOrder,
    required this.admobEnabled,
    required this.unityEnabled,
    required this.metaEnabled,
    required this.bannerEnabled,
    required this.nativeEnabled,
    required this.interstitialEnabled,
    required this.rewardedEnabled,
    required this.rewardedRequiredForPremiumStreams,
    required this.appOpenEnabled,
    required this.appOpenShowOnColdStart,
    required this.appOpenShowOnResume,
    required this.streamPreRollAdType,
    required this.preRollForFreeStreams,
    required this.preRollForPremiumStreams,
    required this.preRollAllowFallback,
    required this.networks,
    required this.placements,
    required this.frequency,
  });

  final bool enabled;
  final bool testMode;
  final bool consentRequired;
  final AdNetwork primaryNetwork;
  final List<AdNetwork> fallbackOrder;
  final bool admobEnabled;
  final bool unityEnabled;
  final bool metaEnabled;
  final bool bannerEnabled;
  final bool nativeEnabled;
  final bool interstitialEnabled;
  final bool rewardedEnabled;
  final bool rewardedRequiredForPremiumStreams;
  final bool appOpenEnabled;
  final bool appOpenShowOnColdStart;
  final bool appOpenShowOnResume;
  final StreamPreRollAdType streamPreRollAdType;
  final bool preRollForFreeStreams;
  final bool preRollForPremiumStreams;
  final bool preRollAllowFallback;
  final Map<AdNetwork, AdNetworkConfig> networks;
  final Map<String, dynamic> placements;
  final Map<String, dynamic> frequency;

  static final empty = AdConfig(
    enabled: false,
    testMode: true,
    consentRequired: false,
    primaryNetwork: AdNetwork.admob,
    fallbackOrder: const [AdNetwork.admob, AdNetwork.unity, AdNetwork.meta],
    admobEnabled: true,
    unityEnabled: false,
    metaEnabled: false,
    bannerEnabled: false,
    nativeEnabled: false,
    interstitialEnabled: false,
    rewardedEnabled: false,
    rewardedRequiredForPremiumStreams: false,
    appOpenEnabled: false,
    appOpenShowOnColdStart: true,
    appOpenShowOnResume: true,
    streamPreRollAdType: StreamPreRollAdType.rewardedVideo,
    preRollForFreeStreams: false,
    preRollForPremiumStreams: true,
    preRollAllowFallback: false,
    networks: {
      AdNetwork.admob: AdNetworkConfig.empty(AdNetwork.admob),
      AdNetwork.unity: AdNetworkConfig.empty(AdNetwork.unity),
      AdNetwork.meta: AdNetworkConfig.empty(AdNetwork.meta),
    },
    placements: const {},
    frequency: const {},
  );

  factory AdConfig.fromAppConfig(dynamic value) {
    final root = apiMap(value);
    final ads = apiMap(root['ads']);
    final placements = apiMap(ads['placements'] ?? ads['placementConfig']);
    final frequency = apiMap(ads['frequency'] ?? ads['frequencyConfig']);

    final enabled = apiBool(
      ads['enabled'] ?? root['enableAds'] ?? root['features']?['adsEnabled'],
      false,
    );
    final testMode = apiBool(ads['testMode'] ?? ads['test_mode'], false);

    final admobEnabled =
        apiBool(ads['admobEnabled'] ?? ads['admob_enabled'], true);
    final unityEnabled =
        apiBool(ads['unityEnabled'] ?? ads['unity_enabled'], false);
    final metaEnabled =
        apiBool(ads['metaEnabled'] ?? ads['meta_enabled'], false);

    final networksRaw = apiMap(ads['networks']);
    final networks = <AdNetwork, AdNetworkConfig>{
      AdNetwork.admob: _networkConfig(
        AdNetwork.admob,
        apiMap(networksRaw['admob']),
        legacy: ads,
        enabledFallback: admobEnabled,
        testMode: testMode,
      ),
      AdNetwork.unity: _networkConfig(
        AdNetwork.unity,
        apiMap(networksRaw['unity']),
        legacy: ads,
        enabledFallback: unityEnabled,
        testMode: testMode,
      ),
      AdNetwork.meta: _networkConfig(
        AdNetwork.meta,
        apiMap(networksRaw['meta']),
        legacy: ads,
        enabledFallback: metaEnabled,
        testMode: testMode,
      ),
    };

    final primary = adNetworkFromString(apiString(ads['primaryNetwork'])) ??
        AdNetwork.admob;
    final fallback = _parseFallbackOrder(ads['fallbackOrder'], primary);

    final appOpen = apiMap(ads['appOpen'] ?? ads['app_open']);

    return AdConfig(
      enabled: enabled,
      testMode: testMode,
      consentRequired:
          apiBool(ads['consentRequired'] ?? ads['consent_required'], false),
      primaryNetwork: primary,
      fallbackOrder: fallback,
      admobEnabled: admobEnabled,
      unityEnabled: unityEnabled,
      metaEnabled: metaEnabled,
      bannerEnabled:
          apiBool(ads['bannerEnabled'] ?? ads['banner_enabled'], true),
      nativeEnabled:
          apiBool(ads['nativeEnabled'] ?? ads['native_enabled'], true),
      interstitialEnabled: apiBool(
          ads['interstitialEnabled'] ?? ads['interstitial_enabled'], true),
      rewardedEnabled:
          apiBool(ads['rewardedEnabled'] ?? ads['rewarded_enabled'], false),
      rewardedRequiredForPremiumStreams: apiBool(
        ads['rewardedRequiredForPremiumStreams'] ??
            ads['rewarded_required_for_premium_streams'],
        false,
      ),
      appOpenEnabled:
          apiBool(appOpen['enabled'] ?? ads['appOpenEnabled'], false),
      appOpenShowOnColdStart: apiBool(
          appOpen['showOnColdStart'] ?? appOpen['show_on_cold_start'], true),
      appOpenShowOnResume:
          apiBool(appOpen['showOnResume'] ?? appOpen['show_on_resume'], true),
      streamPreRollAdType: streamPreRollFromString(
        apiString(ads['liveStreamPreRollAdType'] ??
            ads['live_stream_pre_roll_ad_type'] ??
            'rewarded_video'),
      ),
      preRollForFreeStreams: apiBool(
        ads['preRollForFreeStreams'] ?? ads['pre_roll_free_streams'],
        false,
      ),
      preRollForPremiumStreams: apiBool(
        ads['preRollForPremiumStreams'] ?? ads['pre_roll_premium_streams'],
        true,
      ),
      preRollAllowFallback: apiBool(
        ads['preRollAllowFallback'] ?? ads['pre_roll_allow_fallback'],
        false,
      ),
      networks: networks,
      placements: placements,
      frequency: frequency,
    );
  }

  static AdNetworkConfig _networkConfig(
    AdNetwork network,
    Map<String, dynamic> data, {
    required Map<String, dynamic> legacy,
    required bool enabledFallback,
    required bool testMode,
  }) {
    final platform = apiMap(
      _isIos ? (data['ios'] ?? data['iOS']) : data['android'],
    );
    final appIdMap = apiMap(data['appId'] ?? data['app_id']);
    final gameIdMap = apiMap(data['gameId'] ?? data['game_id']);
    final isIos = _isIos;

    String? legacyUnit(String kind) {
      // Legacy flat AdMob fields (android_banner_id, ios_rewarded_id, ...).
      if (network != AdNetwork.admob) return null;
      final prefix = isIos ? 'ios' : 'android';
      return _text(legacy['${prefix}_${kind}_id']);
    }

    return AdNetworkConfig(
      network: network,
      enabled: apiBool(data['enabled'], enabledFallback),
      testMode: apiBool(data['testMode'] ?? data['test_mode'], testMode),
      appId: _text(
          isIos ? (appIdMap['ios'] ?? appIdMap['iOS']) : appIdMap['android']),
      gameId: _text(isIos
          ? (gameIdMap['ios'] ?? gameIdMap['iOS'])
          : gameIdMap['android']),
      bannerId: _text(platform['bannerId'] ?? platform['banner_id']) ??
          legacyUnit('banner'),
      nativeId: _text(platform['nativeId'] ?? platform['native_id']) ??
          legacyUnit('native'),
      interstitialId:
          _text(platform['interstitialId'] ?? platform['interstitial_id']) ??
              legacyUnit('interstitial'),
      rewardedId: _text(platform['rewardedId'] ?? platform['rewarded_id']) ??
          legacyUnit('rewarded'),
      rewardedInterstitialId: _text(platform['rewardedInterstitialId'] ??
              platform['rewarded_interstitial_id']) ??
          legacyUnit('rewarded_interstitial'),
      appOpenId: _text(platform['appOpenId'] ?? platform['app_open_id']) ??
          legacyUnit('app_open'),
      directSupported:
          network == AdNetwork.admob || apiBool(data['directSupported'], false),
    );
  }

  static List<AdNetwork> _parseFallbackOrder(dynamic raw, AdNetwork primary) {
    final list = <AdNetwork>[];
    if (raw is List) {
      for (final item in raw) {
        final n = adNetworkFromString(item.toString());
        if (n != null && !list.contains(n)) list.add(n);
      }
    } else if (raw is String) {
      for (final part in raw.split(',')) {
        final n = adNetworkFromString(part);
        if (n != null && !list.contains(n)) list.add(n);
      }
    }
    // Guarantee the primary is first, then every network appears once.
    final ordered = <AdNetwork>[primary];
    for (final n in list) {
      if (!ordered.contains(n)) ordered.add(n);
    }
    for (final n in AdNetwork.values) {
      if (!ordered.contains(n)) ordered.add(n);
    }
    return ordered;
  }

  /// Networks to try, in waterfall order, that are globally enabled for ads.
  List<AdNetwork> get orderedNetworks =>
      fallbackOrder.where(isNetworkEnabled).toList(growable: false);

  bool isNetworkEnabled(AdNetwork network) {
    switch (network) {
      case AdNetwork.admob:
        return admobEnabled;
      case AdNetwork.unity:
        return unityEnabled;
      case AdNetwork.meta:
        return metaEnabled;
    }
  }

  AdNetworkConfig networkConfig(AdNetwork network) =>
      networks[network] ?? AdNetworkConfig.empty(network);

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

  int get minimumAppOpenSeconds =>
      apiInt(frequency['minimumSecondsBetweenAppOpenAds']) ??
      apiInt(frequency['minimum_seconds_between_app_open_ads']) ??
      120;

  /// Cross-resume cooldown for app-open ads. Defaults to 240 minutes (4 hours)
  /// per AdMob best practice — app-open must not spam on every foreground.
  /// Admin can override via `app_open_min_interval_minutes` (or the
  /// `app_open.minIntervalMinutes` placement value surfaced into frequency).
  int get appOpenMinIntervalMinutes {
    final value = apiInt(frequency['appOpenMinIntervalMinutes']) ??
        apiInt(frequency['app_open_min_interval_minutes']);
    if (value != null && value > 0) return value;
    return 240;
  }

  /// Effective minimum seconds between two app-open ads. This is the LARGER of
  /// the legacy seconds field and the 4-hour (default) minute-based cooldown,
  /// so the strict cooldown always wins.
  int get effectiveAppOpenIntervalSeconds {
    final minutesAsSeconds = appOpenMinIntervalMinutes * 60;
    return minutesAsSeconds > minimumAppOpenSeconds
        ? minutesAsSeconds
        : minimumAppOpenSeconds;
  }

  /// The app must have actually been in the background at least this long
  /// before an app-open ad may show on resume. Guards against notification
  /// shade / quick-settings / app-switcher quick resumes. Default 30s.
  int get appOpenMinBackgroundSeconds {
    final value = apiInt(frequency['appOpenMinBackgroundSeconds']) ??
        apiInt(frequency['app_open_min_background_seconds']);
    if (value != null && value >= 0) return value;
    return 30;
  }

  int get maxAppOpenPerSession =>
      apiInt(frequency['maxAppOpenAdsPerSession']) ??
      apiInt(frequency['max_app_open_ads_per_session']) ??
      4;

  // ---- Stream pre-roll session capping (admin-managed) ----
  // Limits how often the Watch Live / quality-switch pre-roll may show in one
  // app session so users are not bombarded. Counted only for ads that actually
  // showed (see AdsManager). All values live under `ads.frequency` and can be
  // overridden by the admin `frequency_config` JSON.

  /// Whether per-session pre-roll capping is enforced. Default ON.
  bool get preRollSessionCapEnabled => apiBool(
      frequency['preRollSessionCapEnabled'] ??
          frequency['pre_roll_session_cap_enabled'],
      true);

  /// Max pre-roll ads that may show in one app session. Default 3.
  int get preRollMaxPerSession =>
      apiInt(frequency['preRollMaxPerSession']) ??
      apiInt(frequency['pre_roll_max_per_session']) ??
      3;

  /// Minimum seconds between two pre-roll ads. Default 180s.
  int get preRollMinSecondsBetweenAds =>
      apiInt(frequency['preRollMinSecondsBetweenAds']) ??
      apiInt(frequency['pre_roll_min_seconds_between_ads']) ??
      180;

  /// Whether a manual quality-card switch may also attempt a pre-roll. Default
  /// ON. Capping still applies, so it is never spammy.
  bool get preRollApplyToQualitySwitch => apiBool(
      frequency['preRollApplyToQualitySwitch'] ??
          frequency['pre_roll_apply_to_quality_switch'],
      true);

  /// Whether a manual server/stream-card switch may also attempt a pre-roll.
  /// Default ON. (No separate server-card UI exists today; reserved for when
  /// one is added.)
  bool get preRollApplyToServerSwitch => apiBool(
      frequency['preRollApplyToServerSwitch'] ??
          frequency['pre_roll_apply_to_server_switch'],
      true);

  /// Master switch for pre-roll ads. When false, no Watch Live / in-player
  /// pre-roll is ever attempted regardless of the selected ad type. Default ON
  /// so existing configs (which omit this field) keep their current behavior.
  bool get preRollEnabled => apiBool(
      frequency['preRollEnabled'] ?? frequency['pre_roll_enabled'], true);

  /// Max pre-roll ads that may show for a single match/stream session (i.e.
  /// within one live player screen). Caps repeated quality/server switches on
  /// the same match. 0 means no per-match limit. Default 1.
  int get preRollMaxPerMatch =>
      apiInt(frequency['preRollMaxPerMatch']) ??
      apiInt(frequency['pre_roll_max_per_match']) ??
      1;

  /// How long to wait for the whole pre-roll attempt (load + show across the
  /// waterfall) before giving up and opening the stream anyway. Bounded to a
  /// sane range so a bad config can't trap users or disable pre-roll entirely.
  /// Default 8s.
  int get preRollTimeoutSeconds {
    final value = apiInt(frequency['preRollTimeoutSeconds']) ??
        apiInt(frequency['pre_roll_timeout_seconds']);
    if (value == null) return 8;
    return value.clamp(3, 30);
  }

  /// Minimum seconds that must elapse between ANY two full-screen ads
  /// (interstitial, rewarded, rewarded interstitial, app open). This is the
  /// cross-format cooldown that prevents e.g. interstitial → app open back to
  /// back.
  int get minimumFullScreenSeconds =>
      apiInt(frequency['minimumSecondsBetweenFullScreenAds']) ??
      apiInt(frequency['minimum_seconds_between_full_screen_ads']) ??
      90;

  bool bannerFor(AdPlacement placement) {
    if (!enabled || !bannerEnabled) return false;
    return _placementBool(placement, 'bannerEnabled', true);
  }

  bool nativeFor(AdPlacement placement) {
    // Native ads need the platform-registered native ad factory. It is wired up
    // for Android ("cricproNative"); other platforms hide native until added.
    if (!nativeFactoryAvailable) return false;
    if (!enabled || !nativeEnabled) return false;
    // Match Details never renders native ads (too close to live content /
    // Watch Live action). Ignore the admin toggle here by design.
    if (placement == AdPlacement.matchDetails) return false;
    return _placementBool(placement, 'nativeEnabled', true);
  }

  /// Whether an interstitial may show on the natural transition for
  /// [placement]. Respects the global interstitial toggle AND the per-placement
  /// admin switch (defaults to true when unspecified).
  bool interstitialFor(AdPlacement placement) {
    if (!canShowInterstitial) return false;
    return _placementBool(placement, 'interstitialEnabled', true);
  }

  /// Whether the interstitial after leaving the live player is enabled
  /// (defaults OFF — opt-in only).
  bool get interstitialAfterPlayer =>
      canShowInterstitial &&
      _placementBool(AdPlacement.livePlayer, 'interstitialAfterEnabled', false);

  static bool get nativeFactoryAvailable =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  bool get canShowInterstitial => enabled && interstitialEnabled;

  bool get canShowRewarded => enabled && rewardedEnabled;

  /// Rewarded unlock for premium streams is allowed when ads are on AND either
  /// the general rewarded toggle OR the "rewarded required for premium streams"
  /// admin switch is enabled. This is the gate the live player should use so a
  /// premium stream is never opened without showing the rewarded ad.
  bool get canShowRewardedForPremium {
    if (!enabled) return false;
    if (!_placementBool(
        AdPlacement.livePlayer, 'premiumStreamRewardedEnabled', true)) {
      return false;
    }
    return rewardedEnabled || rewardedRequiredForPremiumStreams;
  }

  bool get appOpenAllowed => enabled && appOpenEnabled;

  /// Whether the live-stream rewarded-interstitial placement is enabled.
  bool get rewardedInterstitialForLivePlayer => _placementBool(
      AdPlacement.livePlayer, 'rewardedInterstitialEnabled', true);

  /// Whether the live-stream rewarded-video placement is enabled.
  bool get rewardedVideoForLivePlayer => _placementBool(
      AdPlacement.livePlayer, 'premiumStreamRewardedEnabled', true);

  /// Decides which pre-roll ad (if any) must play between tapping Watch Live
  /// and opening the stream. Returns [StreamPreRollAdType.none] when no ad
  /// should show.
  ///
  /// The admin-selected type is honored exactly. We NEVER silently fall back to
  /// a different format unless [preRollAllowFallback] is explicitly enabled —
  /// if the selected type can't run, we return [none] (open directly) for
  /// optional streams, and the caller blocks required premium streams.
  StreamPreRollAdType resolveStreamPreRoll({
    required bool isPremium,
    required bool requiresRewardAd,
  }) {
    if (!enabled) return StreamPreRollAdType.none;
    final isPremiumGatedEarly = isPremium && requiresRewardAd;
    // Master pre-roll switch. A required premium unlock is NOT a pre-roll in
    // this sense — it is the per-stream reward gate — so it bypasses this.
    if (!preRollEnabled && !isPremiumGatedEarly) {
      return StreamPreRollAdType.none;
    }
    final type = streamPreRollAdType;
    if (type == StreamPreRollAdType.none) return StreamPreRollAdType.none;

    final isPremiumGated = isPremium && requiresRewardAd;

    // Respect free / premium pre-roll switches.
    if (isPremiumGated) {
      if (!preRollForPremiumStreams) return StreamPreRollAdType.none;
    } else {
      if (!preRollForFreeStreams) return StreamPreRollAdType.none;
    }

    // Validate the chosen type can actually run; honor it exactly.
    switch (type) {
      case StreamPreRollAdType.none:
        return StreamPreRollAdType.none;
      case StreamPreRollAdType.interstitial:
        if (!canShowInterstitial) return StreamPreRollAdType.none;
        return StreamPreRollAdType.interstitial;
      case StreamPreRollAdType.rewardedVideo:
        if (!canShowRewardedForPremium || !rewardedVideoForLivePlayer) {
          return _preRollFallback();
        }
        return StreamPreRollAdType.rewardedVideo;
      case StreamPreRollAdType.rewardedInterstitial:
        if (!canShowRewardedForPremium || !rewardedInterstitialForLivePlayer) {
          return _preRollFallback();
        }
        return StreamPreRollAdType.rewardedInterstitial;
    }
  }

  /// Only used when the admin-selected rewarded type is unavailable. Returns a
  /// fallback ONLY if [preRollAllowFallback] is on, otherwise [none].
  StreamPreRollAdType _preRollFallback() {
    if (!preRollAllowFallback) return StreamPreRollAdType.none;
    if (canShowInterstitial) return StreamPreRollAdType.interstitial;
    return StreamPreRollAdType.none;
  }

  /// Resolves the pre-roll ad to show when the user taps **Watch Live**,
  /// independent of any specific stream's premium flag.
  ///
  /// Unlike [resolveStreamPreRoll], this does NOT silently drop the ad based on
  /// the free/premium pre-roll switches — those switches gate the per-stream
  /// reward unlock inside the player, not the Watch Live entry ad. Here we
  /// simply honor the admin-selected pre-roll TYPE as long as that format is
  /// globally enabled. This is what makes "AdMob primary + pre-roll
  /// interstitial enabled" actually show an interstitial on Watch Live for a
  /// normal stream.
  StreamPreRollAdType resolveWatchLivePreRoll() {
    if (!enabled) return StreamPreRollAdType.none;
    if (!preRollEnabled) return StreamPreRollAdType.none;
    switch (streamPreRollAdType) {
      case StreamPreRollAdType.none:
        return StreamPreRollAdType.none;
      case StreamPreRollAdType.interstitial:
        if (canShowInterstitial) return StreamPreRollAdType.interstitial;
        return _preRollFallback();
      case StreamPreRollAdType.rewardedVideo:
        if (canShowRewardedForPremium && rewardedVideoForLivePlayer) {
          return StreamPreRollAdType.rewardedVideo;
        }
        return _preRollFallback();
      case StreamPreRollAdType.rewardedInterstitial:
        if (canShowRewardedForPremium && rewardedInterstitialForLivePlayer) {
          return StreamPreRollAdType.rewardedInterstitial;
        }
        return _preRollFallback();
    }
  }

  bool _placementBool(AdPlacement placement, String key, bool fallback) {
    final raw = apiMap(placements[_placementKey(placement)]);
    return apiBool(raw[key] ?? raw[_snake(key)], fallback);
  }

  static String _placementKey(AdPlacement placement) {
    return switch (placement) {
      AdPlacement.home => 'home',
      AdPlacement.matches => 'matches',
      AdPlacement.schedule => 'schedule',
      AdPlacement.matchDetails => 'matchDetails',
      AdPlacement.news => 'news',
      AdPlacement.series => 'series',
      AdPlacement.more => 'more',
      AdPlacement.livePlayer => 'livePlayer',
    };
  }

  static String _snake(String value) => value.replaceAllMapped(
      RegExp('[A-Z]'), (m) => '_${m.group(0)!.toLowerCase()}');

  static String? _text(dynamic value) {
    final text = apiString(value);
    return text.isEmpty ? null : text;
  }
}
