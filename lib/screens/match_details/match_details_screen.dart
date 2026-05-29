import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../components.dart';
import '../../screens.dart';

class MatchDetailsScreen extends StatefulWidget {
  const MatchDetailsScreen({super.key, this.onWatchLive});

  final VoidCallback? onWatchLive;

  @override
  State<MatchDetailsScreen> createState() => _MatchDetailsScreenState();
}

class _MatchDetailsScreenState extends State<MatchDetailsScreen> {
  int tab = 0;

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
                title: 'Match Details',
                trailing: [
                  GlowIconButton(icon: Icons.search_rounded),
                  const SizedBox(width: 8),
                  GlowIconButton(icon: Icons.filter_alt_outlined),
                ],
              ),
              const SizedBox(height: 16),
              MatchDetailHeroCard(onWatchLive: widget.onWatchLive),
              const SizedBox(height: 16),
              // Match Details has 5 tabs which squeeze "Commentary" into
              // "Comment…" on narrow widths. Use the scrollable variant so
              // every label stays fully visible.
              ScrollableSegmentedTabs(
                items: const [
                  'Scorecard',
                  'Commentary',
                  'Overs',
                  'Info',
                  'Squads'
                ],
                selected: tab,
                onChanged: (v) => setState(() => tab = v),
                height: 52,
              ),
              const SizedBox(height: 16),
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
                    0 => const MatchScorecardTab(),
                    1 => const MatchCommentaryTab(),
                    2 => const MatchOversTab(),
                    3 => const MatchInfoTab(),
                    _ => const MatchSquadsTab(),
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
