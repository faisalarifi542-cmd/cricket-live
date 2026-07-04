import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import 'package:cricpro_flutter/app_theme.dart';
import 'package:cricpro_flutter/api_models.dart';
import 'package:cricpro_flutter/components.dart';
import 'package:cricpro_flutter/models/api_response.dart';
import 'package:cricpro_flutter/models/cricket_match.dart';
import 'package:cricpro_flutter/repositories/cricket_repository.dart';
import 'package:cricpro_flutter/services/player_image_resolver.dart';
import 'package:cricpro_flutter/utils/team_format.dart';
import 'package:cricpro_flutter/utils/match_status.dart';
import 'package:cricpro_flutter/screens/match_details/match_details_screen.dart'
    hide apiMap;
import 'package:cricpro_flutter/screens/series/series_components.dart';
import 'package:cricpro_flutter/screens/series/series_premium.dart';

part 'widgets/series_detail_hero.dart';
part 'widgets/series_detail_overview.dart';
part 'widgets/series_detail_squads.dart';
part 'widgets/series_detail_stats.dart';

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

  /// Loads squads from `/series/:id/squads` as format groups. If that endpoint
  /// is unavailable (older backend) or returns no players, falls back to
  /// deriving a single squad group from a representative match's squad page.
  Future<List<SquadFormat>> _loadSquads({bool forceRefresh = false}) async {
    final id = _seriesId;
    try {
      final res =
          await _repository.seriesSquads(id, forceRefresh: forceRefresh);
      final formats = _parseSquadFormats(res.data);
      if (kDebugMode) {
        for (final f in formats) {
          for (final t in f.teams) {
            debugPrint('[Squads] format=${f.format} team=${t.name} '
                'short=${t.shortName} squadId=${t.id} '
                'players=${t.players.length} '
                'first5=${t.players.take(5).map((p) => p.name).toList()}');
          }
        }
      }
      if (formats.any((f) => f.teams.any((t) => t.players.isNotEmpty))) {
        return formats;
      }
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
      final teams = _parseMatchSquadTeams(squadRes.data, match);
      if (teams.isEmpty) return const [];
      return [SquadFormat(format: '', teams: teams)];
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
        child: Stack(
          children: [
            // Stadium atmosphere behind the top of the screen.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 320,
              child: IgnorePointer(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const StadiumImage(
                      SAsset.topBackdrop,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      remoteKey: 'series_backdrop',
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: c.isDark
                              ? [
                                  const Color(0xff04132a).withValues(alpha: .3),
                                  c.bg.withValues(alpha: .85),
                                  c.bg,
                                ]
                              : [
                                  Colors.white.withValues(alpha: .15),
                                  c.bg.withValues(alpha: .85),
                                  c.bg,
                                ],
                          stops: const [0, .7, 1],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SafeArea(
              child: RefreshIndicator(
                onRefresh: _refresh,
                color: c.cyan,
                child: ListView(
                  padding: EdgeInsets.fromLTRB(context.horizontalPadding, 8,
                      context.horizontalPadding, context.detailBottomPadding),
                  children: [
                    _DetailAppBar(onBack: () => Navigator.pop(context)),
                    const SizedBox(height: 12),
                    FutureBuilder<_SeriesContext>(
                      future: _contextFuture,
                      builder: (context, snapshot) {
                        final ctx = snapshot.data;
                        return SeriesDetailHero(
                          tourLabel: ctx?.tourLabel,
                          title: ctx?.titleWithoutSeason ??
                              (_seriesName.isNotEmpty ? _seriesName : 'Series'),
                          season: ctx?.season,
                          dateRange: ctx?.dateRange ?? '',
                          formats: ctx?.formats ?? const [],
                          left: ctx?.teamA,
                          right: ctx?.teamB,
                        );
                      },
                    ),
                    const SizedBox(height: 14),
                    SeriesGlassTabBar(
                      items: const [
                        ('Overview', Icons.dashboard_rounded),
                        ('Matches', Icons.sports_cricket_rounded),
                        ('Squads', Icons.groups_rounded),
                        ('Stats', Icons.bar_chart_rounded),
                      ],
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
                            ? const SeriesEmptyState(
                                title: 'Select a series',
                                message:
                                    'Open a series from the list to view details.',
                              )
                            : _SeriesTabPanel(
                                tab: tab,
                                future: _tabFutures[tab]!,
                                seriesId: _seriesId,
                                onSwitchTab: _setTab,
                                onOpenMatch: (id) => Navigator.of(context).push(
                                    MaterialPageRoute(
                                        builder: (_) =>
                                            MatchDetailsScreen(matchId: id))),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Premium detail top app bar (back • CricPro logo • bell+badge • overflow)
// ---------------------------------------------------------------------------

