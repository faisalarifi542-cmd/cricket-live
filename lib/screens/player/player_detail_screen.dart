import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../components.dart';
import '../../models.dart';
import '../../models/api_models.dart';
import '../../models/api_response.dart';
import '../../repositories/cricket_repository.dart';

class PlayerDetailScreen extends StatefulWidget {
  const PlayerDetailScreen({super.key, this.player, this.playerId = ''});

  final PlayerInfo? player;
  final String playerId;

  @override
  State<PlayerDetailScreen> createState() => _PlayerDetailScreenState();
}

class _PlayerDetailScreenState extends State<PlayerDetailScreen> {
  final CricketRepository _repository = CricketRepository();
  Future<ApiEnvelope<ApiPlayer>>? _player;
  int _tab = 0;
  Map<String, dynamic>? _routeArgs;

  String get _playerId {
    final arg = ModalRoute.of(context)?.settings.arguments;
    if (arg is String && arg.isNotEmpty) return arg;
    if (arg is Map && apiString(arg['playerId'] ?? arg['id']).isNotEmpty) {
      return apiString(arg['playerId'] ?? arg['id']);
    }
    return widget.playerId;
  }

  Map<String, dynamic>? get _playerArgs {
    final arg = ModalRoute.of(context)?.settings.arguments;
    if (arg is Map<String, dynamic>) return arg;
    if (arg is Map) return Map<String, dynamic>.from(arg);
    return _routeArgs;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _routeArgs ??= _playerArgs;
    if (_player == null && _playerId.isNotEmpty) {
      _player = _repository.player(_playerId);
    }
  }

  Future<void> _refresh() async {
    if (_playerId.isEmpty) return;
    setState(() => _player = _repository.player(_playerId, forceRefresh: true));
    await _player;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final fallback = widget.player;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: c.bgGradient),
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                context.horizontalPadding,
                18,
                context.horizontalPadding,
                context.detailBottomPadding,
              ),
              children: [
                AppHeader(
                  leading: IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.arrow_back_rounded, color: c.text),
                  ),
                  showLogo: true,
                  trailing: [
                    GlowIconButton(
                        icon: Icons.notifications_none_rounded, onTap: () {}),
                  ],
                ),
                const SizedBox(height: 18),
                if (_player != null)
                  _ApiPlayerProfile(
                    future: _player!,
                    tab: _tab,
                    ranking: _playerArgs,
                    onTabChanged: (value) => setState(() => _tab = value),
                  )
                else if (fallback != null)
                  _FallbackPlayerCard(player: fallback)
                else
                  const _PlayerStateCard(
                    title: 'No player selected',
                    text:
                        'Open a player from rankings, squads, or scorecard to view the real profile.',
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ApiPlayerProfile extends StatelessWidget {
  const _ApiPlayerProfile({
    required this.future,
    required this.tab,
    required this.ranking,
    required this.onTabChanged,
  });

  final Future<ApiEnvelope<ApiPlayer>> future;
  final int tab;
  final Map<String, dynamic>? ranking;
  final ValueChanged<int> onTabChanged;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ApiEnvelope<ApiPlayer>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _PlayerLoading();
        }
        if (snapshot.hasError) {
          return const _PlayerStateCard(
            title: 'Unable to load player profile',
            text:
                'Pull to retry. The profile service may be temporarily unavailable.',
          );
        }
        final player = snapshot.data?.data;
        if (player == null || player.id.isEmpty || player.name.trim().isEmpty) {
          return const _PlayerStateCard(
            title: 'Player profile unavailable',
            text: 'Cricbuzz did not return profile data for this player yet.',
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PlayerHero(player: player, ranking: ranking),
            const SizedBox(height: 14),
            _PlayerTabs(selected: tab, onChanged: onTabChanged),
            const SizedBox(height: 14),
            _PlayerTabBody(player: player, tab: tab),
          ],
        );
      },
    );
  }
}

class _PlayerHero extends StatelessWidget {
  const _PlayerHero({required this.player, this.ranking});

