import 'package:flutter/foundation.dart' show kDebugMode;
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
import 'package:cricpro_flutter/screens/series/series_premium.dart';

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
                    Image.asset(
                      SAsset.topBackdrop,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            const Color(0xff04132a).withValues(alpha: .3),
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

class _DetailAppBar extends StatelessWidget {
  const _DetailAppBar({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final logoSize = context.w <= 400 ? 28.0 : 31.0;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          GestureDetector(
            onTap: onBack,
            behavior: HitTestBehavior.opaque,
            child: Icon(Icons.arrow_back_rounded, color: c.text, size: 26),
          ),
          const Spacer(),
          RichText(
            text: TextSpan(
              style: TextStyle(
                fontSize: logoSize,
                fontWeight: FontWeight.w900,
                fontStyle: FontStyle.italic,
                letterSpacing: -1,
                height: 1,
              ),
              children: [
                TextSpan(text: 'CRIC', style: TextStyle(color: c.text)),
                TextSpan(
                  text: 'PRO',
                  style: TextStyle(
                    color: c.cyan,
                    shadows: [
                      Shadow(
                          color: c.cyan.withValues(alpha: .6), blurRadius: 16),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          const _BellWithBadge(),
          const SizedBox(width: 6),
          Icon(Icons.more_vert_rounded, color: c.text, size: 24),
        ],
      ),
    );
  }
}

class _BellWithBadge extends StatelessWidget {
  const _BellWithBadge();

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Icon(Icons.notifications_none_rounded, color: c.text, size: 25),
          Positioned(
            top: 2,
            right: 2,
            child: Container(
              width: 16,
              height: 16,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.live,
                shape: BoxShape.circle,
                border: Border.all(color: c.bg, width: 1.5),
                boxShadow: [
                  BoxShadow(color: c.live.withValues(alpha: .6), blurRadius: 8),
                ],
              ),
              child: const Text(
                '3',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 9,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Premium series detail hero banner
// ---------------------------------------------------------------------------

class SeriesDetailHero extends StatelessWidget {
  const SeriesDetailHero({
    super.key,
    required this.title,
    this.tourLabel,
    this.season,
    this.dateRange = '',
    this.formats = const [],
    this.left,
    this.right,
  });

  final String title;
  final String? tourLabel;
  final String? season;
  final String dateRange;
  final List<String> formats;
  final SeriesTeamRef? left;
  final SeriesTeamRef? right;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final phone = context.w <= 430;
    final logoSize = phone ? 56.0 : 64.0;
    final (small, big) = _splitTitle();
    final formatLine = formats.isEmpty ? '' : formats.join('  •  ');
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: c.cyan.withValues(alpha: .55), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: c.cyan.withValues(alpha: .18),
            blurRadius: 28,
            spreadRadius: -8,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: .4),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              SAsset.detailHeroBg,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Image.asset(
                SAsset.homeStadiumBackdrop,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    const ColoredBox(color: Color(0xff071726)),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xff031126).withValues(alpha: .35),
                    const Color(0xff041731).withValues(alpha: .55),
                    const Color(0xff020b18).withValues(alpha: .72),
                  ],
                ),
              ),
            ),
          ),
          const TopCyanHighlight(),
          Padding(
            padding:
                EdgeInsets.symmetric(horizontal: phone ? 12 : 16, vertical: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _HeroTeam(team: left, size: logoSize, accent: c.cyan),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (small.isNotEmpty)
                        Text(
                          small.toUpperCase(),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .85),
                            fontWeight: FontWeight.w700,
                            fontStyle: FontStyle.italic,
                            fontSize: phone ? 10.5 : 12,
                            letterSpacing: .5,
                          ),
                        ),
                      Text(
                        big.toUpperCase(),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.text,
                          fontWeight: FontWeight.w900,
                          fontStyle: FontStyle.italic,
                          fontSize: phone ? 20 : 23,
                          height: 1.04,
                          shadows: [
                            Shadow(
                                color: c.cyan.withValues(alpha: .4),
                                blurRadius: 12),
                          ],
                        ),
                      ),
                      if (dateRange.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.calendar_today_rounded,
                                  color: c.cyan, size: 12),
                              const SizedBox(width: 5),
                              Text(
                                dateRange.toUpperCase(),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                style: TextStyle(
                                  color: c.cyan,
                                  fontWeight: FontWeight.w800,
                                  fontSize: phone ? 10.5 : 11.5,
                                  letterSpacing: .3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (formatLine.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: c.cyan.withValues(alpha: .12),
                            borderRadius: BorderRadius.circular(999),
                            border:
                                Border.all(color: c.cyan.withValues(alpha: .5)),
                          ),
                          child: Text(
                            formatLine,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: c.text,
                              fontWeight: FontWeight.w800,
                              fontSize: phone ? 11 : 12,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                _HeroTeam(team: right, size: logoSize, accent: c.warning),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Splits "Afghanistan Tour of India 2026" into ("Afghanistan Tour of",
  /// "India 2026"). Falls back to (tourLabel, season) or ('', title).
  (String, String) _splitTitle() {
    final full =
        season != null && !title.contains(season!) ? '$title $season' : title;
    final m = RegExp(r'^(.*\btour of\b)\s+(.*)$', caseSensitive: false)
        .firstMatch(full);
    if (m != null) {
      return (m.group(1)!.trim(), m.group(2)!.trim());
    }
    if (season != null && full.endsWith(season!)) {
      final base = full.substring(0, full.length - season!.length).trim();
      if (base.isNotEmpty) return (base, season!);
    }
    return ('', full);
  }
}

class _HeroTeam extends StatelessWidget {
  const _HeroTeam(
      {required this.team, required this.size, required this.accent});

  final SeriesTeamRef? team;
  final double size;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final t = team;
    final label =
        (t?.name.isNotEmpty == true ? t!.name : (t?.shortName ?? 'TBD'))
            .toUpperCase();
    return SizedBox(
      width: size + 22,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PremiumTeamLogo(
            name: t?.name ?? 'TBD',
            short: t?.shortName ?? 'TBD',
            logo: t?.logoUrl,
            size: size,
            accent: accent,
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: c.text,
                fontWeight: FontWeight.w900,
                fontSize: 12.5,
                letterSpacing: .3,
              ),
            ),
          ),
        ],
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
        color: c.card.withValues(alpha: .5),
        border: Border.all(color: color.withValues(alpha: .55)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: .14),
            blurRadius: 16,
            spreadRadius: -6,
          ),
        ],
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
              color: Colors.white.withValues(alpha: .82),
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
              label: match.isLive ? 'View Match' : 'Set Reminder',
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
              color: Colors.white.withValues(alpha: .85),
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

class _MatchesTab extends StatelessWidget {
  const _MatchesTab({required this.matches, required this.onOpenMatch});

  final List<CricketMatch> matches;
  final ValueChanged<String> onOpenMatch;

  @override
  Widget build(BuildContext context) {
    if (matches.isEmpty) {
      return const SeriesEmptyState(
        title: 'No matches yet',
        message: 'Matches for this series have not been announced yet.',
        icon: Icons.event_busy_rounded,
      );
    }
    final ordered = [...matches]..sort((a, b) =>
        (a.startDateTime ?? DateTime(2100))
            .compareTo(b.startDateTime ?? DateTime(2100)));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < ordered.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _SeriesMatchCard(
              match: ordered[i],
              index: i + 1,
              onTap: () => onOpenMatch(ordered[i].id),
            ),
          ),
      ],
    );
  }
}

