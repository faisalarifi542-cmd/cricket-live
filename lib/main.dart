import 'package:flutter/material.dart';
import 'app_theme.dart';
import 'components.dart';
import 'screens.dart';

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
          isDark: dark, onThemeChanged: (v) => setState(() => dark = v)),
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
  @override
  Widget build(BuildContext context) {
    Widget body = switch (active) {
      AppTab.home => HomeScreen(
          onOpenStream: () => _push(const LiveStreamScreen()),
          onOpenMatch: () => _push(const MatchDetailsScreen()),
          onOpenRanking: () => _push(const RankingScreen())),
      AppTab.matches =>
        MatchesScreen(onOpenMatch: () => _push(const MatchDetailsScreen())),
      AppTab.schedule => const ScheduleScreen(),
      AppTab.news => const NewsScreen(),
      AppTab.more => MoreScreen(
          isDark: widget.isDark,
          onThemeChanged: widget.onThemeChanged,
          onOpenRanking: () => _push(const RankingScreen()),
          onOpenTeams: () => _push(const TeamsScreen())),
    };
    return Scaffold(
      extendBody: true,
      body: body,
      bottomNavigationBar: BottomNav(
          active: active, onTab: (tab) => setState(() => active = tab)),
    );
  }

  Future<void> _push(Widget screen) => Navigator.of(context).push(
        PageRouteBuilder<void>(
          transitionDuration: const Duration(milliseconds: 260),
          reverseTransitionDuration: const Duration(milliseconds: 220),
          pageBuilder: (_, animation, __) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(.03, .02),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                  parent: animation, curve: Curves.easeOutCubic)),
              child: screen,
            ),
          ),
        ),
      );
}
