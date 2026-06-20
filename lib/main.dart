import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:cricpro_flutter/app_theme.dart';
import 'package:cricpro_flutter/api_models.dart';
import 'package:cricpro_flutter/components.dart';
import 'package:cricpro_flutter/models.dart';
import 'package:cricpro_flutter/models/ad_config.dart';
import 'package:cricpro_flutter/sheets.dart';
import 'package:cricpro_flutter/screens/home/home_screen.dart';
import 'package:cricpro_flutter/screens/matches/matches_screen.dart';
import 'package:cricpro_flutter/screens/news/news_detail_screen.dart';
import 'package:cricpro_flutter/screens/more/more_screen.dart';
import 'package:cricpro_flutter/screens/more/favorite_countries_screen.dart';
import 'package:cricpro_flutter/screens/more/contact_us_screen.dart';
import 'package:cricpro_flutter/screens/more/privacy_policy_screen.dart';
import 'package:cricpro_flutter/screens/more/terms_screen.dart';
import 'package:cricpro_flutter/screens/live/live_player_screen.dart';
import 'package:cricpro_flutter/screens/highlights/highlights_screen.dart';
import 'package:cricpro_flutter/screens/rankings/rankings_screen.dart';
import 'package:cricpro_flutter/screens/schedule/schedule_screen.dart';
import 'package:cricpro_flutter/screens/teams/teams_screen.dart';
import 'package:cricpro_flutter/screens/match_details/match_details_screen.dart';
import 'package:cricpro_flutter/screens/series/series_detail_screen.dart';
import 'package:cricpro_flutter/screens/series/series_list_screen.dart';
import 'package:cricpro_flutter/screens/common/notifications_screen.dart';
import 'package:cricpro_flutter/screens/player/player_detail_screen.dart';
import 'package:cricpro_flutter/repositories/cricket_repository.dart';
import 'package:cricpro_flutter/widgets/minimized_score_bar.dart';
import 'package:cricpro_flutter/services/floating_score_overlay_service.dart';
import 'package:cricpro_flutter/screens/more/floating_score_settings_screen.dart';
import 'package:cricpro_flutter/screens/more/notification_settings_screen.dart';
import 'package:cricpro_flutter/services/ad_service.dart';
import 'package:cricpro_flutter/services/ads/ads_manager.dart';
import 'package:cricpro_flutter/services/ads/app_open_ad_manager.dart';
import 'package:cricpro_flutter/services/ads/consent_manager.dart';
import 'package:cricpro_flutter/services/ads/pre_roll_gate.dart';
import 'package:cricpro_flutter/services/notification_service.dart';
import 'package:cricpro_flutter/services/notification_prompt_service.dart';
import 'package:cricpro_flutter/services/notification_settings_service.dart';
import 'package:cricpro_flutter/services/remote_assets_service.dart';
import 'package:cricpro_flutter/services/player_image_resolver.dart';
import 'package:cricpro_flutter/services/team_logo_resolver.dart';
import 'package:cricpro_flutter/services/analytics_service.dart';
import 'package:cricpro_flutter/services/favorite_countries_service.dart';
import 'package:cricpro_flutter/widgets/ads/banner_ad_widget.dart';
import 'package:cricpro_flutter/features/splash/presentation/premium_splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ---- Eliminate white flash: dark system UI before first frame ----
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Color(0xFF060B18),
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  runApp(const CricProApp());
}

final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

class CricProApp extends StatefulWidget {
  const CricProApp({super.key});

  @override
  State<CricProApp> createState() => _CricProAppState();
}

class _CricProAppState extends State<CricProApp> with WidgetsBindingObserver {
  bool dark = true;
  final CricketRepository _repository = CricketRepository();
  AppConfig _appConfig = const AppConfig(values: {});
  bool _adsReady = false;

