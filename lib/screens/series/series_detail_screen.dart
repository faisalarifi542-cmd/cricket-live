import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'package:cricpro_flutter/app_theme.dart';
import 'package:cricpro_flutter/api_models.dart';
import 'package:cricpro_flutter/components.dart';
import 'package:cricpro_flutter/models.dart';
import 'package:cricpro_flutter/models/api_response.dart';
import 'package:cricpro_flutter/models/cricket_match.dart';
import 'package:cricpro_flutter/repositories/cricket_repository.dart';
import 'package:cricpro_flutter/screens/match_details/match_details_screen.dart' hide apiMap;
import 'package:cricpro_flutter/screens/teams/team_detail_screen.dart';
import 'package:cricpro_flutter/widgets/squad.dart';

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
    final teamSet = <String>{
      for (final match in schedule) ...[match.teamA, match.teamB]
    }..removeWhere((team) => team.trim().isEmpty);
    final teamsCount = teamSet.length;
    final firstStart =
        schedule.isNotEmpty ? schedule.first.startDateTime : null;
    final lastStart =
        schedule.isNotEmpty ? schedule.last.startDateTime : null;
    final formatLabels = <String>{
      for (final match in schedule)
        if (match.matchDesc.trim().isNotEmpty &&
            RegExp(r'\b(Test|ODI|T20I?|Match|Final)\b', caseSensitive: false)
                .hasMatch(match.matchDesc))
          match.matchDesc.trim()
    };
    final venueSet = <String>{
      for (final match in schedule) match.venue.trim()
    }..removeWhere((v) => v.isEmpty);
    final detailDateRange = _dateRange(
        detail['startDate'] ??
            detail['start_date'] ??
            detail['startTime'] ??
            detail['start_time'],
        detail['endDate'] ??
            detail['end_date'] ??
            detail['endTime'] ??
            detail['end_time']);
    final scheduleDateRange = _dateRange(firstStart, lastStart);
    final dateRange =
        detailDateRange.isNotEmpty ? detailDateRange : scheduleDateRange;
    final seriesName = apiString(
        detail['name'] ??
            detail['seriesName'] ??
            detail['series_name'] ??
            detail['title'],
        'Series');
    final status = apiString(detail['status']);
    final format = apiString(detail['format'] ??
        detail['series_type'] ??
        detail['type'] ??
        (formatLabels.length <= 4 ? formatLabels.join(', ') : ''));
    final host = apiString(detail['country'] ?? detail['host']);
    final totalMatches = _seriesMatchCount(detail, schedule);
    final bilateralTeams = _bilateralTeams(schedule, teamSet);
    final topTeams =
        _topTeams(schedule, teamSet, exclude: bilateralTeams ?? const []);
    final formatChips = formatLabels.isNotEmpty
        ? formatLabels.toList()
        : (format.isNotEmpty ? [format] : const <String>[]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SeriesHero(
          name: seriesName,
          status: status,
          dateRange: dateRange,
          formats: formatChips,
          teams: bilateralTeams,
        ),
        const SizedBox(height: 14),
        _SeriesInfoGrid(items: [
          if (format.isNotEmpty)
            _InfoItem(Icons.style_rounded, 'Format', format),
          if (host.isNotEmpty)
            _InfoItem(Icons.public_rounded, 'Host', host),
          if (firstStart != null)
            _InfoItem(Icons.calendar_today_rounded, 'Start Date',
                formatMatchDateTime(firstStart)),
          if (lastStart != null)
            _InfoItem(Icons.event_available_rounded, 'End Date',
                formatMatchDateTime(lastStart)),
          if (totalMatches > 0)
            _InfoItem(Icons.sports_cricket_rounded, 'Total Matches',
                totalMatches.toString()),
          if (teamsCount > 0)
            _InfoItem(Icons.groups_rounded, 'Teams', teamsCount.toString()),
          if (status.isNotEmpty)
            _InfoItem(Icons.bolt_rounded, 'Status', status),
        ]),
        const SizedBox(height: 14),
        _SeriesCountStrip(
          live: liveCount,
          upcoming: upcomingCount,
          completed: completedCount,
        ),
        const SizedBox(height: 14),
        if (next != null) _SeriesMatchCard(match: next, title: 'Next Match'),
        if (next == null)
          const _SeriesInfoCard(
              icon: Icons.event_busy_rounded,
              text: 'Schedule summary is not available yet.'),
        if (venueSet.isNotEmpty) ...[
          const SizedBox(height: 14),
          _SeriesVenuesCard(venues: venueSet.toList()),
        ],
        if (topTeams.isNotEmpty) ...[
          const SizedBox(height: 14),
          _SeriesTopTeamsCard(teams: topTeams),
        ],
      ],
    );
  }
}

