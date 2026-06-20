part of '../player_detail_screen.dart';

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
      child: () {
        // Gate the profile photo by the global player-image mode.
        final image = resolvePlayerImageUrl(player.image);
        return image == null
            ? _Initial(player.name, size: size * .32)
            : CachedNetworkImage(
                imageUrl: image,
                fit: BoxFit.cover,
                fadeInDuration: Duration.zero,
                placeholder: (context, _) =>
                    _Initial(player.name, size: size * .32),
                errorWidget: (_, __, ___) =>
                    _Initial(player.name, size: size * .32),
              );
      }(),
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

