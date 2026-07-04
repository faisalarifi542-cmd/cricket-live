import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../../app_theme.dart';
import '../../api_models.dart';
import '../../components.dart';
import '../../models/api_response.dart';
import '../../models/cricket_match.dart';
import '../../repositories/cricket_repository.dart';
import '../../utils/team_format.dart';
import '../../widgets/team_score_view.dart';
import 'schedule_strip.dart';

part 'widgets/schedule_header.dart';
part 'widgets/schedule_cards.dart';
part 'widgets/schedule_sheets.dart';

/// Premium Schedule artwork asset paths (copied into assets/images/schedule/).
class _Asset {
  static const _base = 'assets/images/schedule';
  static const stadiumTop = '$_base/stadium_top_bg.webp';
  static const matchCardBg = '$_base/match_card_bg.webp';
  static const floodLeft = '$_base/flood_light_left.webp';
  static const floodRight = '$_base/flood_light_right.webp';
  static const vsStreak = '$_base/vs_light_streak.webp';
  static const vsGlow = '$_base/vs_glow_transparent.webp';

  static const iconAll = '$_base/icons/category_all.webp';
  static const iconInternational = '$_base/icons/category_international.webp';
  static const iconLeague = '$_base/icons/category_league.webp';
  static const iconDomestic = '$_base/icons/category_domestic.webp';
  static const iconCalendar = '$_base/icons/category_calendar.webp';

  static const _logos = '$_base/tournament_logos';
  static const logoAsianGames = '$_logos/asian_games_fallback.webp';
  static const logoAcc = '$_logos/asian_cricket_council_fallback.webp';
  static const logoWcLeagueTwo = '$_logos/world_cup_league_two_fallback.webp';
  static const logoCounty = '$_logos/county_championship_fallback.webp';
  static const logoT20Mumbai = '$_logos/t20_mumbai_fallback.webp';
  static const logoTour = '$_logos/tour_series_fallback.webp';
  static const logoOther = '$_logos/other_tournament_fallback.webp';

  /// Maps a series/tournament name to its fallback logo asset.
  static String tournamentLogo(String series) {
    final s = series.toLowerCase();
    if (s.contains('asian games')) return logoAsianGames;
    if (s.contains('acc') || s.contains('asian cricket council')) {
      return logoAcc;
    }
    if (s.contains('league two') || s.contains('world cup league')) {
      return logoWcLeagueTwo;
    }
    if (s.contains('county championship') || s.contains('county')) {
      return logoCounty;
    }
    if (s.contains('t20 mumbai') || s.contains('mumbai')) return logoT20Mumbai;
    if (s.contains('tour of')) return logoTour;
    return logoOther;
  }
}

/// Draws a "light-on-black" texture (e.g. the floodlight / VS streak assets,
/// which are RGB with no alpha) using [BlendMode.screen] so the dark
/// background disappears and only the light contributes — i.e. an additive
/// glow over whatever is behind it. Falls back to nothing until decoded.
class _BlendImage extends StatefulWidget {
  const _BlendImage(
    this.asset, {
    this.width,
    this.height,
    this.opacity = 1.0,
  });

  final String asset;
  final double? width;
  final double? height;
  final double opacity;

  @override
  State<_BlendImage> createState() => _BlendImageState();
}

class _BlendImageState extends State<_BlendImage> {
  static final Map<String, ui.Image> _cache = {};
  ui.Image? _image;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cached = _cache[widget.asset];
    if (cached != null) {
      _image = cached;
      return;
    }
    try {
      final data = await rootBundle.load(widget.asset);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      _cache[widget.asset] = frame.image;
      if (mounted) setState(() => _image = frame.image);
    } catch (_) {
      // Asset missing/undecodable — render nothing (graceful).
    }
  }

  @override
  Widget build(BuildContext context) {
    final img = _image;
    final size = Size(
      widget.width ?? (img?.width.toDouble() ?? 0),
      widget.height ?? (img?.height.toDouble() ?? 0),
    );
    if (img == null) return SizedBox(width: size.width, height: size.height);
    return CustomPaint(
      size: size,
      painter: _BlendPainter(img, BlendMode.screen, widget.opacity),
    );
  }
}

class _BlendPainter extends CustomPainter {
  _BlendPainter(this.image, this.blendMode, this.opacity);

  final ui.Image image;
  final BlendMode blendMode;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..blendMode = blendMode
      ..filterQuality = FilterQuality.high
      ..color = Color.fromRGBO(255, 255, 255, opacity.clamp(0.0, 1.0));
    final src =
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    final dst = Offset.zero & size;
    canvas.drawImageRect(image, src, dst, paint);
  }

  @override
  bool shouldRepaint(_BlendPainter old) =>
      old.image != image ||
      old.blendMode != blendMode ||
      old.opacity != opacity;
}

