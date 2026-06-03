import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'package:cricpro_flutter/app_theme.dart';
import 'package:cricpro_flutter/api_models.dart';
import 'package:cricpro_flutter/components.dart';
import 'package:cricpro_flutter/screens/player/player_detail_screen.dart';

/// Premium role-grouped squad display.
/// Accepts a flat list of raw player maps from the API and groups them
/// into Top Order / Middle Order / All-rounders / Bowlers / Reserve.
class PremiumSquad extends StatelessWidget {
  const PremiumSquad({
    super.key,
    required this.playingXi,
    required this.bench,
    this.title,
  });

  final List<dynamic> playingXi;
  final List<dynamic> bench;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final groups = _groupByRole(playingXi);
    final hasAny =
        groups.values.any((list) => list.isNotEmpty) || bench.isNotEmpty;
    if (!hasAny) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: c.border),
        ),
        child: Row(children: [
          Icon(Icons.groups_rounded, color: c.cyan),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Squad players are not available yet.',
              style: TextStyle(color: c.muted, fontWeight: FontWeight.w700),
            ),
          ),
        ]),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 4),
            child: Text(title!.toUpperCase(),
                style: TextStyle(
                    color: c.text,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    letterSpacing: .5)),
          ),
        ],
        for (final group in _kRoleOrder)
          if (groups[group]!.isNotEmpty) ...[
            _SquadSection(title: group, players: groups[group]!),
            const SizedBox(height: 12),
          ],
        if (bench.isNotEmpty)
          _ReservePlayersCard(reserve: bench),
      ],
    );
  }
}

class _SquadSection extends StatelessWidget {
  const _SquadSection({required this.title, required this.players});

  final String title;
  final List<Map<String, dynamic>> players;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 6,
              height: 18,
              decoration: BoxDecoration(
                color: c.cyan,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(title.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: c.text,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      letterSpacing: .5)),
            ),
            Text(players.length.toString().padLeft(2, '0'),
                style: TextStyle(
                    color: c.cyan,
                    fontWeight: FontWeight.w900,
                    fontSize: 12)),
          ]),
          const SizedBox(height: 10),
          for (var i = 0; i < players.length; i++) ...[
            PremiumPlayerCard(row: players[i]),
            if (i != players.length - 1) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _ReservePlayersCard extends StatelessWidget {
  const _ReservePlayersCard({required this.reserve});

  final List<dynamic> reserve;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final players = reserve.map(apiMap).where((m) => m.isNotEmpty).toList();
    if (players.isEmpty) return const SizedBox.shrink();
    return PremiumCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 6,
              height: 18,
              decoration: BoxDecoration(
                color: c.warning,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text('RESERVE PLAYERS',
                  style: TextStyle(
                      color: c.text,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      letterSpacing: .5)),
            ),
            Text(players.length.toString().padLeft(2, '0'),
                style: TextStyle(
                    color: c.warning,
                    fontWeight: FontWeight.w900,
                    fontSize: 12)),
          ]),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final row in players) _ReserveChip(row: row),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReserveChip extends StatelessWidget {
  const _ReserveChip({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final id = apiString(row['playerId'] ?? row['player_id'] ?? row['id']);
    final name =
        apiString(row['name'] ?? row['playerName'] ?? row['player_name'],
            'Player');
    final image = resolveCricbuzzImageUrl(row);
    return InkWell(
      onTap: id.isEmpty
          ? null
          : () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => PlayerDetailScreen(playerId: id))),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: c.card2.withValues(alpha: .55),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: c.warning.withValues(alpha: .35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 13,
              backgroundColor: c.card,
              backgroundImage: image == null
                  ? null
                  : NetworkImage(
                      image,
                      webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
                    ),
              child: image == null
                  ? Text(_initial(name),
                      style: TextStyle(
                          color: c.muted,
                          fontWeight: FontWeight.w900,
                          fontSize: 11))
                  : null,
            ),
            const SizedBox(width: 8),
            Text(name,
                style: TextStyle(
                    color: c.text,
                    fontWeight: FontWeight.w800,
                    fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class PremiumPlayerCard extends StatelessWidget {
  const PremiumPlayerCard({super.key, required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final id = apiString(row['playerId'] ?? row['player_id'] ?? row['id']);
    final name =
        apiString(row['name'] ?? row['playerName'] ?? row['player_name'],
            'Player');
    final role = apiString(row['role'] ?? row['playerRole']);
    final image = resolveCricbuzzImageUrl(row);
    final isCaptain = _truthy(row['isCaptain']) ||
        _truthy(row['is_captain']) ||
        _truthy(row['captain']);
    final isViceCaptain =
        _truthy(row['isViceCaptain']) || _truthy(row['vice_captain']);
    final isWk = _truthy(row['isWicketKeeper']) ||
        _truthy(row['is_wicketkeeper']) ||
        _truthy(row['wicketKeeper']);
    final roleBadge = _roleBadge(role, isWk);

    return InkWell(
      onTap: id.isEmpty
          ? null
          : () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => PlayerDetailScreen(playerId: id))),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: c.card2.withValues(alpha: .55),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.border.withValues(alpha: .65)),
        ),
        child: Row(
          children: [
            _PlayerAvatar(name: name, image: image),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: c.text,
                                fontWeight: FontWeight.w900,
                                fontSize: 14)),
                      ),
                      if (isCaptain) ...[
                        const SizedBox(width: 6),
                        _Badge(text: 'C', color: c.cyan),
                      ],
                      if (isViceCaptain) ...[
                        const SizedBox(width: 4),
                        _Badge(text: 'VC', color: c.cyan),
                      ],
                      if (isWk) ...[
                        const SizedBox(width: 4),
                        _Badge(text: 'WK', color: c.warning),
                      ],
                    ],
                  ),
                  if (role.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(role,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: c.muted,
                            fontWeight: FontWeight.w700,
                            fontSize: 12)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (roleBadge != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: roleBadge.color.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: roleBadge.color.withValues(alpha: .4)),
                ),
                child: Text(roleBadge.label,
                    style: TextStyle(
                        color: roleBadge.color,
                        fontWeight: FontWeight.w900,
                        fontSize: 10,
                        letterSpacing: .4)),
              ),
            if (id.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Icon(Icons.chevron_right_rounded, color: c.muted),
              ),
          ],
        ),
      ),
    );
  }
}

