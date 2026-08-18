part of '../match_details_screen.dart';

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final team1 = apiMap(data['team1']);
    final team2 = apiMap(data['team2']);
    final venue = apiMap(data['venue']);
    final toss = apiMap(data['toss']);
    final officials = apiMap(data['officials'] ?? data['match_officials']);

    final statusText =
        str(data['status_text'] ?? data['statusText'] ?? data['status']);
    final series = str(data['series_name'] ?? data['seriesName']);
    final format = formatMatchFormat(
        str(data['match_format'] ?? data['match_type'] ?? data['matchFormat']));
    final teamsLine = team1.isNotEmpty && team2.isNotEmpty
        ? '${str(team1['name'], fallback: 'Team 1')} vs ${str(team2['name'], fallback: 'Team 2')}'
        : '';
    final venueLine = [venue['name'], venue['city'], venue['country']]
        .where((v) => str(v).isNotEmpty)
        .join(', ');
    // `fixTossGrammar` repairs the feed's "-ing" decisions: "chose to bowling"
    // -> "chose to bowl", "chose to batting" -> "chose to bat".
    final tossLine = toss.isEmpty
        ? ''
        : fixTossGrammar(
            '${str(toss['winner'])} won the toss and chose to ${str(toss['decision']).toLowerCase()}');

    final left = <_InfoItem>[
      if (statusText.isNotEmpty)
        _InfoItem(Icons.emoji_events_outlined, 'Match Status', statusText,
            valueColor: c.success),
      if (series.isNotEmpty) _InfoItem(Icons.layers_outlined, 'Series', series),
      if (format.isNotEmpty)
        _InfoItem(Icons.sports_cricket_rounded, 'Format', format),
    ];
    final right = <_InfoItem>[
      if (tossLine.isNotEmpty)
        _InfoItem(Icons.casino_outlined, 'Toss', tossLine),
      if (venueLine.isNotEmpty)
        _InfoItem(Icons.location_on_outlined, 'Venue', venueLine),
      if (teamsLine.isNotEmpty)
        _InfoItem(Icons.groups_2_outlined, 'Teams', teamsLine),
    ];

    final runRate = str(data['current_run_rate'] ?? data['currentRunRate']);
    final reqRate = str(data['required_run_rate'] ?? data['requiredRunRate']);
    final lastWicket = str(data['last_wicket'] ?? data['lastWicket']);
    final recentOvers = str(data['recent_overs'] ?? data['recentOvers']);

    // Required Run Rate is only meaningful in a live chase (positive target). A
    // Test / 1st-innings feed sends the literal "0"/"0.00" — showing "Required
    // Run Rate 0" is misleading, so hide it unless the value is a real > 0 rate.
    final reqRateVal =
        double.tryParse(reqRate.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0;
    final showReqRate = reqRateVal > 0;
    // Recent Overs runs-per-over tokens: hide the card when every value is 0/–
    // (a "0 0 0 0 0 0" placeholder carries no information) and render the real
    // ones as compact per-over pills instead of a raw space-joined string.
    final overTokens = recentOvers
        .trim()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    final showRecentOvers =
        overTokens.any((t) => t != '0' && t != '-' && t != '–' && t != '.');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (left.isNotEmpty || right.isNotEmpty)
          LayoutBuilder(
            builder: (context, constraints) {
              final stack = constraints.maxWidth < 340;
              final a = _InfoGridCard(items: left);
              final b = _InfoGridCard(items: right);
              if (stack) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (left.isNotEmpty) a,
                    if (left.isNotEmpty && right.isNotEmpty)
                      const SizedBox(height: 12),
                    if (right.isNotEmpty) b,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: left.isEmpty ? const SizedBox() : a),
                  if (left.isNotEmpty && right.isNotEmpty)
                    const SizedBox(width: 12),
                  Expanded(child: right.isEmpty ? const SizedBox() : b),
                ],
              );
            },
          ),
        if (_hasOfficials(officials)) ...[
          const SizedBox(height: 12),
          _OfficialsCard(officials: officials),
        ],
        if (runRate.isNotEmpty || showReqRate) ...[
          const SizedBox(height: 12),
          _SectionCard(
            title: 'Run Rate',
            icon: Icons.show_chart_rounded,
            child: Column(
              children: [
                if (runRate.isNotEmpty)
                  _kvRow(context, 'Current Run Rate', runRate),
                if (showReqRate)
                  _kvRow(context, 'Required Run Rate', reqRate),
              ],
            ),
          ),
        ],
        if (showRecentOvers) ...[
          const SizedBox(height: 12),
          _SectionCard(
            title: 'Recent Overs',
            icon: Icons.timelapse_rounded,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in overTokens) _RecentOverPill(runs: t),
              ],
            ),
          ),
        ],
        if (lastWicket.isNotEmpty) ...[
          const SizedBox(height: 12),
          _SectionCard(
            title: 'Last Wicket',
            icon: Icons.sports_cricket_outlined,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                lastWicket,
                style: TextStyle(
                    color: c.text, fontWeight: FontWeight.w700, height: 1.4),
              ),
            ),
          ),
        ],
        const SizedBox(height: 14),
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: c.isDark ? c.card.withValues(alpha: .4) : c.card,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: c.cyan.withValues(alpha: .25)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.info_outline_rounded, color: c.cyan, size: 13),
                const SizedBox(width: 6),
                Text(
                  'All times are local (IST)',
                  style: TextStyle(
                    color: c.muted,
                    fontWeight: FontWeight.w700,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static bool _hasOfficials(Map<String, dynamic> o) {
    if (o.isEmpty) return false;
    return [
      o['umpires'],
      o['field_umpires'],
      o['tv_umpire'],
      o['tvUmpire'],
      o['referee'],
      o['match_referee'],
      o['reserve_umpire'],
    ].any((v) => str(v).isNotEmpty);
  }

  static Widget _kvRow(BuildContext context, String k, String v) {
    final c = context.cric;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(k,
                style: TextStyle(
                    color: c.muted,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5)),
          ),
          Text(v,
              style: TextStyle(
                  color: c.cyan, fontWeight: FontWeight.w900, fontSize: 14)),
        ],
      ),
    );
  }
}

