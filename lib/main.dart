import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'components.dart';
import 'screens.dart';
import 'sheets.dart';

void main() => runApp(const CricProApp());

class CricProApp extends StatefulWidget {
  const CricProApp({super.key});

  @override
  State<CricProApp> createState() => _CricProAppState();
}

class _CricProAppState extends State<CricProApp> {
  bool dark = true;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'CRICPRO',
      theme: cricTheme(dark),
      home: RootShell(
        isDark: dark,
        onThemeChanged: (v) => setState(() => dark = v),
      ),
    );
  }
}

class RootShell extends StatefulWidget {
  const RootShell({super.key, required this.isDark, required this.onThemeChanged});

  final bool isDark;
  final ValueChanged<bool> onThemeChanged;

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  AppTab active = AppTab.home;

  void _openMatch() => _push(MatchDetailsScreen(onWatchLive: _openLivePlayer));

  void _openLivePlayer() => _push(const HighlightsPlayerScreen());

  void _openSeries({int initialTab = 0}) => _push(SeriesDetailScreen(
        initialTab: initialTab,
        onOpenReminders: () => showReminderSheet(context),
        onOpenCalendar: () => showCalendarSheet(context),
        onOpenPlayer: () => _push(const PlayerDetailScreen()),
      ));

  void _openSearch() => _push(const SearchScreen());

  void _openNotifications() => _push(const NotificationsScreen());

  void _openFilters() => showFilterSheet(context);

  void _openReminders() => showReminderSheet(context);

  void _openArticle() => _push(const NewsDetailScreen());

  void _openHighlights() => _push(HighlightsScreen(
        onOpenVideo: () => _push(const HighlightsPlayerScreen()),
        onOpenSearch: _openSearch,
        onOpenNotifications: _openNotifications,
      ));

  void _openRanking() => _push(const RankingScreen());

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
          onWatchLive: _openLivePlayer,
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
            position: Tween<Offset>(begin: const Offset(0, .02), end: Offset.zero).animate(anim),
            child: child,
          ),
        ),
        child: KeyedSubtree(key: ValueKey(active), child: body),
      ),
      bottomNavigationBar: BottomNav(active: active, onTab: (tab) => setState(() => active = tab)),
    );
  }

  Future<void> _push(Widget screen) => Navigator.of(context).push(
        PageRouteBuilder<void>(
          transitionDuration: const Duration(milliseconds: 280),
          reverseTransitionDuration: const Duration(milliseconds: 220),
          pageBuilder: (_, animation, __) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(begin: const Offset(.05, 0), end: Offset.zero).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
              child: screen,
            ),
          ),
        ),
      );
}
