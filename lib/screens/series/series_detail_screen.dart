import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../../app_theme.dart';
import '../../components.dart';
import '../../models.dart';
import '../../models/api_models.dart';
import '../../models/api_response.dart';
import '../../models/cricket_match.dart';
import '../../repositories/cricket_repository.dart';
import '../match_details/match_details_screen.dart' hide apiMap;
import '../teams/team_detail_screen.dart';

class SeriesDetailScreen extends StatefulWidget {
  const SeriesDetailScreen({
    super.key,
    this.initialTab = 0,
    required this.onOpenReminders,
    required this.onOpenCalendar,
    required this.onOpenPlayer,
    this.seriesId = '',
    this.initialSeries,
  });

  final int initialTab;
  final VoidCallback onOpenReminders;
  final VoidCallback onOpenCalendar;
  final VoidCallback onOpenPlayer;
  final String seriesId;
  final ApiSeries? initialSeries;

  @override
  State<SeriesDetailScreen> createState() => _SeriesDetailScreenState();
}

class _SeriesDetailScreenState extends State<SeriesDetailScreen> {
  late int tab = widget.initialTab;
  int squadTeam = 0;
  final CricketRepository _repository = CricketRepository();
  final Map<int, Future<dynamic>> _tabFutures = {};
  String _resolvedSeriesId = '';
  String _resolvedSeriesName = '';

  String _resolveSeriesId() {
    final arg = ModalRoute.of(context)?.settings.arguments;
    if (arg is String && arg.trim().isNotEmpty) return arg.trim();
    if (arg is ApiSeries && arg.id.isNotEmpty) return arg.id;
    if (arg is Map) {
      final id = apiString(arg['seriesId'] ??
          arg['series_id'] ??
          arg['id'] ??
          arg['source_series_id'] ??
          arg['sourceSeriesId']);
      if (id.isNotEmpty) return id;
    }
    if (widget.initialSeries != null && widget.initialSeries!.id.isNotEmpty) {
      return widget.initialSeries!.id;
    }
    return widget.seriesId;
  }

  String _resolveSeriesName() {
    final arg = ModalRoute.of(context)?.settings.arguments;
    if (arg is ApiSeries && arg.name.isNotEmpty) return arg.name;
    if (arg is Map) {
      final name = apiString(arg['seriesName'] ??
          arg['series_name'] ??
          arg['name'] ??
          arg['source_series_name'] ??
          arg['sourceSeriesName'] ??
          arg['title']);
      if (name.isNotEmpty) return cleanText(name);
    }
    if (widget.initialSeries != null && widget.initialSeries!.name.isNotEmpty) {
      return cleanText(widget.initialSeries!.name);
    }
    return '';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextSeriesId = _resolveSeriesId();
    if (nextSeriesId.isNotEmpty && nextSeriesId != _resolvedSeriesId) {
      _resolvedSeriesId = nextSeriesId;
      _resolvedSeriesName = _resolveSeriesName();
      _tabFutures.clear();
      if (kDebugMode) {
        debugPrint(
            'SeriesDetail opened with seriesId=$_resolvedSeriesId seriesName=$_resolvedSeriesName');
      }
      _tabFutures[tab] = _loadTab(tab);
    }
  }

  Future<dynamic> _loadTab(int index, {bool forceRefresh = true}) {
    final id = _resolvedSeriesId;
    return switch (index) {
      0 => Future.wait([
          _repository.seriesDetail(id, forceRefresh: forceRefresh),
          _repository.seriesMatchList(id, forceRefresh: forceRefresh),
        ]),
      1 => _repository.seriesMatchList(id, forceRefresh: forceRefresh),
      2 => Future.wait([
          _repository.seriesTeams(id, forceRefresh: forceRefresh),
          _repository.seriesMatchList(id, forceRefresh: forceRefresh),
        ]),
      _ => Future.wait([
          _repository.pointsTable(id, forceRefresh: forceRefresh),
          _repository.seriesStats(id, forceRefresh: forceRefresh),
        ]),
    };
  }

