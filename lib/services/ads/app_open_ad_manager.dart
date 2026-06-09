import 'package:flutter/widgets.dart';

import 'package:cricpro_flutter/services/ads/ads_manager.dart';

/// Owns the app-open ad lifecycle decision so it is made in ONE place with
/// strict, policy-safe guards.
///
/// The historical bug: the app showed an App Open ad on *every* `resumed`
/// event. On Android, pulling the notification shade / quick-settings, peeking
/// the app switcher, or a permission dialog all emit `inactive` → `resumed`
/// WITHOUT the app ever truly backgrounding (`paused`). That caused App Open
/// ads to fire on shade close, screen unlock, etc. — against AdMob best
/// practice and annoying to users.
///
/// This reactor fixes that by tracking real lifecycle transitions and only
/// allowing an app-open ad when ALL of the following hold:
///   * the app actually went to the background (`paused`/`detached`), not just
///     `inactive` (shade / switcher / system dialog),
///   * it stayed backgrounded for at least
///     [AdConfig.appOpenMinBackgroundSeconds] (default 30s) — skips quick
///     resumes,
///   * no full-screen ad is currently showing (its own pause/resume must not
///     arm a new app-open),
///   * the admin cooldown (default 4 hours) and per-session cap allow it
///     (enforced inside [AdsManager.maybeShowAppOpen]).
///
/// Cold start is handled explicitly via [notifyColdStartReady] (once per
/// process), gated by the admin `showOnColdStart` switch.
class AppOpenAdManager with WidgetsBindingObserver {
  AppOpenAdManager._();

  static final AppOpenAdManager instance = AppOpenAdManager._();

  bool _registered = false;

  /// Whether ads config has loaded and app-open may be considered at all.
  bool _ready = false;

  /// True only after a real background transition (`paused`/`detached`). An
  /// `inactive` event (notification shade, app switcher, permission/consent
  /// dialog, incoming-call banner) does NOT set this — that is the core guard
  /// against shade-close / unlock app-open ads.
  bool _trulyBackgrounded = false;

  /// When the app last truly went to the background.
  DateTime? _pausedAt;

  /// When the app last resumed (diagnostics).
  DateTime? _resumedAt;

  /// Whether the cold-start app-open has already been considered this process.
  bool _coldStartHandled = false;

  /// Whether an app-open ad has been shown at least once this session
  /// (diagnostics / future per-session policies).
  bool _didShowOnThisSession = false;

  /// APP_OPEN_DEBUG logging. Kept unconditional (not gated by kDebugMode) so
  /// the full lifecycle trace is visible via `flutter logs` / logcat while
  /// diagnosing on a real device. Flip to false to silence.
  static const bool _verbose = true;

  void _log(String message) {
    if (_verbose) debugPrint('APP_OPEN_DEBUG: $message');
  }

  String _ts(DateTime? t) => t?.toIso8601String() ?? '—';

  /// Registers the lifecycle observer. Safe to call more than once.
  void register() {
    if (_registered) return;
    WidgetsBinding.instance.addObserver(this);
    _registered = true;
    _log('observer registered');
  }

  void unregister() {
    if (!_registered) return;
    WidgetsBinding.instance.removeObserver(this);
    _registered = false;
  }

  /// Marks ads as ready (config loaded). App-open is a no-op until this is set.
  void markReady() {
    _ready = true;
    final ads = AdsManager.instance.config;
    _log('ready=true (appOpenAllowed=${ads.appOpenAllowed} '
        'coldStart=${ads.appOpenShowOnColdStart} resume=${ads.appOpenShowOnResume} '
        'minBackground=${ads.appOpenMinBackgroundSeconds}s '
        'cooldown=${ads.appOpenMinIntervalMinutes}m)');
  }

