import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../components.dart';
import '../../models/api_models.dart';
import '../../models/api_response.dart';
import '../../models/cricket_match.dart';
import '../../repositories/cricket_repository.dart';
import '../../screens.dart';
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
  });

  final int initialTab;
  final VoidCallback onOpenReminders;
  final VoidCallback onOpenCalendar;
  final VoidCallback onOpenPlayer;
  final String seriesId;

  @override
  State<SeriesDetailScreen> createState() => _SeriesDetailScreenState();
}

class _SeriesDetailScreenState extends State<SeriesDetailScreen> {
  late int tab = widget.initialTab;
  int squadTeam = 0;
  final CricketRepository _repository = CricketRepository();
  final Map<int, Future<dynamic>> _tabFutures = {};

  String get _seriesId {
    final arg = ModalRoute.of(context)?.settings.arguments;
    if (arg is String && arg.isNotEmpty) return arg;
    return widget.seriesId;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_seriesId.isNotEmpty) {
      _tabFutures.putIfAbsent(tab, () => _loadTab(tab));
    }
  }

  Future<dynamic> _loadTab(int index, {bool forceRefresh = false}) {
    final id = _seriesId;
    return switch (index) {
      0 => Future.wait([
          _repository.seriesDetail(id, forceRefresh: forceRefresh),
          _repository.seriesSchedule(id, forceRefresh: forceRefresh),
        ]),
      1 => _repository.seriesMatchList(id, forceRefresh: forceRefresh),
      2 => _repository.seriesTeams(id, forceRefresh: forceRefresh),
      _ => Future.wait([
          _repository.pointsTable(id, forceRefresh: forceRefresh),
          _repository.seriesStats(id, forceRefresh: forceRefresh),
        ]),
    };
  }

  void _setTab(int value) {
    setState(() {
      tab = value;
      if (_seriesId.isNotEmpty) _tabFutures.putIfAbsent(value, () => _loadTab(value));
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
                trailing: [
                  GlowIconButton(
                      icon: Icons.notifications_none_rounded, badge: '3'),
                  const SizedBox(width: 8),
                  GlowIconButton(icon: Icons.more_vert_rounded),
                ],
              ),
              const SizedBox(height: 14),
              const SeriesHeroCard(),
              const SizedBox(height: 16),
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
                  child: _seriesId.isNotEmpty && _tabFutures[tab] != null
                      ? _SeriesApiPanel(tab: tab, future: _tabFutures[tab]!)
                      : switch (tab) {
                          0 => SeriesOverviewTab(onOpenReminder: widget.onOpenReminders),
                          1 => SeriesMatchesTab(onOpenCalendar: widget.onOpenCalendar),
                          2 => SeriesSquadsTab(
                              squadTeam: squadTeam,
                              onTeamChanged: (v) => setState(() => squadTeam = v),
                              onOpenPlayer: widget.onOpenPlayer,
                            ),
                          _ => const SeriesStatsTab(),
                        },
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
  const _SeriesApiPanel({required this.tab, required this.future});

  final int tab;
  final Future<dynamic> future;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<dynamic>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LinearProgressIndicator();
        }
        if (snapshot.hasError) {
          return _SeriesInfoCard(
            icon: Icons.cloud_off_rounded,
            text: 'This series section is temporarily unavailable. Pull back and try again.',
          );
        }
        if (tab == 1) {
          final response = snapshot.data as ApiEnvelope<List<CricketMatch>>?;
          final matches = response?.data ?? const <CricketMatch>[];
          if (matches.isEmpty) {
            return const _SeriesInfoCard(
              icon: Icons.event_busy_rounded,
              text: 'No matches are available for this series yet.',
            );
          }
          return _SeriesMatchesPanel(matches: matches);
        }
        if (tab == 2) {
          final response = snapshot.data as ApiEnvelope<List<dynamic>>?;
          final teams = response?.data ?? const [];
          if (teams.isEmpty) {
            return const _SeriesInfoCard(
              icon: Icons.groups_rounded,
              text: 'Teams and squads are not available yet.',
            );
          }
          return _SeriesTeamsPanel(teams: teams);
        }
        if (tab == 3) {
          final responses = snapshot.data as List<dynamic>?;
          final points = responses != null && responses.isNotEmpty ? apiMap((responses.first as ApiEnvelope<Map<String, dynamic>>).data) : const <String, dynamic>{};
          final stats = responses != null && responses.length > 1 ? apiMap((responses[1] as ApiEnvelope<Map<String, dynamic>>).data) : const <String, dynamic>{};
          return _SeriesStatsApiPanel(points: points, stats: stats);
        }
        final responses = snapshot.data as List<dynamic>?;
        final detail = responses != null && responses.isNotEmpty ? apiMap((responses.first as ApiEnvelope<Map<String, dynamic>>).data) : const <String, dynamic>{};
        final schedule = responses != null && responses.length > 1 ? (responses[1] as ApiEnvelope<List<CricketMatch>>).data : const <CricketMatch>[];
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
    final next = schedule.isEmpty ? null : schedule.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PremiumCard(
          padding: const EdgeInsets.all(20),
          gradient: LinearGradient(colors: [context.cric.cyan.withOpacity(0.20), context.cric.card]),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ChipText(text: apiString(detail['status'], 'Series')),
              const SizedBox(height: 12),
              Text(apiString(detail['name'] ?? detail['seriesName'], 'Series'), style: TextStyle(color: context.cric.text, fontWeight: FontWeight.w900, fontSize: 24)),
              const SizedBox(height: 10),
              _InfoPairs(rows: {
                'Dates': _dateRange(detail['startDate'] ?? detail['start_date'], detail['endDate'] ?? detail['end_date']),
                'Format': detail['format'] ?? detail['series_type'],
                'Host': detail['country'] ?? detail['host'],
                'Matches': detail['matchCount'] ?? detail['totalMatches'] ?? schedule.length,
              }),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (next != null)
          _SeriesMatchCard(match: next, title: 'Next match')
        else
          const _SeriesInfoCard(icon: Icons.event_busy_rounded, text: 'Schedule summary is not available yet.'),
      ],
    );
  }
}