  void _setTab(int value) {
    setState(() {
      tab = value;
      if (_resolvedSeriesId.isNotEmpty) {
        _tabFutures[value] = _loadTab(value);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: c.bgGradient),
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.fromLTRB(context.horizontalPadding, 18,
                context.horizontalPadding, context.detailBottomPadding),
            children: [
              AppHeader(
                leading: IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.arrow_back_rounded, color: c.text)),
                showLogo: true,
                trailing: const [
                  GlowIconButton(
                      icon: Icons.notifications_none_rounded, badge: '3'),
                  SizedBox(width: 8),
                  GlowIconButton(icon: Icons.more_vert_rounded),
                ],
              ),
              const SizedBox(height: 14),
              // Hero card removed - was showing hardcoded "India vs Australia" mock data
              // Real series info shown in Overview tab from API
              const SizedBox(height: 4),
              SegmentedTabs(
                items: const [
                  ('Overview', null),
                  ('Matches', null),
                  ('Squads', null),
                  ('Stats', null)
                ],
                selected: tab,
                onChanged: _setTab,
                height: 58,
              ),
              const SizedBox(height: 18),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: child,
                ),
                child: KeyedSubtree(
                  key: ValueKey(tab),
                  child: _resolvedSeriesId.isNotEmpty &&
                          _tabFutures[tab] != null
                      ? _SeriesApiPanel(
                          tab: tab,
                          future: _tabFutures[tab]!,
                          seriesId: _resolvedSeriesId,
                          seriesName: _resolvedSeriesName,
                        )
                      : const _SeriesEmptyState(
                          message: 'Please select a series to view details.'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SeriesApiPanel extends StatelessWidget {
  const _SeriesApiPanel({
    required this.tab,
    required this.future,
    required this.seriesId,
    required this.seriesName,
  });

  final int tab;
  final Future<dynamic> future;
  final String seriesId;
  final String seriesName;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<dynamic>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LinearProgressIndicator();
        }
        if (snapshot.hasError) {
          return const _SeriesInfoCard(
            icon: Icons.cloud_off_rounded,
            text:
                'This series section is temporarily unavailable. Pull back and try again.',
          );
        }
        if (tab == 1) {
          final response = snapshot.data as ApiEnvelope<List<CricketMatch>>?;
          final matches = response?.data ?? const <CricketMatch>[];
          if (kDebugMode) {
            debugPrint(
                'SERIES_DETAIL selectedId=$seriesId selectedName=$seriesName matchesCount=${matches.length}');
          }
          if (matches.isEmpty) {
            return const _SeriesInfoCard(
              icon: Icons.event_busy_rounded,
              text: 'No matches are available for this series yet.',
            );
          }
          return _SeriesMatchesPanel(matches: matches);
        }
        if (tab == 2) {
          final responses = snapshot.data as List<dynamic>?;
          final teamsResponse = responses != null && responses.isNotEmpty
              ? responses.first as ApiEnvelope<List<dynamic>>
              : null;
          final matchesResponse = responses != null && responses.length > 1
              ? responses[1] as ApiEnvelope<List<CricketMatch>>
              : null;
          final rawTeams = teamsResponse?.data ?? const [];
          // Defensive filter: drop empty team objects that have neither a
          // teamId nor a teamName. The deployed backend currently returns
          // 10 empty placeholders for some series; this guarantees the UI
          // doesn't render "Team / TEA" placeholder rows even when the
          // API still returns stale empty entries.
          final teams = rawTeams.where((entry) {
            final map = apiMap(entry);
            final id =
                apiString(map['teamId'] ?? map['team_id'] ?? map['id']);
            final name = apiString(
                map['teamName'] ?? map['team_name'] ?? map['name']);
            return id.isNotEmpty || name.isNotEmpty;
          }).toList(growable: false);
          final matches = matchesResponse?.data ?? const <CricketMatch>[];
          final resolvedTeams =
              teams.isNotEmpty ? teams : teamsFromSeriesMatches(matches);
          if (kDebugMode) {
            debugPrint(
                'SERIES_DETAIL selectedId=$seriesId selectedName=$seriesName teamsCount=${resolvedTeams.length} source=${teams.isNotEmpty ? 'teams-endpoint' : 'matches-derived'}');
          }
          if (resolvedTeams.isEmpty) {
            return const _SeriesInfoCard(
              icon: Icons.groups_rounded,
              text: 'Teams and squads are not available yet.',
            );
          }
          return _SeriesTeamsPanel(teams: resolvedTeams);
        }
        if (tab == 3) {
          final responses = snapshot.data as List<dynamic>?;
          final points = responses != null && responses.isNotEmpty
              ? apiMap(
                  (responses.first as ApiEnvelope<Map<String, dynamic>>).data)
              : const <String, dynamic>{};
          final stats = responses != null && responses.length > 1
              ? apiMap((responses[1] as ApiEnvelope<Map<String, dynamic>>).data)
              : const <String, dynamic>{};
          if (kDebugMode) {
            debugPrint(
                'SERIES_DETAIL selectedId=$seriesId selectedName=$seriesName pointsRows=${seriesPointsRows(points).length} battingRows=${seriesStatsRows(stats, 'batting').length} bowlingRows=${seriesStatsRows(stats, 'bowling').length}');
          }
          return _SeriesStatsApiPanel(points: points, stats: stats);
        }
        final responses = snapshot.data as List<dynamic>?;
        final detail = responses != null && responses.isNotEmpty
            ? apiMap(
                (responses.first as ApiEnvelope<Map<String, dynamic>>).data)
            : const <String, dynamic>{};
        final schedule = responses != null && responses.length > 1
            ? (responses[1] as ApiEnvelope<List<CricketMatch>>).data
            : const <CricketMatch>[];
        if (kDebugMode) {
          debugPrint(
              'SERIES_DETAIL selectedId=$seriesId selectedName=$seriesName overviewMatches=${schedule.length}');
        }
        return _SeriesOverviewApiPanel(detail: detail, schedule: schedule);
      },
    );
  }
}

