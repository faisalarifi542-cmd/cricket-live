part of '../match_details_screen.dart';

/// One commentary row (a real delivery or a non-ball note).
///
/// Expansion state is deliberately NOT held here. The rows are built lazily by a
/// `SliverList.builder`, so a row's `State` is destroyed as soon as it scrolls
/// out of the viewport — local state would silently collapse. `_CommentaryPanel`
/// owns it instead, keyed by the item's canonical identity, so an expanded row
/// survives scrolling AND stays attached to its own delivery when a poll
/// prepends newer balls.
class _CommentaryTimelineItem extends StatelessWidget {
  const _CommentaryTimelineItem({
    super.key,
    required this.row,
    required this.isFirst,
    required this.isLast,
    required this.expanded,
    required this.onToggleExpanded,
  });

  final Map<String, dynamic> row;
  final bool isFirst;
  final bool isLast;
  final bool expanded;
  final VoidCallback onToggleExpanded;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;

    // Trust the server-normalized feed. Never re-guess event types here.
    final isBall = truthy(row['isBall']) || truthy(row['is_ball']);
    final type = str(row['type']).toLowerCase();
    final label = str(row['label'],
        fallback: isBall ? 'BALL' : 'COMMENTARY');
    final text = str(row['text'] ?? row['commentary']);
    final scoreLine = str(row['score']);
    final over = str(row['over']);
    final team = str(row['teamShort'] ?? row['team']);
    final isWicket = truthy(row['isWicket']) || type == 'wicket';

    return isBall
        ? _buildBall(context, c, type, label, text, scoreLine, over, team,
            isWicket)
        : _buildNote(context, c, label, text);
  }

  // ---- Real delivery -------------------------------------------------------
  Widget _buildBall(
    BuildContext context,
    dynamic c,
    String type,
    String label,
    String text,
    String scoreLine,
    String over,
    String team,
    bool isWicket,
  ) {
    final runs = str(row['runs'], fallback: '0');
    final Color tone = switch (type) {
      'wicket' => const Color(0xffb05cff),
      'six' => const Color(0xff38f28b),
      'four' => c.cyan,
      'extra' => c.warning,
      'dot' => c.muted,
      _ => c.cyan,
    };
    final ballLabel = switch (type) {
      'wicket' => 'W',
      'six' => '6',
      'four' => '4',
      'dot' => '0',
      'extra' => (label.isNotEmpty ? label[0] : '+'),
      _ => runs,
    };

    // On a 360px phone the fixed left gutter (over column + rail + gap) used to
    // eat ~94px, leaving the commentary card cramped. Slim it on compact so the
    // text card gets ~16px more width.
    final compact = context.isCompact;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: compact ? 32 : 40,
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Column(
                children: [
                  Text(over.isEmpty ? '--' : over,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.visible,
                      softWrap: false,
                      style: TextStyle(
                          color: c.cyan,
                          fontWeight: FontWeight.w900,
                          fontSize: compact ? 11.5 : 12.5)),
                  if (team.isNotEmpty)
                    Text(team.toUpperCase(),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: c.muted,
                            fontWeight: FontWeight.w700,
                            fontSize: 9)),
                ],
              ),
            ),
          ),
          _TimelineRail(
            isFirst: isFirst,
            isLast: isLast,
            width: compact ? 42 : 46,
            child: MDBallChip(
              label: ballLabel,
              type: type,
              wicket: type == 'wicket',
              boundary: type == 'four' || type == 'six',
              size: switch (type) {
                'wicket' => compact ? 40 : 44,
                'six' || 'four' => compact ? 38 : 42,
                'dot' => compact ? 34 : 38,
                _ => compact ? 36 : 40,
              },
            ),
          ),
          SizedBox(width: compact ? 6 : 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: MDGlassPanel(
                padding: const EdgeInsets.all(11),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _EventBadge(label: label, color: tone),
                        const Spacer(),
                        if (text.isNotEmpty)
                          _ExpandChevron(
                            expanded: expanded,
                            onTap: onToggleExpanded,
                          ),
                      ],
                    ),
                    if (text.isNotEmpty) ...[
                      const SizedBox(height: 7),
                      Text(text,
                          maxLines: expanded ? null : 3,
                          overflow: expanded
                              ? TextOverflow.visible
                              : TextOverflow.ellipsis,
                          style: TextStyle(
                              color: c.isDark
                                  ? Colors.white.withValues(alpha: .9)
                                  : c.text,
                              height: 1.35,
                              fontWeight: FontWeight.w600,
                              fontSize: 13)),
                    ],
                    if (_isValidCommentaryScore(scoreLine)) ...[
                      const SizedBox(height: 6),
                      Text(
                          team.isEmpty
                              ? scoreLine.trim()
                              : '${formatTeamCode(team)} ${scoreLine.trim()}',
                          style: TextStyle(
                              color: c.cyan,
                              fontWeight: FontWeight.w700,
                              fontSize: 11.5)),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---- Non-ball note (presentation / update / pre-match) -------------------
  Widget _buildNote(
      BuildContext context, dynamic c, String label, String text) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // No fake over/team for notes — just a clean spacer.
          const SizedBox(width: 40),
          _TimelineRail(
            isFirst: isFirst,
            isLast: isLast,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c.isDark ? const Color(0xff0a1f33) : c.card,
                border: Border.all(
                    color: c.muted.withValues(alpha: .75), width: 2),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: c.isDark ? c.card2.withValues(alpha: .4) : c.card2,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: c.border.withValues(alpha: .6)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _EventBadge(label: label, color: c.muted, subtle: true),
                        const Spacer(),
                        if (text.isNotEmpty)
                          _ExpandChevron(
                            expanded: expanded,
                            onTap: onToggleExpanded,
                          ),
                      ],
                    ),
                    if (text.isNotEmpty) ...[
                      const SizedBox(height: 7),
                      Text(text,
                          maxLines: expanded ? null : 3,
                          overflow: expanded
                              ? TextOverflow.visible
                              : TextOverflow.ellipsis,
                          style: TextStyle(
                              color: c.onImageText,
                              height: 1.35,
                              fontWeight: FontWeight.w500,
                              fontSize: 12.5)),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Vertical cyan rail with a centered marker, shared by ball + note rows.
class _TimelineRail extends StatelessWidget {
  const _TimelineRail({
    required this.child,
    required this.isFirst,
    required this.isLast,
    this.width = 46,
  });

  final Widget child;
  final bool isFirst;
  final bool isLast;
  final double width;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return SizedBox(
      width: width,
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          Positioned.fill(
            child: Center(
              child: Padding(
                padding: EdgeInsets.only(
                  top: isFirst ? 18 : 0,
                  bottom: isLast ? 18 : 0,
                ),
                child:
                    Container(width: 2, color: c.cyan.withValues(alpha: .28)),
              ),
            ),
          ),
          Padding(padding: const EdgeInsets.only(top: 2), child: child),
        ],
      ),
    );
  }
}