class _SeriesMatchCard extends StatelessWidget {
  const _SeriesMatchCard({
    required this.match,
    required this.index,
    required this.onTap,
  });

  final CricketMatch match;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final phone = context.w <= 430;
    final logoSize = phone ? 46.0 : 50.0;
    final (statusLabel, statusColor, isLive) = match.isLive
        ? ('Live', c.live, true)
        : match.isFinished
            ? ('Completed', c.success, false)
            : ('Upcoming', c.cyan, false);
    final fmt = _formatTag(match);
    final desc = match.matchDesc.isNotEmpty
        ? 'MATCH $index • ${match.matchDesc.toUpperCase()}'
        : 'MATCH $index';

    return PremiumGlassPanel(
      bgAsset: SAsset.matchCardBg,
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SeriesOutlineChip(label: fmt, icon: Icons.sports_cricket_rounded),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    desc,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .82),
                      fontWeight: FontWeight.w800,
                      fontSize: phone ? 10 : 11,
                      letterSpacing: .3,
                    ),
                  ),
                ),
              ),
              SeriesStatusPill(
                label: statusLabel,
                color: statusColor,
                live: isLive,
                dense: true,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: phone ? 66 : 74,
                child: PremiumTeamColumn(
                  name: match.teamA,
                  short: match.teamAShort,
                  logo: match.teamALogo,
                  logoSize: logoSize,
                  codeSize: phone ? 15 : 16,
                  accent: c.cyan,
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    PremiumVsBadge(
                      width: phone ? 50 : 54,
                      height: phone ? 34 : 38,
                    ),
                    const SizedBox(height: 8),
                    if (match.startDateTime != null)
                      Text(
                        _dateOnlyYear(match.startDateTime!).toUpperCase(),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.text,
                          fontWeight: FontWeight.w800,
                          fontSize: phone ? 11 : 12,
                        ),
                      ),
                    if (match.venue.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.location_on_outlined,
                              color: c.cyan, size: 11),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              match.venue,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: .72),
                                fontWeight: FontWeight.w600,
                                fontSize: 10.5,
                                height: 1.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(
                width: phone ? 66 : 74,
                child: Column(
                  children: [
                    PremiumTeamColumn(
                      name: match.teamB,
                      short: match.teamBShort,
                      logo: match.teamBLogo,
                      logoSize: logoSize,
                      codeSize: phone ? 15 : 16,
                      accent: c.warning,
                    ),
                    const SizedBox(height: 6),
                    _MatchRightNote(match: match),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _formatTag(CricketMatch m) {
    final t = m.matchDesc.toUpperCase();
    if (t.contains('TEST')) return 'TEST';
    if (t.contains('T20')) return 'T20';
    if (t.contains('ODI')) return 'ODI';
    if (t.contains('FINAL')) return 'FINAL';
    return 'MATCH';
  }
}

/// Right-aligned note under the right team: countdown (upcoming), result
/// (completed) or live status.
class _MatchRightNote extends StatelessWidget {
  const _MatchRightNote({required this.match});

  final CricketMatch match;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    if (match.isUpcoming && match.startDateTime != null) {
      final raw = _countdown(match.startDateTime);
      final soon = raw == 'Soon' || raw == 'TBC';
      if (soon) {
        return Text(
          'STARTING SOON',
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: c.cyan,
            fontWeight: FontWeight.w900,
            fontSize: 10.5,
            height: 1.15,
            letterSpacing: .3,
          ),
        );
      }
      return Column(
        children: [
          Text(
            'STARTS IN',
            style: TextStyle(
              color: c.muted,
              fontWeight: FontWeight.w700,
              fontSize: 8.5,
              letterSpacing: .3,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            raw.replaceAll('In ', '').toUpperCase(),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: c.cyan,
              fontWeight: FontWeight.w900,
              fontSize: 11,
            ),
          ),
        ],
      );
    }
    if (match.isFinished && match.resultText.isNotEmpty) {
      return Text(
        match.resultText,
        textAlign: TextAlign.center,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: c.success,
          fontWeight: FontWeight.w700,
          fontSize: 9.5,
          height: 1.15,
        ),
      );
    }
    if (match.isLive) {
      return Text(
        match.statusText.isNotEmpty ? match.statusText : 'LIVE NOW',
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: c.live,
          fontWeight: FontWeight.w800,
          fontSize: 9.5,
          height: 1.15,
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

// ---------------------------------------------------------------------------
// Squads tab
// ---------------------------------------------------------------------------

class _SquadsTab extends StatefulWidget {
  const _SquadsTab({required this.formats});

  final List<SquadFormat> formats;

  @override
  State<_SquadsTab> createState() => _SquadsTabState();
}

class _SquadsTabState extends State<_SquadsTab> {
  int _format = 0;
  int _team = 0;

  @override
  Widget build(BuildContext context) {
    final formats = widget.formats;
    final hasAny = formats.any((f) => f.teams.any((t) => t.players.isNotEmpty));
    if (!hasAny) {
      return const SeriesEmptyState(
        title: 'Squads not announced',
        message:
            'Squads for this series are not available from the provider yet.',
        icon: Icons.groups_rounded,
      );
    }

    final fIndex = _format.clamp(0, formats.length - 1);
    final format = formats[fIndex];
    final teams = format.teams;
    final tIndex = _team.clamp(0, teams.length - 1);
    final team = teams[tIndex];
    final showFormatSelector =
        formats.length > 1 && formats.any((f) => f.format.isNotEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (showFormatSelector) ...[
              Flexible(
                child: _SquadToggle(
                  items: [
                    for (final f in formats)
                      _ToggleItem(label: _formatLabel(f.format))
                  ],
                  selected: fIndex,
                  onChanged: (v) => setState(() {
                    _format = v;
                    _team = 0;
                  }),
                ),
              ),
              const SizedBox(width: 10),
            ],
            if (teams.length > 1)
              Flexible(
                child: _SquadToggle(
                  items: [
                    for (final t in teams)
                      _ToggleItem(
                        label: t.shortName.isNotEmpty ? t.shortName : t.name,
                        team: t,
                      )
                  ],
                  selected: tIndex,
                  onChanged: (v) => setState(() => _team = v),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (team.players.isEmpty)
          const SeriesEmptyState(
            title: 'Squad not announced yet',
            message: 'This team\'s squad for this format has not been '
                'announced yet.',
            icon: Icons.groups_rounded,
          )
        else
          _SquadGroups(
            key: ValueKey('squad-${format.format}-${team.identityKey}'),
            team: team,
          ),
      ],
    );
  }

  static String _formatLabel(String format) {
    final f = format.trim();
    if (f.isEmpty) return 'Squad';
    return f;
  }
}

class _ToggleItem {
  const _ToggleItem({required this.label, this.team});
  final String label;
  final SquadTeam? team;
}

/// Glass segmented toggle used for the format + team selectors. Active
/// segment is a cyan glass pill; team items show a small logo.
class _SquadToggle extends StatelessWidget {
  const _SquadToggle({
    required this.items,
    required this.selected,
    required this.onChanged,
  });

  final List<_ToggleItem> items;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      height: 46,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.card.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: c.cyan.withValues(alpha: .4)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(i),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  height: 38,
                  decoration: BoxDecoration(
                    gradient: i == selected
                        ? const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xff35e2ff), Color(0xff0a86ff)],
                          )
                        : null,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: i == selected
                        ? [
                            BoxShadow(
                              color: c.cyan.withValues(alpha: .45),
                              blurRadius: 12,
                              spreadRadius: -2,
                            ),
                          ]
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (items[i].team != null) ...[
                        TeamLogoWidget(
                          logoUrl: items[i].team!.logoUrl,
                          teamName: items[i].team!.name,
                          abbreviation: items[i].label,
                          color: c.cyan,
                          size: 20,
                        ),
                        const SizedBox(width: 6),
                      ],
                      Flexible(
                        child: Text(
                          items[i].label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: i == selected ? Colors.white : c.muted,
                            fontWeight: i == selected
                                ? FontWeight.w800
                                : FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
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

class _SquadGroups extends StatelessWidget {
  const _SquadGroups({super.key, required this.team});

  final SquadTeam team;

  static const _meta = <(String, IconData)>[
    ('Batters', Icons.sports_cricket_rounded),
    ('Wicketkeepers', Icons.back_hand_outlined),
    ('All-Rounders', Icons.change_circle_outlined),
    ('Bowlers', Icons.sports_baseball_outlined),
    ('Reserves / Bench', Icons.event_seat_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final groups = _group(team.players);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final m in _meta)
          if ((groups[m.$1] ?? const []).isNotEmpty) ...[
            _SquadSection(
              title: m.$1,
              icon: m.$2,
              players: groups[m.$1]!,
              team: team,
            ),
            const SizedBox(height: 14),
          ],
      ],
    );
  }

  /// Groups players into the real squad categories. Substitutes/bench players
  /// (when the backend provides them) are pulled into a dedicated Reserves /
  /// Bench section; everyone else is classified by the backend `category`
  /// field, falling back to role-text heuristics for legacy payloads.
  Map<String, List<SquadPlayer>> _group(List<SquadPlayer> players) {
    final batters = <SquadPlayer>[];
    final keepers = <SquadPlayer>[];
    final allRounders = <SquadPlayer>[];
    final bowlers = <SquadPlayer>[];
    final reserves = <SquadPlayer>[];

    for (final p in players) {
      if (p.isSubstitute) {
        reserves.add(p);
        continue;
      }
      final cat = p.category.toLowerCase();
      if (cat.isNotEmpty) {
        switch (cat) {
          case 'wicketkeepers':
            keepers.add(p);
            break;
          case 'allrounders':
            allRounders.add(p);
            break;
          case 'bowlers':
            bowlers.add(p);
            break;
          default:
            batters.add(p);
        }
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
        batters.add(p);
      }
    }
    return {
      'Batters': batters,
      'Wicketkeepers': keepers,
      'All-Rounders': allRounders,
      'Bowlers': bowlers,
      'Reserves / Bench': reserves,
    };
  }
}

class _SquadSection extends StatelessWidget {
  const _SquadSection({
    required this.title,
    required this.icon,
    required this.players,
    required this.team,
  });

  final String title;
  final IconData icon;
  final List<SquadPlayer> players;
  final SquadTeam team;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumGlassPanel(
      bgAsset: SAsset.squadSectionBg,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: c.cyan, size: 16),
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
                    fontSize: 13,
                    letterSpacing: .4,
                  ),
                ),
              ),
              Text(
                '${players.length} PLAYER${players.length == 1 ? '' : 'S'}',
                style: TextStyle(
                  color: c.cyan,
                  fontWeight: FontWeight.w800,
                  fontSize: 10.5,
                  letterSpacing: .3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _PlayerGrid(team: team, players: players),
        ],
      ),
    );
  }
}