  final ApiPlayer player;
  final Map<String, dynamic>? ranking;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final primary = _primarySummary(player);
    final statItems = _heroStats(player, primary);
    final rank = apiMap((player.rankings != null && player.rankings!.isNotEmpty)
        ? player.rankings
        : ranking);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          colors: [
            c.cyan.withValues(alpha: .20),
            c.card,
            c.card2,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: c.cyan.withValues(alpha: .55), width: 1.4),
        boxShadow: [
          BoxShadow(
            color: c.cyan.withValues(alpha: .18),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Stack(
          children: [
            Positioned(
              right: -40,
              top: -40,
              child: Icon(
                Icons.sports_cricket_rounded,
                size: 180,
                color: c.cyan.withValues(alpha: .05),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _PlayerPortrait(player: player),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if ((player.country ?? '').isNotEmpty)
                              _MiniChip(
                                icon: Icons.flag_rounded,
                                text: player.country!.toUpperCase(),
                              ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    player.name.toUpperCase(),
                                    style: TextStyle(
                                      color: c.text,
                                      fontWeight: FontWeight.w900,
                                      fontSize: context.sp(28),
                                      height: 1.0,
                                    ),
                                  ),
                                ),
                                Icon(Icons.verified_rounded,
                                    color: c.cyan, size: 24),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              apiString(player.role, 'Role unavailable'),
                              style: TextStyle(
                                color: c.text.withValues(alpha: .86),
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 16),
                            _StyleRow(
                                icon: Icons.sports_cricket_rounded,
                                label: 'Batting Style',
                                value: player.battingStyle),
                            _StyleRow(
                                icon: Icons.sports_baseball_rounded,
                                label: 'Bowling Style',
                                value: player.bowlingStyle),
                            if ((player.jerseyNumber ?? '').isNotEmpty)
                              _StyleRow(
                                  icon: Icons.checkroom_rounded,
                                  label: 'Jersey Number',
                                  value: player.jerseyNumber),
                          ],
                        ),
                      ),
                      if (rank.isNotEmpty) ...[
                        const SizedBox(width: 10),
                        _RankCard(rank: rank),
                      ],
                    ],
                  ),
                  if (statItems.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    _HeroStatStrip(items: statItems),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerPortrait extends StatelessWidget {
  const _PlayerPortrait({required this.player});

  final ApiPlayer player;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      width: 132,
      height: 178,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.card2,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: c.cyan.withValues(alpha: .45)),
        boxShadow: [
          BoxShadow(color: c.cyan.withValues(alpha: .12), blurRadius: 24),
        ],
      ),
      child: player.image == null
          ? _Initial(player.name, size: 42)
          : Image.network(
              player.image!,
              fit: BoxFit.cover,
              webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
              errorBuilder: (_, __, ___) => _Initial(player.name, size: 42),
            ),
    );
  }
}

