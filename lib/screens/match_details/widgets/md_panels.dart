part of '../match_details_screen.dart';

class _ApiMatchTabFutureContent extends StatelessWidget {
  const _ApiMatchTabFutureContent(
      {required this.tab,
      required this.future,
      this.summaryData,
      this.scorecardData,
      this.matchStatus,
      this.fullCommentaryData,
      this.fallbackSummary,
      this.onViewMoreCommentary});

  final int tab;
  final Future<ApiEnvelope<Map<String, dynamic>>> future;
  final Map<String, dynamic>? summaryData;
  final Map<String, dynamic>? scorecardData;
  final String? matchStatus;
  final Map<String, dynamic>? fullCommentaryData;
  final CricketMatch? fallbackSummary;
  final VoidCallback? onViewMoreCommentary;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ApiEnvelope<Map<String, dynamic>>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return _MatchTabErrorCard(error: snapshot.error);
        }
        final data = snapshot.data?.data ?? const <String, dynamic>{};
        return _ApiMatchTabDataContent(
          tab: tab,
          data: data,
          summaryData: summaryData,
          scorecardData: scorecardData,
          matchStatus: matchStatus,
          fullCommentaryData: fullCommentaryData,
          fallbackSummary: fallbackSummary,
          onViewMoreCommentary: onViewMoreCommentary,
        );
      },
    );
  }
}

class _ApiMatchTabDataContent extends StatelessWidget {
  const _ApiMatchTabDataContent(
      {required this.tab,
      required this.data,
      this.summaryData,
      this.scorecardData,
      this.matchStatus,
      this.fullCommentaryData,
      this.fallbackSummary,
      this.onViewMoreCommentary});

  final int tab;
  final Map<String, dynamic> data;
  final Map<String, dynamic>? summaryData;
  final Map<String, dynamic>? scorecardData;
  final String? matchStatus;
  final Map<String, dynamic>? fullCommentaryData;

  /// Last-known good summary captured from the originating list/card. Used to
  /// render a useful Info tab (teams, series, venue, format, status) for an
  /// upcoming match even when the `/match/:id` info payload is thin/empty —
  /// instead of the bare "not available yet" placeholder.
  final CricketMatch? fallbackSummary;
  final VoidCallback? onViewMoreCommentary;

  @override
  Widget build(BuildContext context) {
    // The Live tab manages its own empty state and also draws from
    // summaryData, so it must build even when the live-center payload is empty.
    if (tab == 1) {
      return LiveMatchTab(
        summary: summaryData,
        liveCenter: data,
        scorecardData: scorecardData,
        fullCommentary: fullCommentaryData,
        onViewMoreCommentary: onViewMoreCommentary,
      );
    }
    if (data.isEmpty) {
      // Info tab: synthesize a basic info view from the known summary so an
      // upcoming match still shows teams/series/venue/format/status.
      if (tab == 0 && fallbackSummary != null) {
        final synth = _infoFromSummary(fallbackSummary!);
        if (synth.isNotEmpty) return _InfoPanel(data: synth);
      }
      return _MatchDataStateCard(
        icon: tab == 3 ? Icons.groups_rounded : Icons.info_outline_rounded,
        text: _emptyText(tab, matchStatus),
      );
    }
    return switch (tab) {
      0 => _InfoPanel(data: data),
      2 => _ScorecardPanel(data: data, matchStatus: matchStatus),
      3 => _SquadsPanel(data: data),
      4 => _CommentaryPanel(data: data, matchStatus: matchStatus),
      _ => _OversPanel(data: data),
    };
  }

  /// Maps a [CricketMatch] summary into the nested shape `_InfoPanel` reads,
  /// so the Info tab can render real fields without the detail endpoint.
  static Map<String, dynamic> _infoFromSummary(CricketMatch m) {
    final out = <String, dynamic>{};
    if (m.teamA.isNotEmpty && m.teamA != 'TBD') {
      out['team1'] = {'name': m.teamA, 'short': m.teamAShort};
    }
    if (m.teamB.isNotEmpty && m.teamB != 'TBD') {
      out['team2'] = {'name': m.teamB, 'short': m.teamBShort};
    }
    if (m.venue.isNotEmpty) out['venue'] = {'name': m.venue};
    if (m.series.isNotEmpty) out['series_name'] = m.series;
    if (m.matchDesc.isNotEmpty) out['match_format'] = m.matchDesc;
    final status = m.statusText.isNotEmpty ? m.statusText : m.statusLabel;
    if (status.isNotEmpty) out['status_text'] = status;
    // Only return something if there is at least team data worth showing.
    if (!out.containsKey('team1') && !out.containsKey('team2')) {
      return const <String, dynamic>{};
    }
    return out;
  }