class _PlayerGrid extends StatelessWidget {
  const _PlayerGrid({required this.team, required this.players});

  final SquadTeam team;
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
              SizedBox(
                width: width,
                child: _SquadPlayerCard(
                  key: ValueKey(
                    '${team.identityKey}-'
                    '${p.id.isNotEmpty ? p.id : _normalizedPlayerKey(p.name)}',
                  ),
                  player: p,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SquadPlayerCard extends StatelessWidget {
  const _SquadPlayerCard({super.key, required this.player});

  final SquadPlayer player;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final roleTag = _roleTag(player);
    final captainTag = player.isCaptain
        ? 'C'
        : player.isViceCaptain
            ? 'VC'
            : null;
    final (first, last) = _splitName(player.name);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: c.card.withValues(alpha: .45),
        border: Border.all(color: c.cyan.withValues(alpha: .28)),
      ),
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              SeriesPlayerAvatar(
                name: player.name,
                imageUrl: player.imageUrl,
                size: 56,
              ),
              if (captainTag != null)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    width: 19,
                    height: 19,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: captainTag == 'C' ? c.warning : c.cyan,
                      shape: BoxShape.circle,
                      border: Border.all(color: c.bg, width: 1.5),
                    ),
                    child: Text(
                      captainTag,
                      style: TextStyle(
                        color: captainTag == 'C'
                            ? const Color(0xff04101f)
                            : Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 8.5,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            first,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .82),
              fontWeight: FontWeight.w600,
              fontSize: 11,
              height: 1.05,
            ),
          ),
          Text(
            last.isEmpty ? ' ' : last,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: c.text,
              fontWeight: FontWeight.w900,
              fontSize: 12,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 7),
          if (roleTag != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: roleTag.$2.withValues(alpha: .16),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: roleTag.$2.withValues(alpha: .6)),
              ),
              child: Text(
                roleTag.$1,
                style: TextStyle(
                  color: roleTag.$2,
                  fontWeight: FontWeight.w900,
                  fontSize: 9,
                  letterSpacing: .3,
                ),
              ),
            ),
        ],
      ),
    );
  }

  static (String, String) _splitName(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return ('', '');
    if (parts.length == 1) return ('', parts.first);
    return (parts.first, parts.sublist(1).join(' '));
  }

  (String, Color)? _roleTag(SquadPlayer p) {
    switch (p.roleCode.toUpperCase()) {
      case 'WK':
        return ('WK', const Color(0xfff59e0b));
      case 'AR':
        return ('AR', const Color(0xff14b8a6));
      case 'BOWL':
        return ('BOWL', const Color(0xff60a5fa));
      case 'BAT':
        return ('BAT', const Color(0xff22d3ee));
    }
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
      return const SeriesEmptyState(
        title: 'Stats not available',
        message: 'Player stats are not available for this series yet.',
        icon: Icons.bar_chart_rounded,
      );
    }

    final cards = _statCards(batting, bowling);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (pointsRows.isNotEmpty) ...[
          _PointsTableCard(rows: pointsRows),
          const SizedBox(height: 14),
        ],
        if (batting.isNotEmpty) ...[
          _StatsTableCard(
            title: 'Top Run Scorers',
            icon: Icons.sports_cricket_rounded,
            rows: batting.take(5).toList(),
            metricHeader: 'RUNS',
            isBowling: false,
          ),
          const SizedBox(height: 14),
        ],
        if (bowling.isNotEmpty) ...[
          _StatsTableCard(
            title: 'Top Wicket Takers',
            icon: Icons.sports_baseball_outlined,
            rows: bowling.take(5).toList(),
            metricHeader: 'WICKETS',
            isBowling: true,
          ),
          const SizedBox(height: 14),
        ],
        if (cards.isNotEmpty) _SeriesStatsGrid(cards: cards),
      ],
    );
  }

  List<_StatCard> _statCards(
    List<Map<String, dynamic>> batting,
    List<Map<String, dynamic>> bowling,
  ) {
    final cards = <_StatCard>[];
    if (batting.isNotEmpty) {
      final top = batting.first;
      cards.add(_StatCard(
        icon: Icons.sports_cricket_rounded,
        label: 'Most Runs',
        value: apiString(top['runs'], '0'),
        sub: _nameTeam(top),
      ));
    }
    if (bowling.isNotEmpty) {
      final top = bowling.first;
      cards.add(_StatCard(
        icon: Icons.sports_baseball_outlined,
        label: 'Most Wickets',
        value: apiString(top['wickets'], '0'),
        sub: _nameTeam(top),
      ));
    }
    final played = _maxMatches([...batting, ...bowling]);
    if (played > 0) {
      cards.add(_StatCard(
        icon: Icons.event_available_rounded,
        label: 'Matches Played',
        value: '$played',
        sub: 'In this series',
      ));
    }
    if (batting.isNotEmpty) {
      final best = batting.reduce((a, b) =>
          (apiDouble(a['average']) ?? 0) >= (apiDouble(b['average']) ?? 0)
              ? a
              : b);
      final avg = apiDouble(best['average']);
      if (avg != null && avg > 0) {
        cards.add(_StatCard(
          icon: Icons.trending_up_rounded,
          label: 'Best Batting Avg',
          value: avg.toStringAsFixed(2),
          sub: _nameTeam(best),
        ));
      }
    }
    return cards;
  }

  String _nameTeam(Map<String, dynamic> row) {
    final name = apiString(row['playerName'] ?? row['name'], 'Player');
    final team = apiString(row['team']);
    return team.isEmpty ? name : '$name ($team)';
  }

  int _maxMatches(List<Map<String, dynamic>> rows) {
    var max = 0;
    for (final r in rows) {
      final m = apiInt(r['matches']) ?? 0;
      if (m > max) max = m;
    }
    return max;
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
    final rows =
        apiList(section['rows'] ?? section['players'] ?? section['items']);
    return rows.map(apiMap).where((m) => m.isNotEmpty).toList();
  }
}