class _SeriesHero extends StatelessWidget {
  const _SeriesHero({
    required this.name,
    required this.status,
    required this.dateRange,
    required this.formats,
    required this.teams,
  });

  final String name;
  final String status;
  final String dateRange;
  final List<String> formats;
  final List<CricketMatch>? teams;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            c.cyan.withValues(alpha: .22),
            c.card,
            c.card2,
          ],
        ),
        border: Border.all(color: c.cyan.withValues(alpha: .55), width: 1.4),
        boxShadow: [
          BoxShadow(
              color: c.cyan.withValues(alpha: .18),
              blurRadius: 28,
              offset: const Offset(0, 10)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Stack(
          children: [
            Positioned(
              right: -50,
              bottom: -30,
              child: Icon(Icons.stadium_rounded,
                  size: 200, color: c.cyan.withValues(alpha: .06)),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (status.isNotEmpty) _ChipText(text: status),
                  if (teams != null && teams!.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    _BilateralTeamsHeader(teams: teams!),
                  ],
                  const SizedBox(height: 14),
                  Text(
                    name,
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    softWrap: true,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: c.text,
                        fontWeight: FontWeight.w900,
                        fontSize: 22,
                        height: 1.15),
                  ),
                  if (dateRange.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.calendar_today_rounded,
                            color: c.cyan, size: 14),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            dateRange,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: c.muted, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (formats.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final f in formats.take(4))
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: c.cyan.withValues(alpha: .14),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                  color: c.cyan.withValues(alpha: .35)),
                            ),
                            child: Text(f,
                                style: TextStyle(
                                    color: c.cyan,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 11)),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BilateralTeamsHeader extends StatelessWidget {
  const _BilateralTeamsHeader({required this.teams});

  final List<CricketMatch> teams;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final match = teams.first;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _HeroTeam(name: match.teamA, short: match.teamAShort, logo: match.teamALogo),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: c.card2,
              border: Border.all(color: c.cyan.withValues(alpha: .5)),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text('VS',
                style: TextStyle(
                    color: c.cyan,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                    letterSpacing: 1)),
          ),
        ),
        _HeroTeam(name: match.teamB, short: match.teamBShort, logo: match.teamBLogo),
      ],
    );
  }
}

class _HeroTeam extends StatelessWidget {
  const _HeroTeam({required this.name, required this.short, required this.logo});

  final String name;
  final String short;
  final String? logo;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return SizedBox(
      width: 96,
      child: Column(
        children: [
          TeamBadge(
            TeamInfo(
              code: short,
              name: name,
              shortName: short,
              color: c.cyan,
              asset: logo,
            ),
            size: 56,
            borderColor: c.cyan.withValues(alpha: .5),
          ),
          const SizedBox(height: 8),
          Text(
            short.isNotEmpty ? short : safeTeamInitials(name),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: c.text, fontWeight: FontWeight.w900, fontSize: 14),
          ),
          if (name.isNotEmpty)
            Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: c.muted,
                  fontWeight: FontWeight.w700,
                  fontSize: 10),
            ),
        ],
      ),
    );
  }
}

class _InfoItem {
  const _InfoItem(this.icon, this.label, this.value);
  final IconData icon;
  final String label;
  final String value;
}

class _SeriesInfoGrid extends StatelessWidget {
  const _SeriesInfoGrid({required this.items});

