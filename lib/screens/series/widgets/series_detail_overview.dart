part of '../series_detail_screen.dart';

class _SeriesContext {
  _SeriesContext({
    required this.seriesId,
    required this.fallbackName,
    required this.detail,
    required this.matches,
    this.initialSeries,
  });

  final String seriesId;
  final String fallbackName;
  final Map<String, dynamic> detail;
  final List<CricketMatch> matches;
  final ApiSeries? initialSeries;

  String get title {
    final name = apiString(
      detail['seriesName'] ??
          detail['series_name'] ??
          detail['name'] ??
          detail['title'],
      fallbackName,
    );
    return cleanSeriesText(name);
  }

  /// Year/season suffix, e.g. "2024-25" extracted from the title.
  String? get season {
    final match = RegExp(r'(\d{4}(?:[-/]\d{2,4})?)\s*$').firstMatch(title);
    return match?.group(1);
  }

  /// "India Tour of Australia" without the trailing year.
  String? get tourLabel {
    final s = season;
    if (s == null) return null;
    final base = title.replaceFirst(RegExp(r'\s*$s\s*$'), '').trim();
    return base.isEmpty ? null : base;
  }

  String get titleWithoutSeason => tourLabel ?? title;

  List<CricketMatch> get _ordered {
    final list = [...matches];
    list.sort((a, b) => (a.startDateTime ?? DateTime(2100))
        .compareTo(b.startDateTime ?? DateTime(2100)));
    return list;
  }

  DateTime? get startDate => _ordered.isNotEmpty
      ? _ordered.first.startDateTime
      : SeriesView.fromApi(initialSeries ?? _emptySeries).startDate;

  DateTime? get endDate =>
      _ordered.isNotEmpty ? _ordered.last.startDateTime : null;

