part of '../series_detail_screen.dart';

class _StatsTab extends StatelessWidget {
  const _StatsTab({required this.points, required this.stats});

  final Map<String, dynamic> points;
  final Map<String, dynamic> stats;

  @override
  Widget build(BuildContext context) {
    final pointsRows = _pointsRows(points);
    final batting = _statRows(stats, 'batting');
    final bowling = _statRows(stats, 'bowling');

    final hasAny =
        pointsRows.isNotEmpty || batting.isNotEmpty || bowling.isNotEmpty;
    if (!hasAny) {
      return const SeriesEmptyState(
        title: 'Stats not available',
        message: 'Player stats are not available for this series yet.',
        icon: Icons.bar_chart_rounded,
      );
    }

    final cards = _statCards(batting, bowling);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (pointsRows.isNotEmpty) ...[
          _PointsTableCard(rows: pointsRows),
          const SizedBox(height: 14),
        ],
        if (batting.isNotEmpty) ...[
          _StatsTableCard(
            title: 'Top Run Scorers',
            icon: Icons.sports_cricket_rounded,
            rows: batting.take(5).toList(),
            metricHeader: 'RUNS',
            isBowling: false,
          ),
          const SizedBox(height: 14),
        ],
        if (bowling.isNotEmpty) ...[
          _StatsTableCard(
            title: 'Top Wicket Takers',
            icon: Icons.sports_baseball_outlined,
            rows: bowling.take(5).toList(),
            // "WKTS" not "WICKETS" — the full word wrapped to two lines in the
            // 42px metric column.
            metricHeader: 'WKTS',
            isBowling: true,
          ),
          const SizedBox(height: 14),
        ],
        if (cards.isNotEmpty) _SeriesStatsGrid(cards: cards),
      ],
    );
  }

  List<_StatCard> _statCards(
    List<Map<String, dynamic>> batting,
    List<Map<String, dynamic>> bowling,
  ) {
    final cards = <_StatCard>[];
    if (batting.isNotEmpty) {
      final top = batting.first;
      cards.add(_StatCard(
        icon: Icons.sports_cricket_rounded,
        label: 'Most Runs',
        value: apiString(top['runs'], '0'),
        sub: _nameTeam(top),
      ));
    }
    if (bowling.isNotEmpty) {
      final top = bowling.first;
      cards.add(_StatCard(
        icon: Icons.sports_baseball_outlined,
        label: 'Most Wickets',
        value: apiString(top['wickets'], '0'),
        sub: _nameTeam(top),
      ));
    }
    final played = _maxMatches([...batting, ...bowling]);
    if (played > 0) {
      cards.add(_StatCard(
        icon: Icons.event_available_rounded,
        label: 'Matches Played',
        value: '$played',
        sub: 'In this series',
      ));
    }
    if (batting.isNotEmpty) {
      final best = batting.reduce((a, b) =>
          (apiDouble(a['average']) ?? 0) >= (apiDouble(b['average']) ?? 0)
              ? a
              : b);
      final avg = apiDouble(best['average']);
      if (avg != null && avg > 0) {
        cards.add(_StatCard(
          icon: Icons.trending_up_rounded,
          label: 'Best Batting Avg',
          value: avg.toStringAsFixed(2),
          sub: _nameTeam(best),
        ));
      }
    }
    return cards;
  }

  String _nameTeam(Map<String, dynamic> row) {
    final name = apiString(row['playerName'] ?? row['name'], 'Player');
    final team = apiString(row['team']);
    return team.isEmpty ? name : '$name ($team)';
  }

  int _maxMatches(List<Map<String, dynamic>> rows) {
    var max = 0;
    for (final r in rows) {
      final m = apiInt(r['matches']) ?? 0;
      if (m > max) max = m;
    }
    return max;
  }

  List<Map<String, dynamic>> _pointsRows(Map<String, dynamic> value) {
    final root = value['data'] is Map ? apiMap(value['data']) : value;
    final groups = apiList(root['groups'] ?? root['pointsTable']);
    final rows = <dynamic>[];
    for (final g in groups) {
      final m = apiMap(g);
      rows.addAll(apiList(m['rows'] ?? m['teams'] ?? m['pointsTableInfo']));
    }
    if (rows.isEmpty) rows.addAll(apiList(root['rows']));
    final parsed = rows.map(apiMap).where((m) => m.isNotEmpty).toList();
    // Sort canonically: points desc → NRR desc → wins desc → team name asc.
    // A provider's official `rank`/`position` is honoured ONLY as the final
    // tiebreaker (and only when it's a positive integer), so the displayed
    // order is never wrong when points/NRR/wins actually differ but still
    // respects an official ordering for a true dead heat. This is what stops
    // two equal-points teams from appearing in arbitrary payload order.
    parsed.sort(_comparePointsRow);
    return parsed;
  }

  List<Map<String, dynamic>> _statRows(Map<String, dynamic> value, String key) {
    final root = value['data'] is Map ? apiMap(value['data']) : value;
    final section = apiMap(root[key]);
    final rows =
        apiList(section['rows'] ?? section['players'] ?? section['items']);
    return rows.map(apiMap).where((m) => m.isNotEmpty).toList();
  }
}