  // ---- Premium animated splash gate ----
  // The splash is the MaterialApp's `home` until it finishes, then it is
  // removed from the tree entirely (replaced by RootShell). Because it is never
  // a pushed route, the Android back button can never return to it.
  bool _showSplash = true;
  // Set when init finishes (and the cold-start App Open ad is ready) while the
  // splash is still visible. Flushed once the splash is dismissed.
  bool _coldStartAppOpenPending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // App-open lifecycle decisions live entirely in AppOpenAdManager so the
    // notification-shade / quick-resume guards are enforced in one place.
    AppOpenAdManager.instance.register();
    // Privacy-safe analytics. Fire-and-forget: never blocks UI, never throws.
    AnalyticsService.instance.initialize();
    // Load favourite-country preferences so Home/Matches ordering can apply
    // them from the first frame. Fire-and-forget; defaults to normal sorting.
    FavoriteCountriesService.instance.load();
    // Load notification category preferences so app-side gating + tag sync can
    // apply them. Fire-and-forget; defaults to the product defaults.
    NotificationSettingsService.instance.load();
    ConsentManager.instance.privacyOptionsRequired.addListener(
      _onPrivacyOptionsRequirementChanged,
    );
    // Kick heavy initialization (config, ads, OneSignal) IMMEDIATELY, in
    // parallel with the splash animation — not after it. Previously this ran
    // only once the splash dismissed, so a slow network stalled right after the
    // splash and looked like a half-loaded launch. Now the splash floor and the
    // init overlap, so by the time the splash finishes the app is usually ready.
    _loadAppConfig();
  }

  @override
  void dispose() {
    ConsentManager.instance.privacyOptionsRequired.removeListener(
      _onPrivacyOptionsRequirementChanged,
    );
    WidgetsBinding.instance.removeObserver(this);
    AppOpenAdManager.instance.unregister();
    super.dispose();
  }

  void _onPrivacyOptionsRequirementChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // App-open-on-resume is handled exclusively by AppOpenAdManager (which
    // distinguishes a real background return from a transient `inactive`
    // notification-shade / dialog resume). Nothing to do here.
    if (state == AppLifecycleState.resumed) {
      // Let analytics decide whether this resume continues the current session
      // or (after the 30-min inactivity window) starts a new one. Records an
      // app_open but never a new user. Fire-and-forget.
      AnalyticsService.instance.onAppForeground();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      // Flush queued analytics when the app goes to background so events
      // aren't lost. Fire-and-forget.
      AnalyticsService.instance.onAppBackground();
    }
  }

  Future<void> _loadAppConfig() async {
    // Best-effort load of admin-managed remote assets. Never blocks UI: on
    // failure the app uses its bundled fallback images.
    RemoteAssetsService.instance.load();
    try {
      final response = await _repository.appConfig();
      if (mounted) {
        final config = AppConfig.fromJson(response.data);
        // Propagate the admin player-image mode globally so every avatar honors
        // it. Updated on each config load (cold start + refresh).
        PlayerImageResolver.updateModeFromString(config.playerImageMode);
        // Propagate the admin team-logo source priority order globally so every
        // team logo honors it. Updated on each config load (cold start + refresh).
        TeamLogoResolver.updateFromConfig(
          config.teamLogoOrder,
          enabled: config.teamLogosEnabled,
        );
        await AdService.instance
            .initialize(AdConfig.fromAppConfig(response.data));
        _adsReady = true;
        AppOpenAdManager.instance.markReady();
        // Warm full-screen formats so the first eligible transition can show.
        AdsManager.instance.preloadInterstitial();
        AdsManager.instance.preloadAppOpen();
        await NotificationService.instance.initialize(
          config,
          onDeepLink: _handleNotificationDeepLink,
        );
        // Now that OneSignal is initialised, register a single tag-sync hook
        // that mirrors BOTH the saved category choices and favourite countries
        // to tags. Calling it here covers the "permission already granted"
        // startup case; requestPermission() calls it again right after a fresh
        // grant so a brand-new install is targetable without opening settings.
        NotificationService.instance.registerTagsSync(() {
          NotificationService.instance.syncCategoryTags(
            NotificationSettingsService.instance.values.value,
          );
          NotificationService.instance.syncFavoriteTags(
            FavoriteCountriesService.instance.selected.value,
            FavoriteCountriesService.catalog.map((c) => c.code),
          );
        });
        NotificationService.instance.syncAllTags();
        setState(() => _appConfig = config);
        _maybeShowColdStartAppOpen();
      }
    } catch (_) {
      // The app can still render with built-in defaults when config is unavailable.
    }
  }

  /// Shows the cold-start App Open ad once, after the first frame so the UI is
  /// visible first (policy-safe timing). All gating lives in AppOpenAdManager.
  ///
  /// Init can now finish while the splash is still on screen, so this defers
  /// until the splash has actually been dismissed — preserving the original
  /// "ad shows after the splash, over the app UI" timing.
  void _maybeShowColdStartAppOpen() {
    if (!_adsReady) return;
    if (_showSplash) {
      _coldStartAppOpenPending = true;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppOpenAdManager.instance.notifyColdStartReady();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: appNavigatorKey,
      title: 'CRICPRO',
      theme: cricTheme(dark),
      home: _buildHome(),
    );
  }

  /// Splash gate -> maintenance/RootShell.
  ///
  /// The splash is local-only and shows on the first Flutter frame. It does not
  /// wait for `/app/config`, Admin URLs, or cached remote splash settings.
  /// Normal app config still loads separately in [_loadAppConfig].
  Widget _buildHome() {
    if (_showSplash) {
      return PremiumSplashScreen(
        onFinish: () {
          // Init was already started in initState (runs concurrently with the
          // splash). Here we only swap the splash out for the app shell.
          if (mounted) setState(() => _showSplash = false);
          // If init finished while the splash was still up, the cold-start App
          // Open ad was deferred — fire it now that the app UI is visible.
          if (_coldStartAppOpenPending) {
            _coldStartAppOpenPending = false;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              AppOpenAdManager.instance.notifyColdStartReady();
            });
          }
        },
      );
    }
    final Widget shell = _appConfig.maintenanceMode
        ? const _MaintenanceScreen()
        : RootShell(
            isDark: dark,
            onThemeChanged: (v) => setState(() => dark = v),
          );
    // Soft cross-fade from the splash navy into the app so the hard swap never
    // reads as a flash/jump. Keyed so AnimatedSwitcher animates the transition.
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      switchInCurve: Curves.easeOut,
      child: KeyedSubtree(
        key: ValueKey<bool>(_appConfig.maintenanceMode),
        child: shell,
      ),
    );
  }

  void _handleNotificationDeepLink(Map<String, dynamic> data) {
    final navigator = appNavigatorKey.currentState;
    if (navigator == null) return;
    final type = apiString(data['type'] ?? data['deepLinkType']).toLowerCase();
    final matchId = apiString(data['matchId'] ?? data['match_id']);
    final newsId = apiString(data['newsId'] ?? data['news_id']);
    final seriesId = apiString(data['seriesId'] ?? data['series_id']);
    if (type == 'live_stream' && matchId.isNotEmpty) {
      navigator.push(MaterialPageRoute<void>(
          builder: (_) => LivePlayerScreen(matchId: matchId)));
      return;
    }
    if (type == 'match' && matchId.isNotEmpty) {
      navigator.push(MaterialPageRoute<void>(
          builder: (_) => MatchDetailsScreen(matchId: matchId)));
      return;
    }
    if (type == 'news' && newsId.isNotEmpty) {
      navigator.push(MaterialPageRoute<void>(
        builder: (_) => NewsDetailScreen(
          article: NewsArticle(
            id: newsId,
            title: apiString(data['title'], 'Cricket news'),
            subtitle: apiString(data['body']),
            source: 'CricPro',
            date: 'Latest',
            tag: 'News',
          ),
        ),
      ));
      return;
    }
    if (type == 'series' && seriesId.isNotEmpty) {
      navigator.push(MaterialPageRoute<void>(
        builder: (_) => SeriesDetailScreen(
          seriesId: seriesId,
          onOpenReminders: () {},
          onOpenCalendar: () {},
          onOpenPlayer: () {},
        ),
      ));
      return;
    }
    // Tab deep links: the target screens are RootShell tabs (not standalone
    // pushable routes), so pop back to the shell and switch its bottom-nav tab.
    // RootShell.switchTab is null while the splash is up — no-op in that case.
    if (type == 'home') {
      navigator.popUntil((r) => r.isFirst);
      RootShell.switchTab?.call(AppTab.home);
      return;
    }
    if (type == 'schedule') {
      navigator.popUntil((r) => r.isFirst);
      RootShell.switchTab?.call(AppTab.schedule);
      return;
    }
    // Rankings is reached by pushing the screen (same as the More menu does).
    if (type == 'rankings') {
      navigator.push(MaterialPageRoute<void>(
          builder: (_) => const RankingsScreen()));
      return;
    }
  }
}