class _SeriesOverviewApiPanel extends StatelessWidget {
  const _SeriesOverviewApiPanel({required this.detail, required this.schedule});

  final Map<String, dynamic> detail;
  final List<CricketMatch> schedule;

  @override
  Widget build(BuildContext context) {
    CricketMatch? next;
    for (final match in schedule) {
      if (match.isLive || match.isUpcoming) {
        next = match;
        break;
      }
    }
    next ??= schedule.isNotEmpty ? schedule.first : null;
    final liveCount = schedule.where((m) => m.isLive).length;
    final upcomingCount = schedule.where((m) => m.isUpcoming).length;
    final completedCount = schedule.where((m) => m.isFinished).length;
    final teamsCount = {
      for (final match in schedule) ...[match.teamA, match.teamB]
    }.where((team) => team.trim().isNotEmpty).length;
    final firstStart = schedule.isNotEmpty ? schedule.first.startDateTime : null;
    final lastStart = schedule.isNotEmpty ? schedule.last.startDateTime : null;
    final formats = {
      for (final match in schedule)
        if (match.matchDesc.trim().isNotEmpty &&
            RegExp(r'\b(Test|ODI|T20I?|Match|Final)\b',
                    caseSensitive: false)
                .hasMatch(match.matchDesc))
          match.matchDesc.trim()
    };
    final detailDateRange = _dateRange(
        detail['startDate'] ??
            detail['start_date'] ??
            detail['startTime'] ??
            detail['start_time'],
        detail['endDate'] ??
            detail['end_date'] ??
            detail['endTime'] ??
            detail['end_time']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PremiumCard(
          padding: const EdgeInsets.all(20),
          gradient: LinearGradient(colors: [
            context.cric.cyan.withValues(alpha: 0.20),
            context.cric.card
          ]),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ChipText(text: apiString(detail['status'], 'Series')),
              const SizedBox(height: 12),
              Text(
                  apiString(
                      detail['name'] ??
                          detail['seriesName'] ??
                          detail['series_name'] ??
                          detail['title'],
                      'Series'),
                  style: TextStyle(
                      color: context.cric.text,
                      fontWeight: FontWeight.w900,
                      fontSize: 24)),
              const SizedBox(height: 10),
              _InfoPairs(rows: {
                'Dates': detailDateRange.isNotEmpty
                    ? detailDateRange
                    : _dateRange(firstStart, lastStart),
                'Format': detail['format'] ??
                    detail['series_type'] ??
                    detail['type'] ??
                    (formats.length <= 4 ? formats.join(', ') : ''),
                'Host': detail['country'] ?? detail['host'] ?? detail['venue'],
                'Matches': _seriesMatchCount(detail, schedule),
                'Teams': teamsCount,
                'Live': liveCount,
                'Upcoming': upcomingCount,
                'Completed': completedCount,
              }),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (next != null)
          _SeriesMatchCard(match: next, title: 'Next match')
        else
          const _SeriesInfoCard(
              icon: Icons.event_busy_rounded,
              text: 'Schedule summary is not available yet.'),
      ],
    );
  }
}

