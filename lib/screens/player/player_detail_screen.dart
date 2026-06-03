import 'package:flutter/material.dart';

import 'package:cricpro_flutter/app_theme.dart';
import 'package:cricpro_flutter/api_models.dart';
import 'package:cricpro_flutter/components.dart';
import 'package:cricpro_flutter/models.dart';
import 'package:cricpro_flutter/models/api_response.dart';
import 'package:cricpro_flutter/repositories/cricket_repository.dart';

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
                    const SizedBox(width: 8),
                    GlowIconButton(
                        icon: Icons.more_vert_rounded, onTap: () {}),
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
    final rankValue = apiString(rank['rank']);
    final pointsValue = apiString(rank['points']);
    final country = apiString(player.country ?? player.nationality);
    final role = apiString(player.role);

    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final compact = width < 380;
      final portraitSize = compact ? 96.0 : (width < 460 ? 116.0 : 132.0);

      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          gradient: LinearGradient(
            colors: [
              c.cyan.withValues(alpha: .22),
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
                padding: EdgeInsets.all(compact ? 14 : 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _PlayerPortrait(player: player, size: portraitSize),
                        SizedBox(width: compact ? 12 : 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (country.isNotEmpty)
                                _CountryChip(country: country),
                              if (country.isNotEmpty)
                                const SizedBox(height: 8),
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      player.name,
                                      maxLines: 2,
                                      softWrap: true,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: c.text,
                                        fontWeight: FontWeight.w900,
                                        fontSize: compact ? 20 : 24,
                                        height: 1.1,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Icon(Icons.verified_rounded,
                                      color: c.cyan,
                                      size: compact ? 18 : 22),
                                ],
                              ),
                              if (role.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  role,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  softWrap: true,
                                  style: TextStyle(
                                    color: c.cyan,
                                    fontWeight: FontWeight.w800,
                                    fontSize: compact ? 12 : 13,
                                  ),
                                ),
                              ],
                              if (rankValue.isNotEmpty ||
                                  pointsValue.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                _RankBadge(
                                    rank: rankValue, points: pointsValue),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (player.battingStyle != null ||
                        player.bowlingStyle != null ||
                        apiString(player.jerseyNumber).isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _StyleGrid(player: player),
                    ],
                    if (statItems.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _HeroStatStrip(items: statItems),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}

class _PlayerPortrait extends StatelessWidget {
  const _PlayerPortrait({required this.player, this.size = 132});

  final ApiPlayer player;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final height = size * 178 / 132;
    return Container(
      width: size,
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.card2,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.cyan.withValues(alpha: .45)),
        boxShadow: [
          BoxShadow(color: c.cyan.withValues(alpha: .12), blurRadius: 24),
        ],
      ),
      child: player.image == null
          ? _Initial(player.name, size: size * .32)
          : Image.network(
              player.image!,
              fit: BoxFit.cover,
              webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
              errorBuilder: (_, __, ___) =>
                  _Initial(player.name, size: size * .32),
            ),
    );
  }
}

class _CountryChip extends StatelessWidget {
  const _CountryChip({required this.country});

  final String country;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.cyan.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.cyan.withValues(alpha: .35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.public_rounded, color: c.cyan, size: 14),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              country,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.text,
                fontWeight: FontWeight.w800,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank, required this.points});

  final String rank;
  final String points;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.cyan.withValues(alpha: .55)),
        color: c.card.withValues(alpha: .65),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.diamond_rounded, color: c.cyan, size: 16),
          if (rank.isNotEmpty) ...[
            const SizedBox(width: 6),
            Text('#$rank',
                style: TextStyle(
                    color: c.text,
                    fontWeight: FontWeight.w900,
                    fontSize: 14)),
          ],
          if (points.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text('$points pts',
                style: TextStyle(
                    color: c.muted,
                    fontWeight: FontWeight.w800,
                    fontSize: 11)),
          ],
        ],
      ),
    );
  }
}

class _StyleGrid extends StatelessWidget {
  const _StyleGrid({required this.player});

  final ApiPlayer player;

  @override
  Widget build(BuildContext context) {
    final rows = <_StyleEntry>[];
    if (apiString(player.battingStyle).isNotEmpty) {
      rows.add(_StyleEntry(
          Icons.sports_cricket_rounded, 'Batting', player.battingStyle!));
    }
    if (apiString(player.bowlingStyle).isNotEmpty) {
      rows.add(_StyleEntry(
          Icons.sports_baseball_rounded, 'Bowling', player.bowlingStyle!));
    }
    if (apiString(player.jerseyNumber).isNotEmpty) {
      rows.add(_StyleEntry(Icons.tag_rounded, 'Jersey',
          '#${apiString(player.jerseyNumber)}'));
    }
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        for (final row in rows) ...[
          _StyleRow(entry: row),
          if (row != rows.last) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _StyleEntry {
  const _StyleEntry(this.icon, this.label, this.value);
  final IconData icon;
  final String label;
  final String value;
}

class _StyleRow extends StatelessWidget {
  const _StyleRow({required this.entry});

  final _StyleEntry entry;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.card2.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border.withValues(alpha: .65)),
      ),
      child: Row(
        children: [
          Icon(entry.icon, color: c.cyan, size: 18),
          const SizedBox(width: 10),
          Text(entry.label,
              style: TextStyle(
                  color: c.muted, fontWeight: FontWeight.w800, fontSize: 12)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              entry.value,
              textAlign: TextAlign.right,
              maxLines: 2,
              softWrap: true,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: c.text, fontWeight: FontWeight.w800, fontSize: 13),
            ),
          ),
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
              Icon(icon, color: c.cyan, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(title.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: c.text,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .4,
                        fontSize: 15)),
              ),
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
      width: 124,
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
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: c.cyan, fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text('vs ${apiString(item['opponent'], '-')}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: c.text, fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          Text(apiString(item['format']),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: c.cyan, fontSize: 11, fontWeight: FontWeight.w800)),
          Text(apiString(item['date']),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: c.muted, fontSize: 10, fontWeight: FontWeight.w600)),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.workspace_premium_rounded, color: c.cyan, size: 20),
          const SizedBox(width: 10),
          Expanded(
              child: Text(apiString(item['title'] ?? item['name']),
                  softWrap: true,
                  style:
                      TextStyle(color: c.text, fontWeight: FontWeight.w800))),
          const SizedBox(width: 8),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 110,
              child: Text(row.label,
                  style:
                      TextStyle(color: c.muted, fontWeight: FontWeight.w700))),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              row.value,
              textAlign: TextAlign.right,
              softWrap: true,
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline_rounded, color: c.cyan, size: 20),
        const SizedBox(width: 10),
        Expanded(
            child: Text(text,
                softWrap: true,
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
          Icon(icon, color: c.cyan, size: 14),
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
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: c.text, fontSize: 24, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text('${player.team.name} - ${player.role}',
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: c.cyan, fontWeight: FontWeight.w700)),
          if (player.subtitle != null) ...[
            const SizedBox(height: 6),
            Text(player.subtitle!,
                textAlign: TextAlign.center,
                style: TextStyle(color: c.muted)),
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
          height: 280,
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.person_outline_rounded, color: c.cyan, size: 28),
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
                    softWrap: true,
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