class _PlayerAvatar extends StatelessWidget {
  const _PlayerAvatar({required this.name, required this.image});

  final String name;
  final String? image;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      width: 44,
      height: 44,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: c.card,
        border: Border.all(color: c.cyan.withValues(alpha: .35)),
      ),
      child: image == null
          ? Center(
              child: Text(_initial(name),
                  style: TextStyle(
                      color: c.text,
                      fontWeight: FontWeight.w900,
                      fontSize: 16)),
            )
          : Image.network(image!,
              fit: BoxFit.cover,
              webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
              errorBuilder: (_, __, ___) => Center(
                  child: Text(_initial(name),
                      style: TextStyle(
                          color: c.text,
                          fontWeight: FontWeight.w900,
                          fontSize: 16)))),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .2),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: .55)),
      ),
      child: Text(text,
          style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 10,
              letterSpacing: .3)),
    );
  }
}

class _RoleBadge {
  const _RoleBadge(this.label, this.color);
  final String label;
  final Color color;
}

_RoleBadge? _roleBadge(String role, bool isWk) {
  final r = role.toLowerCase();
  if (r.isEmpty && !isWk) return null;
  if (isWk || r.contains('wicketkeeper') || r.contains('wk')) {
    return const _RoleBadge('WK', Color(0xfff59e0b));
  }
  if (r.contains('all-rounder') || r.contains('allrounder')) {
    return const _RoleBadge('AR', Color(0xff14b8a6));
  }
  if (r.contains('bowler')) {
    return const _RoleBadge('BOWL', Color(0xff60a5fa));
  }
  if (r.contains('bat')) {
    return const _RoleBadge('BAT', Color(0xff67e8f9));
  }
  return null;
}

const _kRoleOrder = [
  'Top Order',
  'Middle Order',
  'All-rounders',
  'Bowlers',
];

Map<String, List<Map<String, dynamic>>> _groupByRole(List<dynamic> raw) {
  final groups = <String, List<Map<String, dynamic>>>{
    for (final r in _kRoleOrder) r: [],
  };
  final batting = <Map<String, dynamic>>[];
  for (final entry in raw) {
    final p = apiMap(entry);
    if (p.isEmpty) continue;
    final role = apiString(p['role'] ?? p['playerRole']).toLowerCase();
    final isWk = _truthy(p['isWicketKeeper']) ||
        _truthy(p['is_wicketkeeper']) ||
        role.contains('wk') ||
        role.contains('wicketkeeper');
    if (role.contains('all-rounder') || role.contains('allrounder')) {
      groups['All-rounders']!.add(p);
    } else if (role.contains('bowler') && !role.contains('bat')) {
      groups['Bowlers']!.add(p);
    } else if (isWk || role.contains('bat') || role.isEmpty) {
      batting.add(p);
    } else {
      // Unknown role - treat as a batter so player is still visible.
      batting.add(p);
    }
  }
  // Split batting into top order (first ~6) and middle order. If batting is
  // small, all go into top order.
  if (batting.isNotEmpty) {
    final top = batting.take(6).toList();
    final middle = batting.skip(6).toList();
    groups['Top Order']!.addAll(top);
    if (middle.isNotEmpty) {
      groups['Middle Order']!.addAll(middle);
    }
  }
  if (kDebugMode) {
    debugPrint(
        'PremiumSquad groups topOrder=${groups['Top Order']!.length} middle=${groups['Middle Order']!.length} ar=${groups['All-rounders']!.length} bowl=${groups['Bowlers']!.length}');
  }
  return groups;
}

bool _truthy(dynamic value) =>
    value == true ||
    value == 1 ||
    value == '1' ||
    value.toString().toLowerCase() == 'true';

String _initial(String name) {
  final trim = name.trim();
  if (trim.isEmpty) return '?';
  return trim[0].toUpperCase();
}