  String get dateRange {
    const m = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec' //
    ];
    final s = startDate;
    final e = endDate;
    if (s == null) return '';
    String md(DateTime d) => '${m[d.month - 1]} ${d.day}';
    if (e == null || (e.difference(s).inDays).abs() < 1) {
      return '${md(s)}, ${s.year}';
    }
    if (s.year == e.year) {
      return '${md(s)} – ${md(e)}, ${e.year}';
    }
    return '${md(s)}, ${s.year} – ${md(e)}, ${e.year}';
  }

  /// Distinct match formats present in the series, e.g. ["Test", "ODI"].
  List<String> get formats {
    final counts = <String, int>{};
    final re =
        RegExp(r'\b(Test|ODI|T20I|T20|Match|Final)\b', caseSensitive: false);
    for (final m in matches) {
      final hit = re.firstMatch(m.matchDesc);
      if (hit == null) continue;
      var f = hit.group(0)!;
      f = switch (f.toLowerCase()) {
        'test' => 'Test',
        'odi' => 'ODI',
        't20i' => 'T20I',
        't20' => 'T20',
        _ => f,
      };
      counts[f] = (counts[f] ?? 0) + 1;
    }
    if (counts.isEmpty) return const [];
    // Order by typical priority.
    const order = ['Test', 'ODI', 'T20I', 'T20'];
    final keys = counts.keys.toList()
      ..sort((a, b) => order.indexOf(a).compareTo(order.indexOf(b)));
    return [
      for (final k in keys)
        if (order.contains(k)) '${counts[k]} $k${counts[k]! > 1 ? 's' : ''}',
    ];
  }

  String get host {
    final fromDetail = apiString(detail['country'] ?? detail['host']);
    if (fromDetail.isNotEmpty) return fromDetail;
    // Heuristic: "X Tour of Y" → host is Y.
    final m =
        RegExp(r'tour of ([a-z ]+)', caseSensitive: false).firstMatch(title);
    if (m != null) return _titleCase(m.group(1)!.trim());
    return '';
  }

  int get totalMatches {
    final explicit =
        apiInt(detail['matchCount']) ?? apiInt(detail['totalMatches']);
    if (explicit != null && explicit > 0) return explicit;
    return matches.length;
  }

  int get liveCount => matches.where((m) => m.isLive).length;
  int get upcomingCount => matches.where((m) => m.isUpcoming).length;
  int get completedCount => matches.where((m) => m.isFinished).length;

  /// Uses the authoritative [classifySeriesStatus] (date-based, with a live-
  /// match override) so the Overview status agrees with the series LIST card
  /// for the same series — instead of a count-only derivation that could read
  /// "Upcoming" here while the list card reads "Ongoing".
  SeriesStatus get status =>
      classifySeriesStatus(title, startDate, endDate, liveCount: liveCount);

  String get statusLabel => switch (status) {
        SeriesStatus.ongoing => 'In Progress',
        SeriesStatus.upcoming => 'Upcoming',
        SeriesStatus.completed => 'Completed',
        // This getter is derived from match counts and never yields `unknown`;
        // the arm exists only to keep the switch exhaustive.
        SeriesStatus.unknown => 'Upcoming',
      };

  /// The two primary teams (bilateral) for the hero, derived from matches.
  List<SeriesTeamRef> get _bilateralTeams {
    final byKey = <String, SeriesTeamRef>{};
    for (final m in matches) {
      for (final t in [
        SeriesTeamRef(
            name: m.teamA, shortName: m.teamAShort, logoUrl: m.teamALogo),
        SeriesTeamRef(
            name: m.teamB, shortName: m.teamBShort, logoUrl: m.teamBLogo),
      ]) {
        final key =
            (t.shortName.isNotEmpty ? t.shortName : t.name).toUpperCase();
        if (key.trim().isEmpty) continue;
        byKey.putIfAbsent(key, () => t);
      }
    }
    return byKey.values.toList();
  }

  SeriesTeamRef? get teamA =>
      _bilateralTeams.isNotEmpty ? _bilateralTeams.first : null;
  SeriesTeamRef? get teamB =>
      _bilateralTeams.length > 1 ? _bilateralTeams[1] : null;

  List<SeriesTeamRef> get allTeams => _bilateralTeams;

  List<String> get venues {
    final set = <String>{};
    for (final m in matches) {
      final v = m.venue.trim();
      if (v.isNotEmpty && v.toLowerCase() != 'venue tbd') set.add(v);
    }
    return set.toList();
  }

  CricketMatch? get nextMatch {
    for (final m in _ordered) {
      if (m.isLive || m.isUpcoming) return m;
    }
    return _ordered.isNotEmpty ? _ordered.first : null;
  }

  /// Head-to-head insight derived from this series' completed matches only.
  /// Returns null when no completed match has a derivable result, so the
  /// Overview never invents fabricated head-to-head numbers.
  SeriesInsight? get seriesInsight {
    final teams = _bilateralTeams;
    if (teams.length < 2) return null;
    final completed = _ordered.where((m) => m.isFinished).toList();
    if (completed.isEmpty) return null;

    final a = teams[0];
    final b = teams[1];
    final aKey = _teamKey(a);
    final bKey = _teamKey(b);
    var aWins = 0;
    var bWins = 0;
    var noResult = 0;
    var played = 0;
    final last5 = <String>[]; // 'A' / 'B' / '-' most recent last
    var hasResult = false;
    for (final m in completed) {
      if (!_matchInvolves(m, a) || !_matchInvolves(m, b)) continue;
      played++;
      final winner = _winnerShort(m);
      if (winner == aKey) {
        aWins++;
        hasResult = true;
        last5.add('A');
      } else if (winner == bKey) {
        bWins++;
        hasResult = true;
        last5.add('B');
      } else {
        noResult++;
        last5.add('-');
      }
    }
    if (!hasResult) return null;
    final recent = last5.length > 5 ? last5.sublist(last5.length - 5) : last5;
    return SeriesInsight(
      teamA: a,
      teamB: b,
      played: played,
      teamAWins: aWins,
      teamBWins: bWins,
      noResult: noResult,
      last5A: recent.where((r) => r == 'A').length,
      last5B: recent.where((r) => r == 'B').length,
    );
  }

  /// Recent win/loss form per team derived from completed matches. Returns a
  /// map of team short name -> ordered list of 'W'/'L'/'-' (most recent last),
  /// only when at least one completed match has a derivable winner. Used by the
  /// Overview "Series Form / Momentum" card; empty when no real data exists.
  List<_TeamForm> get teamForm {
    final completed = _ordered.where((m) => m.isFinished).toList();
    if (completed.isEmpty) return const [];
    final teams = _bilateralTeams;
    if (teams.length < 2) return const [];

    final forms = <String, List<String>>{};
    for (final t in teams) {
      forms[_teamKey(t)] = [];
    }

    var hasResult = false;
    for (final m in completed) {
      final winner = _winnerShort(m);
      for (final t in teams) {
        final key = _teamKey(t);
        if (!_matchInvolves(m, t)) continue;
        if (winner == null) {
          forms[key]!.add('-');
        } else if (winner == key) {
          forms[key]!.add('W');
          hasResult = true;
        } else {
          forms[key]!.add('L');
          hasResult = true;
        }
      }
    }
    if (!hasResult) return const [];
    return [
      for (final t in teams)
        _TeamForm(team: t, results: forms[_teamKey(t)] ?? const []),
    ];
  }

  String _teamKey(SeriesTeamRef t) =>
      (t.shortName.isNotEmpty ? t.shortName : t.name).toUpperCase();

  bool _matchInvolves(CricketMatch m, SeriesTeamRef t) {
    final key = _teamKey(t);
    return m.teamAShort.toUpperCase() == key ||
        m.teamBShort.toUpperCase() == key ||
        m.teamA.toUpperCase() == t.name.toUpperCase() ||
        m.teamB.toUpperCase() == t.name.toUpperCase();
  }

  /// Extracts the winning team's short name from a completed match's status
  /// text (e.g. "India won by 8 wickets"). Returns null when undeterminable.
  String? _winnerShort(CricketMatch m) {
    final status = '${m.resultText} ${m.statusText}'.toLowerCase();
    if (status.trim().isEmpty || !status.contains('won')) return null;
    for (final t in [
      (m.teamAShort, m.teamA),
      (m.teamBShort, m.teamB),
    ]) {
      final short = t.$1.toLowerCase();
      final full = t.$2.toLowerCase();
      if (full.isNotEmpty && status.contains(full)) return t.$1.toUpperCase();
      if (short.isNotEmpty && status.startsWith(short)) {
        return t.$1.toUpperCase();
      }
    }
    return null;
  }

  static const _emptySeries = ApiSeries(id: '', name: '', status: '');
}

