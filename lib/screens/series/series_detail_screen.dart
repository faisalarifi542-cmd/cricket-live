import 'package:flutter/material.dart';

import 'package:cricpro_flutter/app_theme.dart';
import 'package:cricpro_flutter/api_models.dart';
import 'package:cricpro_flutter/components.dart';
import 'package:cricpro_flutter/models/api_response.dart';
import 'package:cricpro_flutter/models/cricket_match.dart';
import 'package:cricpro_flutter/repositories/cricket_repository.dart';
import 'package:cricpro_flutter/screens/match_details/match_details_screen.dart'
    hide apiMap;
import 'package:cricpro_flutter/screens/series/series_components.dart';

/// Premium Series Details screen with a shared hero and four redesigned tabs:
/// Overview, Matches, Squads, Stats. All series-level metadata (teams,
/// formats, dates, status, counts) is derived from the rich match list since
/// the `/series` list endpoint is intentionally lightweight.
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
  final CricketRepository _repository = CricketRepository();

  String _seriesId = '';
  String _seriesName = '';

  // Shared, loaded-once series context (detail + match list).
  Future<_SeriesContext>? _contextFuture;
  // Per-tab futures, cached so switching tabs never reloads / blinks.
  final Map<int, Future<dynamic>> _tabFutures = {};

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
          arg['title']);
      if (name.isNotEmpty) return cleanSeriesText(name);
    }
    if (widget.initialSeries != null && widget.initialSeries!.name.isNotEmpty) {
      return cleanSeriesText(widget.initialSeries!.name);
    }
    return '';
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = _resolveSeriesId();
    if (next.isNotEmpty && next != _seriesId) {
      _seriesId = next;
      _seriesName = _resolveSeriesName();
      _tabFutures.clear();
      _contextFuture = _loadContext();
      _tabFutures[tab] = _loadTab(tab);
    }
  }

  Future<_SeriesContext> _loadContext({bool forceRefresh = false}) async {
    final results = await Future.wait([
      _repository.seriesDetail(_seriesId, forceRefresh: forceRefresh),
      _repository.seriesMatchList(_seriesId, forceRefresh: forceRefresh),
    ]);
    final detail =
        apiMap((results[0] as ApiEnvelope<Map<String, dynamic>>).data);
    final matches = (results[1] as ApiEnvelope<List<CricketMatch>>).data;
    return _SeriesContext(
      seriesId: _seriesId,
      fallbackName: _seriesName.isNotEmpty
          ? _seriesName
          : widget.initialSeries?.name ?? 'Series',
      detail: detail,
      matches: matches,
      initialSeries: widget.initialSeries,
    );
  }

  Future<dynamic> _loadTab(int index, {bool forceRefresh = false}) {
    final id = _seriesId;
    return switch (index) {
      0 => _loadContext(forceRefresh: forceRefresh),
      1 => _repository.seriesMatchList(id, forceRefresh: forceRefresh),
      2 => _loadSquads(forceRefresh: forceRefresh),
      _ => Future.wait([
          _repository.pointsTable(id, forceRefresh: forceRefresh),
          _repository.seriesStats(id, forceRefresh: forceRefresh),
        ]),
    };
  }

  /// Loads squads from `/series/:id/squads`. If that endpoint is unavailable
  /// (older backend) or returns no players, falls back to deriving squads from
  /// a representative match's squad page.
  Future<List<SquadTeam>> _loadSquads({bool forceRefresh = false}) async {
    final id = _seriesId;
    try {
      final res = await _repository.seriesSquads(id, forceRefresh: forceRefresh);
      final teams = _parseSquadTeams(res.data);
      if (teams.any((t) => t.players.isNotEmpty)) return teams;
    } catch (_) {
      // Fall through to match-based fallback.
    }

    // Fallback: pick a match and read its squad directly.
    try {
      final matchesEnv = await _repository.seriesMatchList(id);
      final match = _pickSquadMatch(matchesEnv.data);
      if (match == null) return const [];
      final squadRes =
          await _repository.matchSquads(match.id, forceRefresh: forceRefresh);
      return _parseMatchSquadTeams(squadRes.data, match);
    } catch (_) {
      return const [];
    }
  }

  CricketMatch? _pickSquadMatch(List<CricketMatch> matches) {
    if (matches.isEmpty) return null;
    final live = matches.where((m) => m.isLive);
    if (live.isNotEmpty) return live.first;
    final upcoming = matches.where((m) => m.isUpcoming).toList()
      ..sort((a, b) => (a.startDateTime ?? DateTime(2100))
          .compareTo(b.startDateTime ?? DateTime(2100)));
    if (upcoming.isNotEmpty) return upcoming.first;
    final completed = matches.where((m) => m.isFinished).toList()
      ..sort((a, b) => (b.startDateTime ?? DateTime(1970))
          .compareTo(a.startDateTime ?? DateTime(1970)));
    if (completed.isNotEmpty) return completed.first;
    return matches.first;
  }

  void _setTab(int value) {
    if (value == tab) return;
    setState(() {
      tab = value;
      if (_seriesId.isNotEmpty) {
        _tabFutures.putIfAbsent(value, () => _loadTab(value));
      }
    });
  }

  Future<void> _refresh() async {
    if (_seriesId.isEmpty) return;
    setState(() {
      _contextFuture = _loadContext(forceRefresh: true);
      _tabFutures[tab] = _loadTab(tab, forceRefresh: true);
    });
    await _tabFutures[tab];
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: c.bgGradient),
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: _refresh,
            color: c.cyan,
            child: ListView(
              padding: EdgeInsets.fromLTRB(context.horizontalPadding, 14,
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
                FutureBuilder<_SeriesContext>(
                  future: _contextFuture,
                  builder: (context, snapshot) {
                    final ctx = snapshot.data;
                    return SeriesHeroCard(
                      tourLabel: ctx?.tourLabel,
                      title: ctx?.title ??
                          (_seriesName.isNotEmpty ? _seriesName : 'Series'),
                      season: ctx?.season,
                      dateRange: ctx?.dateRange ?? '',
                      formats: ctx?.formats ?? const [],
                      status: ctx?.statusLabel ?? '',
                      left: ctx?.teamA,
                      right: ctx?.teamB,
                    );
                  },
                ),
                const SizedBox(height: 14),
                SeriesTabBar(
                  items: const ['Overview', 'Matches', 'Squads', 'Stats'],
                  selected: tab,
                  onChanged: _setTab,
                ),
                const SizedBox(height: 18),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, anim) =>
                      FadeTransition(opacity: anim, child: child),
                  child: KeyedSubtree(
                    key: ValueKey(tab),
                    child: _seriesId.isEmpty || _tabFutures[tab] == null
                        ? const SeriesStateCard(
                            title: 'Select a series',
                            message:
                                'Open a series from the list to view details.',
                          )
                        : _SeriesTabPanel(
                            tab: tab,
                            future: _tabFutures[tab]!,
                            seriesId: _seriesId,
                            onOpenMatch: (id) =>
                                Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => MatchDetailsScreen(matchId: id),
                            )),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Series context — derived series-level metadata
// ---------------------------------------------------------------------------

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
    final s = startDate;
    final e = endDate;
    if (s == null) return '';
    String fmt(DateTime d) {
      const m = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return '${d.day} ${m[d.month - 1]} ${d.year}';
    }

    if (e == null || (e.difference(s).inDays).abs() < 1) return fmt(s);
    return '${fmt(s)} – ${fmt(e)}';
  }

  /// Distinct match formats present in the series, e.g. ["Test", "ODI"].
  List<String> get formats {
    final counts = <String, int>{};
    final re = RegExp(r'\b(Test|ODI|T20I|T20|Match|Final)\b',
        caseSensitive: false);
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
    final m = RegExp(r'tour of ([a-z ]+)', caseSensitive: false)
        .firstMatch(title);
    if (m != null) return _titleCase(m.group(1)!.trim());
    return '';
  }

  int get totalMatches {
    final explicit = apiInt(detail['matchCount']) ?? apiInt(detail['totalMatches']);
    if (explicit != null && explicit > 0) return explicit;
    return matches.length;
  }

  int get liveCount => matches.where((m) => m.isLive).length;
  int get upcomingCount => matches.where((m) => m.isUpcoming).length;
  int get completedCount => matches.where((m) => m.isFinished).length;

  SeriesStatus get status {
    if (liveCount > 0) return SeriesStatus.ongoing;
    if (completedCount > 0 && upcomingCount == 0) return SeriesStatus.completed;
    return SeriesStatus.upcoming;
  }

  String get statusLabel => switch (status) {
        SeriesStatus.ongoing => 'In Progress',
        SeriesStatus.upcoming => 'Upcoming',
        SeriesStatus.completed => 'Completed',
      };

  /// The two primary teams (bilateral) for the hero, derived from matches.
  List<SeriesTeamRef> get _bilateralTeams {
    final byKey = <String, SeriesTeamRef>{};
    for (final m in matches) {
      for (final t in [
        SeriesTeamRef(name: m.teamA, shortName: m.teamAShort, logoUrl: m.teamALogo),
        SeriesTeamRef(name: m.teamB, shortName: m.teamBShort, logoUrl: m.teamBLogo),
      ]) {
        final key = (t.shortName.isNotEmpty ? t.shortName : t.name).toUpperCase();
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

  static const _emptySeries = ApiSeries(id: '', name: '', status: '');
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
  });

  final int tab;
  final Future<dynamic> future;
  final String seriesId;
  final ValueChanged<String> onOpenMatch;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<dynamic>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SeriesLoading();
        }
        if (snapshot.hasError) {
          return const SeriesStateCard(
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
            final teams = (snapshot.data as List<SquadTeam>?) ?? const [];
            return _SquadsTab(teams: teams);
          case 3:
            final responses = snapshot.data as List<dynamic>?;
            final points = responses != null && responses.isNotEmpty
                ? apiMap((responses[0] as ApiEnvelope<Map<String, dynamic>>).data)
                : const <String, dynamic>{};
            final stats = responses != null && responses.length > 1
                ? apiMap((responses[1] as ApiEnvelope<Map<String, dynamic>>).data)
                : const <String, dynamic>{};
            return _StatsTab(points: points, stats: stats);
          default:
            final ctx = snapshot.data as _SeriesContext?;
            if (ctx == null) {
              return const SeriesLoading();
            }
            return _OverviewTab(ctx: ctx, onOpenMatch: onOpenMatch);
        }
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Overview tab
// ---------------------------------------------------------------------------

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.ctx, required this.onOpenMatch});

  final _SeriesContext ctx;
  final ValueChanged<String> onOpenMatch;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final next = ctx.nextMatch;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SeriesSectionCard(
          title: 'Series Info',
          child: _SeriesInfoGrid(
            items: [
              if (ctx.formats.isNotEmpty)
                _InfoRow(Icons.edit_note_rounded, 'Format',
                    ctx.formats.join(' • ')),
              if (ctx.host.isNotEmpty)
                _InfoRow(Icons.shield_outlined, 'Host', ctx.host),
              if (ctx.startDate != null)
                _InfoRow(Icons.calendar_today_rounded, 'Start Date',
                    _shortDate(ctx.startDate!)),
              if (ctx.endDate != null)
                _InfoRow(Icons.event_available_rounded, 'End Date',
                    _shortDate(ctx.endDate!)),
              if (ctx.totalMatches > 0)
                _InfoRow(Icons.sports_cricket_rounded, 'Total Matches',
                    '${ctx.totalMatches} Matches'),
              _InfoRow(
                Icons.monitor_heart_outlined,
                'Series Status',
                ctx.statusLabel,
                valueColor: ctx.status == SeriesStatus.ongoing
                    ? c.success
                    : ctx.status == SeriesStatus.completed
                        ? c.success
                        : c.cyan,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _CountStrip(
          live: ctx.liveCount,
          upcoming: ctx.upcomingCount,
          completed: ctx.completedCount,
        ),
        if (next != null) ...[
          const SizedBox(height: 14),
          _NextMatchCard(match: next, onOpen: () => onOpenMatch(next.id)),
        ],
        if (ctx.venues.isNotEmpty) ...[
          const SizedBox(height: 14),
          _VenuesCard(venues: ctx.venues),
        ],
        if (ctx.allTeams.isNotEmpty) ...[
          const SizedBox(height: 14),
          _ParticipatingTeamsCard(teams: ctx.allTeams),
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
        final twoCol = constraints.maxWidth >= 360;
        final colWidth =
            twoCol ? (constraints.maxWidth - 14) / 2 : constraints.maxWidth;
        return Wrap(
          spacing: 14,
          runSpacing: 16,
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
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: c.cyan.withValues(alpha: .10),
            border: Border.all(color: c.cyan.withValues(alpha: .25)),
          ),
          child: Icon(item.icon, color: c.cyan, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: c.muted,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                item.value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: item.valueColor ?? c.text,
                  fontWeight: FontWeight.w900,
                  fontSize: 14.5,
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

class _CountStrip extends StatelessWidget {
  const _CountStrip({
    required this.live,
    required this.upcoming,
    required this.completed,
  });

  final int live;
  final int upcoming;
  final int completed;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Row(
      children: [
        Expanded(
            child: _CountTile(
                label: 'Live', value: live, color: c.live, icon: Icons.sensors_rounded)),
        const SizedBox(width: 12),
        Expanded(
            child: _CountTile(
                label: 'Upcoming',
                value: upcoming,
                color: c.cyan,
                icon: Icons.schedule_rounded)),
        const SizedBox(width: 12),
        Expanded(
            child: _CountTile(
                label: 'Completed',
                value: completed,
                color: c.success,
                icon: Icons.check_circle_rounded)),
      ],
    );
  }
}

class _CountTile extends StatelessWidget {
  const _CountTile({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String label;
  final int value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: c.card.withValues(alpha: .9),
        border: Border.all(color: color.withValues(alpha: .3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(
            value.toString(),
            style: TextStyle(
                color: c.text, fontWeight: FontWeight.w900, fontSize: 22),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
                color: c.muted, fontWeight: FontWeight.w700, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _NextMatchCard extends StatelessWidget {
  const _NextMatchCard({required this.match, required this.onOpen});

  final CricketMatch match;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return SeriesSectionCard(
      title: 'Next Match',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SeriesPlayerAvatarless(
                  logo: match.teamALogo,
                  name: match.teamA,
                  short: match.teamAShort),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text('vs',
                    style: TextStyle(
                        color: c.muted,
                        fontWeight: FontWeight.w900,
                        fontSize: 13)),
              ),
              SeriesPlayerAvatarless(
                  logo: match.teamBLogo,
                  name: match.teamB,
                  short: match.teamBShort),
              const Spacer(),
              if (match.matchDesc.isNotEmpty)
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: c.cyan.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: c.cyan.withValues(alpha: .3)),
                    ),
                    child: Text(
                      match.matchDesc,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.cyan,
                        fontWeight: FontWeight.w900,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          _MetaLine(
              icon: Icons.calendar_today_rounded,
              text: match.startDateTime != null
                  ? formatMatchDateTime(match.startDateTime)
                  : 'Date to be confirmed'),
          if (match.venue.isNotEmpty)
            _MetaLine(icon: Icons.location_on_rounded, text: match.venue),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: GradientButton(
              label: match.isLive ? 'View Match' : 'Set Reminder',
              icon: match.isLive
                  ? Icons.play_circle_fill_rounded
                  : Icons.notifications_active_rounded,
              onTap: onOpen,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: c.muted, size: 15),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: c.muted,
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VenuesCard extends StatelessWidget {
  const _VenuesCard({required this.venues});

  final List<String> venues;

  @override
  Widget build(BuildContext context) {
    return SeriesSectionCard(
      title: 'Venues',
      child: SizedBox(
        height: 96,
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
      width: 132,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/stadium_live.png',
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
                  const Color(0xff05101f).withValues(alpha: .9),
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

class _ParticipatingTeamsCard extends StatelessWidget {
  const _ParticipatingTeamsCard({required this.teams});

  final List<SeriesTeamRef> teams;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return SeriesSectionCard(
      title: 'Participating Teams',
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final team in teams)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: c.card2.withValues(alpha: .6),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: c.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TeamLogoWidget(
                    logoUrl: team.logoUrl,
                    teamName: team.name,
                    abbreviation:
                        team.shortName.isNotEmpty ? team.shortName : team.name,
                    color: c.cyan,
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    team.shortName.isNotEmpty ? team.shortName : team.name,
                    style: TextStyle(
                      color: c.text,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
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

/// Small team logo + short label used in the Next Match card.
class SeriesPlayerAvatarless extends StatelessWidget {
  const SeriesPlayerAvatarless({
    super.key,
    required this.logo,
    required this.name,
    required this.short,
  });

  final String? logo;
  final String name;
  final String short;

  @override
  Widget build(BuildContext context) {
    return TeamLogoWidget(
      logoUrl: logo,
      teamName: name,
      abbreviation: short.isNotEmpty ? short : name,
      color: const Color(0xff22d3ee),
      size: 40,
    );
  }
}

// ---------------------------------------------------------------------------
// Matches tab
// ---------------------------------------------------------------------------

class _MatchesTab extends StatelessWidget {
  const _MatchesTab({required this.matches, required this.onOpenMatch});

  final List<CricketMatch> matches;
  final ValueChanged<String> onOpenMatch;

  @override
  Widget build(BuildContext context) {
    if (matches.isEmpty) {
      return const SeriesStateCard(
        title: 'No matches yet',
        message: 'Matches for this series have not been announced yet.',
        icon: Icons.event_busy_rounded,
      );
    }
    final live = matches.where((m) => m.isLive).toList();
    final upcoming = matches.where((m) => m.isUpcoming).toList();
    final completed = matches.where((m) => m.isFinished).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (live.isNotEmpty) ...[
          const _SectionLabel('Live Matches'),
          for (final m in live)
            _SeriesMatchTile(match: m, onTap: () => onOpenMatch(m.id)),
        ],
        if (upcoming.isNotEmpty) ...[
          const _SectionLabel('Upcoming Matches'),
          for (final m in upcoming)
            _SeriesMatchTile(match: m, onTap: () => onOpenMatch(m.id)),
        ],
        if (completed.isNotEmpty) ...[
          const _SectionLabel('Completed Matches'),
          for (final m in completed)
            _SeriesMatchTile(match: m, onTap: () => onOpenMatch(m.id)),
        ],
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 10, left: 2),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          color: c.cyan,
          fontWeight: FontWeight.w900,
          fontSize: 12.5,
          letterSpacing: .6,
        ),
      ),
    );
  }
}

class _SeriesMatchTile extends StatelessWidget {
  const _SeriesMatchTile({required this.match, required this.onTap});

  final CricketMatch match;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final statusColor = match.isLive
        ? c.live
        : match.isFinished
            ? c.success
            : c.cyan;
    final statusLabel = match.isLive
        ? 'LIVE'
        : match.isFinished
            ? _winnerTag(match)
            : 'UPCOMING';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TapScale(
        onTap: onTap,
        borderRadius: 18,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: c.card.withValues(alpha: .92),
            border: Border.all(color: c.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    match.matchDesc.isNotEmpty ? match.matchDesc : 'Match',
                    style: TextStyle(
                      color: c.text,
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: .15),
                      borderRadius: BorderRadius.circular(7),
                      border:
                          Border.all(color: statusColor.withValues(alpha: .5)),
                    ),
                    child: Text(
                      statusLabel,
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.w900,
                        fontSize: 10,
                        letterSpacing: .4,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _TeamLine(
                          logo: match.teamALogo,
                          name: match.teamA,
                          short: match.teamAShort,
                          score: match.teamAScoreText,
                        ),
                        const SizedBox(height: 8),
                        _TeamLine(
                          logo: match.teamBLogo,
                          name: match.teamB,
                          short: match.teamBShort,
                          score: match.teamBScoreText,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(width: 1, height: 44, color: c.border),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 96,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (match.startDateTime != null)
                          Text(
                            _dateOnly(match.startDateTime!),
                            textAlign: TextAlign.right,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: c.muted,
                              fontWeight: FontWeight.w700,
                              fontSize: 11.5,
                            ),
                          ),
                        const SizedBox(height: 4),
                        if (match.isUpcoming)
                          Text(
                            _countdown(match.startDateTime),
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              color: c.cyan,
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                            ),
                          )
                        else if (match.isFinished &&
                            match.resultText.isNotEmpty)
                          Text(
                            match.resultText,
                            textAlign: TextAlign.right,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: c.success,
                              fontWeight: FontWeight.w800,
                              fontSize: 11.5,
                              height: 1.2,
                            ),
                          )
                        else if (match.isLive)
                          Text(
                            match.statusText.isNotEmpty
                                ? match.statusText
                                : 'Live now',
                            textAlign: TextAlign.right,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: c.live,
                              fontWeight: FontWeight.w800,
                              fontSize: 11.5,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              if (match.venue.isNotEmpty) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.location_on_rounded, color: c.muted, size: 13),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        match.venue,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.muted,
                          fontWeight: FontWeight.w600,
                          fontSize: 11.5,
                        ),
                      ),
                    ),
                    if (match.hasLiveStream && match.watchLiveEnabled) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: c.live.withValues(alpha: .15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: c.live.withValues(alpha: .5)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.play_arrow_rounded, color: c.live, size: 12),
                            const SizedBox(width: 3),
                            Text(
                              'Watch',
                              style: TextStyle(
                                color: c.live,
                                fontWeight: FontWeight.w900,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _winnerTag(CricketMatch m) {
    final r = m.resultText.toLowerCase();
    if (r.contains('${m.teamAShort.toLowerCase()} won') ||
        r.startsWith(m.teamA.toLowerCase())) {
      return '${m.teamAShort} WON';
    }
    if (r.contains('${m.teamBShort.toLowerCase()} won') ||
        r.startsWith(m.teamB.toLowerCase())) {
      return '${m.teamBShort} WON';
    }
    return 'RESULT';
  }
}

class _TeamLine extends StatelessWidget {
  const _TeamLine({
    required this.logo,
    required this.name,
    required this.short,
    required this.score,
  });

  final String? logo;
  final String name;
  final String short;
  final String score;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Row(
      children: [
        TeamLogoWidget(
          logoUrl: logo,
          teamName: name,
          abbreviation: short.isNotEmpty ? short : name,
          color: c.cyan,
          size: 26,
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            short.isNotEmpty ? short : name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: c.text,
              fontWeight: FontWeight.w800,
              fontSize: 13.5,
            ),
          ),
        ),
        if (score.isNotEmpty) ...[
          const SizedBox(width: 8),
          Text(
            score,
            style: TextStyle(
              color: c.cyan,
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Squads tab
// ---------------------------------------------------------------------------

class _SquadsTab extends StatefulWidget {
  const _SquadsTab({required this.teams});

  final List<SquadTeam> teams;

  @override
  State<_SquadsTab> createState() => _SquadsTabState();
}

class _SquadsTabState extends State<_SquadsTab> {
  int _team = 0;

  @override
  Widget build(BuildContext context) {
    if (widget.teams.isEmpty) {
      return const SeriesStateCard(
        title: 'Squads not announced',
        message:
            'Squads for this series are not available from the provider yet.',
        icon: Icons.groups_rounded,
      );
    }
    final teams = widget.teams;
    final selected = _team.clamp(0, teams.length - 1);
    final team = teams[selected];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (teams.length > 1)
          SeriesTabBar(
            items: [
              for (final t in teams)
                t.shortName.isNotEmpty ? t.shortName : t.name
            ],
            selected: selected,
            onChanged: (v) => setState(() => _team = v),
          ),
        const SizedBox(height: 16),
        _SquadGroups(team: team),
      ],
    );
  }
}

class _SquadGroups extends StatelessWidget {
  const _SquadGroups({required this.team});

  final SquadTeam team;

  @override
  Widget build(BuildContext context) {
    final groups = _group(team.players);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in groups.entries)
          if (entry.value.isNotEmpty) ...[
            _SectionLabel(entry.key),
            _PlayerGrid(players: entry.value),
            const SizedBox(height: 8),
          ],
      ],
    );
  }

  Map<String, List<SquadPlayer>> _group(List<SquadPlayer> players) {
    final top = <SquadPlayer>[];
    final allRounders = <SquadPlayer>[];
    final bowlers = <SquadPlayer>[];
    final keepers = <SquadPlayer>[];
    final bench = <SquadPlayer>[];
    for (final p in players) {
      if (p.isSubstitute) {
        bench.add(p);
        continue;
      }
      final role = p.role.toLowerCase();
      if (p.isWicketKeeper || role.contains('wk') || role.contains('keeper')) {
        keepers.add(p);
      } else if (role.contains('all') && role.contains('round')) {
        allRounders.add(p);
      } else if (role.contains('bowl')) {
        bowlers.add(p);
      } else {
        top.add(p);
      }
    }
    return {
      'Batters': top,
      'Wicketkeepers': keepers,
      'All-Rounders': allRounders,
      'Bowlers': bowlers,
      'Reserves / Bench': bench,
    };
  }
}

class _PlayerGrid extends StatelessWidget {
  const _PlayerGrid({required this.players});

  final List<SquadPlayer> players;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 10.0;
        final cols = constraints.maxWidth >= 420 ? 4 : 3;
        final width = (constraints.maxWidth - (cols - 1) * spacing) / cols;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final p in players)
              SizedBox(width: width, child: _SquadPlayerCard(player: p)),
          ],
        );
      },
    );
  }
}

class _SquadPlayerCard extends StatelessWidget {
  const _SquadPlayerCard({required this.player});

  final SquadPlayer player;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final roleTag = _roleTag(player);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: c.card.withValues(alpha: .9),
        border: Border.all(color: c.border),
      ),
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              SeriesPlayerAvatar(
                name: player.name,
                imageUrl: player.imageUrl,
                size: 58,
              ),
              if (roleTag != null)
                Positioned(
                  right: -4,
                  bottom: -2,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: roleTag.$2,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: c.bg, width: 1.5),
                    ),
                    child: Text(
                      roleTag.$1,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 8.5,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            player.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: c.text,
              fontWeight: FontWeight.w800,
              fontSize: 12,
              height: 1.15,
            ),
          ),
          if (player.isCaptain || player.isWicketKeeper) ...[
            const SizedBox(height: 3),
            Text(
              player.isCaptain ? '(C) Captain' : 'WK',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.cyan,
                fontWeight: FontWeight.w700,
                fontSize: 10,
              ),
            ),
          ],
        ],
      ),
    );
  }

  (String, Color)? _roleTag(SquadPlayer p) {
    final role = p.role.toLowerCase();
    if (p.isWicketKeeper || role.contains('wk') || role.contains('keeper')) {
      return ('WK', const Color(0xfff59e0b));
    }
    if (role.contains('all') && role.contains('round')) {
      return ('AR', const Color(0xff14b8a6));
    }
    if (role.contains('bowl')) {
      return ('BOWL', const Color(0xff60a5fa));
    }
    if (role.contains('bat')) {
      return ('BAT', const Color(0xff22d3ee));
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// Stats tab
// ---------------------------------------------------------------------------

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
      return const SeriesStateCard(
        title: 'Stats not available',
        message:
            'Points table and player stats are not available for this series yet.',
        icon: Icons.bar_chart_rounded,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (pointsRows.isNotEmpty) ...[
          _PointsTableCard(rows: pointsRows),
          const SizedBox(height: 14),
        ],
        if (batting.isNotEmpty) ...[
          _TopPlayersCard(
            title: 'Top Run Scorers',
            rows: batting.take(5).toList(),
            metricLabel: 'Runs',
            isBowling: false,
          ),
          const SizedBox(height: 14),
        ],
        if (bowling.isNotEmpty) ...[
          _TopPlayersCard(
            title: 'Top Wicket Takers',
            rows: bowling.take(5).toList(),
            metricLabel: 'Wickets',
            isBowling: true,
          ),
        ],
      ],
    );
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
    return rows.map(apiMap).where((m) => m.isNotEmpty).toList();
  }

  List<Map<String, dynamic>> _statRows(Map<String, dynamic> value, String key) {
    final root = value['data'] is Map ? apiMap(value['data']) : value;
    final section = apiMap(root[key]);
    final rows = apiList(section['rows'] ?? section['players'] ?? section['items']);
    return rows.map(apiMap).where((m) => m.isNotEmpty).toList();
  }
}