/// Canonical points-table comparator: points desc → NRR desc → wins desc →
/// team name asc, with a provider `rank`/`position` as the final tiebreaker for
/// a true dead heat. NRR is parsed as a (possibly signed) decimal string.
int _comparePointsRow(Map<String, dynamic> a, Map<String, dynamic> b) {
  int cmp = _pointsSortValue(b).compareTo(_pointsSortValue(a));
  if (cmp != 0) return cmp;
  cmp = _nrrSortValue(b).compareTo(_nrrSortValue(a));
  if (cmp != 0) return cmp;
  cmp = _winsSortValue(b).compareTo(_winsSortValue(a));
  if (cmp != 0) return cmp;
  final nameA = _pointsTeamName(a).toLowerCase();
  final nameB = _pointsTeamName(b).toLowerCase();
  cmp = nameA.compareTo(nameB);
  if (cmp != 0) return cmp;
  // Final tiebreaker: a provider-supplied official rank/position, only when it
  // is a positive integer. Falls back to stable input order otherwise.
  final posA = _officialPosition(a);
  final posB = _officialPosition(b);
  if (posA != null && posB != null) return posA.compareTo(posB);
  return 0;
}

int _pointsSortValue(Map<String, dynamic> r) =>
    apiInt(r['points']) ?? apiInt(r['pts']) ?? apiInt(r['point']) ?? 0;

int _winsSortValue(Map<String, dynamic> r) =>
    apiInt(r['won']) ?? apiInt(r['wins']) ?? apiInt(r['w']) ?? 0;

double _nrrSortValue(Map<String, dynamic> r) {
  final raw = r['nrr'] ?? r['netRunRate'] ?? r['net_run_rate'] ?? r['nrrValue'];
  final n = num.tryParse('${raw ?? ''}');
  return n?.toDouble() ?? 0.0;
}

String _pointsTeamName(Map<String, dynamic> r) =>
    apiString(r['teamName'] ?? r['team_name'] ?? r['teamShort'] ?? r['team'], 'Team');

int? _officialPosition(Map<String, dynamic> r) {
  final p = apiInt(r['rank']) ?? apiInt(r['position']);
  return (p != null && p > 0) ? p : null;
}

class _PointsTableCard extends StatelessWidget {
  const _PointsTableCard({required this.rows});

  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumSectionPanel(
      title: 'Points Table',
      icon: Icons.table_chart_outlined,
      bgAsset: SAsset.statsTableBg,
      bgRemoteKey: 'series_stats_table_bg',
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                const SizedBox(width: 22),
                Expanded(child: Text('TEAM', style: _hStyle(c))),
                for (final h in const ['P', 'W', 'L', 'Pts', 'NRR'])
                  SizedBox(
                      width: h == 'NRR' ? 44 : 28,
                      child: Text(h,
                          textAlign: TextAlign.center, style: _hStyle(c))),
              ],
            ),
          ),
          for (var i = 0; i < rows.length; i++)
            _PointsRow(rank: i + 1, row: rows[i]),
        ],
      ),
    );
  }

  TextStyle _hStyle(CricColors c) =>
      TextStyle(color: c.muted, fontWeight: FontWeight.w900, fontSize: 10.5);
}

class _PointsRow extends StatelessWidget {
  const _PointsRow({required this.rank, required this.row});