/// Per-team recent form for the Overview momentum card.
class _TeamForm {
  const _TeamForm({required this.team, required this.results});
  final SeriesTeamRef team;
  final List<String> results;
}

/// Head-to-head insight derived from completed matches in the series.
class SeriesInsight {
  const SeriesInsight({
    required this.teamA,
    required this.teamB,
    required this.played,
    required this.teamAWins,
    required this.teamBWins,
    required this.noResult,
    required this.last5A,
    required this.last5B,
  });

  final SeriesTeamRef teamA;
  final SeriesTeamRef teamB;
  final int played;
  final int teamAWins;
  final int teamBWins;
  final int noResult;
  final int last5A;
  final int last5B;
}

String _titleCase(String s) => s
    .split(' ')
    .where((w) => w.isNotEmpty)
    .map((w) => w[0].toUpperCase() + w.substring(1))
    .join(' ');

// ---------------------------------------------------------------------------
// Tab router
// ---------------------------------------------------------------------------

class _SeriesTabPanel extends StatelessWidget {
  const _SeriesTabPanel({
    required this.tab,
    required this.future,
    required this.seriesId,
    required this.onOpenMatch,
    required this.onSwitchTab,
  });

  final int tab;
  final Future<dynamic> future;
  final String seriesId;
  final ValueChanged<String> onOpenMatch;
  final ValueChanged<int> onSwitchTab;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<dynamic>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Column(
            children: [
              SeriesSkeleton(height: 150),
              SizedBox(height: 14),
              SeriesSkeleton(height: 120),
            ],
          );
        }
        if (snapshot.hasError) {
          return const SeriesEmptyState(
            title: 'Temporarily unavailable',
            message: 'This section could not load. Pull down to refresh.',
            icon: Icons.cloud_off_rounded,
          );
        }
        switch (tab) {
          case 1:
            final env = snapshot.data as ApiEnvelope<List<CricketMatch>>?;
            return _MatchesTab(
              matches: env?.data ?? const [],
              onOpenMatch: onOpenMatch,
            );
          case 2:
            final formats = (snapshot.data as List<SquadFormat>?) ?? const [];
            return _SquadsTab(formats: formats);
          case 3:
            final responses = snapshot.data as List<dynamic>?;
            final points = responses != null && responses.isNotEmpty
                ? apiMap(
                    (responses[0] as ApiEnvelope<Map<String, dynamic>>).data)
                : const <String, dynamic>{};
            final stats = responses != null && responses.length > 1
                ? apiMap(
                    (responses[1] as ApiEnvelope<Map<String, dynamic>>).data)
                : const <String, dynamic>{};
            return _StatsTab(points: points, stats: stats);
          default:
            final ctx = snapshot.data as _SeriesContext?;
            if (ctx == null) {
              return const SeriesSkeleton(height: 160);
            }
            return _OverviewTab(
              ctx: ctx,
              onOpenMatch: onOpenMatch,
              onViewAllMatches: () => onSwitchTab(1),
            );
        }
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Overview tab
// ---------------------------------------------------------------------------

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({
    required this.ctx,
    required this.onOpenMatch,
    required this.onViewAllMatches,
  });

  final _SeriesContext ctx;
  final ValueChanged<String> onOpenMatch;
  final VoidCallback onViewAllMatches;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final next = ctx.nextMatch;
    final insight = ctx.seriesInsight;
    final teamsLabel = ctx.teamA != null && ctx.teamB != null
        ? '${ctx.teamA!.name} vs ${ctx.teamB!.name}'
        : (ctx.allTeams.isNotEmpty ? '${ctx.allTeams.length} Teams' : '');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PremiumSectionPanel(
          title: 'Series Info',
          icon: Icons.info_outline_rounded,
          bgAsset: SAsset.overviewPanelBg,
          bgRemoteKey: 'series_overview_panel_bg',
          child: _SeriesInfoGrid(
            items: [
              if (ctx.dateRange.isNotEmpty)
                _InfoRow(Icons.calendar_today_rounded, 'Series Dates',
                    ctx.dateRange),
              if (ctx.formats.isNotEmpty)
                _InfoRow(
                    Icons.edit_note_rounded, 'Format', ctx.formats.join(' • ')),
              if (ctx.host.isNotEmpty)
                _InfoRow(Icons.location_on_outlined, 'Host', ctx.host),
              if (teamsLabel.isNotEmpty)
                _InfoRow(Icons.groups_2_outlined, 'Teams', teamsLabel),
              if (ctx.totalMatches > 0)
                _InfoRow(Icons.sports_cricket_rounded, 'Matches',
                    '${ctx.totalMatches} Matches'),
              _InfoRow(
                Icons.monitor_heart_outlined,
                'Series Status',
                ctx.statusLabel,
                valueColor: ctx.status == SeriesStatus.ongoing
                    ? c.live
                    : ctx.status == SeriesStatus.completed
                        ? c.success
                        : c.cyan,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _StatusSummaryRow(
          live: ctx.liveCount,
          upcoming: ctx.upcomingCount,
          completed: ctx.completedCount,
          nextDate: next != null && next.startDateTime != null
              ? _dateOnlyYear(next.startDateTime!)
              : null,
        ),
        if (next != null) ...[
          const SizedBox(height: 14),
          _NextMatchCard(
            match: next,
            onOpen: () => onOpenMatch(next.id),
            onViewAll: onViewAllMatches,
          ),
        ],
        if (ctx.venues.isNotEmpty) ...[
          const SizedBox(height: 14),
          _VenuesCard(venues: ctx.venues),
        ],
        if (insight != null) ...[
          const SizedBox(height: 14),
          _SeriesInsightCard(insight: insight),
        ],
      ],
    );
  }
}