class _SeriesMatchesPanel extends StatelessWidget {
  const _SeriesMatchesPanel({required this.matches});

  final List<CricketMatch> matches;

  @override
  Widget build(BuildContext context) {
    final live =
        matches.where((m) => m.status.toLowerCase().contains('live')).toList();
    final upcoming = matches
        .where((m) =>
            m.status.toLowerCase().contains('upcoming') ||
            m.status.toLowerCase().contains('scheduled'))
        .toList();
    final completed = matches
        .where((m) =>
            m.status.toLowerCase().contains('complete') ||
            m.status.toLowerCase().contains('finish'))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (live.isNotEmpty) _MatchSection(title: 'Live', matches: live),
        if (upcoming.isNotEmpty)
          _MatchSection(title: 'Upcoming', matches: upcoming),
        if (completed.isNotEmpty)
          _MatchSection(title: 'Completed', matches: completed),
        if (live.isEmpty && upcoming.isEmpty && completed.isEmpty)
          _MatchSection(title: 'Matches', matches: matches),
      ],
    );
  }
}

class _MatchSection extends StatelessWidget {
  const _MatchSection({required this.title, required this.matches});

  final String title;
  final List<CricketMatch> matches;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10, top: 4),
            child: Text(title,
                style: TextStyle(
                    color: context.cric.text,
                    fontWeight: FontWeight.w900,
                    fontSize: 18)),
          ),
          for (final match in matches)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _SeriesMatchCard(match: match),
            ),
        ],
      );
}

class _SeriesMatchCard extends StatelessWidget {
  const _SeriesMatchCard({required this.match, this.title});

  final CricketMatch match;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final startText =
        formatMatchDateTime(match.startDateTime ?? match.startTime);
    return PremiumCard(
      onTap: match.id.isEmpty
          ? null
          : () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => MatchDetailsScreen(matchId: match.id))),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(title!,
                style: TextStyle(color: c.cyan, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              TeamBadge(
                TeamInfo(
                  code: match.teamAShort,
                  name: match.teamA,
                  shortName: match.teamAShort,
                  color: c.cyan,
                  asset: match.teamALogo,
                ),
                size: 38,
                borderColor: c.border,
              ),
              const SizedBox(width: 10),
              Expanded(
                  child: Text('${match.teamA} vs ${match.teamB}',
                      style: TextStyle(
                          color: c.text,
                          fontWeight: FontWeight.w900,
                          fontSize: 16))),
              const SizedBox(width: 10),
              TeamBadge(
                TeamInfo(
                  code: match.teamBShort,
                  name: match.teamB,
                  shortName: match.teamBShort,
                  color: c.warning,
                  asset: match.teamBLogo,
                ),
                size: 38,
                borderColor: c.border,
              ),
              const SizedBox(width: 10),
              _ChipText(text: formatStatusChip(match.status)),
            ],
          ),
          const SizedBox(height: 8),
          Text(match.venue,
              style: TextStyle(color: c.muted, fontWeight: FontWeight.w700)),
          if (startText.isNotEmpty)
            Text(startText, style: TextStyle(color: c.muted, fontSize: 12)),
        ],
      ),
    );
  }
}

class _SeriesTeamsPanel extends StatelessWidget {
  const _SeriesTeamsPanel({required this.teams});

  final List<dynamic> teams;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (final item in teams)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _TeamCard(data: apiMap(item)),
            ),
        ],
      );
}