class _PointsTableCard extends StatelessWidget {
  const _PointsTableCard({required this.rows});

  final List<Map<String, dynamic>> rows;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumSectionPanel(
      title: 'Points Table',
      icon: Icons.table_chart_outlined,
      bgAsset: SAsset.statsTableBg,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                const SizedBox(width: 22),
                Expanded(child: Text('TEAM', style: _hStyle(c))),
                for (final h in const ['P', 'W', 'L', 'Pts', 'NRR'])
                  SizedBox(
                      width: h == 'NRR' ? 44 : 28,
                      child: Text(h,
                          textAlign: TextAlign.center, style: _hStyle(c))),
              ],
            ),
          ),
          for (var i = 0; i < rows.length; i++)
            _PointsRow(rank: i + 1, row: rows[i]),
        ],
      ),
    );
  }

  TextStyle _hStyle(CricColors c) =>
      TextStyle(color: c.muted, fontWeight: FontWeight.w900, fontSize: 10.5);
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
        border: Border(top: BorderSide(color: c.cyan.withValues(alpha: .14))),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text('$rank',
                style: TextStyle(
                    color: c.muted, fontWeight: FontWeight.w900, fontSize: 12)),
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
          _val(c, row['played'] ?? row['matches'], 28),
          _val(c, row['won'], 28),
          _val(c, row['lost'], 28),
          _val(c, row['points'], 28, bold: true, color: c.cyan),
          _val(c, row['nrr'], 44),
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
          fontSize: 11.5,
        ),
      ),
    );
  }
}