class _InfoRow {
  const _InfoRow(this.icon, this.label, this.value, {this.valueColor});
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
}

class _SeriesInfoGrid extends StatelessWidget {
  const _SeriesInfoGrid({required this.items});

  final List<_InfoRow> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoCol = constraints.maxWidth >= 300;
        final colWidth =
            twoCol ? (constraints.maxWidth - 14) / 2 : constraints.maxWidth;
        return Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            for (final item in items)
              SizedBox(width: colWidth, child: _InfoTile(item: item)),
          ],
        );
      },
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.item});

  final _InfoRow item;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Row(
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
          child: Icon(item.icon, color: c.cyan, size: 15),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.label,
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
                item.value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: item.valueColor ?? c.text,
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// Status summary (Live / Upcoming / Completed) cards with colored borders.
class _StatusSummaryRow extends StatelessWidget {
  const _StatusSummaryRow({
    required this.live,
    required this.upcoming,
    required this.completed,
    this.nextDate,
  });

  final int live;
  final int upcoming;
  final int completed;
  final String? nextDate;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _StatusSummaryCard(
            value: live,
            label: 'Matches',
            sub: 'Live Right Now',
            title: 'LIVE',
            color: c.live,
            icon: Icons.podcasts_rounded,
            live: true,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatusSummaryCard(
            value: upcoming,
            label: 'Matches',
            sub: nextDate != null ? 'Next: $nextDate' : 'Upcoming',
            title: 'UPCOMING',
            color: c.cyan,
            icon: Icons.calendar_month_rounded,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatusSummaryCard(
            value: completed,
            label: 'Matches',
            sub: 'Completed',
            title: 'COMPLETED',
            color: c.success,
            icon: Icons.verified_outlined,
          ),
        ),
      ],
    );
  }
}

