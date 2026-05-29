import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../components.dart';
import '../../screens.dart';

class SeriesDetailScreen extends StatefulWidget {
  const SeriesDetailScreen({
    super.key,
    this.initialTab = 0,
    required this.onOpenReminders,
    required this.onOpenCalendar,
    required this.onOpenPlayer,
  });

  final int initialTab;
  final VoidCallback onOpenReminders;
  final VoidCallback onOpenCalendar;
  final VoidCallback onOpenPlayer;

  @override
  State<SeriesDetailScreen> createState() => _SeriesDetailScreenState();
}

class _SeriesDetailScreenState extends State<SeriesDetailScreen> {
  late int tab = widget.initialTab;
  int squadTeam = 0;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: c.bgGradient),
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.fromLTRB(context.horizontalPadding, 18,
                context.horizontalPadding, context.detailBottomPadding),
            children: [
              AppHeader(
                leading: IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.arrow_back_rounded, color: c.text)),
                showLogo: true,
                trailing: [
                  GlowIconButton(
                      icon: Icons.notifications_none_rounded, badge: '3'),
                  const SizedBox(width: 8),
                  GlowIconButton(icon: Icons.more_vert_rounded),
                ],
              ),
              const SizedBox(height: 14),
              const SeriesHeroCard(),
              const SizedBox(height: 16),
              SegmentedTabs(
                items: const [
                  ('Overview', null),
                  ('Matches', null),
                  ('Squads', null),
                  ('Stats', null)
                ],
                selected: tab,
                onChanged: (v) => setState(() => tab = v),
                height: 58,
              ),
              const SizedBox(height: 18),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: child,
                ),
                child: KeyedSubtree(
                  key: ValueKey(tab),
                  child: switch (tab) {
                    0 =>
                      SeriesOverviewTab(onOpenReminder: widget.onOpenReminders),
                    1 =>
                      SeriesMatchesTab(onOpenCalendar: widget.onOpenCalendar),
                    2 => SeriesSquadsTab(
                        squadTeam: squadTeam,
                        onTeamChanged: (v) => setState(() => squadTeam = v),
                        onOpenPlayer: widget.onOpenPlayer,
                      ),
                    _ => const SeriesStatsTab(),
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