class _PointsTableCard extends StatelessWidget {
  const _PointsTableCard({required this.rows});

  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return SeriesSectionCard(
      title: 'Points Table',
      child: Column(
        children: [
          // Header row
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                const SizedBox(width: 22),
                Expanded(
                    child: Text('TEAM', style: _hStyle(c))),
                for (final h in const ['P', 'W', 'L', 'Pts', 'NRR'])
                  SizedBox(
                      width: h == 'NRR' ? 46 : 30,
                      child: Text(h, textAlign: TextAlign.center, style: _hStyle(c))),
              ],
            ),
          ),
          for (var i = 0; i < rows.length; i++)
            _PointsRow(rank: i + 1, row: rows[i]),
        ],
      ),
    );
  }

  TextStyle _hStyle(CricColors c) => TextStyle(
      color: c.muted, fontWeight: FontWeight.w900, fontSize: 11);
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
        border: Border(top: BorderSide(color: c.border.withValues(alpha: .5))),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text('$rank',
                style: TextStyle(
                    color: c.muted,
                    fontWeight: FontWeight.w900,
                    fontSize: 12)),
          ),
          TeamLogoWidget(
            logoUrl: logo.isEmpty ? null : logo,
            teamName: name,
            abbreviation: short,
            color: c.cyan,
            size: 22,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              short,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: c.text, fontWeight: FontWeight.w800, fontSize: 12.5),
            ),
          ),
          _val(c, row['played'] ?? row['matches'], 30),
          _val(c, row['won'], 30),
          _val(c, row['lost'], 30),
          _val(c, row['points'], 30, bold: true, color: c.cyan),
          _val(c, row['nrr'], 46),
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
          fontSize: 12,
        ),
      ),
    );
  }
}