  static String _emptyText(int tab, String? status) {
    final isUpcoming = status == null ||
        status.toLowerCase() == 'upcoming' ||
        status.toLowerCase() == 'scheduled' ||
        status.toLowerCase() == 'not_started';

    return switch (tab) {
      0 => 'Match information is not available yet.',
      2 => isUpcoming
          ? 'Scorecard will be available once the match starts.'
          : 'Scorecard is not available from the provider yet.',
      3 => 'Squad has not been announced yet.',
      4 => isUpcoming
          ? 'Commentary will appear when the match starts.'
          : 'Commentary is not available from the provider yet.',
      _ => 'Over summaries are not available yet.',
    };
  }
}

/// Error-state card that distinguishes network/offline from server errors.
/// Used by FutureBuilder error snapshots throughout Match Details tabs.
class _MatchTabErrorCard extends StatelessWidget {
  const _MatchTabErrorCard({required this.error});

  final Object? error;

  @override
  Widget build(BuildContext context) {
    final isOffline =
        error is ApiClientException && (error as ApiClientException).isNetwork;
    if (isOffline) {
      return CricOfflineCard(
        onRetry: () {
          // The RefreshIndicator wrapping the parent ListView is the correct
          // handler — surface the pull-to-refresh. This widget is read-only so
          // we cannot reset a Future; the user should pull down.
        },
        compact: true,
      );
    }
    return const _MatchDataStateCard(
      icon: Icons.error_outline_rounded,
      text: 'Something went wrong. Pull to refresh.',
    );
  }
}

class _RefreshStatusRow extends StatelessWidget {
  const _RefreshStatusRow({
    required this.lastUpdatedAt,
    required this.onRefresh,
  });

  final DateTime? lastUpdatedAt;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final label = lastUpdatedAt == null
        ? 'Pull to refresh'
        : DateTime.now().difference(lastUpdatedAt!).inSeconds < 10
            ? 'Updated just now'
            : 'Updated ${DateTime.now().difference(lastUpdatedAt!).inSeconds}s ago';
    return MDUpdatedRow(label: label, onRefresh: () => onRefresh());
  }
}

class _ScorecardPanel extends StatefulWidget {
  const _ScorecardPanel({required this.data, this.matchStatus});

  final Map<String, dynamic> data;
  final String? matchStatus;

  @override
  State<_ScorecardPanel> createState() => _ScorecardPanelState();
}

class _ScorecardPanelState extends State<_ScorecardPanel> {
  int selected = 0;
  bool _battingExpanded = false;
  bool _bowlingExpanded = false;

  @override
  void initState() {
    super.initState();
    selected = _preferredInningsIndex(widget.data);
  }