  final List<_InfoItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final c = context.cric;
    return PremiumCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.info_outline_rounded, color: c.cyan, size: 20),
            const SizedBox(width: 8),
            Text('SERIES INFO',
                style: TextStyle(
                    color: c.text,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    letterSpacing: .5)),
          ]),
          const SizedBox(height: 14),
          LayoutBuilder(builder: (context, constraints) {
            final cols = constraints.maxWidth >= 520 ? 3 : 2;
            final tileWidth =
                (constraints.maxWidth - (cols - 1) * 10) / cols;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final item in items)
                  SizedBox(
                      width: tileWidth, child: _InfoItemTile(item: item)),
              ],
            );
          }),
        ],
      ),
    );
  }
}

class _InfoItemTile extends StatelessWidget {
  const _InfoItemTile({required this.item});

  final _InfoItem item;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.card2.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border.withValues(alpha: .65)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(item.icon, color: c.cyan, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  item.label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: c.muted,
                      fontWeight: FontWeight.w800,
                      fontSize: 10,
                      letterSpacing: .4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(item.value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              softWrap: true,
              style: TextStyle(
                  color: c.text, fontWeight: FontWeight.w900, fontSize: 13)),
        ],
      ),
    );
  }
}

class _SeriesCountStrip extends StatelessWidget {
  const _SeriesCountStrip(
      {required this.live,
      required this.upcoming,
      required this.completed});

  final int live;
  final int upcoming;
  final int completed;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    if (live == 0 && upcoming == 0 && completed == 0) {
      return const SizedBox.shrink();
    }
    return Row(
      children: [
        Expanded(
            child: _CountTile(
                value: live,
                label: 'Live',
                color: c.live,
                icon: Icons.flash_on_rounded)),
        const SizedBox(width: 10),
        Expanded(
            child: _CountTile(
                value: upcoming,
                label: 'Upcoming',
                color: c.cyan,
                icon: Icons.upcoming_rounded)),
        const SizedBox(width: 10),
        Expanded(
            child: _CountTile(
                value: completed,
                label: 'Completed',
                color: c.success,
                icon: Icons.task_alt_rounded)),
      ],
    );
  }
}

class _CountTile extends StatelessWidget {
  const _CountTile({
    required this.value,
    required this.label,
    required this.color,
    required this.icon,
  });

  final int value;
  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: c.card.withValues(alpha: .65),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: .35)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 6),
          Text(value.toString(),
              style: TextStyle(
                  color: c.text,
                  fontWeight: FontWeight.w900,
                  fontSize: 22)),
          const SizedBox(height: 2),
          Text(label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: c.muted,
                  fontWeight: FontWeight.w800,
                  fontSize: 10,
                  letterSpacing: .4)),
        ],
      ),
    );
  }
}

class _SeriesVenuesCard extends StatelessWidget {
  const _SeriesVenuesCard({required this.venues});

  final List<String> venues;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.location_on_rounded, color: c.cyan, size: 20),
            const SizedBox(width: 8),
            Text('VENUES',
                style: TextStyle(
                    color: c.text,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    letterSpacing: .5)),
          ]),
          const SizedBox(height: 12),
          for (final v in venues.take(6))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.place_rounded, color: c.cyan, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(v,
                        softWrap: true,
                        style: TextStyle(
                            color: c.text,
                            fontWeight: FontWeight.w800,
                            fontSize: 13)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SeriesTopTeamsCard extends StatelessWidget {
  const _SeriesTopTeamsCard({required this.teams});

  final List<Map<String, dynamic>> teams;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.groups_rounded, color: c.cyan, size: 20),
            const SizedBox(width: 8),
            Text('PARTICIPATING TEAMS',
                style: TextStyle(
                    color: c.text,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    letterSpacing: .5)),
          ]),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final team in teams.take(12))
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: c.card2.withValues(alpha: .55),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                        color: c.cyan.withValues(alpha: .25)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TeamBadge(
                        TeamInfo(
                          code: apiString(team['shortName']),
                          name: apiString(team['name']),
                          shortName: apiString(team['shortName']),
                          color: c.cyan,
                          asset: team['logoUrl'] as String?,
                        ),
                        size: 22,
                        borderColor: c.border,
                      ),
                      const SizedBox(width: 8),
                      Text(
                          apiString(team['shortName']).isNotEmpty
                              ? apiString(team['shortName'])
                              : apiString(team['name']),
                          style: TextStyle(
                              color: c.text,
                              fontWeight: FontWeight.w900,
                              fontSize: 11)),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