class _TeamCard extends StatelessWidget {
  const _TeamCard({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final id = apiString(data['teamId'] ?? data['team_id'] ?? data['id']);
    final name = apiString(
        data['teamName'] ?? data['team_name'] ?? data['name'], 'Team');
    final short = apiString(
        data['teamShort'] ??
            data['teamShortName'] ??
            data['shortName'] ??
            data['short_name'] ??
            data['team_short'],
        name);
    final team = ApiTeam.fromJson({
      ...data,
      'id': id,
      'name': name,
      'shortName': short,
    });
    final players = apiList(data['players'] ?? data['squad']);
    final subtitle = [
      apiString(data['country']),
      players.isNotEmpty ? '${players.length} players' : '',
    ].where((value) => value.isNotEmpty).join(' • ');
    return PremiumCard(
      onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => TeamDetailScreen(
              teamId: id,
              initialName: name,
              initialShortName: short,
              initialLogoUrl: team.logo,
              sourceSeriesId: apiString(
                  data['seriesId'] ??
                      data['series_id'] ??
                      data['source_series_id'],
                  ''),
            ),
          )),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          TeamBadge(
            TeamInfo(
              code: team.shortName,
              name: team.name,
              shortName: team.shortName,
              color: c.cyan,
              asset: team.logo,
            ),
            size: 46,
            borderColor: c.border,
          ),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.text, fontWeight: FontWeight.w900)),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(subtitle,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: c.muted,
                        fontWeight: FontWeight.w700,
                        fontSize: 12)),
              ],
            ],
          )),
          Icon(Icons.chevron_right_rounded, color: c.muted),
        ],
      ),
    );
  }
}

class _SeriesStatsApiPanel extends StatelessWidget {
  const _SeriesStatsApiPanel({required this.points, required this.stats});

  final Map<String, dynamic> points;
  final Map<String, dynamic> stats;

  @override
  Widget build(BuildContext context) {
    final rows = seriesPointsRows(points);
    final batting = seriesStatsRows(stats, 'batting');
    final bowling = seriesStatsRows(stats, 'bowling');
    final fallbackStats = seriesStatsItems(stats);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PremiumCard(
          padding: const EdgeInsets.all(16),
          child: rows.isEmpty
              ? const _InlineMuted(
                  text: 'Points table is not available for this series.')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Points Table',
                        style: TextStyle(
                            color: context.cric.text,
                            fontWeight: FontWeight.w900,
                            fontSize: 18)),
                    const SizedBox(height: 6),
                    Text('${rows.length} teams',
                        style: TextStyle(
                            color: context.cric.muted,
                            fontWeight: FontWeight.w700,
                            fontSize: 12)),
                    const SizedBox(height: 12),
                    const _PointsTableHeader(),
                    for (final row in rows.take(12))
                      _PointsTableRow(data: apiMap(row)),
                  ],
                ),
        ),
        const SizedBox(height: 12),
        PremiumCard(
          padding: const EdgeInsets.all(16),
          child: batting.isEmpty && bowling.isEmpty && fallbackStats.isEmpty
              ? const _InlineMuted(text: 'Series stats are not available yet.')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (batting.isNotEmpty) ...[
                      _StatsSection(title: 'Top Run Scorers', rows: batting),
                      if (bowling.isNotEmpty) const SizedBox(height: 16),
                    ],
                    if (bowling.isNotEmpty) ...[
                      _StatsSection(title: 'Top Wicket Takers', rows: bowling),
                    ],
                    if (batting.isEmpty && bowling.isEmpty)
                      _StatsSection(title: 'Series Stats', rows: fallbackStats),
                  ],
                ),
        ),
      ],
    );
  }
}

class _PointsTableHeader extends StatelessWidget {
  const _PointsTableHeader();

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(width: 28, child: Text('#', style: _headerStyle(c))),
          Expanded(flex: 3, child: Text('Team', style: _headerStyle(c))),
          for (final label in const ['P', 'W', 'L', 'NR', 'Pts', 'NRR'])
            Expanded(
              child: Text(label,
                  textAlign: TextAlign.center, style: _headerStyle(c)),
            ),
        ],
      ),
    );
  }

  TextStyle _headerStyle(CricColors c) =>
      TextStyle(color: c.muted, fontWeight: FontWeight.w900, fontSize: 11);
}