  final int rank;
  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final name = apiString(
        row['teamName'] ?? row['team_name'] ?? row['teamShort'] ?? row['team'],
        'Team');
    final short = apiString(
        row['teamShort'] ?? row['teamShortName'] ?? row['team_short'], name);
    final logo = apiString(row['logoUrl'] ?? row['logo_url']);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.cyan.withValues(alpha: .14))),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text('$rank',
                style: TextStyle(
                    color: c.muted, fontWeight: FontWeight.w900, fontSize: 12)),
          ),
          TeamLogoWidget(
            logoUrl: logo.isEmpty ? null : logo,
            teamName: name,
            abbreviation: short,
            color: c.cyan,
            size: TeamLogoWidget.miniSize,
            // Points-table row: the team code follows as text in the same row.
            excludeSemantics: true,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              // teamCodeOf maps a known nation + variant suffix even when the
              // `short` field is empty and we fall back to the full name — so
              // "Sri Lanka A" resolves to "SL A", not the un-mapped "SRI LANKA
              // A" that formatTeamCode would produce.
              teamCodeOf(short, name),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: c.text, fontWeight: FontWeight.w800, fontSize: 12.5),
            ),
          ),
          _val(c, row['played'] ?? row['matches'], 28),
          _val(c, row['won'], 28),
          _val(c, row['lost'], 28),
          _val(c, row['points'], 28, bold: true, color: c.cyan),
          _val(c, row['nrr'], 44),
        ],
      ),
    );
  }

  Widget _val(CricColors c, dynamic value, double width,
      {bool bold = false, Color? color}) {
    return SizedBox(
      width: width,
      child: Text(
        apiString(value, '-'),
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color ?? c.text,
          fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
          fontSize: 11.5,
        ),
      ),
    );
  }
}

/// Premium stats table (Top Run Scorers / Top Wicket Takers).
class _StatsTableCard extends StatelessWidget {
  const _StatsTableCard({
    required this.title,
    required this.icon,
    required this.rows,
    required this.metricHeader,
    required this.isBowling,
  });

  final String title;
  final IconData icon;
  final List<Map<String, dynamic>> rows;
  final String metricHeader;
  final bool isBowling;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final showMatches = context.w > 360;
    return PremiumSectionPanel(
      title: title,
      icon: icon,
      bgAsset: SAsset.statsTableBg,
      bgRemoteKey: 'series_stats_table_bg',
      trailing: const PremiumViewAll(label: 'View All'),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                SizedBox(width: 20, child: Text('#', style: _h(c))),
                const SizedBox(width: 36),
                Expanded(child: Text('PLAYER', style: _h(c))),
                SizedBox(
                    width: 34,
                    child: Text('TEAM',
                        style: _h(c), textAlign: TextAlign.center)),
                if (showMatches)
                  SizedBox(
                      width: 34,
                      child: Text('MAT',
                          style: _h(c), textAlign: TextAlign.center)),
                SizedBox(
                    width: 42,
                    child: Text(metricHeader,
                        style: _h(c), textAlign: TextAlign.right)),
                SizedBox(
                    width: 44,
                    child:
                        Text('AVG', style: _h(c), textAlign: TextAlign.right)),
              ],
            ),
          ),
          for (var i = 0; i < rows.length; i++)
            _StatRow(
              rank: i + 1,
              row: rows[i],
              isBowling: isBowling,
              showMatches: showMatches,
            ),
        ],
      ),
    );
  }

  TextStyle _h(CricColors c) => TextStyle(
        color: c.muted,
        fontWeight: FontWeight.w800,
        fontSize: 9.5,
        letterSpacing: .3,
      );
}

class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.rank,
    required this.row,
    required this.isBowling,
    required this.showMatches,
  });

  final int rank;
  final Map<String, dynamic> row;
  final bool isBowling;
  final bool showMatches;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final name = apiString(row['playerName'] ?? row['name'], 'Player');
    final team = apiString(row['team']);
    final image = PlayerImageResolver.resolveServerImage(
        _verifiedSquadImage(row),
        playerName: name);
    final matches = apiString(row['matches'], '-');
    final metric = isBowling
        ? apiString(row['wickets'], '0')
        : apiString(row['runs'], '0');
    final avg = apiDouble(row['average']);
    final avgText = avg != null && avg > 0 ? avg.toStringAsFixed(2) : '-';
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.cyan.withValues(alpha: .12))),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            child: Text(
              '$rank',
              style: TextStyle(
                  color: c.muted, fontWeight: FontWeight.w900, fontSize: 12),
            ),
          ),
          SeriesPlayerAvatar(name: name, imageUrl: image, size: 30),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              compactPlayerName(name, maxLen: 16),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: c.text, fontWeight: FontWeight.w800, fontSize: 12.5),
            ),
          ),
          SizedBox(
            width: 34,
            child: Text(
              formatTeamCode(team),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: c.muted, fontWeight: FontWeight.w700, fontSize: 11),
            ),
          ),
          if (showMatches)
            SizedBox(
              width: 34,
              child: Text(
                matches,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: c.onImageText,
                    fontWeight: FontWeight.w700,
                    fontSize: 12),
              ),
            ),
          SizedBox(
            width: 42,
            child: Text(
              metric,
              textAlign: TextAlign.right,
              style: TextStyle(
                  color: c.cyan, fontWeight: FontWeight.w900, fontSize: 14),
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              avgText,
              textAlign: TextAlign.right,
              style: TextStyle(
                  color: c.text, fontWeight: FontWeight.w700, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.sub,
  });
  final IconData icon;
  final String label;
  final String value;
  final String sub;
}