  @override
  void didUpdateWidget(covariant _ScorecardPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) {
      selected = _preferredInningsIndex(widget.data);
    }
  }

  int _preferredInningsIndex(Map<String, dynamic> data) {
    final innings = apiList(data['innings']);
    if (innings.isEmpty) return 0;
    final currentBatTeamId =
        str(data['curr_bat_team_id'] ?? data['currentBatTeamId']);
    if (currentBatTeamId.isEmpty) return 0;
    for (var i = 0; i < innings.length; i++) {
      final inn = apiMap(innings[i]);
      final batTeamId =
          str(inn['batting_team_id'] ?? inn['batTeamId'] ?? inn['teamId']);
      if (batTeamId.isNotEmpty && batTeamId == currentBatTeamId) {
        return i;
      }
    }
    return 0;
  }

  /// Builds the innings selector labels, de-duplicating teams that bat more
  /// than once (e.g. a Test) into "IND Inn 1 / AFG Inn 1 / AFG Inn 2".
  List<MDTeamSelectorItem> _inningsSelectorItems(List<dynamic> innings) {
    final shorts = <String>[];
    final counts = <String, int>{};
    for (final raw in innings) {
      final m = apiMap(raw);
      final name = str(m['teamName'] ?? m['batting_team'], fallback: 'Team');
      var short = str(m['teamShort'] ?? m['team_short'] ?? m['teamShortName']);
      if (short.isEmpty) {
        short = name.length >= 3
            ? name.substring(0, 3).toUpperCase()
            : name.toUpperCase();
      }
      shorts.add(short);
      counts[short] = (counts[short] ?? 0) + 1;
    }
    final multi = counts.values.any((v) => v > 1);
    final seen = <String, int>{};
    final items = <MDTeamSelectorItem>[];
    for (var i = 0; i < innings.length; i++) {
      final m = apiMap(innings[i]);
      final short = shorts[i];
      final name = str(m['teamName'] ?? m['batting_team'], fallback: short);
      final logo = str(m['logoUrl'] ?? m['logo_url']);
      final n = (seen[short] ?? 0) + 1;
      seen[short] = n;
      final ord = n == 1
          ? '1st'
          : n == 2
              ? '2nd'
              : n == 3
                  ? '3rd'
                  : '${n}th';
      items.add(MDTeamSelectorItem(
        // Single-innings teams show the full name when it fits; multi-innings
        // (Tests) use the short code + ordinal so both fit cleanly.
        label: multi
            ? '$short $ord Inn'
            : (name.length <= 14 ? name : short),
        name: name,
        logo: logo.isEmpty ? null : logo,
      ));
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final innings = apiList(widget.data['innings']);

    // Check if innings data is actually empty (no batting/bowling data)
    final hasData = innings.isNotEmpty &&
        innings.any((inn) {
          final inningsMap = apiMap(inn);
          final batting = apiList(inningsMap['batting'] ??
              inningsMap['batters'] ??
              inningsMap['batsmen']);
          final bowling =
              apiList(inningsMap['bowling'] ?? inningsMap['bowlers']);
          return batting.isNotEmpty || bowling.isNotEmpty;
        });

    if (!hasData) {
      final isUpcoming = widget.matchStatus == null ||
          widget.matchStatus!.toLowerCase() == 'upcoming' ||
          widget.matchStatus!.toLowerCase() == 'scheduled' ||
          widget.matchStatus!.toLowerCase() == 'not_started';

      return _MatchDataStateCard(
        icon: Icons.scoreboard_rounded,
        text: isUpcoming
            ? 'Scorecard will be available once the match starts.'
            : 'Scorecard data is not available yet.',
      );
    }
    final safeSelected = selected.clamp(0, innings.length - 1);
    final current = apiMap(innings[safeSelected]);
    final batting =
        apiList(current['batting'] ?? current['batters'] ?? current['batsmen']);
    final bowling = apiList(current['bowling'] ?? current['bowlers']);
    final battingRows =
        batting.map(apiMap).where(_shouldShowBatter).toList(growable: false);
    final yetToBatRows = _yetToBatRows(
      batting.map(apiMap).toList(growable: false),
      apiList(current['did_not_bat'] ??
          current['didNotBat'] ??
          current['yet_to_bat'] ??
          current['yetToBat']),
    );
    final bowlingRows =
        bowling.map(apiMap).where(_shouldShowBowler).toList(growable: false);
    final c = context.cric;

    const previewCount = 5;
    final battingVisible = _battingExpanded
        ? battingRows
        : battingRows.take(previewCount).toList(growable: false);
    final bowlingVisible = _bowlingExpanded
        ? bowlingRows
        : bowlingRows.take(previewCount).toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (innings.length > 1)
          MDTeamSelector(
            items: _inningsSelectorItems(innings),
            selected: safeSelected,
            onChanged: (value) => setState(() {
              selected = value;
              _battingExpanded = false;
              _bowlingExpanded = false;
            }),
          ),
        if (innings.length > 1) const SizedBox(height: 10),
        _SectionCard(
          title:
              str(current['teamName'] ?? current['batting_team'] ?? 'Batting'),
          asset: MDAsset.icBatting,
          icon: Icons.sports_cricket_rounded,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _StatTable(
                headers: const ['Batter', 'R', 'B', '4s', '6s', 'SR'],
                rows: [
                  for (final row in battingVisible)
                    [
                      _batterCell(context, row),
                      Text(str(row['runs'], fallback: '0')),
                      Text(str(row['balls'], fallback: '0')),
                      Text(str(row['fours'], fallback: '0')),
                      Text(str(row['sixes'], fallback: '0')),
                      Text(_fmtStat(str(row['strike_rate'] ??
                          row['strikeRate']))),
                    ],
                ],
                empty: 'Batting card is not available yet.',
              ),
              if (battingRows.length > previewCount)
                _ViewAllButton(
                  label: _battingExpanded
                      ? 'Show Less'
                      : 'View All Batting (${battingRows.length})',
                  expanded: _battingExpanded,
                  onTap: () =>
                      setState(() => _battingExpanded = !_battingExpanded),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _YetToBatCard(players: yetToBatRows),
        if (yetToBatRows.isNotEmpty) const SizedBox(height: 10),
        _ScorecardSummaryCard(innings: current),
        const SizedBox(height: 10),
        _SectionCard(
          title: 'Bowling',
          asset: MDAsset.icBowling,
          icon: Icons.sports_baseball_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _StatTable(
                headers: const ['Bowler', 'O', 'M', 'R', 'W', 'Econ'],
                rows: [
                  for (final row in bowlingVisible)
                    [
                      _playerCell(
                          context,
                          row,
                          formatCompactPlayerName(str(row['name'] ??
                              row['player_name'] ??
                              row['bowler']))),
                      Text(str(row['overs'], fallback: '0')),
                      Text(str(row['maidens'], fallback: '0')),
                      Text(str(row['runs'] ?? row['runs_conceded'],
                          fallback: '0')),
                      Text(str(row['wickets'], fallback: '0')),
                      Text(_fmtStat(str(row['economy']))),
                    ],
                ],
                empty: 'Bowling figures are not available yet.',
              ),
              if (bowlingRows.length > previewCount)
                _ViewAllButton(
                  label: _bowlingExpanded
                      ? 'Show Less'
                      : 'View All Bowling (${bowlingRows.length})',
                  expanded: _bowlingExpanded,
                  onTap: () =>
                      setState(() => _bowlingExpanded = !_bowlingExpanded),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _FallOfWicketsCard(
            fows: apiList(current['fall_of_wickets'] ?? current['fow'])),
        const SizedBox(height: 10),
        _PartnershipsCard(partnerships: apiList(current['partnerships'])),
        if (batting.isEmpty && bowling.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
                'Raw scorecard loaded, but no innings table was provided by the API.',
                style: TextStyle(color: c.muted)),
          ),
      ],
    );
  }
}

String _formatExtrasLine(Map<String, dynamic> extras) {
  if (extras.isEmpty) return '';
  final total = str(extras['total'] ?? extras['t'], fallback: '0');
  final byes = str(extras['byes'] ?? extras['b'], fallback: '0');
  final legByes = str(extras['leg_byes'] ?? extras['legByes'] ?? extras['lb'],
      fallback: '0');
  final wides = str(extras['wides'] ?? extras['w'], fallback: '0');
  final noBalls = str(extras['no_balls'] ?? extras['noBalls'] ?? extras['nb'],
      fallback: '0');
  final penalty = str(extras['penalty'] ?? extras['p'], fallback: '0');
  return '$total (b $byes, lb $legByes, w $wides, nb $noBalls, p $penalty)';
}

String _formatTotalLine(
    Map<String, dynamic> total, Map<String, dynamic> innings) {
  // Prefer structured backend shape: { runs, wickets, overs }.
  if (total.isNotEmpty) {
    final runs = str(total['runs'] ?? total['r'], fallback: '0');
    final wickets = str(total['wickets'] ?? total['w'], fallback: '0');
    final oversRaw = str(total['overs'] ?? total['o']);
    final overs = oversRaw.isEmpty ? '' : normalizeOversText(oversRaw);
    if (runs == '0' && wickets == '0' && overs.isEmpty) return '';
    return overs.isEmpty ? '$runs/$wickets' : '$runs/$wickets ($overs ov)';
  }
  return _scoreText(innings);
}

class _ScorecardSummaryCard extends StatelessWidget {
  const _ScorecardSummaryCard({required this.innings});

  final Map<String, dynamic> innings;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final extrasRaw = innings['extras'];
    final extrasMap =
        extrasRaw is Map<String, dynamic> ? extrasRaw : <String, dynamic>{};
    final extrasText = extrasRaw is String && extrasRaw.trim().isNotEmpty
        ? extrasRaw.trim()
        : _formatExtrasLine(extrasMap);
    final totalRaw = innings['total'];
    final totalMap =
        totalRaw is Map<String, dynamic> ? totalRaw : <String, dynamic>{};
    final totalText = totalRaw is String && totalRaw.trim().isNotEmpty
        ? totalRaw.trim()
        : _formatTotalLine(totalMap, innings);
    final rrRaw = str(innings['run_rate'] ?? innings['runRate']);
    final rrText = rrRaw.isEmpty ? '' : 'Run rate: $rrRaw';
    final visible = <MapEntry<String, String>>[];
    if (extrasText.isNotEmpty) visible.add(MapEntry('Extras', extrasText));
    if (totalText.isNotEmpty) visible.add(MapEntry('Total', totalText));
    if (rrText.isNotEmpty) visible.add(MapEntry('Run rate', rrRaw));
    if (visible.isEmpty) return const SizedBox.shrink();
    return PremiumCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final entry in visible)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 78,
                    child: Text(entry.key,
                        style: TextStyle(
                            color: c.muted,
                            fontWeight: FontWeight.w800,
                            fontSize: 11.5,
                            letterSpacing: 0.4)),
                  ),
                  Expanded(
                    child: Text(entry.value,
                        style: TextStyle(
                            color: c.text,
                            fontWeight: FontWeight.w900,
                            fontSize: 12.5,
                            height: 1.25)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _FallOfWicketsCard extends StatelessWidget {
  const _FallOfWicketsCard({required this.fows});

  final List<dynamic> fows;

  @override
  Widget build(BuildContext context) {
    if (fows.isEmpty) return const SizedBox.shrink();
    final entries = <String>[];
    for (final raw in fows) {
      final row = apiMap(raw);
      // Backend shape may vary: {wicket_number, score, batsman, overs}
      // or {wktNbr, score, batsmanName, overNbr}.
      final wkt = str(
          row['wicket_number'] ?? row['wktNbr'] ?? row['wicket'] ?? row['wkt']);
      final score = str(row['score'] ??
          row['runs'] ??
          row['wicketScore'] ??
          row['scoreAtFall']);
      final batsman = str(row['batsman'] ??
          row['batsmanName'] ??
          row['player_name'] ??
          row['name']);
      final oversRaw = str(row['overs'] ?? row['overNbr'] ?? row['over']);
      final overs = oversRaw.isEmpty ? '' : normalizeOversText(oversRaw);
      if (wkt.isEmpty && score.isEmpty && batsman.isEmpty) continue;
      final left = wkt.isEmpty ? score : (score.isEmpty ? wkt : '$wkt-$score');
      final tail = <String>[
        if (batsman.isNotEmpty) batsman,
        if (overs.isNotEmpty) '$overs ov',
      ].join(', ');
      entries.add(tail.isEmpty ? left : '$left ($tail)');
    }
    if (entries.isEmpty) return const SizedBox.shrink();
    return _SectionCard(
      title: 'Fall of Wickets',
      asset: MDAsset.icFallWickets,
      icon: Icons.trending_down_rounded,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const spacing = 8.0;
          final chipWidth = (constraints.maxWidth - spacing) / 2;
          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: [
              for (final text in entries)
                SizedBox(
                  width: chipWidth,
                  child: MDPillChip(text: text, center: true),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _PartnershipsCard extends StatelessWidget {
  const _PartnershipsCard({required this.partnerships});

  final List<dynamic> partnerships;

  @override
  Widget build(BuildContext context) {
    if (partnerships.isEmpty) return const SizedBox.shrink();
    final entries = <String>[];
    for (final raw in partnerships) {
      final row = apiMap(raw);
      final runs = str(row['runs'] ?? row['totalRuns'] ?? row['r']);
      final balls = str(row['balls'] ?? row['totalBalls'] ?? row['b']);
      if (runs.isEmpty && balls.isEmpty) continue;
      // Compact figure-only chip like the target: "75 (127)".
      final figure = balls.isEmpty ? runs : '$runs ($balls)';
      if (figure.isEmpty) continue;
      entries.add(figure);
    }
    if (entries.isEmpty) return const SizedBox.shrink();
    return _SectionCard(
      title: 'Partnerships',
      asset: MDAsset.icPartnership,
      icon: Icons.people_alt_outlined,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [for (final entry in entries) MDPillChip(text: entry)],
      ),
    );
  }
}

class _YetToBatCard extends StatelessWidget {
  const _YetToBatCard({required this.players});

  final List<Map<String, dynamic>> players;

  @override
  Widget build(BuildContext context) {
    if (players.isEmpty) return const SizedBox.shrink();
    final c = context.cric;
    final names = players
        .map((row) => _playerName(row))
        .where((name) => name.isNotEmpty)
        .toList();
    if (names.isEmpty) return const SizedBox.shrink();
    return PremiumCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Yet to bat',
            style: TextStyle(
              color: c.muted,
              fontWeight: FontWeight.w900,
              fontSize: 11.5,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            names.join(', '),
            style: TextStyle(
              color: c.text,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentaryPanel extends StatefulWidget {
  const _CommentaryPanel({required this.data, this.matchStatus});

  final Map<String, dynamic> data;
  final String? matchStatus;

  @override
  State<_CommentaryPanel> createState() => _CommentaryPanelState();
}

class _CommentaryPanelState extends State<_CommentaryPanel> {
  int filter = 0;
  int _shown = 80;

  static const _pageSize = 80;

  @override
  Widget build(BuildContext context) {
    // New normalized feed: { matchId, innings, items: [...] }. Falls back to
    // legacy shapes so an older payload still renders.
    final source = apiList(widget.data['items'] ??
        widget.data['data'] ??
        widget.data['commentary'] ??
        widget.data['commentaryList']);

    if (kDebugMode) {
      debugPrint('Commentary feed items: ${source.length}');
    }

    final filtered = source.where((item) {
      final row = apiMap(item);
      final type = str(row['type']).toLowerCase();
      final isBall = truthy(row['isBall']) || truthy(row['is_ball']);
      final isWicket = truthy(row['isWicket']) || type == 'wicket';
      final isBoundary =
          truthy(row['isBoundary']) || type == 'four' || type == 'six';
      switch (filter) {
        case 1: // Wickets — only real wicket deliveries.
          return isBall && isWicket;
        case 2: // Boundaries — only real fours/sixes.
          return isBall && isBoundary;
        case 3: // Key Events — trust the server's isKeyEvent flag.
          return truthy(row['isKeyEvent']) || truthy(row['is_key_event']);
        default:
          return true;
      }
    }).toList();

    if (source.isEmpty) {
      final isUpcoming = widget.matchStatus == null ||
          widget.matchStatus!.toLowerCase() == 'upcoming' ||
          widget.matchStatus!.toLowerCase() == 'scheduled' ||
          widget.matchStatus!.toLowerCase() == 'not_started';

      return _MatchDataStateCard(
        icon: Icons.chat_bubble_outline_rounded,
        text: isUpcoming
            ? 'Commentary will appear when the match starts.'
            : 'Commentary is not available from the provider yet.',
      );
    }

    final emptyText = switch (filter) {
      1 => 'No wicket commentary available.',
      2 => 'No boundary commentary available.',
      3 => 'No key events available yet.',
      _ => 'No commentary items match this filter.',
    };

    final visible = filtered.length > _shown ? _shown : filtered.length;
    final hasMore = filtered.length > visible;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ScrollableSegmentedTabs(
          items: const ['All', 'Wickets', 'Boundaries', 'Key Events'],
          selected: filter,
          onChanged: (value) => setState(() {
            filter = value;
            _shown = _pageSize; // reset paging when switching filters
          }),
          height: 44,
        ),
        const SizedBox(height: 12),
        if (filtered.isEmpty)
          _MatchDataStateCard(
              icon: Icons.filter_alt_off_rounded, text: emptyText),
        for (var i = 0; i < visible; i++)
          _CommentaryTimelineItem(
            row: apiMap(filtered[i]),
            isFirst: i == 0,
            isLast: i == visible - 1,
          ),
        if (hasMore)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 4),
            child: MDViewMore(
              label: 'View More Commentary',
              icon: Icons.keyboard_arrow_down_rounded,
              onTap: () => setState(() => _shown += _pageSize),
            ),
          ),
      ],
    );
  }
}

class _OversPanel extends StatelessWidget {
  const _OversPanel({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final overs = apiList(data['overs'] ?? data['over_summary_list']);
    final performance = apiList(data['latest_performance']);
    final recent = apiList(data['recent_overs']);
    if (overs.isEmpty && recent.isEmpty && performance.isEmpty) {
      return const _MatchDataStateCard(
          icon: Icons.sports_cricket_rounded,
          text: 'Over summaries are not available yet.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (overs.isNotEmpty) ...[
          _LastTenOversCard(overs: overs),
          const SizedBox(height: 12),
        ],
        if (recent.isNotEmpty)
          _SectionCard(
            title: 'Recent Balls',
            icon: Icons.timelapse_rounded,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final ball in recent) _BallBubble(label: str(ball))
              ],
            ),
          ),
        if (recent.isNotEmpty) const SizedBox(height: 12),
        for (final item in overs)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _OverCard(row: apiMap(item)),
          ),
      ],
    );
  }
}

/// "Last 10 Overs Summary" header card with Runs / Wickets / Avg + over grid.
class _LastTenOversCard extends StatelessWidget {
  const _LastTenOversCard({required this.overs});

  final List<dynamic> overs;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    // Take the most recent 10 overs (the list is newest-first from the API).
    final recent = overs.take(10).toList();
    var runs = 0;
    var wkts = 0;
    for (final raw in recent) {
      final o = apiMap(raw);
      runs += _num(o['runs']).toInt();
      wkts += apiList(o['balls'])
          .where((b) => truthy(apiMap(b)['isWicket']))
          .length;
    }
    final avg = recent.isEmpty ? 0.0 : runs / recent.length;
    return MDGlassPanel(
      topGlow: true,
      borderAlpha: .35,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.insights_rounded, color: c.cyan, size: 17),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'LAST 10 OVERS SUMMARY',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.text,
                    fontWeight: FontWeight.w900,
                    fontStyle: FontStyle.italic,
                    fontSize: 12.5,
                    letterSpacing: .3,
                  ),
                ),
              ),
              _miniStat(context, 'Runs', '$runs'),
              const SizedBox(width: 10),
              _miniStat(context, 'Wkts', '$wkts'),
              const SizedBox(width: 10),
              _miniStat(context, 'Avg', avg.toStringAsFixed(2)),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final display = recent.reversed.toList();
              const gap = 6.0;
              final n = display.length.clamp(1, 10);
              final w = (constraints.maxWidth - gap * (n - 1)) / n;
              return Row(
                children: [
                  for (var i = 0; i < display.length; i++) ...[
                    if (i != 0) const SizedBox(width: gap),
                    SizedBox(
                      width: w,
                      child: _overChip(context, apiMap(display[i]),
                          highlight: i == display.length - 1),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _miniStat(BuildContext context, String label, String value) {
    final c = context.cric;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(label,
            style: TextStyle(
                color: c.muted, fontWeight: FontWeight.w700, fontSize: 9)),
        Text(value,
            style: TextStyle(
                color: c.cyan, fontWeight: FontWeight.w900, fontSize: 13)),
      ],
    );
  }

  Widget _overChip(BuildContext context, Map<String, dynamic> over,
      {required bool highlight}) {
    final c = context.cric;
    final num = normalizeOversText(str(over['overNumber'] ?? over['over']));
    final overLabel = num.split('.').first;
    final runs = str(over['runs'], fallback: '0');
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: highlight ? c.cyan.withValues(alpha: .14) : Colors.transparent,
        border: Border.all(
          color: highlight
              ? c.cyan.withValues(alpha: .7)
              : c.cyan.withValues(alpha: .15),
        ),
      ),
      child: Column(
        children: [
          Text(overLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: c.muted, fontWeight: FontWeight.w700, fontSize: 10)),
          const SizedBox(height: 2),
          Text(runs,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: c.text, fontWeight: FontWeight.w900, fontSize: 13)),
        ],
      ),
    );
  }
}