class _InfoItem {
  const _InfoItem(this.icon, this.label, this.value, {this.valueColor});
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
}

/// A single "runs in that over" pill for the Info tab's Recent Overs row.
/// A wicket-carrying over (feed sends e.g. "1W" / "Xw") is tinted with the live
/// accent; a boundary-heavy over leans cyan; a plain over stays neutral glass.
class _RecentOverPill extends StatelessWidget {
  const _RecentOverPill({required this.runs});

  final String runs;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final hasWicket = runs.toLowerCase().contains('w');
    final accent = hasWicket ? c.live : c.cyan;
    return Container(
      constraints: const BoxConstraints(minWidth: 30),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: c.isDark ? .12 : .10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: .40)),
      ),
      child: Text(
        runs,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: hasWicket ? c.live : c.text,
          fontWeight: FontWeight.w900,
          fontSize: 12.5,
          height: 1,
        ),
      ),
    );
  }
}

class _InfoGridCard extends StatelessWidget {
  const _InfoGridCard({required this.items});

  final List<_InfoItem> items;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return MDGlassPanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i != 0) ...[
              const SizedBox(height: 10),
              Divider(color: c.cyan.withValues(alpha: .12), height: 1),
              const SizedBox(height: 10),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.cyan.withValues(alpha: .12),
                    border: Border.all(color: c.cyan.withValues(alpha: .35)),
                  ),
                  child: Icon(items[i].icon, color: c.cyan, size: 15),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        items[i].label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.cyan.withValues(alpha: .9),
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        items[i].value,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: items[i].valueColor ?? c.text,
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _OfficialsCard extends StatelessWidget {
  const _OfficialsCard({required this.officials});

  final Map<String, dynamic> officials;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final items = <(String, String)>[
      ('Umpires', str(officials['umpires'] ?? officials['field_umpires'])),
      ('TV Umpire', str(officials['tv_umpire'] ?? officials['tvUmpire'])),
      (
        'Match Referee',
        str(officials['referee'] ?? officials['match_referee'])
      ),
      (
        'Reserve Umpire',
        str(officials['reserve_umpire'] ?? officials['reserveUmpire'])
      ),
    ].where((e) => e.$2.isNotEmpty).toList();
    if (items.isEmpty) return const SizedBox.shrink();
    return _SectionCard(
      title: 'Match Officials',
      icon: Icons.person_outline_rounded,
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final e in items)
            SizedBox(
              width: (context.w - context.horizontalPadding * 2 - 32 - 12) / 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.$1,
                    style: TextStyle(
                      color: c.cyan,
                      fontWeight: FontWeight.w800,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    e.$2,
                    style: TextStyle(
                      color: c.text,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SquadsPanel extends StatefulWidget {
  const _SquadsPanel({required this.data});

  final Map<String, dynamic> data;

  @override
  State<_SquadsPanel> createState() => _SquadsPanelState();
}

class _SquadsPanelState extends State<_SquadsPanel> {
  int team = 0;

  @override
  Widget build(BuildContext context) {
    final teams = apiList(widget.data['teams']);
    if (teams.isEmpty) {
      return const _MatchDataStateCard(
          icon: Icons.groups_rounded,
          text: 'Squad has not been announced yet.');
    }
    final safeTeam = team.clamp(0, teams.length - 1);
    final current = apiMap(teams[safeTeam]);
    final xi = apiList(current['playingXI'] ?? current['playing_xi']);
    final bench = apiList(current['bench'] ?? current['substitutes']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MDTeamSelector(
          items: [
            for (final item in teams)
              MDTeamSelectorItem(
                label: str(
                    apiMap(item)['teamName'] ??
                        apiMap(item)['team_name'] ??
                        apiMap(item)['teamShort'] ??
                        apiMap(item)['team_short'],
                    fallback: 'Team'),
                name: str(apiMap(item)['teamName'] ??
                    apiMap(item)['team_name'] ??
                    apiMap(item)['teamShort']),
                logo: str(apiMap(item)['logoUrl'] ??
                            apiMap(item)['logo_url'] ??
                            apiMap(item)['flag'])
                        .isEmpty
                    ? null
                    : str(apiMap(item)['logoUrl'] ??
                        apiMap(item)['logo_url'] ??
                        apiMap(item)['flag']),
              ),
          ],
          selected: safeTeam,
          onChanged: (value) => setState(() => team = value),
        ),
        const SizedBox(height: 14),
        PremiumSquad(playingXi: xi, bench: bench, title: 'Playing XI'),
      ],
    );
  }
}

/// Formats a strike-rate / economy value to a single decimal so it never
/// wraps in the compact scorecard table. Empty values show a clean dash.
String _fmtStat(String raw) {
  final v = formatStatNumber(raw, decimals: 1);
  return v.isEmpty ? '—' : v;
}

/// Compact "View All / Show Less" toggle shown under a collapsed table.
class _ViewAllButton extends StatelessWidget {
  const _ViewAllButton({
    required this.label,
    required this.expanded,
    required this.onTap,
  });

  final String label;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Column(
        children: [
          const SizedBox(height: 6),
          Divider(color: c.cyan.withValues(alpha: .14), height: 1),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: c.cyan,
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(width: 3),
                Icon(
                  expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: c.cyan,
                  size: 19,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard(
      {required this.title, required this.child, this.icon, this.asset});

  final String title;
  final Widget child;
  final IconData? icon;
  final String? asset;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return MDGlassPanel(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          asset != null
              ? Row(
                  children: [
                    MDIcon(asset!,
                        fallback: icon ?? Icons.sports_cricket_rounded,
                        size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.text,
                          fontWeight: FontWeight.w900,
                          fontStyle: FontStyle.italic,
                          fontSize: 13.5,
                          letterSpacing: .4,
                        ),
                      ),
                    ),
                  ],
                )
              : MDSectionHeader(title: title, icon: icon),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _StatTable extends StatelessWidget {
  const _StatTable(
      {required this.headers, required this.rows, required this.empty});

  final List<String> headers;
  final List<List<Widget>> rows;
  final String empty;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    if (rows.isEmpty) return _InlineEmpty(text: empty);
    return LayoutBuilder(
      builder: (context, constraints) {
        final hideLast = headers.length >= 7 && constraints.maxWidth < 270;
        final visibleHeaders =
            hideLast ? headers.take(headers.length - 1).toList() : headers;
        final numericCount = visibleHeaders.length - 1;
        final narrow = constraints.maxWidth < 360;

        // Fixed column widths; the last numeric column (SR / Econ) is widest so
        // values like "105.9" / "54.4" stay on one line and never wrap.
        double widthFor(int numericIndex) {
          final isLast = numericIndex == numericCount - 1;
          if (isLast) return narrow ? 42.0 : 48.0;
          return narrow ? 28.0 : 32.0;
        }

        Widget numericHeader(int i, String h) => SizedBox(
              width: widthFor(i),
              child: Text(
                h,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: c.muted,
                  fontWeight: FontWeight.w900,
                  fontSize: 11.5,
                ),
              ),
            );

        Widget numericCell(int i, Widget child) => SizedBox(
              width: widthFor(i),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.center,
                child: DefaultTextStyle.merge(
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    color: c.text,
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                  ),
                  child: child,
                ),
              ),
            );

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      visibleHeaders.first,
                      style: TextStyle(
                        color: c.muted,
                        fontWeight: FontWeight.w900,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                  for (var i = 1; i < visibleHeaders.length; i++)
                    numericHeader(i - 1, visibleHeaders[i]),
                ],
              ),
            ),
            Divider(color: c.border.withValues(alpha: .55), height: 1),
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(child: row.first),
                    for (var i = 0; i < numericCount; i++)
                      numericCell(
                          i,
                          i + 1 < row.length
                              ? row[i + 1]
                              : const Text('—')),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