/// Premium stats table (Top Run Scorers / Top Wicket Takers).
class _StatsTableCard extends StatelessWidget {
  const _StatsTableCard({
    required this.title,
    required this.icon,
    required this.rows,
    required this.metricHeader,
    required this.isBowling,
  });

  final String title;
  final IconData icon;
  final List<Map<String, dynamic>> rows;
  final String metricHeader;
  final bool isBowling;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final showMatches = context.w > 360;
    return PremiumSectionPanel(
      title: title,
      icon: icon,
      bgAsset: SAsset.statsTableBg,
      trailing: const PremiumViewAll(label: 'View All'),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                SizedBox(width: 20, child: Text('#', style: _h(c))),
                const SizedBox(width: 36),
                Expanded(child: Text('PLAYER', style: _h(c))),
                SizedBox(
                    width: 34,
                    child: Text('TEAM',
                        style: _h(c), textAlign: TextAlign.center)),
                if (showMatches)
                  SizedBox(
                      width: 34,
                      child: Text('MAT',
                          style: _h(c), textAlign: TextAlign.center)),
                SizedBox(
                    width: 42,
                    child: Text(metricHeader,
                        style: _h(c), textAlign: TextAlign.right)),
                SizedBox(
                    width: 44,
                    child:
                        Text('AVG', style: _h(c), textAlign: TextAlign.right)),
              ],
            ),
          ),
          for (var i = 0; i < rows.length; i++)
            _StatRow(
              rank: i + 1,
              row: rows[i],
              isBowling: isBowling,
              showMatches: showMatches,
            ),
        ],
      ),
    );
  }

  TextStyle _h(CricColors c) => TextStyle(
        color: c.muted,
        fontWeight: FontWeight.w800,
        fontSize: 9.5,
        letterSpacing: .3,
      );
}