class _SeriesStatsGrid extends StatelessWidget {
  const _SeriesStatsGrid({required this.cards});

  final List<_StatCard> cards;

  @override
  Widget build(BuildContext context) {
    return PremiumSectionPanel(
      title: 'Series Stats',
      icon: Icons.bar_chart_rounded,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const spacing = 10.0;
          final width = (constraints.maxWidth - spacing) / 2;
          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: [
              for (final card in cards)
                SizedBox(width: width, child: _StatGridTile(card: card)),
            ],
          );
        },
      ),
    );
  }
}

class _StatGridTile extends StatelessWidget {
  const _StatGridTile({required this.card});

  final _StatCard card;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: c.isDark ? c.card.withValues(alpha: .5) : c.card,
        border: Border.all(color: c.cyan.withValues(alpha: .3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(card.icon, color: c.cyan, size: 13),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  card.label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.cyan,
                    fontWeight: FontWeight.w800,
                    fontSize: 9.5,
                    letterSpacing: .3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            card.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: c.text,
              fontWeight: FontWeight.w900,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            card.sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: c.muted,
              fontWeight: FontWeight.w600,
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Squad data models + parsers
// ---------------------------------------------------------------------------

/// A named format group (e.g. Test, ODI) holding the teams that have an
/// announced squad for that format.
class SquadFormat {
  const SquadFormat({required this.format, required this.teams});

  final String format;
  final List<SquadTeam> teams;
}

class SquadTeam {
  const SquadTeam({
    required this.name,
    required this.shortName,
    this.id = '',
    this.logoUrl,
    this.players = const [],
  });

  final String name;
  final String shortName;

  /// Stable team identity (Cricbuzz team id or short name). Used to build
  /// unique per-team player widget keys so Team B never reuses Team A images.
  final String id;
  final String? logoUrl;
  final List<SquadPlayer> players;

  /// Key used to namespace this team's player widgets. Prefers the team id,
  /// falling back to the normalized short name / name.
  String get identityKey {
    if (id.trim().isNotEmpty) return id.trim();
    if (shortName.trim().isNotEmpty) return shortName.trim().toLowerCase();
    return name.trim().toLowerCase();
  }
}

/// Normalizes a player name for use in a fallback widget key.
String _normalizedPlayerKey(String name) =>
    name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');

class SquadPlayer {
  const SquadPlayer({
    required this.id,
    required this.name,
    required this.role,
    this.imageUrl,
    this.isCaptain = false,
    this.isViceCaptain = false,
    this.isWicketKeeper = false,
    this.isSubstitute = false,
    this.category = '',
    this.roleCode = '',
  });

  final String id;
  final String name;
  final String role;
  final String? imageUrl;
  final bool isCaptain;
  final bool isViceCaptain;
  final bool isWicketKeeper;
  final bool isSubstitute;

  /// Backend-provided category bucket: batters / wicketkeepers / allRounders /
  /// bowlers. Empty when the backend does not classify (legacy payloads).
  final String category;

  /// Compact role pill text: BAT / WK / AR / BOWL. Empty when unknown.
  final String roleCode;
}

/// Parses the `/series/:id/squads` payload into format groups
/// (`formats[].teams[].players[]`). Falls back to a single unnamed format
/// built from the flat `teams[]` when the backend does not provide formats.
List<SquadFormat> _parseSquadFormats(Map<String, dynamic> data) {
  final root = data['data'] is Map ? apiMap(data['data']) : data;
  final rawFormats = apiList(root['formats']);
  final formats = <SquadFormat>[];
  for (final rawF in rawFormats) {
    final f = apiMap(rawF);
    final teams = _teamsFromRawList(apiList(f['teams']));
    if (teams.isEmpty) continue;
    formats.add(SquadFormat(
      format: apiString(f['format'] ?? f['squadType']),
      teams: teams,
    ));
  }
  if (formats.isNotEmpty) return formats;

  // Legacy / fallback: a single group from the flat teams[].
  final teams = _parseSquadTeams(data);
  if (teams.isEmpty) return const [];
  return [SquadFormat(format: '', teams: teams)];
}

List<SquadTeam> _teamsFromRawList(List<dynamic> rawTeams) {
  final teams = <SquadTeam>[];
  for (final raw in rawTeams) {
    final t = apiMap(raw);
    final players = apiList(t['players'])
        .map(_parseSquadPlayer)
        .where((p) => !_isSupportStaffPlayer(p))
        .toList();
    if (players.isEmpty) continue;
    final teamName = apiString(t['teamName'] ?? t['team_name'], 'Team');
    final teamShort =
        apiString(t['teamShortName'] ?? t['teamShort'] ?? t['team_short']);
    teams.add(SquadTeam(
      id: apiString(t['squadId'] ?? t['teamId'] ?? t['team_id'] ?? t['id'],
          teamShort.isNotEmpty ? teamShort : teamName),
      name: teamName,
      shortName: teamShort,
      logoUrl: apiString(t['logoUrl'] ?? t['logo_url']).isEmpty
          ? null
          : apiString(t['logoUrl'] ?? t['logo_url']),
      players: players,
    ));
  }
  return teams;
}

/// Parses the `/series/:id/squads` payload (teams[].players[]).
List<SquadTeam> _parseSquadTeams(Map<String, dynamic> data) {
  final root = data['data'] is Map ? apiMap(data['data']) : data;
  final rawTeams = apiList(root['teams']);
  final teams = <SquadTeam>[];
  for (final raw in rawTeams) {
    final t = apiMap(raw);
    final players = apiList(t['players'])
        .map(_parseSquadPlayer)
        .where((p) => !_isSupportStaffPlayer(p))
        .toList();
    if (players.isEmpty) continue;
    final teamName = apiString(t['teamName'] ?? t['team_name'], 'Team');
    final teamShort =
        apiString(t['teamShortName'] ?? t['teamShort'] ?? t['team_short']);
    teams.add(SquadTeam(
      id: apiString(t['teamId'] ?? t['team_id'] ?? t['id'],
          teamShort.isNotEmpty ? teamShort : teamName),
      name: teamName,
      shortName: teamShort,
      logoUrl: apiString(t['logoUrl'] ?? t['logo_url']).isEmpty
          ? null
          : apiString(t['logoUrl'] ?? t['logo_url']),
      players: players,
    ));
  }
  return teams;
}

SquadPlayer _parseSquadPlayer(dynamic raw) {
  final p = apiMap(raw);
  final id = apiString(p['playerId'] ?? p['player_id'] ?? p['id']);
  // Only trust a real Cricbuzz face image from the backend; a missing image
  // stays null so the card renders a neutral initials avatar (never a wrong
  // face synthesised from the player id).
  final image = _verifiedSquadImage(p);
  return SquadPlayer(
    id: id,
    name: apiString(p['name'] ?? p['playerName'] ?? p['player_name'], 'Player'),
    role: apiString(p['role'] ?? p['playerRole']),
    // Gate the server image through the global player-image mode so admin_only /
    // initials_only never show a provider photo.
    imageUrl: PlayerImageResolver.resolveServerImage(image,
        playerName: apiString(p['name'] ?? p['playerName'] ?? p['player_name'])),
    isCaptain: apiBool(p['isCaptain'] ?? p['is_captain']),
    isViceCaptain: apiBool(p['isViceCaptain'] ?? p['is_vice_captain']),
    isWicketKeeper: apiBool(p['isWicketKeeper'] ?? p['is_wicketkeeper']),
    isSubstitute: apiBool(p['isSubstitute'] ?? p['is_substitute']),
    category: apiString(p['category']),
    roleCode: apiString(p['roleCode']),
  );
}

bool _isSupportStaffPlayer(SquadPlayer player) {
  final text = '${player.name} ${player.role}'.toLowerCase();
  return RegExp(
    r'\b(head coach|assistant coach|batting coach|bowling coach|fielding coach|support staff|team manager|manager|physio|analyst|selector|mentor|coach)\b',
  ).hasMatch(text);
}

String? _verifiedSquadImage(Map<String, dynamic> p) {
  final image = apiString(p['imageUrl'] ??
      p['image_url'] ??
      p['faceImageUrl'] ??
      p['face_image_url']);
  if (image.isEmpty) return null;
  final source = apiString(p['imageSource'] ?? p['image_source']).toLowerCase();
  final profile = apiString(p['profileUrl'] ?? p['profile_url']);
  final playerId = apiString(p['playerId'] ?? p['player_id'] ?? p['id']);
  final trustedHost = image.contains('static.cricbuzz.com') ||
      image.contains('cricbuzz.com/a/img/');
  final hasIdentity = playerId.isNotEmpty || profile.contains('/profiles/');
  if (trustedHost && (source == 'cricbuzz' || source.isEmpty) && hasIdentity) {
    return image;
  }
  if (kDebugMode) {
    debugPrint('[SquadImage] rejected unverified image player='
        '${apiString(p['name'] ?? p['playerName'] ?? p['player_name'])} '
        'id=$playerId source=$source image=$image');
  }
  return null;
}

/// Parses the match-squads payload (team1/team2 with playing_xi + bench) into
/// the same SquadTeam shape, used as a fallback source.
List<SquadTeam> _parseMatchSquadTeams(
    Map<String, dynamic> data, CricketMatch match) {
  final root = data['data'] is Map ? apiMap(data['data']) : data;
  final teams = <SquadTeam>[];

  SquadTeam? buildTeam(dynamic rawTeam, String fallbackName,
      String fallbackShort, String? fallbackLogo) {
    final t = apiMap(rawTeam);
    if (t.isEmpty) return null;
    final players = <SquadPlayer>[];
    for (final key in const ['playing_xi', 'playingXI', 'playingXi']) {
      for (final raw in apiList(t[key])) {
        final player = _parseSquadPlayer(raw);
        if (!_isSupportStaffPlayer(player)) players.add(player);
      }
      if (players.isNotEmpty) break;
    }
    for (final raw in apiList(t['bench'] ?? t['substitutes'])) {
      final p = _parseSquadPlayer(raw);
      if (_isSupportStaffPlayer(p)) continue;
      players.add(SquadPlayer(
        id: p.id,
        name: p.name,
        role: p.role,
        imageUrl: p.imageUrl,
        isCaptain: p.isCaptain,
        isWicketKeeper: p.isWicketKeeper,
        isSubstitute: true,
      ));
    }
    if (players.isEmpty) return null;
    final teamName = apiString(t['team_name'] ?? t['teamName'], fallbackName);
    final teamShort =
        apiString(t['team_short'] ?? t['teamShort'], fallbackShort);
    return SquadTeam(
      id: apiString(t['teamId'] ?? t['team_id'] ?? t['id'],
          teamShort.isNotEmpty ? teamShort : teamName),
      name: teamName,
      shortName: teamShort,
      logoUrl: apiString(t['logoUrl'] ?? t['logo_url']).isEmpty
          ? fallbackLogo
          : apiString(t['logoUrl'] ?? t['logo_url']),
      players: players,
    );
  }

  final t1 =
      buildTeam(root['team1'], match.teamA, match.teamAShort, match.teamALogo);
  final t2 =
      buildTeam(root['team2'], match.teamB, match.teamBShort, match.teamBLogo);
  if (t1 != null) teams.add(t1);
  if (t2 != null) teams.add(t2);
  return teams;
}

// ---------------------------------------------------------------------------
// Small shared helpers
// ---------------------------------------------------------------------------

String _dateOnlyYear(DateTime d) {
  const m = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];
  return '${m[d.month - 1]} ${d.day}, ${d.year}';
}

String _countdown(DateTime? start) {
  if (start == null) return 'TBC';
  final now = DateTime.now();
  final diff = start.difference(now);
  if (diff.isNegative) return 'Soon';
  if (diff.inDays >= 1) {
    return 'In ${diff.inDays} Day${diff.inDays > 1 ? 's' : ''}';
  }
  if (diff.inHours >= 1) return 'In ${diff.inHours}h';
  if (diff.inMinutes >= 1) return 'In ${diff.inMinutes}m';
  return 'Soon';
}