List<CricketMatch>? _bilateralTeams(
    List<CricketMatch> schedule, Set<String> teamSet) {
  if (teamSet.length != 2 || schedule.isEmpty) return null;
  return [schedule.first];
}

List<Map<String, dynamic>> _topTeams(
    List<CricketMatch> schedule, Set<String> teamSet,
    {required Iterable exclude}) {
  if (teamSet.length <= 2) return const [];
  return teamsFromSeriesMatches(schedule);
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
            Row(
              children: [
                Text(
                  title!,
                  style: TextStyle(
                      color: c.cyan, fontWeight: FontWeight.w900, fontSize: 13),
                ),
                const Spacer(),
                _ChipText(text: formatStatusChip(match.status)),
              ],
            ),
            const SizedBox(height: 8),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              TeamBadge(
                TeamInfo(
                  code: match.teamAShort,
                  name: match.teamA,
                  shortName: match.teamAShort,
                  color: c.cyan,
                  asset: match.teamALogo,
                ),
                size: 42,
                borderColor: c.border,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${match.teamA} vs ${match.teamB}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: c.text,
                          fontWeight: FontWeight.w900,
                          fontSize: 15.5),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      match.venue,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: c.muted,
                          fontWeight: FontWeight.w700,
                          fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              TeamBadge(
                TeamInfo(
                  code: match.teamBShort,
                  name: match.teamB,
                  shortName: match.teamBShort,
                  color: c.warning,
                  asset: match.teamBLogo,
                ),
                size: 42,
                borderColor: c.border,
              ),
            ],
          ),
          if (startText.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(startText, style: TextStyle(color: c.muted, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}

class _SeriesTeamsPanel extends StatelessWidget {
  const _SeriesTeamsPanel({required this.teams});

  final List<dynamic> teams;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final items = teams.map(apiMap).where((m) => m.isNotEmpty).toList();
    if (items.isEmpty) {
      return const _SeriesInfoCard(
        icon: Icons.groups_rounded,
        text: 'Teams and squads are not available yet.',
      );
    }
    final hasInlineSquads = items.any((data) =>
        apiList(data['players']).isNotEmpty ||
        apiList(data['squad']).isNotEmpty);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10, left: 4),
          child: Row(
            children: [
              Icon(Icons.groups_rounded, color: c.cyan, size: 18),
              const SizedBox(width: 8),
              Text('TEAMS (${items.length})',
                  style: TextStyle(
                      color: c.text,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      letterSpacing: .5)),
            ],
          ),
        ),
        if (hasInlineSquads)
          _SeriesInlineSquads(items: items)
        else
          LayoutBuilder(builder: (context, constraints) {
            final cols = constraints.maxWidth >= 520 ? 2 : 1;
            final tileWidth =
                (constraints.maxWidth - (cols - 1) * 10) / cols;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final data in items)
                  SizedBox(
                      width: tileWidth, child: _TeamCard(data: data)),
              ],
            );
          }),
      ],
    );
  }
}

class _SeriesInlineSquads extends StatefulWidget {
  const _SeriesInlineSquads({required this.items});

  final List<Map<String, dynamic>> items;

  @override
  State<_SeriesInlineSquads> createState() => _SeriesInlineSquadsState();
}

class _SeriesInlineSquadsState extends State<_SeriesInlineSquads> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final teams = widget.items;
    if (teams.isEmpty) return const SizedBox.shrink();
    final selected = _selected.clamp(0, teams.length - 1);
    final current = teams[selected];
    final players = apiList(current['players'] ?? current['squad']);
    final bench = apiList(current['bench'] ?? current['reserve']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ScrollableSegmentedTabs(
          items: [
            for (final t in teams)
              apiString(t['teamShort'] ??
                  t['teamShortName'] ??
                  t['shortName'] ??
                  t['short_name'] ??
                  t['teamName'] ??
                  t['name']),
          ],
          selected: selected,
          onChanged: (value) => setState(() => _selected = value),
          height: 44,
        ),
        const SizedBox(height: 14),
        _TeamCard(data: current),
        const SizedBox(height: 12),
        PremiumSquad(playingXi: players, bench: bench, title: 'Squad'),
      ],
    );
  }
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
              initialSquad: players,
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