class _StatusSummaryCard extends StatelessWidget {
  const _StatusSummaryCard({
    required this.value,
    required this.label,
    required this.sub,
    required this.title,
    required this.color,
    required this.icon,
    this.live = false,
  });

  final int value;
  final String label;
  final String sub;
  final String title;
  final Color color;
  final IconData icon;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final tight = context.w <= 360;
    return Container(
      padding: EdgeInsets.symmetric(vertical: 12, horizontal: tight ? 8 : 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: c.isDark ? c.card.withValues(alpha: .5) : c.card,
        border: Border.all(color: color.withValues(alpha: .55)),
        boxShadow: c.isDark
            ? [
                BoxShadow(
                  color: color.withValues(alpha: .14),
                  blurRadius: 16,
                  spreadRadius: -6,
                ),
              ]
            : c.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (live)
                PulseDot(color: color, size: 6)
              else
                Icon(icon, color: color, size: 12),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w900,
                    fontSize: tight ? 9.5 : 10.5,
                    letterSpacing: .3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$value',
            style: TextStyle(
              color: c.text,
              fontWeight: FontWeight.w900,
              fontSize: 22,
              height: 1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: c.onImageText,
              fontWeight: FontWeight.w700,
              fontSize: 10.5,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            sub,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: c.muted,
              fontWeight: FontWeight.w600,
              fontSize: 9.5,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

// Premium Next Match card.
class _NextMatchCard extends StatelessWidget {
  const _NextMatchCard({
    required this.match,
    required this.onOpen,
    required this.onViewAll,
  });

  final CricketMatch match;
  final VoidCallback onOpen;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final phone = context.w <= 430;
    final logoSize = phone ? 50.0 : 56.0;
    return PremiumGlassPanel(
      bgAsset: SAsset.matchCardBg,
      bgRemoteKey: 'series_match_card_bg',
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_today_rounded, color: c.cyan, size: 15),
              const SizedBox(width: 8),
              Text(
                'NEXT MATCH',
                style: TextStyle(
                  color: c.text,
                  fontWeight: FontWeight.w900,
                  fontStyle: FontStyle.italic,
                  fontSize: 13.5,
                  letterSpacing: .4,
                ),
              ),
              const Spacer(),
              PremiumViewAll(label: 'View All Matches', onTap: onViewAll),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: PremiumTeamColumn(
                  name: match.teamA,
                  short: match.teamAShort,
                  logo: match.teamALogo,
                  logoSize: logoSize,
                  codeSize: phone ? 16 : 18,
                  accent: c.cyan,
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (match.matchDesc.isNotEmpty) ...[
                    Text(
                      match.matchDesc,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.cyan,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                  PremiumVsBadge(
                    width: phone ? 52 : 58,
                    height: phone ? 36 : 40,
                  ),
                ],
              ),
              Expanded(
                child: PremiumTeamColumn(
                  name: match.teamB,
                  short: match.teamBShort,
                  logo: match.teamBLogo,
                  logoSize: logoSize,
                  codeSize: phone ? 16 : 18,
                  accent: c.warning,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _MetaRow(
            icon: Icons.calendar_today_rounded,
            text: match.startDateTime != null
                ? formatMatchDateTime(match.startDateTime)
                : 'Date to be confirmed',
          ),
          if (match.venue.isNotEmpty) ...[
            const SizedBox(height: 8),
            _MetaRow(icon: Icons.location_on_rounded, text: match.venue),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: GradientButton(
              label: match.isLive ? 'Match Center' : 'Set Reminder',
              icon: match.isLive
                  ? Icons.play_circle_fill_rounded
                  : Icons.notifications_active_rounded,
              outlined: !match.isLive,
              height: 48,
              onTap: onOpen,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: c.cyan, size: 14),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: c.onImageText,
              fontWeight: FontWeight.w600,
              fontSize: 12.5,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}

// Venues — horizontal premium cards with real venue thumbnails.
class _VenuesCard extends StatelessWidget {
  const _VenuesCard({required this.venues});

  final List<String> venues;

  @override
  Widget build(BuildContext context) {
    return PremiumSectionPanel(
      title: 'Venues',
      icon: Icons.location_on_outlined,
      child: SizedBox(
        height: 104,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          itemCount: venues.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (context, i) => _VenueTile(venue: venues[i]),
        ),
      ),
    );
  }
}

class _VenueTile extends StatelessWidget {
  const _VenueTile({required this.venue});

  final String venue;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final parts = venue.split(',');
    final name = parts.first.trim();
    final city = parts.length > 1 ? parts.sublist(1).join(',').trim() : '';
    return Container(
      width: 150,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.cyan.withValues(alpha: .3)),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            SAsset.venueFor(venue),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                const ColoredBox(color: Color(0xff0a1f3a)),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  const Color(0xff05101f).withValues(alpha: .92),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    height: 1.1,
                  ),
                ),
                if (city.isNotEmpty)
                  Text(
                    city,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.cyan,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
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

// Series Insight — head-to-head derived from completed matches.
class _SeriesInsightCard extends StatelessWidget {
  const _SeriesInsightCard({required this.insight});

  final SeriesInsight insight;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final aShort = insight.teamA.shortName.isNotEmpty
        ? insight.teamA.shortName
        : insight.teamA.name;
    final bShort = insight.teamB.shortName.isNotEmpty
        ? insight.teamB.shortName
        : insight.teamB.name;
    return PremiumSectionPanel(
      title: 'Series Insight',
      icon: Icons.insights_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _InsightStat(
                  value: '${insight.played}',
                  label: 'Matches Played',
                  color: c.text,
                ),
              ),
              Expanded(
                child: _InsightStat(
                  value: '${insight.teamAWins}',
                  label: '$aShort Wins',
                  color: c.cyan,
                ),
              ),
              Expanded(
                child: _InsightStat(
                  value: '${insight.teamBWins}',
                  label: '$bShort Wins',
                  color: c.live,
                ),
              ),
              Expanded(
                child: _InsightStat(
                  value: '${insight.noResult}',
                  label: 'No Result',
                  color: c.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: c.cyan.withValues(alpha: .08),
              border: Border.all(color: c.cyan.withValues(alpha: .3)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Recent: ',
                  style: TextStyle(
                    color: c.muted,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                Text(
                  '$aShort ${insight.last5A}',
                  style: TextStyle(
                    color: c.cyan,
                    fontWeight: FontWeight.w900,
                    fontSize: 12.5,
                  ),
                ),
                Text(
                  '  -  ',
                  style: TextStyle(
                    color: c.muted,
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
                Text(
                  '${insight.last5B} $bShort',
                  style: TextStyle(
                    color: c.live,
                    fontWeight: FontWeight.w900,
                    fontSize: 12.5,
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

class _InsightStat extends StatelessWidget {
  const _InsightStat({
    required this.value,
    required this.label,
    required this.color,
  });

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w900,
            fontSize: 22,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: c.muted,
            fontWeight: FontWeight.w600,
            fontSize: 10,
            height: 1.2,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Matches tab
// ---------------------------------------------------------------------------