  /// Called once after the first frame on a cold launch. Shows the cold-start
  /// app-open ad if the admin enabled it. No-op on later calls.
  Future<void> notifyColdStartReady() async {
    if (_coldStartHandled) return;
    _coldStartHandled = true;
    if (!_ready) {
      _log('cold-start skipped: ads not ready');
      return;
    }
    final ads = AdsManager.instance.config;
    if (!ads.appOpenAllowed || !ads.appOpenShowOnColdStart) {
      _log('cold-start skipped: reason=disabled '
          '(allowed=${ads.appOpenAllowed} showOnColdStart=${ads.appOpenShowOnColdStart})');
      return;
    }
    _log('cold-start: attempting show (reason=cold launch)');
    final shown = await AdsManager.instance
        .maybeShowAppOpen(trigger: AppOpenTrigger.coldStart);
    if (shown) _didShowOnThisSession = true;
    _log('cold-start: shown=$shown');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final showing = AdsManager.instance.isShowingAd;
    _log('state change -> ${state.name} | trulyBackgrounded=$_trulyBackgrounded '
        'pausedAt=${_ts(_pausedAt)} resumedAt=${_ts(_resumedAt)} '
        'isShowingAd=$showing');

    // While a full-screen ad is on screen, the OS fires inactive/paused/resumed
    // for the ad itself. Ignore those entirely so the ad's own lifecycle can
    // never arm a second app-open ad.
    if (showing) {
      _log('lifecycle ignored: a full-screen ad is showing ($state)');
      return;
    }

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        // Real background. Arm the resume check.
        _pausedAt = DateTime.now();
        _trulyBackgrounded = true;
        _log('armed: truly backgrounded at ${_ts(_pausedAt)} (state=${state.name})');
        break;
      case AppLifecycleState.hidden:
      case AppLifecycleState.inactive:
        // Transient: notification shade, quick settings, app-switcher peek,
        // permission/consent dialog, split-screen focus change. NOT a real
        // background — do not arm anything. This is the notification-shade fix.
        _log('transient state ${state.name}: NOT arming app-open '
            '(notification shade / dialog / peek)');
        break;
      case AppLifecycleState.resumed:
        _resumedAt = DateTime.now();
        _handleResume();
        break;
    }
  }

  void _handleResume() {
    if (!_ready) {
      _log('resume: skip reason=ads not ready');
      return;
    }

    // Never backgrounded for real → this resume came from a shade/dialog/peek.
    if (!_trulyBackgrounded) {
      _log('resume: SKIP reason=not truly backgrounded '
          '(notification drawer / dialog / app-switcher quick resume) -> NEVER show');
      return;
    }

    final pausedAt = _pausedAt;
    // Consume the background state regardless of outcome.
    _trulyBackgrounded = false;
    _pausedAt = null;

    final backgroundSeconds =
        pausedAt == null ? 0 : DateTime.now().difference(pausedAt).inSeconds;

    final ads = AdsManager.instance.config;
    if (!ads.appOpenAllowed || !ads.appOpenShowOnResume) {
      _log('resume: SKIP reason=disabled '
          '(allowed=${ads.appOpenAllowed} showOnResume=${ads.appOpenShowOnResume}) '
          'elapsedBackground=${backgroundSeconds}s');
      return;
    }

    final minBackground = ads.appOpenMinBackgroundSeconds;
    if (backgroundSeconds < minBackground) {
      _log('resume: SKIP reason=foreground gap too short '
          'elapsedBackground=${backgroundSeconds}s < required ${minBackground}s '
          '(screen unlock / quick resume) -> NEVER show');
      return;
    }

    if (AdsManager.instance.isShowingAd) {
      _log('resume: SKIP reason=another ad visible');
      return;
    }

    _log('resume: ELIGIBLE elapsedBackground=${backgroundSeconds}s '
        '(>= ${minBackground}s) lastShown=${_ts(AdsManager.instance.lastAppOpenShownAt)} '
        'sessionCount=${AdsManager.instance.appOpensThisSession} '
        '-> handing to AdsManager (enforces 4h cooldown + session cap)');

    // All lifecycle conditions met. AdsManager enforces the rest (4h cooldown,
    // session cap, full-screen cooldown, video, already-showing).
    AdsManager.instance.maybeShowAppOpen(trigger: AppOpenTrigger.resume).then(
      (shown) {
        if (shown) _didShowOnThisSession = true;
        _log('resume: AdsManager result shown=$shown');
      },
    );
  }

  /// Diagnostics for debug overlays / admin troubleshooting.
  Map<String, dynamic> get diagnostics => {
        'ready': _ready,
        'trulyBackgrounded': _trulyBackgrounded,
        'pausedAt': _pausedAt?.toIso8601String(),
        'resumedAt': _resumedAt?.toIso8601String(),
        'coldStartHandled': _coldStartHandled,
        'didShowOnThisSession': _didShowOnThisSession,
        'isShowingAd': AdsManager.instance.isShowingAd,
      };
}
