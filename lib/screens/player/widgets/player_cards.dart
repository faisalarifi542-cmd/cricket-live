part of '../player_detail_screen.dart';

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
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
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