class _MaintenanceScreen extends StatelessWidget {
  const _MaintenanceScreen();

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: c.bgGradient),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(28),
        child: PremiumCard(
          padding: const EdgeInsets.all(24),
          child: Text(
            'CRICPRO is under maintenance. Please check back shortly.',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: c.text, fontWeight: FontWeight.w900, fontSize: 20),
          ),
        ),
      ),
    );
  }
}

class RootShell extends StatefulWidget {
  const RootShell(
      {super.key, required this.isDark, required this.onThemeChanged});

  final bool isDark;
  final ValueChanged<bool> onThemeChanged;

  /// Set by the live [_RootShellState] so the notification deep-link handler
  /// (which lives on the separate app State and only holds [appNavigatorKey])
  /// can switch the bottom-nav tab for `home` / `schedule` deep links. Null when
  /// no shell is mounted (e.g. during the splash); callers no-op in that case.
  static void Function(AppTab tab)? switchTab;

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  AppTab active = AppTab.home;

  /// Tabs the user has opened at least once. Visited tabs stay mounted in the
  /// [IndexedStack] (preserving their state/scroll); unvisited tabs are not
  /// built until first opened.
  final Set<AppTab> _visitedTabs = {AppTab.home};

  /// Bumped each time the user re-selects the already-built Home tab, so the
  /// live HomeScreen (kept alive in the IndexedStack) can silently refresh its
  /// scores on re-entry. A ValueNotifier avoids leaking Home's private State.
  final ValueNotifier<int> _homeReentrySignal = ValueNotifier<int>(0);