class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.rank,
    required this.row,
    required this.isBowling,
    required this.showMatches,
  });

  final int rank;
  final Map<String, dynamic> row;
  final bool isBowling;
  final bool showMatches;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final name = apiString(row['playerName'] ?? row['name'], 'Player');
    final team = apiString(row['team']);
    final image = _verifiedSquadImage(row);
    final matches = apiString(row['matches'], '-');
    final metric = isBowling
        ? apiString(row['wickets'], '0')
        : apiString(row['runs'], '0');
    final avg = apiDouble(row['average']);
    final avgText = avg != null && avg > 0 ? avg.toStringAsFixed(2) : '-';
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.cyan.withValues(alpha: .12))),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            child: Text(
              '$rank',
              style: TextStyle(
                  color: c.muted, fontWeight: FontWeight.w900, fontSize: 12),
            ),
          ),
          SeriesPlayerAvatar(name: name, imageUrl: image, size: 30),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: c.text, fontWeight: FontWeight.w800, fontSize: 12.5),
            ),
          ),
          SizedBox(
            width: 34,
            child: Text(
              team,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: c.muted, fontWeight: FontWeight.w700, fontSize: 11),
            ),
          ),
          if (showMatches)
            SizedBox(
              width: 34,
              child: Text(
                matches,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Colors.white.withValues(alpha: .85),
                    fontWeight: FontWeight.w700,
                    fontSize: 12),
              ),
            ),
          SizedBox(
            width: 42,
            child: Text(
              metric,
              textAlign: TextAlign.right,
              style: TextStyle(
                  color: c.cyan, fontWeight: FontWeight.w900, fontSize: 14),
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              avgText,
              textAlign: TextAlign.right,
              style: TextStyle(
                  color: c.text, fontWeight: FontWeight.w700, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.sub,
  });
  final IconData icon;
  final String label;
  final String value;
  final String sub;
}

