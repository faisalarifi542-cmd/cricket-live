import 'package:flutter/material.dart';

import 'package:cricpro_flutter/app_theme.dart';
import 'package:cricpro_flutter/api_models.dart';
import 'package:cricpro_flutter/components.dart';
import 'package:cricpro_flutter/models.dart';
import 'package:cricpro_flutter/models/ad_config.dart';
import 'package:cricpro_flutter/sheets.dart';
import 'package:cricpro_flutter/screens/home/home_screen.dart';
import 'package:cricpro_flutter/screens/matches/matches_screen.dart';
import 'package:cricpro_flutter/screens/news/news_screen.dart';
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
import 'package:cricpro_flutter/services/notification_service.dart';

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

class _CricProAppState extends State<CricProApp> {
  bool dark = true;
  final CricketRepository _repository = CricketRepository();
  AppConfig _appConfig = const AppConfig(values: {});

  @override
  void initState() {
    super.initState();
    _loadAppConfig();
  }

  Future<void> _loadAppConfig() async {
    try {
      final response = await _repository.appConfig();
      if (mounted) {
        final config = AppConfig.fromJson(response.data);
        await AdService.instance.initialize(AdConfig.fromAppConfig(response.data));
        await NotificationService.instance.initialize(
          config,
          onDeepLink: _handleNotificationDeepLink,
        );
        setState(() => _appConfig = config);
      }
    } catch (_) {
      // The app can still render with built-in defaults when config is unavailable.
    }
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

  /// Opens the match details screen. Accepts a positional [matchId] so it
  /// can be passed as a `ValueChanged<String>` callback directly. Empty
  /// strings are tolerated and surface the demo hero.
  void _openMatch([String matchId = '']) => _push(MatchDetailsScreen(
        matchId: matchId,
        onWatchLive: (id) => _openLivePlayer(matchId: id),
      ));

  void _openLivePlayer({String matchId = ''}) =>
      _push(LivePlayerScreen(matchId: matchId));

  void _openSeries({int initialTab = 0}) => _push(SeriesListScreen(
        onOpenSeries: (seriesId) => _push(SeriesDetailScreen(
          seriesId: seriesId,
          initialTab: initialTab,
          onOpenReminders: () => showReminderSheet(context),
          onOpenCalendar: () => showCalendarSheet(context),
          onOpenPlayer: () => _push(const PlayerDetailScreen()),
        )),
      ));

  void _openNotifications() => _push(const NotificationsScreen());

  void _openFilters() => showFilterSheet(context);

  void _openReminders() => showReminderSheet(context);

  void _openArticle(NewsArticle article) =>
      _push(NewsDetailScreen(article: article));

  void _openHighlights() => _push(HighlightsScreen(
        onOpenNotifications: _openNotifications,
      ));

  void _openRanking() => _push(const RankingsScreen());

  @override
  Widget build(BuildContext context) {
    Widget body = switch (active) {
      AppTab.home => HomeScreen(
          onOpenMatchDetails: _openMatch,
          onOpenSeries: _openSeries,
          onOpenNotifications: _openNotifications,
          onOpenFilters: _openFilters,
          onOpenReminders: _openReminders,
          onOpenRanking: _openRanking,
          onWatchLive: (id) => _openLivePlayer(matchId: id),
        ),
      AppTab.matches => MatchesScreen(
          onOpenMatch: _openMatch,
          onOpenFilters: _openFilters,
          onOpenReminders: _openReminders,
          onOpenSeries: _openSeries,
          onWatchLive: (id) => _openLivePlayer(matchId: id),
        ),
      AppTab.schedule => ScheduleScreen(
          onOpenSeries: _openSeries,
          onOpenMatch: _openMatch,
        ),
      AppTab.news => NewsScreen(
          onOpenFilters: _openFilters,
          onOpenArticle: _openArticle,
        ),
      AppTab.more => MoreScreen(
          isDark: widget.isDark,
          onThemeChanged: widget.onThemeChanged,
          onOpenRanking: _openRanking,
          onOpenTeams: () => _push(const TeamsScreen()),
          onOpenContact: () => _push(const ContactUsScreen()),
          onOpenPolicy: () => _push(const PrivacyPolicyScreen()),
          onOpenTerms: () => _push(const TermsScreen()),
          onOpenHighlights: _openHighlights,
        ),
    };
    return Scaffold(
      extendBody: true,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 240),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position:
                Tween<Offset>(begin: const Offset(0, .02), end: Offset.zero)
                    .animate(anim),
            child: child,
          ),
        ),
        child: KeyedSubtree(key: ValueKey(active), child: body),
      ),
      bottomNavigationBar: BottomNav(
          active: active, onTab: (tab) => setState(() => active = tab)),
    );
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