/// Premium Schedule screen — stadium-atmosphere header, rich date selector,
/// icon category chips, a summary/sort row, and premium match cards with a
/// glowing VS badge and a split time/venue panel. Mirrors the CricPro
/// dark-navy/cyan design used across the redesigned app.
class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({
    super.key,
    required this.onOpenSeries,
    this.onOpenMatch,
  });

  final VoidCallback onOpenSeries;

  /// Invoked with the resolved match id when the user taps a fixture card.
  final ValueChanged<String>? onOpenMatch;

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

enum _Sort { time, series, type }

class _ScheduleScreenState extends State<ScheduleScreen> {
  int selectedDay = 0;
  int filterIndex = 0;
  _Sort _sort = _Sort.time;
  String _search = '';
  final CricketRepository _repository = CricketRepository();
  late Future<ApiEnvelope<List<ScheduleDay>>> _schedule;

  static const _filters = <_CategoryFilter>[
    _CategoryFilter('All', Icons.apps_rounded, asset: _Asset.iconAll),
    _CategoryFilter('International', Icons.public_rounded,
        asset: _Asset.iconInternational),
    _CategoryFilter('League', Icons.emoji_events_rounded,
        asset: _Asset.iconLeague),
    _CategoryFilter('Domestic', Icons.shield_rounded,
        asset: _Asset.iconDomestic),
    _CategoryFilter('Women', Icons.female_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _schedule = _repository.scheduleByDay(type: _filterType);
  }

  String get _filterType => switch (filterIndex) {
        1 => 'international',
        2 => 'league',
        3 => 'domestic',
        4 => 'women',
        _ => 'all',
      };

  void _setFilter(int index) {
    setState(() {
      filterIndex = index;
      selectedDay = 0;
      _schedule = _repository.scheduleByDay(type: _filterType);
    });
  }

  Future<void> _refresh() async {
    setState(() {
      _schedule =
          _repository.scheduleByDay(type: _filterType, forceRefresh: true);
    });
    await _schedule;
  }

  /// Builds the date strip as a FIXED 14-day window starting at the device's
  /// LOCAL today (see [buildScheduleStrip]) and buckets every match into it by
  /// its effective calendar date. The strip is independent of the payload, so
  /// Schedule always opens on today and live multi-day Tests show under today.
  List<ScheduleDay> _regroupByLocalDate(List<ScheduleDay> days) {
    final matches = [for (final day in days) ...day.matches];
    return buildScheduleStrip(matches: matches, now: DateTime.now());
  }

  List<CricketMatch> _applySearchSort(List<CricketMatch> matches) {
    var list = matches;
    if (_search.trim().isNotEmpty) {
      final q = _search.toLowerCase();
      list = list
          .where((m) =>
              m.series.toLowerCase().contains(q) ||
              m.teamA.toLowerCase().contains(q) ||
              m.teamB.toLowerCase().contains(q) ||
              m.teamAShort.toLowerCase().contains(q) ||
              m.teamBShort.toLowerCase().contains(q) ||
              m.venue.toLowerCase().contains(q))
          .toList();
    } else {
      list = [...list];
    }
    switch (_sort) {
      case _Sort.time:
        list.sort((a, b) => (a.startDateTime ?? DateTime(2100))
            .compareTo(b.startDateTime ?? DateTime(2100)));
      case _Sort.series:
        list.sort((a, b) {
          final s = a.series.toLowerCase().compareTo(b.series.toLowerCase());
          if (s != 0) return s;
          return (a.startDateTime ?? DateTime(2100))
              .compareTo(b.startDateTime ?? DateTime(2100));
        });
      case _Sort.type:
        list.sort((a, b) {
          final t =
              a.matchDesc.toLowerCase().compareTo(b.matchDesc.toLowerCase());
          if (t != 0) return t;
          return (a.startDateTime ?? DateTime(2100))
              .compareTo(b.startDateTime ?? DateTime(2100));
        });
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      decoration: BoxDecoration(gradient: c.bgGradient),
      child: Stack(
        children: [
          // Stadium-broadcast atmosphere behind the header + date selector:
          // a real stadium image, dark gradient for readability, dual
          // floodlight images and a fade into the page background.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 300,
            child: IgnorePointer(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const StadiumImage(
                    _Asset.stadiumTop,
                    alignment: Alignment.topCenter,
                    remoteKey: 'schedule_backdrop',
                  ),
                  // Darken + fade into the page background for readability.
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: c.stadiumOverlayColors,
                        stops: const [0, .45, .86, 1],
                      ),
                    ),
                  ),
                  // Left + right floodlight beams ON TOP of the dark layer,
                  // screen-blended so only their light shows (the assets are
                  // RGB with no alpha). Reads as stadium floodlights.
                  const Align(
                    alignment: Alignment.topLeft,
                    child: _BlendImage(
                      _Asset.floodLeft,
                      width: 240,
                      height: 240,
                      opacity: .62,
                    ),
                  ),
                  const Align(
                    alignment: Alignment.topRight,
                    child: _BlendImage(
                      _Asset.floodRight,
                      width: 240,
                      height: 240,
                      opacity: .62,
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
              child: FutureBuilder<ApiEnvelope<List<ScheduleDay>>>(
                future: _schedule,
                builder: (context, snapshot) {
                  // The date strip is ALWAYS the fixed 14-day window from today
                  // (independent of the payload), so `days` is never empty.
                  // Loading/empty/error are driven by the snapshot itself.
                  final days = _regroupByLocalDate(
                      snapshot.data?.data ?? const <ScheduleDay>[]);
                  final waiting =
                      snapshot.connectionState == ConnectionState.waiting &&
                          !snapshot.hasData;
                  final safeSelected = selectedDay.clamp(0, days.length - 1);
                  final rawMatches = days[safeSelected].matches;
                  final matches = _applySearchSort(rawMatches);

                  return ListView(
                    padding: EdgeInsets.fromLTRB(
                      context.horizontalPadding,
                      14,
                      context.horizontalPadding,
                      // Clear the nav + sticky banner so the last fixture card
                      // is never tucked under the bottom navigation.
                      context.mainScrollBottomInset,
                    ),
                    children: [
                      _ScheduleHeader(
                        onSearch: _openSearch,
                        onFilter: _openFilter,
                      ),
                      const SizedBox(height: 18),
                      _DateSelector(
                        days: days,
                        selected: safeSelected,
                        loading: waiting,
                        onSelect: (i) => setState(() => selectedDay = i),
                      ),
                      const SizedBox(height: 18),
                      _CategoryChips(
                        filters: _filters,
                        selected: filterIndex,
                        onSelect: _setFilter,
                      ),
                      const SizedBox(height: 18),
                      if (!waiting)
                        _SummaryRow(
                          label:
                              _summaryLabel(days, safeSelected, matches.length),
                          sortLabel: _sortLabel,
                          onSort: _openSort,
                        ),
                      const SizedBox(height: 14),
                      if (waiting)
                        const _ScheduleSkeletonList()
                      else if (snapshot.hasError && !snapshot.hasData)
                        _ScheduleStateCard(
                          icon: Icons.cloud_off_rounded,
                          title: 'Unable to load schedule',
                          message:
                              'Please check your connection and try again.',
                          onRetry: _refresh,
                        )
                      else if (matches.isEmpty)
                        _ScheduleStateCard(
                          icon: Icons.sports_cricket_rounded,
                          title: _search.isNotEmpty
                              ? 'No matches found'
                              : 'No matches scheduled',
                          message: _search.isNotEmpty
                              ? 'No fixtures match "$_search". Try another search.'
                              : 'Check another date or view upcoming matches.',
                          onRetry: _refresh,
                        )
                      else
                        for (final match in matches)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: _ScheduleMatchCard(
                              match: match,
                              onTap: () {
                                if (match.id.isNotEmpty &&
                                    widget.onOpenMatch != null) {
                                  widget.onOpenMatch!(match.id);
                                } else {
                                  widget.onOpenSeries();
                                }
                              },
                            ),
                          ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  String get _sortLabel => switch (_sort) {
        _Sort.time => 'Sort by Time',
        _Sort.series => 'Sort by Series',
        _Sort.type => 'Sort by Type',
      };

  String _summaryLabel(List<ScheduleDay> days, int index, int count) {
    final day = days[index];
    // Prefer "Today"/"Tomorrow" for the selected day so the Schedule summary
    // matches the wording Series Overview / Match Details use for the same
    // match (the cross-screen date-wording consistency the QA flagged).
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    String base;
    if (day.date != null) {
      final d = DateTime(day.date!.year, day.date!.month, day.date!.day);
      if (d == today) {
        base = 'Today';
      } else if (d == tomorrow) {
        base = 'Tomorrow';
      } else {
        base = day.dayDescriptive;
      }
    } else {
      base = day.dayDescriptive;
    }
    if (base.isEmpty) base = 'Schedule';
    return '$base — $count match${count == 1 ? '' : 'es'}';
  }

  // --- Bottom sheets --------------------------------------------------------

  void _openSearch() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SearchSheet(
        initial: _search,
        onChanged: (v) => setState(() => _search = v),
      ),
    );
  }

  void _openFilter() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => _FilterSheet(
        filters: _filters,
        selected: filterIndex,
        onSelect: (i) {
          Navigator.pop(sheetCtx);
          _setFilter(i);
        },
      ),
    );
  }

  void _openSort() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => _SortSheet(
        selected: _sort,
        onSelect: (s) {
          Navigator.pop(sheetCtx);
          setState(() => _sort = s);
        },
      ),
    );
  }
}

class _CategoryFilter {
  const _CategoryFilter(this.label, this.icon, {this.asset});
  final String label;
  final IconData icon;
  final String? asset;
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

