part of '../player_detail_screen.dart';

class _HeroStatStrip extends StatelessWidget {
  const _HeroStatStrip({required this.items});

  final List<_StatItem> items;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: c.card.withValues(alpha: .55),
        border: Border.all(color: c.cyan.withValues(alpha: .38)),
      ),
      child: LayoutBuilder(builder: (context, constraints) {
        final visible = items.take(5).toList();
        final perItemMin = constraints.maxWidth / visible.length;
        if (perItemMin >= 56) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final item in visible)
                Expanded(child: _StatTile(item: item)),
            ],
          );
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              for (final item in visible)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: SizedBox(width: 84, child: _StatTile(item: item)),
                ),
            ],
          ),
        );
      }),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.item});

  final _StatItem item;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(item.icon, color: c.cyan, size: 18),
          const SizedBox(height: 6),
          Text(
            item.label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: c.muted,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: .4),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              item.value,
              maxLines: 1,
              style: TextStyle(
                color: c.text,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayerTabs extends StatelessWidget {
  const _PlayerTabs({required this.selected, required this.onChanged});

  final int selected;
  final ValueChanged<int> onChanged;

  static const tabs = ['Overview', 'Stats', 'Career', 'Recent', 'Achievements'];

  @override
  Widget build(BuildContext context) {
    return ScrollableSegmentedTabs(
      items: tabs,
      selected: selected,
      onChanged: onChanged,
      height: 52,
    );
  }
}

class _PlayerTabBody extends StatelessWidget {
  const _PlayerTabBody({required this.player, required this.tab});

  final ApiPlayer player;
  final int tab;

  @override
  Widget build(BuildContext context) {
    return switch (tab) {
      1 => _StatsTab(player: player),
      2 => _CareerTab(player: player),
      3 => _RecentTab(player: player),
      4 => _AchievementsTab(player: player),
      _ => _OverviewTab(player: player),
    };
  }
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.player});

  final ApiPlayer player;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _BioCard(player: player),
        const SizedBox(height: 12),
        _CareerSummaryCard(player: player),
        const SizedBox(height: 12),
        _RecentTab(player: player, compact: true),
        const SizedBox(height: 12),
        _AchievementsTab(player: player, compact: true),
      ],
    );
  }
}

class _BioCard extends StatelessWidget {
  const _BioCard({required this.player});

  final ApiPlayer player;

  @override
  Widget build(BuildContext context) {
    final rows = <_InfoRow>[
      _InfoRow('Full Name', apiString(player.fullName ?? player.name)),
      _InfoRow('Date of Birth', apiString(player.dateOfBirth)),
      _InfoRow('Birthplace', apiString(player.birthPlace)),
      _InfoRow('Nationality', apiString(player.nationality ?? player.country)),
      _InfoRow('Role', apiString(player.role)),
      _InfoRow('Debut', apiString(player.debut)),
    ].where((row) => row.value.isNotEmpty).toList();
    return _SectionCard(
      title: 'Player Bio',
      icon: Icons.person_rounded,
      child: rows.isEmpty
          ? const _InlineEmpty('Bio details are not available yet.')
          : Column(children: rows.map((row) => _InfoLine(row: row)).toList()),
    );
  }
}

class _CareerSummaryCard extends StatelessWidget {
  const _CareerSummaryCard({required this.player});

  final ApiPlayer player;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Career Summary',
      icon: Icons.bar_chart_rounded,
      child: player.careerSummary.isEmpty
          ? const _InlineEmpty('Career summary is not available yet.')
          : _StatsTable(
              rows: player.careerSummary,
              columns: const [
                'Format',
                'Matches',
                'Runs',
                'Average',
                '100s',
                'Wickets',
                'Economy'
              ],
            ),
    );
  }
}

class _StatsTab extends StatelessWidget {
  const _StatsTab({required this.player});

  final ApiPlayer player;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionCard(
          title: 'Batting Stats',
          icon: Icons.sports_cricket_rounded,
          child: player.battingStats.isEmpty
              ? const _InlineEmpty('Batting stats are not available yet.')
              : _StatsTable(
                  rows: player.battingStats,
                  columns: const [
                    'Format',
                    'Matches',
                    'Innings',
                    'Runs',
                    'Highest',
                    'Average',
                    'SR',
                    '100s',
                    '50s',
                    '4s',
                    '6s'
                  ],
                ),
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'Bowling Stats',
          icon: Icons.sports_baseball_rounded,
          child: player.bowlingStats.isEmpty
              ? const _InlineEmpty('Bowling stats are not available yet.')
              : _StatsTable(
                  rows: player.bowlingStats,
                  columns: const [
                    'Format',
                    'Matches',
                    'Innings',
                    'Balls',
                    'Runs',
                    'Wickets',
                    'BBI',
                    'Avg',
                    'Eco',
                    'SR',
                    '4w',
                    '5w'
                  ],
                ),
        ),
      ],
    );
  }
}

class _CareerTab extends StatelessWidget {
  const _CareerTab({required this.player});

  final ApiPlayer player;

  @override
  Widget build(BuildContext context) {
    final teams =
        player.teams.map(apiString).where((x) => x.isNotEmpty).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CareerSummaryCard(player: player),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'Teams Represented',
          icon: Icons.groups_rounded,
          child: teams.isEmpty
              ? const _InlineEmpty('Team history is not available yet.')
              : Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final team in teams)
                      _MiniChip(icon: Icons.shield_rounded, text: team),
                  ],
                ),
        ),
      ],
    );
  }
}

class _RecentTab extends StatelessWidget {
  const _RecentTab({required this.player, this.compact = false});

  final ApiPlayer player;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final recent = player.recentForm;
    return _SectionCard(
      title: compact ? 'Recent Form' : 'Recent Performance',
      icon: Icons.timeline_rounded,
      child: recent.isEmpty
          ? const _InlineEmpty('Recent performance data is not available yet.')
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final raw
                      in recent.take(compact ? 5 : recent.length))
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: _RecentChip(item: apiMap(raw)),
                    ),
                ],
              ),
            ),
    );
  }
}

class _AchievementsTab extends StatelessWidget {
  const _AchievementsTab({required this.player, this.compact = false});

  final ApiPlayer player;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final achievements = player.achievements;
    return _SectionCard(
      title: 'Key Achievements',
      icon: Icons.emoji_events_rounded,
      child: achievements.isEmpty
          ? const _InlineEmpty('Achievements are not available yet.')
          : Column(
              children: [
                for (final raw
                    in achievements.take(compact ? 4 : achievements.length))
                  _AchievementLine(item: apiMap(raw)),
              ],
            ),
    );
  }
}

