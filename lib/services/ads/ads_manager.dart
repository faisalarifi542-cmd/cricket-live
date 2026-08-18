import 'package:flutter/foundation.dart';

import 'package:cricpro_flutter/models/ad_config.dart';
import 'package:cricpro_flutter/services/ads/ad_adapter.dart';
import 'package:cricpro_flutter/services/ads/admob_adapter.dart';
import 'package:cricpro_flutter/services/ads/att_service.dart';
import 'package:cricpro_flutter/services/ads/consent_manager.dart';
import 'package:cricpro_flutter/services/ads/meta_adapter.dart';
import 'package:cricpro_flutter/services/ads/unity_adapter.dart';

/// Outcome of a stream pre-roll ad attempt.
enum StreamAdResult { allowed, failed }

/// Why a pre-roll attempt may be skipped by session capping.
enum PreRollCapDecision { allow, sessionCap, minInterval }

/// What triggered an app-open ad attempt. Used for logging and policy gating.
enum AppOpenTrigger { coldStart, resume }

/// Central, adapter-based ads coordinator.
///
/// Owns one adapter per network and runs the admin-configured waterfall:
/// primary network first, then each enabled fallback network in order. It
/// never crashes the app when a network fails — it just moves on, and hides ad
/// space when every network has no fill.
class AdsManager {
  AdsManager._();

  static final AdsManager instance = AdsManager._();

  final Map<AdNetwork, AdNetworkAdapter> _adapters = {
    AdNetwork.admob: AdMobAdapter(),
    AdNetwork.unity: UnityAdapter(),
    AdNetwork.meta: MetaAdapter(),
  };

  AdConfig _config = AdConfig.empty;
  bool _initialized = false;
  final ValueNotifier<int> configRevision = ValueNotifier<int>(0);

  // Frequency control.
  DateTime? _lastInterstitialAt;
  int _interstitialsThisSession = 0;
  DateTime? _lastAppOpenAt;
  int _appOpensThisSession = 0;

  // Stream pre-roll session capping. Counts only ads that ACTUALLY showed,
  // resets when the app process restarts (in-memory only).
  DateTime? _lastPreRollAt;
  int _preRollShownThisSession = 0;

  /// Timestamp of the most recent FULL-SCREEN ad of any kind (interstitial,
  /// rewarded, rewarded interstitial, app open). Used for the cross-format
  /// cooldown that prevents stacking two full-screen ads on one transition
  /// (e.g. interstitial immediately followed by app open).
  DateTime? _lastFullScreenAt;

  /// When true, a video is playing (live player active) — interstitials and
  /// app-open ads must NOT show. Live player sets/clears this.
  bool _videoPlaying = false;

  /// True while ANY full-screen ad (interstitial, rewarded, rewarded
  /// interstitial, app open) is currently on screen. Prevents stacking a new
  /// full-screen ad on top of another, and prevents the ad's own
  /// pause/resume lifecycle from arming a second app-open ad.
  bool _isShowingAd = false;

  AdConfig get config => _config;

  /// Whether a full-screen ad is currently visible.
  bool get isShowingAd => _isShowingAd;

  /// When the last app-open ad was shown (null if none this process). Exposed
  /// for APP_OPEN_DEBUG diagnostics.
  DateTime? get lastAppOpenShownAt => _lastAppOpenAt;

  /// How many app-open ads have shown this session. Exposed for diagnostics.
  int get appOpensThisSession => _appOpensThisSession;

  /// How many stream pre-rolls have actually shown this session. Exposed for
  /// PreRollGate diagnostics/logging.
  int get preRollShownThisSession => _preRollShownThisSession;

  set videoPlaying(bool value) {
    _videoPlaying = value;
    if (kDebugMode) debugPrint('[Ads] videoPlaying=$value');
  }

  bool get videoPlaying => _videoPlaying;

  /// Whether the cross-format full-screen cooldown currently blocks a new
  /// full-screen ad.
  bool get _fullScreenCooldownActive {
    final last = _lastFullScreenAt;
    if (last == null) return false;
    return DateTime.now().difference(last).inSeconds <
        _config.minimumFullScreenSeconds;
  }