class _SeriesMatchesPanel extends StatelessWidget {
  const _SeriesMatchesPanel({required this.matches});

  final List<CricketMatch> matches;

  @override
  Widget build(BuildContext context) {
    final live = matches.where((m) => m.status.toLowerCase().contains('live')).toList();
    final upcoming = matches.where((m) => m.status.toLowerCase().contains('upcoming') || m.status.toLowerCase().contains('scheduled')).toList();
    final completed = matches.where((m) => m.status.toLowerCase().contains('complete') || m.status.toLowerCase().contains('finish')).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (live.isNotEmpty) _MatchSection(title: 'Live', matches: live),
        if (upcoming.isNotEmpty) _MatchSection(title: 'Upcoming', matches: upcoming),
        if (completed.isNotEmpty) _MatchSection(title: 'Completed', matches: completed),
        if (live.isEmpty && upcoming.isEmpty && completed.isEmpty) _MatchSection(title: 'Matches', matches: matches),
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
            child: Text(title, style: TextStyle(color: context.cric.text, fontWeight: FontWeight.w900, fontSize: 18)),
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
    return PremiumCard(
      onTap: match.id.isEmpty ? null : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => MatchDetailsScreen(matchId: match.id))),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(title!, style: TextStyle(color: c.cyan, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Expanded(child: Text('${match.teamA} vs ${match.teamB}', style: TextStyle(color: c.text, fontWeight: FontWeight.w900, fontSize: 16))),
              _ChipText(text: match.status),
            ],
          ),
          const SizedBox(height: 8),
          Text(match.venue, style: TextStyle(color: c.muted, fontWeight: FontWeight.w700)),
          if (match.startTime.isNotEmpty) Text(match.startTime, style: TextStyle(color: c.muted, fontSize: 12)),
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
    final id = apiString(data['teamId'] ?? data['id']);
    final name = apiString(data['teamName'] ?? data['name'], 'Team');
    final short = apiString(data['teamShort'] ?? data['shortName'], name);
    return PremiumCard(
      onTap: id.isEmpty ? null : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TeamDetailScreen(teamId: id))),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          CircleAvatar(backgroundColor: c.card2, child: Text(short.characters.take(2).toString(), style: TextStyle(color: c.text, fontWeight: FontWeight.w900))),
          const SizedBox(width: 12),
          Expanded(child: Text(name, style: TextStyle(color: c.text, fontWeight: FontWeight.w900))),
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
    final rows = apiList(points['rows'] ?? points['pointsTable'] ?? points['table']);
    final statItems = apiList(stats['items'] ?? stats['stats'] ?? stats['topRunScorers']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PremiumCard(
          padding: const EdgeInsets.all(16),
          child: rows.isEmpty
              ? const _InlineMuted(text: 'Points table is not available for this series.')
              : Column(children: [for (final row in rows.take(12)) _InfoPairs(rows: {'Team': apiMap(row)['teamName'] ?? apiMap(row)['team'], 'Pts': apiMap(row)['points'], 'NRR': apiMap(row)['nrr']})]),
        ),
        const SizedBox(height: 12),
        PremiumCard(
          padding: const EdgeInsets.all(16),
          child: statItems.isEmpty
              ? const _InlineMuted(text: 'Series stats are not available yet.')
              : Column(children: [for (final item in statItems.take(8)) _InfoPairs(rows: {'Player': apiMap(item)['playerName'] ?? apiMap(item)['name'], 'Value': apiMap(item)['value'] ?? apiMap(item)['runs'] ?? apiMap(item)['wickets']})]),
        ),
      ],
    );
  }
}

class _InfoPairs extends StatelessWidget {
  const _InfoPairs({required this.rows});

  final Map<String, dynamic> rows;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final visible = rows.entries.where((entry) => apiString(entry.value).isNotEmpty).toList();
    if (visible.isEmpty) return const _InlineMuted(text: 'Details are not available yet.');
    return Column(
      children: [
        for (final entry in visible)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                SizedBox(width: 92, child: Text(entry.key, style: TextStyle(color: c.muted, fontWeight: FontWeight.w800))),
                Expanded(child: Text(apiString(entry.value), style: TextStyle(color: c.text, fontWeight: FontWeight.w800))),
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
  Widget build(BuildContext context) => Text(text, style: TextStyle(color: context.cric.muted, fontWeight: FontWeight.w700));
}

class _ChipText extends StatelessWidget {
  const _ChipText({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(color: c.cyan.withOpacity(0.12), borderRadius: BorderRadius.circular(999), border: Border.all(color: c.cyan.withOpacity(0.28))),
      child: Text(text.isEmpty ? 'Unknown' : text, style: TextStyle(color: c.cyan, fontWeight: FontWeight.w900, fontSize: 11)),
    );
  }
}

String _dateRange(dynamic start, dynamic end) {
  final left = apiString(start);
  final right = apiString(end);
  if (left.isEmpty && right.isEmpty) return '';
  if (right.isEmpty) return left;
  if (left.isEmpty) return right;
  return '$left - $right';
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
          Expanded(child: Text(text, style: TextStyle(color: c.muted, fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }
}
