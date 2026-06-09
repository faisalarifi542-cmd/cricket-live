import 'package:flutter/material.dart';

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
import 'package:cricpro_flutter/services/ad_service.dart';
import 'package:cricpro_flutter/services/ads/ads_manager.dart';
import 'package:cricpro_flutter/services/ads/app_open_ad_manager.dart';
import 'package:cricpro_flutter/services/notification_service.dart';
import 'package:cricpro_flutter/widgets/ads/banner_ad_widget.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // App-open lifecycle decisions live entirely in AppOpenAdManager so the
    // notification-shade / quick-resume guards are enforced in one place.
    AppOpenAdManager.instance.register();
    _loadAppConfig();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AppOpenAdManager.instance.unregister();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // App-open-on-resume is handled exclusively by AppOpenAdManager (which
    // distinguishes a real background return from a transient `inactive`
    // notification-shade / dialog resume). Nothing to do here.
  }

  Future<void> _loadAppConfig() async {
    try {
      final response = await _repository.appConfig();
      if (mounted) {
        final config = AppConfig.fromJson(response.data);
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
        setState(() => _appConfig = config);
        _maybeShowColdStartAppOpen();
      }
    } catch (_) {
      // The app can still render with built-in defaults when config is unavailable.
    }
  }

  /// Shows the cold-start App Open ad once, after the first frame so the UI is
  /// visible first (policy-safe timing). All gating lives in AppOpenAdManager.
  void _maybeShowColdStartAppOpen() {
    if (!_adsReady) return;
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
      home: _appConfig.maintenanceMode
          ? const _MaintenanceScreen()
          : RootShell(
              isDark: dark,
              onThemeChanged: (v) => setState(() => dark = v),
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

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  AppTab active = AppTab.home;

  /// Tabs the user has opened at least once. Visited tabs stay mounted in the
  /// [IndexedStack] (preserving their state/scroll); unvisited tabs are not
  /// built until first opened.
  final Set<AppTab> _visitedTabs = {AppTab.home};

  /// Opens the match details screen. Accepts a positional [matchId] so it
  /// can be passed as a `ValueChanged<String>` callback directly. Empty
  /// strings are tolerated and surface the demo hero.
  void _openMatch([String matchId = '']) {
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
  bool _watchLiveLoaderUp = false;

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
    });

    var preRollShown = false;
    try {
      if (type != StreamPreRollAdType.none) {
        _watchLiveLog('loadStarted', matchId, {'format': type.name});
        _showWatchLiveLoading();
        // Tap-level pre-roll never hard-blocks entry (premium reward unlock is
        // enforced per-stream inside the player). So we always proceed after.
        final result = await AdsManager.instance.showStreamPreRoll(
          type: type,
          isRequiredForPremium: false,
        );
        _dismissWatchLiveLoading();
        preRollShown = result == StreamAdResult.allowed;
        _watchLiveLog('preRollResult', matchId, {
          'result': result.name,
          'shown': preRollShown,
        });
      } else {
        _watchLiveLog('preRollSkipped', matchId, {
          'reason': ads.enabled ? 'pre-roll type=none' : 'ads disabled',
        });
      }
    } catch (e) {
      _dismissWatchLiveLoading();
      _watchLiveLog('error', matchId, {'reason': '$e'});
    } finally {
      _watchLiveInProgress = false;
    }

    _watchLiveLog('navigatingToPlayer', matchId, {
      'value': true,
      'preRollShown': preRollShown,
    });
    await _push(LivePlayerScreen(
      matchId: matchId,
      skipInitialPreRoll: preRollShown,
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
    final net = ads.networkConfig(ads.primaryNetwork);
    switch (type) {
      case StreamPreRollAdType.none:
        return false;
      case StreamPreRollAdType.interstitial:
        return (net.interstitialId ?? '').isNotEmpty || ads.testMode;
      case StreamPreRollAdType.rewardedVideo:
        return (net.rewardedId ?? '').isNotEmpty || ads.testMode;
      case StreamPreRollAdType.rewardedInterstitial:
        return (net.rewardedInterstitialId ?? '').isNotEmpty || ads.testMode;
    }
  }

  void _watchLiveLog(String event, String matchId, Map<String, Object?> fields) {
    final parts = fields.entries.map((e) => '${e.key}=${e.value}').join(' ');
    debugPrint('WATCH_LIVE_AD: event=$event matchId=${matchId.isEmpty ? '-' : matchId} $parts');
  }

  void _showWatchLiveLoading() {
    if (_watchLiveLoaderUp || !mounted) return;
    _watchLiveLoaderUp = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
  }

  void _dismissWatchLiveLoading() {
    if (!_watchLiveLoaderUp) return;
    _watchLiveLoaderUp = false;
    final navigator = Navigator.of(context, rootNavigator: true);
    if (navigator.canPop()) navigator.pop();
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

  void _openFilters() => showFilterSheet(context);

  void _openReminders() => showReminderSheet(context);

  void _openHighlights() => _push(HighlightsScreen(
        onOpenNotifications: _openNotifications,
      ));

  void _openRanking() => _push(const RankingsScreen());

  /// Builds the screen for [tab]. Each tab is constructed once and then kept
  /// alive inside the [IndexedStack] below, so its state, loaded data and
  /// scroll position survive bottom-nav switches.
  Widget _buildTab(AppTab tab) {
    switch (tab) {
      case AppTab.home:
        return HomeScreen(
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
          onOpenTeams: () => _push(const TeamsScreen()),
          onOpenContact: () => _push(const ContactUsScreen()),
          onOpenPolicy: () => _push(const PrivacyPolicyScreen()),
          onOpenTerms: () => _push(const TermsScreen()),
          onOpenHighlights: _openHighlights,
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
          // Sticky bottom banner above the bottom navigation. Renders nothing
          // when ads are disabled, the placement is off, or no ad fills.
          StickyBannerBar(placement: _bannerPlacementForTab(active)),
          BottomNav(
              active: active, onTab: (tab) => setState(() => active = tab)),
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