class _SeriesStatsGrid extends StatelessWidget {
  const _SeriesStatsGrid({required this.cards});

  final List<_StatCard> cards;

  @override
  Widget build(BuildContext context) {
    return PremiumSectionPanel(
      title: 'Series Stats',
      icon: Icons.bar_chart_rounded,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const spacing = 10.0;
          final width = (constraints.maxWidth - spacing) / 2;
          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: [
              for (final card in cards)
                SizedBox(width: width, child: _StatGridTile(card: card)),
            ],
          );
        },
      ),
    );
  }
}

class _StatGridTile extends StatelessWidget {
  const _StatGridTile({required this.card});

  final _StatCard card;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: c.card.withValues(alpha: .5),
        border: Border.all(color: c.cyan.withValues(alpha: .3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(card.icon, color: c.cyan, size: 13),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  card.label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.cyan,
                    fontWeight: FontWeight.w800,
                    fontSize: 9.5,
                    letterSpacing: .3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            card.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: c.text,
              fontWeight: FontWeight.w900,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            card.sub,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: c.muted,
              fontWeight: FontWeight.w600,
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Squad data models + parsers
// ---------------------------------------------------------------------------

/// A named format group (e.g. Test, ODI) holding the teams that have an
/// announced squad for that format.
class SquadFormat {
  const SquadFormat({required this.format, required this.teams});

  final String format;
  final List<SquadTeam> teams;
}

class SquadTeam {
  const SquadTeam({
    required this.name,
    required this.shortName,
    this.id = '',
    this.logoUrl,
    this.players = const [],
  });

  final String name;
  final String shortName;

  /// Stable team identity (Cricbuzz team id or short name). Used to build
  /// unique per-team player widget keys so Team B never reuses Team A images.
  final String id;
  final String? logoUrl;
  final List<SquadPlayer> players;

  /// Key used to namespace this team's player widgets. Prefers the team id,
  /// falling back to the normalized short name / name.
  String get identityKey {
    if (id.trim().isNotEmpty) return id.trim();
    if (shortName.trim().isNotEmpty) return shortName.trim().toLowerCase();
    return name.trim().toLowerCase();
  }
}

/// Normalizes a player name for use in a fallback widget key.
String _normalizedPlayerKey(String name) =>
    name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');

class SquadPlayer {
  const SquadPlayer({
    required this.id,
    required this.name,
    required this.role,
    this.imageUrl,
    this.isCaptain = false,
    this.isViceCaptain = false,
    this.isWicketKeeper = false,
    this.isSubstitute = false,
    this.category = '',
    this.roleCode = '',
  });

  final String id;
  final String name;
  final String role;
  final String? imageUrl;
  final bool isCaptain;
  final bool isViceCaptain;
  final bool isWicketKeeper;
  final bool isSubstitute;

  /// Backend-provided category bucket: batters / wicketkeepers / allRounders /
  /// bowlers. Empty when the backend does not classify (legacy payloads).
  final String category;

  /// Compact role pill text: BAT / WK / AR / BOWL. Empty when unknown.
  final String roleCode;
}

/// Parses the `/series/:id/squads` payload into format groups
/// (`formats[].teams[].players[]`). Falls back to a single unnamed format
/// built from the flat `teams[]` when the backend does not provide formats.
List<SquadFormat> _parseSquadFormats(Map<String, dynamic> data) {
  final root = data['data'] is Map ? apiMap(data['data']) : data;
  final rawFormats = apiList(root['formats']);
  final formats = <SquadFormat>[];
  for (final rawF in rawFormats) {
    final f = apiMap(rawF);
    final teams = _teamsFromRawList(apiList(f['teams']));
    if (teams.isEmpty) continue;
    formats.add(SquadFormat(
      format: apiString(f['format'] ?? f['squadType']),
      teams: teams,
    ));
  }
  if (formats.isNotEmpty) return formats;

  // Legacy / fallback: a single group from the flat teams[].
  final teams = _parseSquadTeams(data);
  if (teams.isEmpty) return const [];
  return [SquadFormat(format: '', teams: teams)];
}

List<SquadTeam> _teamsFromRawList(List<dynamic> rawTeams) {
  final teams = <SquadTeam>[];
  for (final raw in rawTeams) {
    final t = apiMap(raw);
    final players = apiList(t['players'])
        .map(_parseSquadPlayer)
        .where((p) => !_isSupportStaffPlayer(p))
        .toList();
    if (players.isEmpty) continue;
    final teamName = apiString(t['teamName'] ?? t['team_name'], 'Team');
    final teamShort =
        apiString(t['teamShortName'] ?? t['teamShort'] ?? t['team_short']);
    teams.add(SquadTeam(
      id: apiString(t['squadId'] ?? t['teamId'] ?? t['team_id'] ?? t['id'],
          teamShort.isNotEmpty ? teamShort : teamName),
      name: teamName,
      shortName: teamShort,
      logoUrl: apiString(t['logoUrl'] ?? t['logo_url']).isEmpty
          ? null
          : apiString(t['logoUrl'] ?? t['logo_url']),
      players: players,
    ));
  }
  return teams;
}

/// Parses the `/series/:id/squads` payload (teams[].players[]).
List<SquadTeam> _parseSquadTeams(Map<String, dynamic> data) {
  final root = data['data'] is Map ? apiMap(data['data']) : data;
  final rawTeams = apiList(root['teams']);
  final teams = <SquadTeam>[];
  for (final raw in rawTeams) {
    final t = apiMap(raw);
    final players = apiList(t['players'])
        .map(_parseSquadPlayer)
        .where((p) => !_isSupportStaffPlayer(p))
        .toList();
    if (players.isEmpty) continue;
    final teamName = apiString(t['teamName'] ?? t['team_name'], 'Team');
    final teamShort =
        apiString(t['teamShortName'] ?? t['teamShort'] ?? t['team_short']);
    teams.add(SquadTeam(
      id: apiString(t['teamId'] ?? t['team_id'] ?? t['id'],
          teamShort.isNotEmpty ? teamShort : teamName),
      name: teamName,
      shortName: teamShort,
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
  final image = _verifiedSquadImage(p);
  return SquadPlayer(
    id: id,
    name: apiString(p['name'] ?? p['playerName'] ?? p['player_name'], 'Player'),
    role: apiString(p['role'] ?? p['playerRole']),
    imageUrl: image,
    isCaptain: apiBool(p['isCaptain'] ?? p['is_captain']),
    isViceCaptain: apiBool(p['isViceCaptain'] ?? p['is_vice_captain']),
    isWicketKeeper: apiBool(p['isWicketKeeper'] ?? p['is_wicketkeeper']),
    isSubstitute: apiBool(p['isSubstitute'] ?? p['is_substitute']),
    category: apiString(p['category']),
    roleCode: apiString(p['roleCode']),
  );
}

bool _isSupportStaffPlayer(SquadPlayer player) {
  final text = '${player.name} ${player.role}'.toLowerCase();
  return RegExp(
    r'\b(head coach|assistant coach|batting coach|bowling coach|fielding coach|support staff|team manager|manager|physio|analyst|selector|mentor|coach)\b',
  ).hasMatch(text);
}

String? _verifiedSquadImage(Map<String, dynamic> p) {
  final image = apiString(p['imageUrl'] ??
      p['image_url'] ??
      p['faceImageUrl'] ??
      p['face_image_url']);
  if (image.isEmpty) return null;
  final source = apiString(p['imageSource'] ?? p['image_source']).toLowerCase();
  final profile = apiString(p['profileUrl'] ?? p['profile_url']);
  final playerId = apiString(p['playerId'] ?? p['player_id'] ?? p['id']);
  final trustedHost = image.contains('static.cricbuzz.com') ||
      image.contains('cricbuzz.com/a/img/');
  final hasIdentity = playerId.isNotEmpty || profile.contains('/profiles/');
  if (trustedHost && (source == 'cricbuzz' || source.isEmpty) && hasIdentity) {
    return image;
  }
  if (kDebugMode) {
    debugPrint('[SquadImage] rejected unverified image player='
        '${apiString(p['name'] ?? p['playerName'] ?? p['player_name'])} '
        'id=$playerId source=$source image=$image');
  }
  return null;
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
        final player = _parseSquadPlayer(raw);
        if (!_isSupportStaffPlayer(player)) players.add(player);
      }
      if (players.isNotEmpty) break;
    }
    for (final raw in apiList(t['bench'] ?? t['substitutes'])) {
      final p = _parseSquadPlayer(raw);
      if (_isSupportStaffPlayer(p)) continue;
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
    final teamName = apiString(t['team_name'] ?? t['teamName'], fallbackName);
    final teamShort =
        apiString(t['team_short'] ?? t['teamShort'], fallbackShort);
    return SquadTeam(
      id: apiString(t['teamId'] ?? t['team_id'] ?? t['id'],
          teamShort.isNotEmpty ? teamShort : teamName),
      name: teamName,
      shortName: teamShort,
      logoUrl: apiString(t['logoUrl'] ?? t['logo_url']).isEmpty
          ? fallbackLogo
          : apiString(t['logoUrl'] ?? t['logo_url']),
      players: players,
    );
  }

  final t1 =
      buildTeam(root['team1'], match.teamA, match.teamAShort, match.teamALogo);
  final t2 =
      buildTeam(root['team2'], match.teamB, match.teamBShort, match.teamBLogo);
  if (t1 != null) teams.add(t1);
  if (t2 != null) teams.add(t2);
  return teams;
}

// ---------------------------------------------------------------------------
// Small shared helpers
// ---------------------------------------------------------------------------

String _dateOnlyYear(DateTime d) {
  const m = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];
  return '${m[d.month - 1]} ${d.day}, ${d.year}';
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
