import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'components.dart';
import 'sheets.dart';
import 'screens/home/home_screen.dart';
import 'screens/matches/matches_screen.dart';
import 'screens/news/news_screen.dart';
import 'screens/news/news_detail_screen.dart';
import 'screens/more/more_screen.dart';
import 'screens/more/contact_us_screen.dart';
import 'screens/more/privacy_policy_screen.dart';
import 'screens/more/terms_screen.dart';
import 'screens/live/live_player_screen.dart';
import 'screens/highlights/highlight_detail_screen.dart';
import 'screens/highlights/highlights_screen.dart';
import 'screens/rankings/rankings_screen.dart';
import 'screens/schedule/schedule_screen.dart';
import 'screens/teams/teams_screen.dart';
import 'screens/match_details/match_details_screen.dart';
import 'screens/series/series_detail_screen.dart';
import 'screens/series/series_list_screen.dart';
import 'screens/common/search_screen.dart';
import 'screens/common/notifications_screen.dart';
import 'screens/player/player_detail_screen.dart';
import 'repositories/cricket_repository.dart';

void main() => runApp(const CricProApp());

class CricProApp extends StatefulWidget {
  const CricProApp({super.key});

  @override
  State<CricProApp> createState() => _CricProAppState();
}

class _CricProAppState extends State<CricProApp> {
  bool dark = true;
  final CricketRepository _repository = CricketRepository();
  Map<String, dynamic> _appConfig = const {};

  @override
  void initState() {
    super.initState();
    _loadAppConfig();
  }

  Future<void> _loadAppConfig() async {
    try {
      final response = await _repository.appConfig();
      if (mounted) setState(() => _appConfig = response.data);
    } catch (_) {
      // The app can still render with built-in defaults when config is unavailable.
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'CRICPRO',
      theme: cricTheme(dark),
      home: _appConfig['maintenanceMode'] == true
          ? const _MaintenanceScreen()
          : RootShell(
              isDark: dark,
              onThemeChanged: (v) => setState(() => dark = v),
            ),
    );
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

  void _openMatch({String matchId = ''}) => _push(MatchDetailsScreen(
        matchId: matchId,
        onWatchLive: (id) => _openLivePlayer(matchId: id),
      ));

  void _openLivePlayer({String matchId = ''}) =>
      _push(LivePlayerScreen(matchId: matchId));

  void _openHighlightDetail() => _push(const HighlightDetailScreen());

  void _openSeries({int initialTab = 0}) => _push(SeriesListScreen(
        onOpenSeries: (seriesId) => _push(SeriesDetailScreen(
          seriesId: seriesId,
          initialTab: initialTab,
          onOpenReminders: () => showReminderSheet(context),
          onOpenCalendar: () => showCalendarSheet(context),
          onOpenPlayer: () => _push(const PlayerDetailScreen()),
        )),
      ));

  void _openSearch() => _push(const SearchScreen());

  void _openNotifications() => _push(const NotificationsScreen());

  void _openFilters() => showFilterSheet(context);

  void _openReminders() => showReminderSheet(context);

  void _openArticle() => _push(const NewsDetailScreen());

  void _openHighlights() => _push(HighlightsScreen(
        onOpenVideo: _openHighlightDetail,
        onOpenSearch: _openSearch,
        onOpenNotifications: _openNotifications,
      ));

  void _openRanking() => _push(const RankingsScreen());

  @override
  Widget build(BuildContext context) {
    Widget body = switch (active) {
      AppTab.home => HomeScreen(
          onOpenMatchDetails: _openMatch,
          onOpenSeries: _openSeries,
          onOpenSearch: _openSearch,
          onOpenNotifications: _openNotifications,
          onOpenFilters: _openFilters,
          onOpenReminders: _openReminders,
          onOpenRanking: _openRanking,
          onWatchLive: (id) => _openLivePlayer(matchId: id),
        ),
      AppTab.matches => MatchesScreen(
          onOpenMatch: _openMatch,
          onOpenSearch: _openSearch,
          onOpenFilters: _openFilters,
          onOpenReminders: _openReminders,
          onOpenSeries: _openSeries,
        ),
      AppTab.schedule => ScheduleScreen(onOpenSeries: _openSeries),
      AppTab.news => NewsScreen(
          onOpenSearch: _openSearch,
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