class _StyleRow extends StatelessWidget {
  const _StyleRow(
      {required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    if (apiString(value).isEmpty) return const SizedBox.shrink();
    final c = context.cric;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, color: c.cyan, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        color: c.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
                Text(value!,
                    style: TextStyle(
                        color: c.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w800)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RankCard extends StatelessWidget {
  const _RankCard({required this.rank});

  final Map<String, dynamic> rank;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final rankValue = apiString(rank['rank']);
    final points = apiString(rank['points']);
    if (rankValue.isEmpty && points.isEmpty) return const SizedBox.shrink();
    return Container(
      width: 104,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.cyan.withValues(alpha: .55)),
        color: c.card.withValues(alpha: .65),
      ),
      child: Column(
        children: [
          Icon(Icons.diamond_rounded, color: c.cyan, size: 24),
          if (rankValue.isNotEmpty)
            Text(rankValue,
                style: TextStyle(
                    color: c.text, fontWeight: FontWeight.w900, fontSize: 24)),
          Text('RANK',
              style: TextStyle(
                  color: c.muted, fontWeight: FontWeight.w800, fontSize: 11)),
          if (points.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('$points PTS',
                style: TextStyle(
                    color: c.text, fontWeight: FontWeight.w800, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}

class _HeroStatStrip extends StatelessWidget {
  const _HeroStatStrip({required this.items});

  final List<_StatItem> items;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: c.card.withValues(alpha: .55),
        border: Border.all(color: c.cyan.withValues(alpha: .38)),
      ),
      child: Row(
        children: [
          for (final item in items.take(5))
            Expanded(
              child: Column(
                children: [
                  Icon(item.icon, color: c.cyan, size: 22),
                  const SizedBox(height: 6),
                  Text(item.label.toUpperCase(),
                      style: TextStyle(
                          color: c.muted,
                          fontSize: 10,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(item.value,
                      style: TextStyle(
                          color: c.text,
                          fontSize: 20,
                          fontWeight: FontWeight.w900)),
                ],
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
    final c = context.cric;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: c.border),
        ),
        child: Row(
          children: [
            for (var i = 0; i < tabs.length; i++)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => onChanged(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 128,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      gradient: i == selected ? c.primaryGradient : null,
                    ),
                    child: Text(
                      tabs[i],
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: i == selected ? Colors.white : c.muted,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
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
          : Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final raw in recent.take(compact ? 5 : recent.length))
                  _RecentChip(item: apiMap(raw)),
              ],
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

class _SectionCard extends StatelessWidget {
  const _SectionCard(
      {required this.title, required this.icon, required this.child});

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: c.cyan, size: 24),
              const SizedBox(width: 10),
              Text(title.toUpperCase(),
                  style: TextStyle(
                      color: c.text,
                      fontWeight: FontWeight.w900,
                      fontSize: 16)),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _StatsTable extends StatelessWidget {
  const _StatsTable({required this.rows, required this.columns});

  final List<dynamic> rows;
  final List<String> columns;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 700),
        child: Column(
          children: [
            _TableRow(
              cells: columns,
              color: c.cyan.withValues(alpha: .10),
              header: true,
            ),
            for (final row in rows)
              _TableRow(
                cells: columns
                    .map((key) => _valueForColumn(apiMap(row), key))
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }
}

class _TableRow extends StatelessWidget {
  const _TableRow({required this.cells, this.color, this.header = false});

  final List<String> cells;
  final Color? color;
  final bool header;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      decoration: BoxDecoration(
        color: color,
        border:
            Border(bottom: BorderSide(color: c.border.withValues(alpha: .55))),
      ),
      child: Row(
        children: [
          for (final cell in cells)
            SizedBox(
              width: cell == cells.first ? 92 : 74,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                child: Text(
                  cell.isEmpty ? '-' : cell,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: header ? c.muted : c.text,
                    fontWeight: header ? FontWeight.w900 : FontWeight.w700,
                    fontSize: header ? 11 : 13,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RecentChip extends StatelessWidget {
  const _RecentChip({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      width: 104,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.card2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.cyan.withValues(alpha: .28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(apiString(item['score'], '-'),
              style: TextStyle(
                  color: c.cyan, fontSize: 20, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text('vs ${apiString(item['opponent'], '-')}',
              style: TextStyle(color: c.text, fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          Text(apiString(item['format']),
              style: TextStyle(
                  color: c.cyan, fontSize: 12, fontWeight: FontWeight.w800)),
          Text(apiString(item['date']),
              style: TextStyle(
                  color: c.muted, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _AchievementLine extends StatelessWidget {
  const _AchievementLine({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(Icons.workspace_premium_rounded, color: c.cyan, size: 22),
          const SizedBox(width: 10),
          Expanded(
              child: Text(apiString(item['title'] ?? item['name']),
                  style:
                      TextStyle(color: c.text, fontWeight: FontWeight.w800))),
          Text(apiString(item['year'] ?? item['date']),
              style: TextStyle(color: c.muted, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.row});

  final _InfoRow row;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
              child: Text(row.label,
                  style:
                      TextStyle(color: c.muted, fontWeight: FontWeight.w700))),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              row.value,
              textAlign: TextAlign.right,
              style: TextStyle(color: c.text, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineEmpty extends StatelessWidget {
  const _InlineEmpty(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Row(
      children: [
        Icon(Icons.info_outline_rounded, color: c.cyan, size: 20),
        const SizedBox(width: 10),
        Expanded(
            child: Text(text,
                style: TextStyle(color: c.muted, fontWeight: FontWeight.w700))),
      ],
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: c.cyan.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.cyan.withValues(alpha: .28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: c.cyan, size: 16),
          const SizedBox(width: 6),
          Text(text,
              style: TextStyle(
                  color: c.text, fontSize: 12, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class _FallbackPlayerCard extends StatelessWidget {
  const _FallbackPlayerCard({required this.player});

  final PlayerInfo player;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          PlayerAvatar(player: player, size: 110, borderColor: c.cyan),
          const SizedBox(height: 16),
          Text(player.name,
              style: TextStyle(
                  color: c.text, fontSize: 28, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text('${player.team.name} - ${player.role}',
              style: TextStyle(color: c.cyan, fontWeight: FontWeight.w700)),
          if (player.subtitle != null) ...[
            const SizedBox(height: 6),
            Text(player.subtitle!, style: TextStyle(color: c.muted)),
          ],
        ],
      ),
    );
  }
}

class _PlayerLoading extends StatelessWidget {
  const _PlayerLoading();

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Column(
      children: [
        Container(
          height: 320,
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: c.border),
          ),
          child: const Center(child: CircularProgressIndicator()),
        ),
        const SizedBox(height: 14),
        const LinearProgressIndicator(),
      ],
    );
  }
}

class _PlayerStateCard extends StatelessWidget {
  const _PlayerStateCard({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Icon(Icons.person_outline_rounded, color: c.cyan, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        color: c.text,
                        fontWeight: FontWeight.w900,
                        fontSize: 16)),
                const SizedBox(height: 4),
                Text(text,
                    style: TextStyle(
                        color: c.muted,
                        fontWeight: FontWeight.w700,
                        height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Initial extends StatelessWidget {
  const _Initial(this.name, {this.size = 26});

  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Center(
      child: Text(
        initial,
        style: TextStyle(
            color: context.cric.text,
            fontSize: size,
            fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _InfoRow {
  const _InfoRow(this.label, this.value);
  final String label;
  final String value;
}

class _StatItem {
  const _StatItem(this.label, this.value, this.icon);
  final String label;
  final String value;
  final IconData icon;
}

Map<String, dynamic> _primarySummary(ApiPlayer player) {
  final rows =
      player.careerSummary.map(apiMap).where((row) => row.isNotEmpty).toList();
  if (rows.isEmpty) return const {};
  final priorities = ['ODI', 'Test', 'T20', 'T20I', 'IPL'];
  for (final key in priorities) {
    final found = rows.where(
        (row) => apiString(row['format']).toLowerCase() == key.toLowerCase());
    if (found.isNotEmpty) return found.first;
  }
  return rows.first;
}

List<_StatItem> _heroStats(ApiPlayer player, Map<String, dynamic> row) {
  if (row.isEmpty) return const [];
  final role = apiString(player.role).toLowerCase();
  final isBowler = role.contains('bowler') && !role.contains('bat');
  final items = <_StatItem>[];
  void add(String label, dynamic value, IconData icon) {
    final text = apiString(value);
    if (text.isNotEmpty && text != '0.0') {
      items.add(_StatItem(label, text, icon));
    }
  }

  add('Matches', row['matches'] ?? row['Matches'],
      Icons.calendar_month_rounded);
  if (isBowler) {
    add('Wickets', row['wickets'] ?? row['Wickets'],
        Icons.sports_baseball_rounded);
    add('Economy', row['economy'] ?? row['Eco'], Icons.speed_rounded);
    add('Average', row['average'] ?? row['Avg'], Icons.bar_chart_rounded);
    add('Runs', row['runs'] ?? row['Runs'], Icons.sports_cricket_rounded);
  } else {
    add('Runs', row['runs'] ?? row['Runs'], Icons.sports_cricket_rounded);
    add('Average', row['average'] ?? row['Average'], Icons.bar_chart_rounded);
    add('Strike Rate', row['strikeRate'] ?? row['SR'], Icons.speed_rounded);
    add('Hundreds', row['hundreds'] ?? row['100s'], Icons.looks_one_rounded);
  }
  return items;
}

String _valueForColumn(Map<String, dynamic> row, String key) {
  const aliases = {
    'Format': ['format'],
    'Matches': ['matches', 'Matches'],
    'Innings': ['innings', 'Innings'],
    'Runs': ['runs', 'Runs'],
    'Highest': ['highest', 'Highest'],
    'Average': ['average', 'Average', 'Avg'],
    'SR': ['strikeRate', 'SR'],
    '100s': ['hundreds', '100s'],
    '50s': ['fifties', '50s'],
    '4s': ['4s', 'Fours'],
    '6s': ['6s', 'Sixes'],
    'Balls': ['balls', 'Balls'],
    'Wickets': ['wickets', 'Wickets'],
    'BBI': ['BBI'],
    'Avg': ['Avg', 'average'],
    'Eco': ['Eco', 'economy'],
    '4w': ['4w'],
    '5w': ['5w'],
    'Economy': ['economy', 'Eco'],
  };
  for (final candidate in aliases[key] ?? [key]) {
    final text = apiString(row[candidate]);
    if (text.isNotEmpty) return text;
  }
  return '';
}