class _ExpandChevron extends StatelessWidget {
  const _ExpandChevron({required this.expanded, required this.onTap});

  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Icon(
        expanded
            ? Icons.keyboard_arrow_up_rounded
            : Icons.keyboard_arrow_down_rounded,
        color: c.muted,
        size: 18,
      ),
    );
  }
}



class _OverCard extends StatelessWidget {
  const _OverCard({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final balls = apiList(row['balls']);
    final overNumber = str(row['overNumber'] ?? row['over']);
    final normalizedOver = normalizeOversText(overNumber);

    return PremiumCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                  'Over ${normalizedOver.isEmpty ? overNumber : normalizedOver}',
                  style: TextStyle(color: c.text, fontWeight: FontWeight.w900)),
              const Spacer(),
              Text('${str(row['runs'], fallback: '0')} runs',
                  style: TextStyle(color: c.cyan, fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
              '${str(row['bowlerName'] ?? row['bowler'])} | ${str(row['scoreAfter'])}',
              style: TextStyle(color: c.muted, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final ball in balls)
                _BallBubble(
                    label: str(apiMap(ball)['result']),
                    type: str(apiMap(ball)['type'] ?? apiMap(ball)['event']),
                    wicket: truthy(apiMap(ball)['isWicket']),
                    boundary: truthy(apiMap(ball)['isBoundary']))
            ],
          ),
        ],
      ),
    );
  }
}

class _BallBubble extends StatelessWidget {
  const _BallBubble(
      {required this.label, this.type = '', this.wicket = false, this.boundary = false});

  final String label;
  final String type;
  final bool wicket;
  final bool boundary;

  @override
  Widget build(BuildContext context) {
    return MDBallChip(label: label, type: type, wicket: wicket, boundary: boundary);
  }
}

class _EventBadge extends StatelessWidget {
  const _EventBadge(
      {required this.label, required this.color, this.subtle = false});

  final String label;
  final Color color;
  final bool subtle;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
            color: color.withValues(alpha: subtle ? 0.10 : 0.14),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
                color: color.withValues(alpha: subtle ? 0.3 : 0.35))),
        child: Text(label,
            style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: 10.5,
                letterSpacing: .3)),
      );
}

class _InlineEmpty extends StatelessWidget {
  const _InlineEmpty({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Text(text,
      style: TextStyle(color: context.cric.muted, fontWeight: FontWeight.w700));
}

Widget _playerCell(
    BuildContext context, Map<String, dynamic> row, String label) {
  final id = str(row['playerId'] ?? row['player_id']);
  final safeLabel = label.isEmpty ? 'Player' : label;
  final style = TextStyle(
    color: context.cric.cyan,
    fontWeight: FontWeight.w800,
    fontSize: 13.5,
  );
  if (id.isEmpty) {
    return Text(
      safeLabel,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }
  return InkWell(
    onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PlayerDetailScreen(playerId: id))),
    child: Text(
      safeLabel,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    ),
  );
}

Widget _batterCell(BuildContext context, Map<String, dynamic> row) {
  final dismissal = _dismissalText(row);
  final isCurrent = _isCurrentBatter(row);
  final subtitle = dismissal.isNotEmpty
      ? dismissal
      : (isCurrent ? 'not out' : str(row['status']));
  return Padding(
    padding: const EdgeInsets.only(right: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        _playerCell(context, row,
            formatCompactPlayerName(_playerName(row), maxLen: 18)),
        if (subtitle.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(
              subtitle,
              // Dismissal lines ("c Mendis b Hasaranga") get up to two lines so
              // they read in full instead of being clipped mid-fielder.
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isCurrent ? context.cric.success : context.cric.muted,
                fontWeight: FontWeight.w600,
                fontSize: 10.5,
                height: 1.2,
              ),
            ),
          ),

      ],
    ),
  );
}