class _PointsTableRow extends StatelessWidget {
  const _PointsTableRow({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final teamName =
        apiString(data['teamName'] ?? data['team'] ?? data['name'], 'Team');
    final short = apiString(
        data['teamShort'] ??
            data['teamShortName'] ??
            data['shortName'] ??
            data['short_name'],
        teamName);
    final team = ApiTeam.fromJson({
      ...data,
      'name': teamName,
      'shortName': short,
    });
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        border:
            Border(top: BorderSide(color: c.border.withValues(alpha: 0.45))),
      ),
      child: Row(
        children: [
          SizedBox(
              width: 28,
              child: Text(apiString(data['position'] ?? data['rank'], '-'),
                  style: TextStyle(
                      color: c.text,
                      fontWeight: FontWeight.w900,
                      fontSize: 12))),
          Expanded(
            flex: 3,
            child: Row(
              children: [
                TeamBadge(
                  TeamInfo(
                      code: team.shortName,
                      name: team.name,
                      shortName: team.shortName,
                      color: c.cyan,
                      asset: team.logo),
                  size: 28,
                  borderColor: c.border,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    short,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: c.text,
                        fontWeight: FontWeight.w900,
                        fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          for (final value in [
            data['played'] ?? data['matches'],
            data['won'],
            data['lost'],
            data['noResult'] ?? data['nr'],
            data['points'],
            data['nrr'],
          ])
            Expanded(
              child: Text(apiString(value, '-'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: c.text,
                      fontWeight: FontWeight.w800,
                      fontSize: 11)),
            ),
        ],
      ),
    );
  }
}

class _StatsSection extends StatelessWidget {
  const _StatsSection({required this.title, required this.rows});

  final String title;
  final List<dynamic> rows;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title,
            style: TextStyle(
                color: c.text, fontWeight: FontWeight.w900, fontSize: 18)),
        const SizedBox(height: 10),
        for (final item in rows.take(8)) _PlayerStatRow(data: apiMap(item)),
      ],
    );
  }
}

class _PlayerStatRow extends StatelessWidget {
  const _PlayerStatRow({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final name = apiString(data['playerName'] ?? data['name'], 'Player');
    final image = apiString(data['imageUrl'] ?? data['image_url']);
    final value = apiString(data['runs'] ?? data['wickets'] ?? data['value']);
    final sub = [
      if (apiString(data['matches']).isNotEmpty) '${data['matches']} matches',
      if (apiString(data['average']).isNotEmpty) 'Avg ${data['average']}',
      if (apiString(data['strikeRate'] ?? data['economy']).isNotEmpty)
        apiString(data['strikeRate']).isNotEmpty
            ? 'SR ${data['strikeRate']}'
            : 'Eco ${data['economy']}',
    ].join(' • ');
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border:
            Border(top: BorderSide(color: c.border.withValues(alpha: 0.45))),
      ),
      child: Row(
        children: [
          _NetworkAvatar(imageUrl: image, label: name),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(color: c.text, fontWeight: FontWeight.w900)),
                if (sub.isNotEmpty)
                  Text(sub,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: c.muted,
                          fontWeight: FontWeight.w700,
                          fontSize: 12)),
              ],
            ),
          ),
          if (value.isNotEmpty)
            Text(value,
                style: TextStyle(
                    color: c.cyan, fontWeight: FontWeight.w900, fontSize: 16)),
        ],
      ),
    );
  }
}

class _NetworkAvatar extends StatelessWidget {
  const _NetworkAvatar({required this.imageUrl, required this.label});

  final String imageUrl;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      width: 38,
      height: 38,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: c.cyan.withValues(alpha: 0.16),
        border: Border.all(color: c.border),
      ),
      child: imageUrl.isEmpty
          ? _fallback(c)
          : Image.network(
              imageUrl,
              fit: BoxFit.cover,
              webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
              errorBuilder: (_, __, ___) => _fallback(c),
            ),
    );
  }

  Widget _fallback(CricColors c) => Center(
        child: Text(
          safeTeamInitials(label),
          style: TextStyle(
              color: c.text, fontWeight: FontWeight.w900, fontSize: 12),
        ),
      );
}

class _InfoPairs extends StatelessWidget {
  const _InfoPairs({required this.rows});

  final Map<String, dynamic> rows;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final visible = rows.entries
        .where((entry) => apiString(entry.value).isNotEmpty)
        .toList();
    if (visible.isEmpty) {
      return const _InlineMuted(text: 'Details are not available yet.');
    }
    return Column(
      children: [
        for (final entry in visible)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                SizedBox(
                    width: 92,
                    child: Text(entry.key,
                        style: TextStyle(
                            color: c.muted, fontWeight: FontWeight.w800))),
                Expanded(
                    child: Text(apiString(entry.value),
                        style: TextStyle(
                            color: c.text, fontWeight: FontWeight.w800))),
              ],
            ),
          ),
      ],
    );
  }
}