  /// Records that a full-screen ad was shown (drives the cross-format cooldown).
  void _markFullScreenShown() {
    _lastFullScreenAt = DateTime.now();
  }

  /// Unconditional waterfall logging for Watch Live pre-roll diagnostics.
  /// Visible in logcat / `flutter logs` on a real device.
  void _waterfallLog(
    String network,
    String format,
    String result, [
    String reason = '',
  ]) {
    debugPrint('AD_WATERFALL: placement=live_player_preroll network=$network '
        'format=$format result=$result'
        '${reason.isEmpty ? '' : ' reason=$reason'}');
  }

  /// Initializes/refreshes ads from the latest [AdConfig]. Safe to call again
  /// when the config changes; only enabled, supported networks are touched.
  Future<void> initialize(AdConfig config) async {
    _config = config;
    configRevision.value += 1;
    if (kIsWeb || !config.enabled) {
      debugPrint('ADS_CONFIG: disabled enabled=${config.enabled} web=$kIsWeb');
      return;
    }

    debugPrint(
      'ADS_CONFIG: loaded enabled=${config.enabled} '
      'primary=${adNetworkName(config.primaryNetwork)} '
      'order=${config.orderedNetworks.map(adNetworkName).join(">")} '
      'testMode=${config.testMode} consentRequired=${config.consentRequired} '
      'banner=${config.bannerEnabled} interstitial=${config.interstitialEnabled} '
      'rewarded=${config.rewardedEnabled} preRoll=${config.streamPreRollAdType.name}',
    );
    debugPrint(
      'ADS_CONFIG: appOpen=${config.appOpenAllowed} '
      'coldStart=${config.appOpenShowOnColdStart} '
      'resume=${config.appOpenShowOnResume} '
      'nativeFactoryAvailable=${AdConfig.nativeFactoryAvailable}',
    );

    // GDPR/UMP consent must be resolved BEFORE any ad SDK loads ads.
    await ConsentManager.instance.gatherConsent(
      testMode: config.testMode,
    );
    if (!ConsentManager.instance.canRequestAdsNow) {
      debugPrint('ADS_CONFIG: ad initialization skipped '
          'reason=ump_can_request_ads_false');
      _initialized = false;
      return;
    }
    debugPrint('ADS_CONFIG: UMP complete; ad SDK initialization starting');

    // iOS ATT: request tracking authorization before the ad SDKs load so they
    // can access IDFA when the user grants it. Apple requires this prompt
    // before IDFA access; it is the platform-level counterpart to UMP's
    // regional consent. No-op on Android/web; fail-open (never blocks init).
    await AttService.instance.requestIfNeeded();

    for (final network in config.orderedNetworks) {
      final adapter = _adapters[network]!;
      if (!adapter.isDirectSupported) {
        if (kDebugMode) {
          debugPrint(
            '[Ads] ${adNetworkName(network)} not available on this platform; skipping',
          );
        }
        continue;
      }
      try {
        await adapter.initialize(
          config.networkConfig(network),
          testMode: config.testMode,
        );
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[Ads] ${adNetworkName(network)} init failed: $e');
        }
      }
    }
    _initialized = true;
  }

  Future<void> updateConfig(AdConfig config) => initialize(config);

  /// Adapters to try for a placement, in waterfall order, that are enabled,
  /// supported and ready.
  Iterable<AdNetworkAdapter> get _activeAdapters sync* {
    for (final network in _config.orderedNetworks) {
      final adapter = _adapters[network];
      if (adapter == null) continue;
      if (!adapter.isDirectSupported || !adapter.isReady) continue;
      yield adapter;
    }
  }

  // ---- Banner ----

  /// Tries each enabled network in order for a banner. Returns an empty result
  /// (caller hides the slot) when nothing fills.
  Future<BannerLoadResult> loadBanner(AdPlacement placement) async {
    if (kIsWeb || !_config.bannerFor(placement)) {
      debugPrint('ADS_LOAD: placement=${placement.name} format=banner skipped '
          'reason=disabled_or_web');
      return BannerLoadResult.empty;
    }
    for (final adapter in _activeAdapters) {
      debugPrint('ADS_LOAD: placement=${placement.name} format=banner '
          'network=${adNetworkName(adapter.network)} start');
      final result = await adapter.loadBanner(placement);
      if (result.loaded) {
        debugPrint('ADS_LOAD: placement=${placement.name} format=banner '
            'network=${adNetworkName(adapter.network)} loaded');
        return result;
      }
    }
    debugPrint('ADS_LOAD: placement=${placement.name} format=banner failed '
        'reason=no_fill_all_networks');
    return BannerLoadResult.empty;
  }

  // ---- Native ----

  /// Tries each enabled network in order for a native ad. Returns an empty
  /// result (caller hides the slot) when nothing fills.
  Future<NativeLoadResult> loadNative(AdPlacement placement) async {
    if (kIsWeb || !_config.nativeFor(placement)) return NativeLoadResult.empty;
    for (final adapter in _activeAdapters) {
      final result = await adapter.loadNative(placement);
      if (result.loaded) {
        if (kDebugMode) {
          debugPrint(
              '[Ads] native filled by ${adNetworkName(adapter.network)}');
        }
        return result;
      }
    }
    if (kDebugMode) debugPrint('[Ads] native no-fill across all networks');
    return NativeLoadResult.empty;
  }

  // ---- Interstitial ----

  bool get _interstitialAllowedByFrequency {
    if (_interstitialsThisSession >= _config.interstitialFrequencyCap) {
      return false;
    }
    final last = _lastInterstitialAt;
    if (last == null) return true;
    return DateTime.now().difference(last).inSeconds >=
        _config.minimumInterstitialSeconds;
  }

  Future<void> preloadInterstitial() async {
    if (kIsWeb || !_config.canShowInterstitial) return;
    for (final adapter in _activeAdapters) {
      debugPrint('ADS_LOAD: placement=preload format=interstitial '
          'network=${adNetworkName(adapter.network)} start');
      if (await adapter.loadInterstitial()) return;
    }
    debugPrint('ADS_LOAD: placement=preload format=interstitial failed '
        'reason=no_fill_all_networks');
  }

  /// Shows an interstitial on a natural transition for [placement] if the
  /// per-placement admin toggle and frequency caps allow it. Never shown
  /// during launch or live video.
  Future<bool> maybeShowInterstitial({AdPlacement? placement}) async {
    if (kIsWeb || !_config.canShowInterstitial) return false;
    if (_isShowingAd) {
      if (kDebugMode) {
        debugPrint('[Ads] interstitial blocked: another ad is already showing');
      }
      return false;
    }
    if (_videoPlaying) {
      if (kDebugMode) debugPrint('[Ads] interstitial blocked: video playing');
      return false;
    }
    if (placement != null && !_config.interstitialFor(placement)) {
      if (kDebugMode) {
        debugPrint('[Ads] interstitial disabled for placement $placement');
      }
      return false;
    }
    if (_fullScreenCooldownActive) {
      if (kDebugMode) {
        debugPrint('[Ads] interstitial blocked: full-screen cooldown active');
      }
      return false;
    }
    if (!_interstitialAllowedByFrequency) {
      if (kDebugMode) debugPrint('[Ads] interstitial blocked by frequency cap');
      return false;
    }
    for (final adapter in _activeAdapters) {
      if (!await adapter.loadInterstitial()) continue;
      _isShowingAd = true;
      bool shown;
      try {
        shown = await adapter.showInterstitial();
      } finally {
        _isShowingAd = false;
      }
      if (shown) {
        _lastInterstitialAt = DateTime.now();
        _interstitialsThisSession += 1;
        _markFullScreenShown();
        if (kDebugMode) {
          debugPrint(
              '[Ads] interstitial shown by ${adNetworkName(adapter.network)}');
        }
        // Warm the next one for this adapter.
        unawaitedPreload(adapter);
        return true;
      }
    }
    return false;
  }

  void unawaitedPreload(AdNetworkAdapter adapter) {
    // Fire-and-forget preload; failures are swallowed by the adapter.
    adapter.loadInterstitial();
  }

  // ---- Rewarded ----

  Future<void> preloadRewarded() async {
    if (kIsWeb || !_config.canShowRewardedForPremium) return;
    for (final adapter in _activeAdapters) {
      if (await adapter.loadRewarded()) return;
    }
  }

  /// User-initiated only. Returns true only when the reward is actually earned.
  /// Tries each enabled network so a rewarded unlock can fall back too. Uses
  /// the premium gate so it works when only "rewarded required for premium
  /// streams" is enabled (not just the general rewarded toggle).
  Future<bool> showRewardedForUnlock() async {
    if (kIsWeb || !_config.canShowRewardedForPremium) {
      if (kDebugMode) {
        debugPrint('[Ads] rewarded unlock blocked: enabled=${_config.enabled} '
            'rewardedEnabled=${_config.rewardedEnabled} '
            'premiumRewarded=${_config.rewardedRequiredForPremiumStreams}');
      }
      return false;
    }
    for (final adapter in _activeAdapters) {
      if (kDebugMode) {
        debugPrint(
            '[Ads] rewarded load start via ${adNetworkName(adapter.network)}');
      }
      if (!await adapter.loadRewarded()) continue;
      _isShowingAd = true;
      bool earned;
      try {
        earned = await adapter.showRewarded();
      } finally {
        _isShowingAd = false;
      }
      if (kDebugMode) {
        debugPrint(
            '[Ads] rewarded earned=$earned via ${adNetworkName(adapter.network)}');
      }
      if (earned) {
        _markFullScreenShown();
        return true;
      }
    }
    if (kDebugMode) {
      debugPrint('[Ads] rewarded unavailable across all networks');
    }
    return false;
  }

  // ---- Stream pre-roll session capping ----

  /// Decides whether a pre-roll may be attempted now under the admin session
  /// cap. Does NOT consider whether an ad will fill — only frequency policy.
  /// Callers must still fail open when an attempt fails. Required premium
  /// unlocks should bypass this (capping must never gate a paid unlock).
  PreRollCapDecision preRollCapDecision() {
    if (!_config.preRollSessionCapEnabled) return PreRollCapDecision.allow;
    if (_preRollShownThisSession >= _config.preRollMaxPerSession) {
      return PreRollCapDecision.sessionCap;
    }
    final last = _lastPreRollAt;
    if (last != null &&
        DateTime.now().difference(last).inSeconds <
            _config.preRollMinSecondsBetweenAds) {
      return PreRollCapDecision.minInterval;
    }
    return PreRollCapDecision.allow;
  }

  /// Records a pre-roll that ACTUALLY showed (drives session capping). Called
  /// from the stream pre-roll show paths only, so failed/no-fill/timeout
  /// attempts never count against the cap.
  void _markPreRollShown() {
    _preRollShownThisSession += 1;
    _lastPreRollAt = DateTime.now();
  }

  // ---- Stream pre-roll (Watch Live → ad → stream) ----

  /// Plays the admin-configured pre-roll ad for a stream and reports whether
  /// the stream may open. Exactly ONE ad show attempt per call.
  ///
  /// * [StreamPreRollAdType.none] → allowed immediately.
  /// * interstitial → show once; allowed even if it fails (it's not a gate),
  ///   but for a *required premium* stream a failure blocks opening.
  /// * rewarded / rewarded interstitial → must be earned to open.
  Future<StreamAdResult> showStreamPreRoll({
    required StreamPreRollAdType type,
    required bool isRequiredForPremium,
  }) async {
    if (kIsWeb || type == StreamPreRollAdType.none) {
      return StreamAdResult.allowed;
    }
    switch (type) {
      case StreamPreRollAdType.none:
        return StreamAdResult.allowed;
      case StreamPreRollAdType.interstitial:
        final shown =
            await _showStreamInterstitial(isRequiredForPremium: isRequiredForPremium);
        // Interstitial is not a hard reward gate. For a required premium
        // stream we still require it to have shown; for free streams we allow.
        if (shown || !isRequiredForPremium) return StreamAdResult.allowed;
        return StreamAdResult.failed;
      case StreamPreRollAdType.rewardedVideo:
        final earned = await _showStreamRewarded(rewardedInterstitial: false);
        return earned ? StreamAdResult.allowed : StreamAdResult.failed;
      case StreamPreRollAdType.rewardedInterstitial:
        final earned = await _showStreamRewarded(rewardedInterstitial: true);
        return earned ? StreamAdResult.allowed : StreamAdResult.failed;
    }
  }

  /// Load timeout for the pre-roll load phase ONLY. The show → dismiss phase is
  /// NEVER timed out — once an ad is on screen we wait for the real dismiss/fail
  /// callback, so the stream never starts behind a still-visible ad.
  Duration get _preRollLoadTimeout =>
      Duration(seconds: _config.preRollTimeoutSeconds);

  Future<bool> _showStreamInterstitial({
    required bool isRequiredForPremium,
  }) async {
    // Hard guard: a second concurrent full-screen ad show is never allowed.
    // `_isShowingAd` stays true for the WHOLE show → dismiss/fail window (see
    // the try/finally below), so this also blocks a duplicate pre-roll that
    // tries to start while the first ad is still on screen.
    if (_isShowingAd) {
      _waterfallLog('none', 'interstitial', 'skipped', 'ad already showing');
      return false;
    }
    // A non-required pre-roll interstitial must respect the cross-format
    // full-screen cooldown so it cannot stack right after a match-details
    // interstitial. A required premium unlock is explicit user action and
    // bypasses the cooldown.
    if (!isRequiredForPremium && _fullScreenCooldownActive) {
      _waterfallLog('none', 'interstitial', 'skipped', 'full-screen cooldown');
      return false;
    }
    var attempted = false;
    for (final adapter in _activeAdapters) {
      attempted = true;
      final net = adNetworkName(adapter.network);
      // Timeout bounds the LOAD only; the show/dismiss wait is never bounded.
      final loaded = await adapter
          .loadInterstitial()
          .timeout(_preRollLoadTimeout, onTimeout: () => false);
      if (!loaded) {
        _waterfallLog(net, 'interstitial', 'failed', 'no-fill/load failed');
        continue;
      }
      _waterfallLog(net, 'interstitial', 'loaded');
      _isShowingAd = true;
      bool shown;
      try {
        // No timeout: wait for the real onAdDismissed/onAdFailedToShow callback.
        shown = await adapter.showInterstitial();
      } finally {
        _isShowingAd = false;
      }
      _waterfallLog(net, 'interstitial', shown ? 'shown' : 'failed',
          shown ? '' : 'show failed');
      if (shown) {
        _lastInterstitialAt = DateTime.now();
        _interstitialsThisSession += 1;
        _markFullScreenShown();
        _markPreRollShown();
        return true;
      }
    }
    if (!attempted) {
      _waterfallLog('none', 'interstitial', 'skipped', 'no active networks');
    }
    return false;
  }

  Future<bool> _showStreamRewarded({required bool rewardedInterstitial}) async {
    final format = rewardedInterstitial ? 'rewarded_interstitial' : 'rewarded';
    // Hard guard: never overlap a second full-screen ad show. `_isShowingAd`
    // covers the full show → dismiss window via the try/finally blocks below.
    if (_isShowingAd) {
      _waterfallLog('none', format, 'skipped', 'ad already showing');
      return false;
    }
    var attempted = false;
    for (final adapter in _activeAdapters) {
      attempted = true;
      final net = adNetworkName(adapter.network);
      if (rewardedInterstitial) {
        // Timeout bounds the LOAD only; never the show/dismiss wait.
        final loaded = await adapter
            .loadRewardedInterstitial()
            .timeout(_preRollLoadTimeout, onTimeout: () => false);
        if (!loaded) {
          _waterfallLog(net, format, 'failed', 'no-fill/load failed');
          continue;
        }
        _waterfallLog(net, format, 'loaded');
        _isShowingAd = true;
        bool earned;
        try {
          // No timeout: wait for the real reward/dismiss/fail callback.
          earned = await adapter.showRewardedInterstitial();
        } finally {
          _isShowingAd = false;
        }
        _waterfallLog(
            net, format, earned ? 'shown' : 'failed', 'rewardEarned=$earned');
        if (earned) {
          _markFullScreenShown();
          _markPreRollShown();
          return true;
        }
      } else {
        // Timeout bounds the LOAD only; never the show/dismiss wait.
        final loaded = await adapter
            .loadRewarded()
            .timeout(_preRollLoadTimeout, onTimeout: () => false);
        if (!loaded) {
          _waterfallLog(net, format, 'failed', 'no-fill/load failed');
          continue;
        }
        _waterfallLog(net, format, 'loaded');
        _isShowingAd = true;
        bool earned;
        try {
          // No timeout: wait for the real reward/dismiss/fail callback.
          earned = await adapter.showRewarded();
        } finally {
          _isShowingAd = false;
        }
        _waterfallLog(
            net, format, earned ? 'shown' : 'failed', 'rewardEarned=$earned');
        if (earned) {
          _markFullScreenShown();
          _markPreRollShown();
          return true;
        }
      }
    }
    if (!attempted) {
      _waterfallLog('none', format, 'skipped', 'no active networks');
    }
    return false;
  }

  bool get _appOpenAllowedByFrequency {
    if (_appOpensThisSession >= _config.maxAppOpenPerSession) return false;
    final last = _lastAppOpenAt;
    if (last == null) return true;
    return DateTime.now().difference(last).inSeconds >=
        _config.effectiveAppOpenIntervalSeconds;
  }

  Future<void> preloadAppOpen() async {
    if (kIsWeb || !_config.appOpenAllowed) return;
    for (final adapter in _activeAdapters) {
      if (await adapter.loadAppOpen()) return;
    }
  }

  /// Shows an app open ad if enabled, not during video, and within frequency
  /// caps. Returns true if shown.
  ///
  /// The lifecycle decision (cold start vs real foreground, background
  /// duration, notification-shade quick resume) is made by
  /// [AppOpenAdManager] — this method only enforces ads-policy guards: global
  /// toggle, video playback, "already showing an ad", cross-format cooldown,
  /// and the 4-hour (default) app-open frequency cap.
  Future<bool> maybeShowAppOpen({AppOpenTrigger? trigger}) async {
    if (kIsWeb || !_config.appOpenAllowed) return false;
    if (_isShowingAd) {
      if (kDebugMode) {
        debugPrint('[Ads] app-open blocked: another ad is already showing');
      }
      return false;
    }
    if (_videoPlaying) {
      if (kDebugMode) debugPrint('[Ads] app-open blocked: video playing');
      return false;
    }
    if (_fullScreenCooldownActive) {
      if (kDebugMode) {
        debugPrint('[Ads] app-open blocked: full-screen cooldown active '
            '(another full-screen ad shown recently)');
      }
      return false;
    }
    if (!_appOpenAllowedByFrequency) {
      if (kDebugMode) {
        debugPrint('[Ads] app-open blocked by frequency cap '
            '(min interval ${_config.appOpenMinIntervalMinutes}m, '
            'session $_appOpensThisSession/${_config.maxAppOpenPerSession})');
      }
      return false;
    }
    for (final adapter in _activeAdapters) {
      if (!await adapter.loadAppOpen()) continue;
      _isShowingAd = true;
      bool shown;
      try {
        shown = await adapter.showAppOpen();
      } finally {
        _isShowingAd = false;
      }
      if (shown) {
        _lastAppOpenAt = DateTime.now();
        _appOpensThisSession += 1;
        _markFullScreenShown();
        if (kDebugMode) {
          debugPrint(
              '[Ads] app-open shown by ${adNetworkName(adapter.network)} '
              '(trigger=${trigger?.name ?? 'manual'})');
        }
        return true;
      }
    }
    return false;
  }

  void dispose() {
    for (final adapter in _adapters.values) {
      adapter.dispose();
    }
  }

  /// Diagnostics snapshot for debug overlays / admin troubleshooting.
  Map<String, dynamic> get diagnostics => {
        'enabled': _config.enabled,
        'initialized': _initialized,
        'testMode': _config.testMode,
        'primary': adNetworkName(_config.primaryNetwork),
        'fallbackOrder':
            _config.fallbackOrder.map(adNetworkName).toList(growable: false),
        'networks': {
          for (final n in AdNetwork.values)
            adNetworkName(n): {
              'enabled': _config.isNetworkEnabled(n),
              'directSupported': _adapters[n]?.isDirectSupported ?? false,
              'ready': _adapters[n]?.isReady ?? false,
              'status': (_adapters[n]?.status ?? AdNetworkStatus.disabled).name,
            },
        },
      };
}