  @override
  void initState() {
    super.initState();
    // Expose tab-switching to the notification deep-link handler.
    RootShell.switchTab = _switchTab;
    // When the user taps the Android floating-score bubble, open Match Details.
    // No-op on non-Android platforms.
    FloatingScoreOverlay.instance.registerOpenMatchHandler((matchId) {
      if (matchId.isNotEmpty) _openMatch(matchId);
    });
    // First-run notification permission prompt (after first frame so context is
    // available and the shell is fully rendered).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        NotificationPromptService.instance.maybePrompt(context);
      }
    });
  }

  @override
  void dispose() {
    if (identical(RootShell.switchTab, _switchTab)) RootShell.switchTab = null;
    _homeReentrySignal.dispose();
    super.dispose();
  }

  /// Opens the match details screen. Accepts a positional [matchId] so it
  /// can be passed as a `ValueChanged<String>` callback directly. Empty
  /// strings are tolerated and surface the demo hero.
  void _openMatch([String matchId = '']) {
    // When the user taps the floating overlay bubble, the overlay must close
    // immediately — otherwise it sits on top of Match Details.
    FloatingScoreOverlay.instance.stop();
    // Interstitial on a natural transition (gated by admin toggle + frequency).
    AdsManager.instance
        .maybeShowInterstitial(placement: AdPlacement.matchDetails);
    _push(MatchDetailsScreen(
      matchId: matchId,
      onWatchLive: (id) => _openLivePlayer(matchId: id),
    ));
  }

  /// Guards against double taps on Watch Live while a pre-roll ad is resolving.
  bool _watchLiveInProgress = false;

  /// Central Watch Live entry point. Every "Watch Live" button (Home, Matches,
  /// Match Details) routes here. It runs the admin-configured pre-roll ad
  /// (primary network first, then fallback order) BEFORE opening the player,
  /// then navigates regardless of ad outcome so the user is never blocked.
  ///
  /// One ad per tap. Premium per-stream reward unlock still happens inside the
  /// player for locked premium streams.
  Future<void> _openLivePlayer({String matchId = ''}) async {
    if (_watchLiveInProgress) {
      _watchLiveLog('debounced', matchId, {'reason': 'tap while ad resolving'});
      return;
    }
    _watchLiveInProgress = true;

    // Register the single logical opening for this Watch Live tap. The player
    // reads it from the gate so it can never run a second initial pre-roll for
    // the same opening, whatever the entry ad outcome was.
    final openingId = PreRollGate.instance.newOpening(matchId);

    final ads = AdsManager.instance.config;
    final type = ads.resolveWatchLivePreRoll();
    final primary = adNetworkName(ads.primaryNetwork);
    final order = ads.orderedNetworks.map(adNetworkName).join('>');

    _watchLiveLog('tap', matchId, {
      'placement': 'live_player_preroll',
      'adEnabled': ads.enabled,
      'format': type.name,
      'primaryNetwork': primary,
      'fallbackOrder': order.isEmpty ? '-' : order,
      'adUnitIdExists': _preRollUnitExists(ads, type),
      'adUnitId': _maskAdUnit(_preRollUnitId(ads, type)),
    });

    try {
      final capDecision = AdsManager.instance.preRollCapDecision();
      // Try to own the entry pre-roll attempt. If a previous attempt is somehow
      // still in flight, skip the entry ad entirely (the gate, not this tap,
      // decides) and let the player open directly.
      final claimed = PreRollGate.instance.beginAttempt();
      if (type == StreamPreRollAdType.none || !claimed) {
        // Mark the initial pre-roll handled so the player does NOT run one.
        PreRollGate.instance.markInitialHandled(openingId);
        if (claimed) PreRollGate.instance.endAttempt();
        PreRollGate.instance.log(
          type == StreamPreRollAdType.none
              ? 'WATCH_LIVE_PRE_ROLL_SKIPPED_CAP'
              : 'LIVE_PLAYER_INITIAL_PRE_ROLL_BLOCKED_ALREADY_HANDLED',
          matchId: matchId,
          attemptId: openingId,
          source: 'watch_live',
        );
        _watchLiveLog('preRollSkipped', matchId, {
          'reason': ads.enabled ? 'pre-roll type=none' : 'ads disabled',
        });
      } else if (capDecision != PreRollCapDecision.allow) {
        // Session-capped — skip the entry ad but ALWAYS continue to the player.
        // Mark handled so the player does not retry the initial pre-roll.
        PreRollGate.instance.markInitialHandled(openingId);
        PreRollGate.instance.endAttempt();
        PreRollGate.instance.log(
          'WATCH_LIVE_PRE_ROLL_SKIPPED_CAP',
          matchId: matchId,
          attemptId: openingId,
          source: 'watch_live',
          sessionCount: AdsManager.instance.preRollShownThisSession,
        );
        _watchLiveLog('preRollSkipped', matchId, {'reason': 'sessionCap'});
      } else {
        // We own the attempt. Mark the initial pre-roll handled up front so any
        // race (player auto-select firing while this ad resolves) sees it as
        // handled. Released in the finally below.
        PreRollGate.instance.markInitialHandled(openingId);
        PreRollGate.instance.log(
          'WATCH_LIVE_PRE_ROLL_START',
          matchId: matchId,
          attemptId: openingId,
          source: 'watch_live',
          sessionCount: AdsManager.instance.preRollShownThisSession,
        );
        _watchLiveLog('loadStarted', matchId, {'format': type.name});
        // No loading skeleton/placeholder before pre-roll: the show path is
        // bounded by a LOAD timeout inside AdsManager and is fail-open, so we
        // never trap the user behind a blocking spinner. Crucially, we do NOT
        // time out here: once an ad is showing we must wait for its real
        // dismiss/fail callback, otherwise we would navigate and start the
        // video behind a still-visible ad. The load phase is already bounded
        // inside `showStreamPreRoll`, so a no-fill/slow load surfaces as
        // `failed` quickly without blocking.
        StreamAdResult result;
        try {
          result = await AdsManager.instance
              .showStreamPreRoll(type: type, isRequiredForPremium: false);
        } finally {
          // Released only AFTER the ad truly dismissed/failed/no-filled/
          // load-timed-out — so the gate lock covers the whole ad lifetime.
          PreRollGate.instance.endAttempt();
        }
        if (result == StreamAdResult.allowed) {
          PreRollGate.instance.recordShown(matchId);
          PreRollGate.instance.log(
            'WATCH_LIVE_PRE_ROLL_RESULT_SHOWN',
            matchId: matchId,
            attemptId: openingId,
            source: 'watch_live',
            perMatchCount: PreRollGate.instance.shownForMatch(matchId),
          );
        } else {
          PreRollGate.instance.log(
            'WATCH_LIVE_PRE_ROLL_RESULT_FAILED',
            matchId: matchId,
            attemptId: openingId,
            source: 'watch_live',
          );
        }
        _watchLiveLog('preRollResult', matchId, {
          'result': result.name,
          'shown': result == StreamAdResult.allowed,
        });
      }
    } catch (e) {
      // Defensive: never leave the lock held or the opening unmarked on error.
      PreRollGate.instance.markInitialHandled(openingId);
      PreRollGate.instance.endAttempt();
      _watchLiveLog('error', matchId, {'reason': '$e'});
    } finally {
      _watchLiveInProgress = false;
    }

    _watchLiveLog('navigatingToPlayer', matchId, {'value': true});
    PreRollGate.instance.log(
      'STREAM_OPEN_CONTINUE',
      matchId: matchId,
      attemptId: openingId,
      source: 'watch_live',
    );
    await _push(LivePlayerScreen(
      matchId: matchId,
      openingId: openingId,
    ));
    // After the user leaves the live player, optionally show an interstitial
    // (opt-in via admin "after player" toggle). Never during playback.
    if (AdsManager.instance.config.interstitialAfterPlayer) {
      AdsManager.instance
          .maybeShowInterstitial(placement: AdPlacement.livePlayer);
    }
  }

  /// Whether the primary network has a unit/placement id for [type]. Logged so
  /// a "no ad showed" report can be diagnosed as missing-id vs no-fill.
  bool _preRollUnitExists(AdConfig ads, StreamPreRollAdType type) {
    return (_preRollUnitId(ads, type) ?? '').isNotEmpty;
  }

  String? _preRollUnitId(AdConfig ads, StreamPreRollAdType type) {
    final net = ads.networkConfig(ads.primaryNetwork);
    switch (type) {
      case StreamPreRollAdType.none:
        return null;
      case StreamPreRollAdType.interstitial:
        return net.interstitialId;
      case StreamPreRollAdType.rewardedVideo:
        return net.rewardedId;
      case StreamPreRollAdType.rewardedInterstitial:
        return net.rewardedInterstitialId;
    }
  }

  String _maskAdUnit(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'missing';
    if (text.length <= 12) return '***';
    return '${text.substring(0, 10)}...${text.substring(text.length - 6)}';
  }

  void _watchLiveLog(
      String event, String matchId, Map<String, Object?> fields) {
    final parts = fields.entries.map((e) => '${e.key}=${e.value}').join(' ');
    debugPrint(
        'WATCH_LIVE_AD: event=$event matchId=${matchId.isEmpty ? '-' : matchId} $parts');
  }

  void _openSeries({int initialTab = 0}) {
    AdsManager.instance.maybeShowInterstitial(placement: AdPlacement.series);
    _push(SeriesListScreen(
      showBack: true,
      onOpenSeries: (seriesId) => _push(SeriesDetailScreen(
        seriesId: seriesId,
        initialTab: initialTab,
        onOpenReminders: () => showReminderSheet(context),
        onOpenCalendar: () => showCalendarSheet(context),
        onOpenPlayer: () => _push(const PlayerDetailScreen()),
      )),
    ));
  }

  void _openNotifications() => _push(const NotificationsScreen());

  /// Switches the bottom-nav to [tab] (used by Home Quick Actions that map to
  /// a primary destination, e.g. Schedule). Keeps the visited-tab/IndexedStack
  /// state intact.
  void _switchTab(AppTab tab) {
    if (active == tab) return;
    setState(() => active = tab);
    // Returning to Home should refresh live scores immediately (no loader, no
    // scroll jump) instead of waiting for the next poll tick.
    if (tab == AppTab.home) _homeReentrySignal.value++;
  }

  void _openFilters() => showFilterSheet(context);

  void _openReminders() => showReminderSheet(context);

  void _openHighlights() => _push(HighlightsScreen(
        onOpenNotifications: _openNotifications,
      ));

  void _openRanking() => _push(const RankingsScreen());

  void _openWomenRanking() => _push(const RankingsScreen(
        initialGender: 'women',
        initialCategory: 'teams',
        initialFormat: 'odi',
      ));

  /// Builds the screen for [tab]. Each tab is constructed once and then kept
  /// alive inside the [IndexedStack] below, so its state, loaded data and
  /// scroll position survive bottom-nav switches.
  Widget _buildTab(AppTab tab) {
    switch (tab) {
      case AppTab.home:
        return HomeScreen(
          reentrySignal: _homeReentrySignal,
          onOpenMatchDetails: _openMatch,
          onOpenSeries: _openSeries,
          onOpenSeriesDetail: (seriesId) => _push(SeriesDetailScreen(
            seriesId: seriesId,
            onOpenReminders: () => showReminderSheet(context),
            onOpenCalendar: () => showCalendarSheet(context),
            onOpenPlayer: () => _push(const PlayerDetailScreen()),
          )),
          onOpenNotifications: _openNotifications,
          onOpenFilters: _openFilters,
          onOpenReminders: _openReminders,
          onOpenRanking: _openRanking,
          onOpenSchedule: () => _switchTab(AppTab.schedule),
          onOpenMatches: () => _switchTab(AppTab.matches),
          onWatchLive: (id) => _openLivePlayer(matchId: id),
        );
      case AppTab.matches:
        return MatchesScreen(
          onOpenMatch: _openMatch,
          onOpenFilters: _openFilters,
          onOpenReminders: _openReminders,
          onOpenSeries: _openSeries,
          onWatchLive: (id) => _openLivePlayer(matchId: id),
        );
      case AppTab.schedule:
        return ScheduleScreen(
          onOpenSeries: _openSeries,
          onOpenMatch: _openMatch,
        );
      case AppTab.series:
        return SeriesListScreen(
          onOpenSeries: (seriesId) => _push(SeriesDetailScreen(
            seriesId: seriesId,
            onOpenReminders: () => showReminderSheet(context),
            onOpenCalendar: () => showCalendarSheet(context),
            onOpenPlayer: () => _push(const PlayerDetailScreen()),
          )),
        );
      case AppTab.more:
        return MoreScreen(
          isDark: widget.isDark,
          onThemeChanged: widget.onThemeChanged,
          onOpenRanking: _openRanking,
          onOpenWomenRanking: _openWomenRanking,
          onOpenTeams: () => _push(const TeamsScreen()),
          onOpenFavorites: () => _push(const FavoriteCountriesScreen()),
          onOpenContact: () => _push(const ContactUsScreen()),
          onOpenPolicy: () => _push(const PrivacyPolicyScreen()),
          onOpenTerms: () => _push(const TermsScreen()),
          onOpenNotificationSettings: () =>
              _push(const NotificationSettingsScreen()),
          onOpenHighlights: _openHighlights,
          showPrivacyOptions:
              ConsentManager.instance.privacyOptionsRequired.value,
          onOpenPrivacyOptions: () {
            ConsentManager.instance.showPrivacyOptionsForm();
          },
          onOpenFloatingScore: (!kIsWeb &&
                  defaultTargetPlatform == TargetPlatform.android)
              ? () => _push(const FloatingScoreSettingsScreen())
              : null,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    _visitedTabs.add(active);
    // IndexedStack keeps every visited tab mounted (off-stage) so their state
    // and scroll position are preserved across switches. Tabs are built lazily:
    // an unvisited tab stays an empty placeholder until the user first opens it.
    final children = [
      for (final tab in AppTab.values)
        _visitedTabs.contains(tab)
            ? KeyedSubtree(key: ValueKey(tab), child: _buildTab(tab))
            : const SizedBox.shrink(),
    ];
    return Scaffold(
      // extendBody:false so the body is laid out ABOVE the bottom bar
      // (sticky banner ad + nav). Content can never scroll behind the ad at
      // any scroll position — the banner/nav occupy real layout height.
      extendBody: false,
      body: IndexedStack(
        index: active.index,
        children: children,
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Floating minimized live-score bar. Renders nothing when no match
          // is minimized; sits just above the ad banner + nav so it never
          // covers navigation or blocks taps.
          AnimatedBuilder(
            animation: MinimizedScoreController.instance,
            builder: (context, _) {
              final match = MinimizedScoreController.instance.activeMatch;
              if (match == null) return const SizedBox.shrink();
              return MinimizedScoreBar(
                match: match,
                onTap: () {
                  MinimizedScoreController.instance.clear();
                  _openMatch(match.id);
                },
                onClose: MinimizedScoreController.instance.clear,
              );
            },
          ),
          // Sticky bottom banner above the bottom navigation. Renders nothing
          // when ads are disabled, the placement is off, or no ad fills.
          StickyBannerBar(placement: _bannerPlacementForTab(active)),
          BottomNav(active: active, onTab: _switchTab),
        ],
      ),
    );
  }

  /// Maps the active tab to its banner placement (null = no sticky banner).
  AdPlacement? _bannerPlacementForTab(AppTab tab) {
    switch (tab) {
      case AppTab.home:
        return AdPlacement.home;
      case AppTab.matches:
        return AdPlacement.matches;
      case AppTab.schedule:
        return AdPlacement.schedule;
      case AppTab.series:
        return AdPlacement.series;
      case AppTab.more:
        return null;
    }
  }

  Future<void> _push(Widget screen) => Navigator.of(context).push(
        PageRouteBuilder<void>(
          transitionDuration: const Duration(milliseconds: 280),
          reverseTransitionDuration: const Duration(milliseconds: 220),
          pageBuilder: (_, animation, __) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position:
                  Tween<Offset>(begin: const Offset(.05, 0), end: Offset.zero)
                      .animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
              child: screen,
            ),
          ),
        ),
      );
}