class _InlineMuted extends StatelessWidget {
  const _InlineMuted({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Text(text,
      style: TextStyle(color: context.cric.muted, fontWeight: FontWeight.w700));
}

class _ChipText extends StatelessWidget {
  const _ChipText({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
          color: c.cyan.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: c.cyan.withValues(alpha: 0.28))),
      child: Text(text.isEmpty ? 'Unknown' : text,
          style: TextStyle(
              color: c.cyan, fontWeight: FontWeight.w900, fontSize: 11)),
    );
  }
}

String _dateRange(dynamic start, dynamic end) {
  final left = formatMatchDateTime(start);
  final right = formatMatchDateTime(end);
  if (left.isEmpty && right.isEmpty) return '';
  if (right.isEmpty) return left;
  if (left.isEmpty) return right;
  return '$left - $right';
}

int _seriesMatchCount(
    Map<String, dynamic> detail, List<CricketMatch> schedule) {
  final explicit =
      apiInt(detail['matchCount']) ?? apiInt(detail['totalMatches']);
  if (explicit != null && explicit > 0) return explicit;
  final matches = apiList(detail['matches']);
  if (matches.isNotEmpty) return matches.length;
  return schedule.length;
}

List<dynamic> seriesPointsRows(Map<String, dynamic> value) {
  final root = _seriesPayload(value);
  final groups = apiList(root['groups'] ?? root['pointsTable'] ?? value['groups']);
  final rows = <dynamic>[];
  for (final group in groups) {
    final map = apiMap(group);
    rows.addAll(apiList(map['rows'] ??
        map['pointsTableInfo'] ??
        map['teams'] ??
        map['table'] ??
        map['items']));
  }
  if (rows.isNotEmpty) return rows;
  final direct = apiList(root['rows'] ?? root['table'] ?? root['items']);
  if (direct.isNotEmpty) return direct;
  return rows;
}

List<dynamic> seriesStatsRows(Map<String, dynamic> value, String key) {
  final root = _seriesPayload(value);
  final section = apiMap(root[key]);
  final direct =
      apiList(section['rows'] ?? section['items'] ?? section['players']);
  if (direct.isNotEmpty) return direct;
  return apiList(
      root['rows'] ?? root['items'] ?? root['players'] ?? root['data']);
}

List<dynamic> seriesStatsItems(Map<String, dynamic> value) {
  final root = _seriesPayload(value);
  final direct =
      apiList(root['items'] ?? root['stats'] ?? root['topRunScorers']);
  if (direct.isNotEmpty) return direct;
  return apiList(root['data']);
}

List<Map<String, dynamic>> teamsFromSeriesMatches(List<CricketMatch> matches) {
  final teams = <String, Map<String, dynamic>>{};
  void addTeam({
    required String name,
    required String shortName,
    required String? logoUrl,
  }) {
    final cleanName = name.trim();
    final cleanShort = shortName.trim();
    final key = cleanName.isNotEmpty ? cleanName : cleanShort;
    if (key.isEmpty || teams.containsKey(key)) return;
    teams[key] = {
      'name': cleanName.isNotEmpty ? cleanName : cleanShort,
      'shortName': cleanShort.isNotEmpty ? cleanShort : safeTeamInitials(key),
      'logoUrl': logoUrl,
    };
  }

  for (final match in matches) {
    addTeam(
      name: match.teamA,
      shortName: match.teamAShort,
      logoUrl: match.teamALogo,
    );
    addTeam(
      name: match.teamB,
      shortName: match.teamBShort,
      logoUrl: match.teamBLogo,
    );
  }
  return teams.values.toList();
}

Map<String, dynamic> _seriesPayload(Map<String, dynamic> value) {
  final data = apiMap(value['data']);
  if (data.isNotEmpty) return data;
  return value;
}

class _SeriesInfoCard extends StatelessWidget {
  const _SeriesInfoCard({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      padding: const EdgeInsets.all(16),
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

class _SeriesEmptyState extends StatelessWidget {
  const _SeriesEmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(Icons.emoji_events_outlined, color: c.cyan, size: 64),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: c.muted, fontWeight: FontWeight.w700, fontSize: 16),
          ),
        ],
      ),
    );
  }
}