class _TopPlayersCard extends StatelessWidget {
  const _TopPlayersCard({
    required this.title,
    required this.rows,
    required this.metricLabel,
    required this.isBowling,
  });

  final String title;
  final List<Map<String, dynamic>> rows;
  final String metricLabel;
  final bool isBowling;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return SeriesSectionCard(
      title: title,
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i != 0)
              Divider(color: c.border.withValues(alpha: .5), height: 1),
            _StatPlayerRow(
              row: rows[i],
              metricLabel: metricLabel,
              isBowling: isBowling,
            ),
          ],
        ],
      ),
    );
  }
}

class _StatPlayerRow extends StatelessWidget {
  const _StatPlayerRow({
    required this.row,
    required this.metricLabel,
    required this.isBowling,
  });

  final Map<String, dynamic> row;
  final String metricLabel;
  final bool isBowling;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final name = apiString(row['playerName'] ?? row['name'], 'Player');
    final team = apiString(row['team']);
    // Use only the real Cricbuzz face image resolved by the backend; never
    // synthesise one from the player id (that produced wrong faces). A missing
    // image falls through to the initials avatar.
    final image = apiString(row['imageUrl'] ?? row['image_url']);
    final metric = isBowling
        ? apiString(row['wickets'], '0')
        : apiString(row['runs'], '0');
    final sub = isBowling
        ? _bowlSub(row)
        : _batSub(row);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          SeriesPlayerAvatar(
              name: name, imageUrl: image.isEmpty ? null : image, size: 38),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: c.text,
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5),
                ),
                if (team.isNotEmpty || sub.isNotEmpty)
                  Text(
                    [if (team.isNotEmpty) team, if (sub.isNotEmpty) sub]
                        .join(' • '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: c.muted,
                        fontWeight: FontWeight.w600,
                        fontSize: 11.5),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                metric,
                style: TextStyle(
                    color: c.cyan,
                    fontWeight: FontWeight.w900,
                    fontSize: 18),
              ),
              Text(
                metricLabel,
                style: TextStyle(
                    color: c.muted,
                    fontWeight: FontWeight.w700,
                    fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _batSub(Map<String, dynamic> row) {
    final matches = apiInt(row['matches']);
    final avg = apiDouble(row['average']);
    final parts = <String>[];
    if (matches != null && matches > 0) parts.add('$matches Mat');
    if (avg != null && avg > 0) parts.add('Avg ${avg.toStringAsFixed(1)}');
    return parts.join(' • ');
  }

  String _bowlSub(Map<String, dynamic> row) {
    final matches = apiInt(row['matches']);
    final econ = apiDouble(row['economy']);
    final parts = <String>[];
    if (matches != null && matches > 0) parts.add('$matches Mat');
    if (econ != null && econ > 0) parts.add('Econ ${econ.toStringAsFixed(2)}');
    return parts.join(' • ');
  }
}

// ---------------------------------------------------------------------------
// Squad data models + parsers
// ---------------------------------------------------------------------------

class SquadTeam {
  const SquadTeam({
    required this.name,
    required this.shortName,
    this.logoUrl,
    this.players = const [],
  });

  final String name;
  final String shortName;
  final String? logoUrl;
  final List<SquadPlayer> players;
}

class SquadPlayer {
  const SquadPlayer({
    required this.id,
    required this.name,
    required this.role,
    this.imageUrl,
    this.isCaptain = false,
    this.isWicketKeeper = false,
    this.isSubstitute = false,
  });

  final String id;
  final String name;
  final String role;
  final String? imageUrl;
  final bool isCaptain;
  final bool isWicketKeeper;
  final bool isSubstitute;
}

/// Parses the `/series/:id/squads` payload (teams[].players[]).
List<SquadTeam> _parseSquadTeams(Map<String, dynamic> data) {
  final root = data['data'] is Map ? apiMap(data['data']) : data;
  final rawTeams = apiList(root['teams']);
  final teams = <SquadTeam>[];
  for (final raw in rawTeams) {
    final t = apiMap(raw);
    final players = apiList(t['players']).map(_parseSquadPlayer).toList();
    if (players.isEmpty) continue;
    teams.add(SquadTeam(
      name: apiString(t['teamName'] ?? t['team_name'], 'Team'),
      shortName: apiString(t['teamShortName'] ?? t['teamShort'] ?? t['team_short']),
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
  final image = apiString(p['imageUrl'] ?? p['image_url']);
  return SquadPlayer(
    id: id,
    name: apiString(p['name'] ?? p['playerName'] ?? p['player_name'], 'Player'),
    role: apiString(p['role'] ?? p['playerRole']),
    imageUrl: image.isEmpty ? null : image,
    isCaptain: apiBool(p['isCaptain'] ?? p['is_captain']),
    isWicketKeeper: apiBool(p['isWicketKeeper'] ?? p['is_wicketkeeper']),
    isSubstitute: apiBool(p['isSubstitute'] ?? p['is_substitute']),
  );
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
        players.add(_parseSquadPlayer(raw));
      }
      if (players.isNotEmpty) break;
    }
    for (final raw in apiList(t['bench'] ?? t['substitutes'])) {
      final p = _parseSquadPlayer(raw);
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
    return SquadTeam(
      name: apiString(t['team_name'] ?? t['teamName'], fallbackName),
      shortName: apiString(t['team_short'] ?? t['teamShort'], fallbackShort),
      logoUrl: apiString(t['logoUrl'] ?? t['logo_url']).isEmpty
          ? fallbackLogo
          : apiString(t['logoUrl'] ?? t['logo_url']),
      players: players,
    );
  }

  final t1 = buildTeam(
      root['team1'], match.teamA, match.teamAShort, match.teamALogo);
  final t2 = buildTeam(
      root['team2'], match.teamB, match.teamBShort, match.teamBLogo);
  if (t1 != null) teams.add(t1);
  if (t2 != null) teams.add(t2);
  return teams;
}

// ---------------------------------------------------------------------------
// Small shared helpers
// ---------------------------------------------------------------------------

String _shortDate(DateTime d) {
  const m = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return '${d.day} ${m[d.month - 1]} ${d.year}';
}

String _dateOnly(DateTime d) {
  const m = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return '${d.day} ${m[d.month - 1]}';
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