String _playerName(Map<String, dynamic> row) {
  return str(row['name'] ??
      row['player_name'] ??
      row['batsman'] ??
      row['bowler'] ??
      row['fullName']);
}

/// Guards the small commentary score line against the malformed `0/9`-style
/// values some feeds emit (0 runs but several wickets). When the value is not a
/// believable cumulative score we return false so the caller hides the line
/// instead of rendering a wrong number.
bool _isValidCommentaryScore(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return false;
  final m = RegExp(r'^(\d+)\s*/\s*(\d+)').firstMatch(t);
  if (m == null) return true; // non runs/wickets shape — leave it as-is.
  final runs = int.tryParse(m.group(1)!) ?? 0;
  final wickets = int.tryParse(m.group(2)!) ?? 0;
  if (wickets > 10) return false; // impossible wicket count.
  if (runs == 0 && wickets == 0) return false; // "0/0" — innings not begun.
  if (runs == 0 && wickets >= 1) return false; // the "0/9" artifact.
  return true;
}

String _dismissalText(Map<String, dynamic> row) {
  return str(row['dismissal'] ??
      row['dismissal_text'] ??
      row['dismissalText'] ??
      row['outDesc'] ??
      row['out_desc'] ??
      row['how_out']);
}

bool _isCurrentBatter(Map<String, dynamic> row) {
  final status = str(row['status']).toLowerCase();
  return truthy(row['is_current']) ||
      truthy(row['isCurrent']) ||
      truthy(row['is_striker']) ||
      truthy(row['isStriker']) ||
      truthy(row['is_non_striker']) ||
      truthy(row['isNonStriker']) ||
      status == 'not out' ||
      status == 'batting';
}

bool _shouldShowBatter(Map<String, dynamic> row) {
  final runs = _num(row['runs']);
  final balls = _num(row['balls']);
  return runs > 0 ||
      balls > 0 ||
      _dismissalText(row).isNotEmpty ||
      _isCurrentBatter(row);
}

List<Map<String, dynamic>> _yetToBatRows(
  List<Map<String, dynamic>> batting,
  List<dynamic> explicit,
) {
  final rows = <Map<String, dynamic>>[];
  for (final row in batting) {
    if (!_shouldShowBatter(row) && _playerName(row).isNotEmpty) {
      rows.add(row);
    }
  }
  for (final raw in explicit) {
    final row = raw is String ? {'name': raw} : apiMap(raw);
    final name = _playerName(row);
    if (name.isEmpty) continue;
    if (rows.any((existing) => _playerName(existing) == name)) continue;
    rows.add(row);
  }
  return rows;
}

bool _shouldShowBowler(Map<String, dynamic> row) {
  return str(row['overs']).isNotEmpty ||
      _num(row['balls']) > 0 ||
      _num(row['runs'] ?? row['runs_conceded']) > 0 ||
      _num(row['wickets']) > 0 ||
      _num(row['maidens']) > 0;
}

num _num(dynamic value) {
  if (value is num) return value;
  return num.tryParse(str(value)) ?? 0;
}

String _scoreText(Map<String, dynamic> row) {
  final runs = str(row['runs'] ?? row['total_runs']);
  final wickets = str(row['wickets'] ?? row['total_wickets']);
  final overs = str(row['overs'] ?? row['total_overs']);
  if (runs.isEmpty) return '';
  final normalizedOvers = overs.isEmpty ? '' : normalizeOversText(overs);
  return '$runs/$wickets${normalizedOvers.isEmpty ? '' : ' ($normalizedOvers OV)'}';
}

Map<String, dynamic> apiMap(dynamic value) =>
    value is Map<String, dynamic> ? value : <String, dynamic>{};

String str(dynamic value, {String fallback = ''}) {
  if (value == null) return fallback;
  if (value is List) {
    return value
        .map((item) => str(item))
        .where((item) => item.isNotEmpty)
        .join(', ');
  }
  final text = value.toString().trim();
  return text.isEmpty || text == 'null' ? fallback : text;
}

bool truthy(dynamic value) =>
    value == true ||
    value == 1 ||
    value == '1' ||
    value.toString().toLowerCase() == 'true';

class _MatchDataStateCard extends StatelessWidget {
  const _MatchDataStateCard({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Icon(icon, color: c.cyan),
          const SizedBox(width: 12),
          Expanded(
              child: Text(text,
                  style:
                      TextStyle(color: c.muted, fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }
}
