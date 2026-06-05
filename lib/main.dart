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
  bool _appOpenColdStartDone = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAppConfig();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // App Open on resume — only when enabled, config loaded, and safe.
    if (state == AppLifecycleState.resumed &&
        _adsReady &&
        AdsManager.instance.config.appOpenAllowed &&
        AdsManager.instance.config.appOpenShowOnResume) {
      AdsManager.instance.maybeShowAppOpen();
    }
  }

  Future<void> _loadAppConfig() async {
    try {
      final response = await _repository.appConfig();
      if (mounted) {
        final config = AppConfig.fromJson(response.data);
        await AdService.instance.initialize(AdConfig.fromAppConfig(response.data));
        _adsReady = true;
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
  /// visible first (policy-safe timing). No-op unless enabled in admin config.
  void _maybeShowColdStartAppOpen() {
    if (_appOpenColdStartDone) return;
    final ads = AdsManager.instance.config;
    if (!ads.appOpenAllowed || !ads.appOpenShowOnColdStart) return;
    _appOpenColdStartDone = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AdsManager.instance.maybeShowAppOpen();
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
            style: TextStyle(color: c.text, fontWeight: FontWeight.w900, fontSize: 20),
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
    AdsManager.instance.maybeShowInterstitial(placement: AdPlacement.matchDetails);
    _push(MatchDetailsScreen(
      matchId: matchId,
      onWatchLive: (id) => _openLivePlayer(matchId: id),
    ));
  }

  void _openLivePlayer({String matchId = ''}) async {
    await _push(LivePlayerScreen(matchId: matchId));
    // After the user leaves the live player, optionally show an interstitial
    // (opt-in via admin "after player" toggle). Never during playback.
    if (AdsManager.instance.config.interstitialAfterPlayer) {
      AdsManager.instance.maybeShowInterstitial(placement: AdPlacement.livePlayer);
    }
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
      extendBody: true,
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
