import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../../app_theme.dart';
import '../../components.dart';
import '../../models/api_response.dart';
import '../../models/cricket_match.dart';
import '../../repositories/cricket_repository.dart';

/// Premium Schedule artwork asset paths (copied into assets/images/schedule/).
class _Asset {
  static const _base = 'assets/images/schedule';
  static const stadiumTop = '$_base/stadium_top_bg.png';
  static const matchCardBg = '$_base/match_card_bg.png';
  static const floodLeft = '$_base/flood_light_left.png';
  static const floodRight = '$_base/flood_light_right.png';
  static const vsStreak = '$_base/vs_light_streak.png';
  static const vsGlow = '$_base/vs_glow_transparent.png';

  static const iconAll = '$_base/icons/category_all.png';
  static const iconInternational = '$_base/icons/category_international.png';
  static const iconLeague = '$_base/icons/category_league.png';
  static const iconDomestic = '$_base/icons/category_domestic.png';
  static const iconCalendar = '$_base/icons/category_calendar.png';

  static const _logos = '$_base/tournament_logos';
  static const logoAsianGames = '$_logos/asian_games_fallback.png';
  static const logoAcc = '$_logos/asian_cricket_council_fallback.png';
  static const logoWcLeagueTwo = '$_logos/world_cup_league_two_fallback.png';
  static const logoCounty = '$_logos/county_championship_fallback.png';
  static const logoT20Mumbai = '$_logos/t20_mumbai_fallback.png';
  static const logoTour = '$_logos/tour_series_fallback.png';
  static const logoOther = '$_logos/other_tournament_fallback.png';

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
                      opacity: .85,
                    ),
                  ),
                  const Align(
                    alignment: Alignment.topRight,
                    child: _BlendImage(
                      _Asset.floodRight,
                      width: 240,
                      height: 240,
                      opacity: .85,
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
                  final days = snapshot.data?.data ?? const <ScheduleDay>[];
                  final waiting =
                      snapshot.connectionState == ConnectionState.waiting &&
                          days.isEmpty;
                  final safeSelected =
                      days.isEmpty ? 0 : selectedDay.clamp(0, days.length - 1);
                  final rawMatches = days.isEmpty
                      ? <CricketMatch>[]
                      : days[safeSelected].matches;
                  final matches = _applySearchSort(rawMatches);

                  return ListView(
                    padding: EdgeInsets.fromLTRB(
                      context.horizontalPadding,
                      14,
                      context.horizontalPadding,
                      // With extendBody:false the bottom bar reserves real
                      // space; a small inset is enough breathing room.
                      context.mainBottomPadding + 8,
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
                      if (!waiting && days.isNotEmpty)
                        _SummaryRow(
                          label:
                              _summaryLabel(days, safeSelected, matches.length),
                          sortLabel: _sortLabel,
                          onSort: _openSort,
                        ),
                      const SizedBox(height: 14),
                      if (waiting)
                        const _ScheduleSkeletonList()
                      else if (snapshot.hasError && days.isEmpty)
                        _ScheduleStateCard(
                          icon: Icons.cloud_off_rounded,
                          title: 'Unable to load schedule',
                          message:
                              'Please check your connection and try again.',
                          onRetry: _refresh,
                        )
                      else if (days.isEmpty)
                        _ScheduleStateCard(
                          icon: Icons.event_busy_rounded,
                          title: 'No fixtures found',
                          message:
                              'Try another schedule filter or refresh shortly.',
                          onRetry: _refresh,
                        )
                      else if (matches.isEmpty)
                        _ScheduleStateCard(
                          icon: Icons.sports_cricket_rounded,
                          title: _search.isNotEmpty
                              ? 'No matches found'
                              : 'No matches scheduled for this day',
                          message: _search.isNotEmpty
                              ? 'No fixtures match "$_search". Try another search.'
                              : 'Pick another date above or check back later.',
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
    final descriptive = days[index].dayDescriptive;
    final base = descriptive.isEmpty ? 'Schedule' : descriptive;
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

class _ScheduleHeader extends StatelessWidget {
  const _ScheduleHeader({required this.onSearch, required this.onFilter});

  final VoidCallback onSearch;
  final VoidCallback onFilter;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Row(
      children: [
        Expanded(
          child: Text(
            'SCHEDULE',
            style: TextStyle(
              color: c.text,
              fontWeight: FontWeight.w900,
              fontSize: context.sp(33),
              letterSpacing: .5,
              height: .95,
            ),
          ),
        ),
        _GlassIconButton(icon: Icons.search_rounded, onTap: onSearch),
        const SizedBox(width: 10),
        _GlassIconButton(icon: Icons.tune_rounded, onTap: onFilter),
      ],
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  const _GlassIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: c.card.withValues(alpha: .55),
          border: Border.all(color: c.cyan.withValues(alpha: .35)),
          boxShadow: [
            BoxShadow(
              color: c.cyan.withValues(alpha: .12),
              blurRadius: 14,
              spreadRadius: -4,
            ),
          ],
        ),
        child: Icon(icon, color: c.text, size: 21),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Date selector
// ---------------------------------------------------------------------------

class _DateSelector extends StatelessWidget {
  const _DateSelector({
    required this.days,
    required this.selected,
    required this.loading,
    required this.onSelect,
  });

  final List<ScheduleDay> days;
  final int selected;
  final bool loading;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    if (loading || days.isEmpty) {
      // Placeholder date cards (today onwards) while loading.
      final placeholders = List.generate(7, (i) {
        final d = DateTime.now().add(Duration(days: i));
        return _DateParts.fromDate(d);
      });
      return SizedBox(
        height: 92,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: placeholders.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (_, i) => _DateCard(
            parts: placeholders[i],
            selected: i == 0,
            onTap: null,
          ),
        ),
      );
    }
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: days.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) => _DateCard(
          parts: _DateParts.fromDay(days[i]),
          selected: i == selected,
          onTap: () => onSelect(i),
        ),
      ),
    );
  }
}

class _DateParts {
  const _DateParts({
    required this.weekday,
    required this.day,
    required this.month,
  });

  final String weekday;
  final String day;
  final String month;

  static const _months = [
    'JAN',
    'FEB',
    'MAR',
    'APR',
    'MAY',
    'JUN',
    'JUL',
    'AUG',
    'SEP',
    'OCT',
    'NOV',
    'DEC'
  ];
  static const _weekdays = ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'];

  factory _DateParts.fromDate(DateTime d) => _DateParts(
        weekday: _weekdays[d.weekday - 1],
        day: d.day.toString(),
        month: _months[d.month - 1],
      );

  factory _DateParts.fromDay(ScheduleDay day) {
    final date = day.date;
    if (date != null) return _DateParts.fromDate(date);
    return _DateParts(
      weekday: day.dayShort.toUpperCase(),
      day: day.dayNumber,
      month: '',
    );
  }
}

class _DateCard extends StatelessWidget {
  const _DateCard({
    required this.parts,
    required this.selected,
    required this.onTap,
  });

  final _DateParts parts;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
        width: 70,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          gradient: selected ? c.primaryGradient : null,
          color: selected ? null : c.card.withValues(alpha: .5),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? c.cyan.withValues(alpha: .8) : c.border,
            width: selected ? 1.6 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: c.cyan.withValues(alpha: .34),
                    blurRadius: 18,
                    spreadRadius: 0,
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              parts.weekday,
              maxLines: 1,
              style: TextStyle(
                color: selected ? Colors.white.withValues(alpha: .9) : c.muted,
                fontWeight: FontWeight.w700,
                fontSize: 11,
                letterSpacing: .5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              parts.day,
              maxLines: 1,
              style: TextStyle(
                color: selected ? Colors.white : c.text,
                fontWeight: FontWeight.w900,
                fontSize: 22,
                height: 1,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              parts.month,
              maxLines: 1,
              style: TextStyle(
                color: selected
                    ? Colors.white.withValues(alpha: .85)
                    : c.muted.withValues(alpha: .8),
                fontWeight: FontWeight.w700,
                fontSize: 10.5,
                letterSpacing: .5,
              ),
            ),
            const SizedBox(height: 5),
            // Selected accent underline.
            AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              width: selected ? 18 : 0,
              height: 2.5,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Category chips
// ---------------------------------------------------------------------------

class _CategoryChips extends StatelessWidget {
  const _CategoryChips({
    required this.filters,
    required this.selected,
    required this.onSelect,
  });

  final List<_CategoryFilter> filters;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, i) => _CategoryChip(
          filter: filters[i],
          selected: i == selected,
          onTap: () => onSelect(i),
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.filter,
    required this.selected,
    required this.onTap,
  });

  final _CategoryFilter filter;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    // GestureDetector (no InkWell) so there is never a splash/highlight that
    // could paint a rectangular patch behind the rounded pill.
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: selected ? c.primaryGradient : null,
          color: selected ? null : c.card.withValues(alpha: .5),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: selected ? c.cyan.withValues(alpha: .8) : c.border,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: c.cyan.withValues(alpha: .28),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            filter.asset != null
                ? Image.asset(
                    filter.asset!,
                    width: 16,
                    height: 16,
                    color: selected ? Colors.white : c.cyan,
                    errorBuilder: (_, __, ___) => Icon(
                      filter.icon,
                      size: 15,
                      color: selected ? Colors.white : c.cyan,
                    ),
                  )
                : Icon(
                    filter.icon,
                    size: 15,
                    color: selected ? Colors.white : c.cyan,
                  ),
            const SizedBox(width: 7),
            Text(
              filter.label,
              style: TextStyle(
                color: selected ? Colors.white : c.muted,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                fontSize: 13.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Summary / sort row
// ---------------------------------------------------------------------------

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.sortLabel,
    required this.onSort,
  });

  final String label;
  final String sortLabel;
  final VoidCallback onSort;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: c.cyan.withValues(alpha: .12),
            border: Border.all(color: c.cyan.withValues(alpha: .3)),
          ),
          child: Image.asset(
            _Asset.iconCalendar,
            width: 15,
            height: 15,
            color: c.cyan,
            errorBuilder: (_, __, ___) =>
                Icon(Icons.calendar_today_rounded, color: c.cyan, size: 15),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: c.text,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
        ),
        const SizedBox(width: 8),
        InkWell(
          onTap: onSort,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: c.card.withValues(alpha: .55),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: c.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  sortLabel,
                  style: TextStyle(
                    color: c.muted,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.sort_rounded, color: c.cyan, size: 15),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Premium match card
// ---------------------------------------------------------------------------

class _ScheduleMatchCard extends StatelessWidget {
  const _ScheduleMatchCard({required this.match, required this.onTap});

  final CricketMatch match;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return TapScale(
      onTap: onTap,
      borderRadius: 22,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: c.cyan.withValues(alpha: .3)),
          boxShadow: c.heroShadow,
        ),
        child: Stack(
          children: [
            // Premium stadium card background.
            const Positioned.fill(
              child: StadiumImage(
                _Asset.matchCardBg,
                hero: true,
                alignment: Alignment.center,
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: c.isDark
                        ? [
                            const Color(0xff0c2c50).withValues(alpha: .68),
                            c.card.withValues(alpha: .74),
                            const Color(0xff06182c).withValues(alpha: .82),
                          ]
                        : [
                            Colors.white.withValues(alpha: .82),
                            Colors.white.withValues(alpha: .88),
                            c.card2.withValues(alpha: .94),
                          ],
                  ),
                ),
              ),
            ),
            // Soft cyan inner highlight at the top edge.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -1.4),
                    radius: 1.2,
                    colors: [
                      c.cyan.withValues(alpha: .1),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            // Center spotlight behind the team row / VS so the matchup pops.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, 0.15),
                    radius: .75,
                    colors: [
                      c.cyan.withValues(alpha: .16),
                      Colors.transparent,
                    ],
                    stops: const [0, 1],
                  ),
                ),
              ),
            ),
            // Top + bottom cyan edge glow lines for the broadcast-card feel.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 3,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      c.cyan.withValues(alpha: .65),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 30,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        c.cyan.withValues(alpha: .18),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Series row: logo + name + status pill.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SeriesBadge(match: match),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              match.series.toUpperCase(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: c.cyan,
                                fontWeight: FontWeight.w800,
                                fontSize: 11.5,
                                height: 1.2,
                                letterSpacing: .2,
                              ),
                            ),
                            if (match.matchDesc.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(
                                match.matchDesc,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: c.text,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13.5,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _MatchStatusPill(match: match),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Team row with glowing VS badge.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: _CardTeam(
                          logoUrl: match.teamALogo,
                          shortName: match.teamAShort,
                          fullName: match.teamA,
                        ),
                      ),
                      const _VsBadge(),
                      Expanded(
                        child: _CardTeam(
                          logoUrl: match.teamBLogo,
                          shortName: match.teamBShort,
                          fullName: match.teamB,
                          alignEnd: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Time + venue split panel.
                  _TimeVenuePanel(match: match),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SeriesBadge extends StatelessWidget {
  const _SeriesBadge({required this.match});

  final CricketMatch match;

  /// Derives up to two letters from the series name as the very last fallback
  /// (only used if the tournament logo asset also fails to load).
  String get _initials {
    const skip = {
      'tour',
      'of',
      'the',
      'and',
      'vs',
      'men',
      "men's",
      'women',
      "women's",
      'series',
      'trophy',
      'cup',
      'league',
      'division',
      'one',
      'two',
      'premier',
      'qualifier',
      't20i',
      't20',
      'odi',
      'test',
    };
    final words = match.series
        .replaceAll(RegExp(r'[^A-Za-z ]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty && !skip.contains(w.toLowerCase()))
        .toList();
    if (words.isEmpty) {
      final first = match.series.replaceAll(RegExp(r'[^A-Za-z]'), '');
      return first.isEmpty
          ? ''
          : first.substring(0, first.length.clamp(0, 2)).toUpperCase();
    }
    if (words.length == 1) {
      return words.first
          .substring(0, words.first.length.clamp(0, 2))
          .toUpperCase();
    }
    return (words[0][0] + words[1][0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final logoAsset = _Asset.tournamentLogo(match.series);
    return Container(
      width: 44,
      height: 44,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: c.isDark ? const Color(0xff0e2742) : c.card,
        border: Border.all(color: c.cyan.withValues(alpha: .55), width: 1.3),
        boxShadow: [
          BoxShadow(
            color: c.cyan.withValues(alpha: .22),
            blurRadius: 12,
            spreadRadius: -3,
          ),
        ],
      ),
      // Real tournament fallback logo asset, contained with slight padding so
      // the emblem is never cropped. Degrades to an initials badge on failure.
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Image.asset(
          logoAsset,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => _initialsFallback(c),
        ),
      ),
    );
  }

  Widget _initialsFallback(CricColors c) {
    final initials = _initials;
    return Stack(
      fit: StackFit.expand,
      children: [
        const StadiumImage(
          'assets/images/stadium_live.png',
          hero: true,
          alignment: Alignment.center,
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: c.isDark
                  ? [
                      const Color(0xff0b2238).withValues(alpha: .82),
                      const Color(0xff061528).withValues(alpha: .92),
                    ]
                  : [
                      Colors.white.withValues(alpha: .80),
                      c.card2.withValues(alpha: .90),
                    ],
            ),
          ),
        ),
        Center(
          child: initials.isEmpty
              ? Icon(Icons.emoji_events_rounded, color: c.cyan, size: 16)
              : Text(
                  initials,
                  style: TextStyle(
                    color: c.cyan,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    letterSpacing: .3,
                  ),
                ),
        ),
      ],
    );
  }
}

class _MatchStatusPill extends StatelessWidget {
  const _MatchStatusPill({required this.match});

  final CricketMatch match;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final live = match.isLive;
    final finished = match.isFinished;
    final color = live
        ? c.live
        : finished
            ? c.success
            : c.cyan;
    final label = live
        ? 'LIVE'
        : finished
            ? 'Completed'
            : 'Upcoming';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .6)),
        boxShadow: live
            ? [BoxShadow(color: color.withValues(alpha: .3), blurRadius: 10)]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (live) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _CardTeam extends StatelessWidget {
  const _CardTeam({
    required this.logoUrl,
    required this.shortName,
    required this.fullName,
    this.alignEnd = false,
  });

  final String? logoUrl;
  final String shortName;
  final String fullName;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final short = shortName.isEmpty ? fullName : shortName;
    // TBC/TBD placeholders often resolve to an ugly white block image —
    // force the clean initials fallback for them.
    final upper = short.toUpperCase();
    final isPlaceholder = upper == 'TBC' || upper == 'TBD' || upper.isEmpty;
    final logo = TeamLogoWidget(
      logoUrl: isPlaceholder ? null : logoUrl,
      teamName: fullName,
      abbreviation: short,
      color: c.cyan,
      size: 50,
    );
    final texts = Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          short.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: alignEnd ? TextAlign.right : TextAlign.left,
          style: TextStyle(
            color: c.text,
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
        if (fullName.isNotEmpty &&
            fullName.toUpperCase() != short.toUpperCase())
          Text(
            fullName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: alignEnd ? TextAlign.right : TextAlign.left,
            style: TextStyle(
              color: c.muted,
              fontWeight: FontWeight.w600,
              fontSize: 11.5,
              height: 1.15,
            ),
          ),
      ],
    );

    final children = alignEnd
        ? [Expanded(child: texts), const SizedBox(width: 10), logo]
        : [logo, const SizedBox(width: 10), Expanded(child: texts)];
    return Row(
      mainAxisAlignment:
          alignEnd ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: children,
    );
  }
}

class _VsBadge extends StatelessWidget {
  const _VsBadge();

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    // Compact layout footprint (so the team text columns keep their width),
    // but the diagonal streak + glow deliberately overflow well beyond it via
    // Clip.none so the VS reads as a wide broadcast centerpiece, not a button.
    return SizedBox(
      width: 64,
      height: 66,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // 1) Big soft radial cyan bloom (pure Flutter) — guarantees a strong
          // glow halo regardless of the asset, behind everything.
          Container(
            width: 150,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  c.cyan.withValues(alpha: .5),
                  c.cyan.withValues(alpha: .16),
                  Colors.transparent,
                ],
                stops: const [0, .42, 1],
              ),
            ),
          ),
          // 2) Radial glow bloom asset (has alpha) behind the slash, stronger.
          Image.asset(
            _Asset.vsGlow,
            width: 168,
            height: 118,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
          // 3) Wide diagonal electric light streak (RGB no-alpha asset → screen
          // blend so the dark background vanishes), rotated like the target and
          // extending far past the badge on both sides.
          Transform.rotate(
            angle: -0.5,
            child: const _BlendImage(
              _Asset.vsStreak,
              width: 210,
              height: 40,
              opacity: 1,
            ),
          ),
          // 4) A second, narrower hot-core streak layered on top for a brighter
          // central slash.
          Transform.rotate(
            angle: -0.5,
            child: const _BlendImage(
              _Asset.vsStreak,
              width: 120,
              height: 18,
              opacity: 1,
            ),
          ),
          // 5) Dark glass VS badge with a bright glowing cyan border. Kept
          // compact — the size comes from the surrounding light, not the chip.
          Container(
            width: 42,
            height: 33,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: c.isDark
                    ? const [Color(0xff0e3155), Color(0xff04101f)]
                    : [c.primary, c.cyan],
              ),
              border:
                  Border.all(color: c.cyan.withValues(alpha: .98), width: 1.6),
              boxShadow: [
                BoxShadow(
                  color: c.cyan.withValues(alpha: .8),
                  blurRadius: 22,
                  spreadRadius: -1,
                ),
                BoxShadow(
                  color: c.cyan.withValues(alpha: .35),
                  blurRadius: 38,
                  spreadRadius: 2,
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Text(
              'VS',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 14,
                letterSpacing: .5,
                shadows: [
                  Shadow(color: c.cyan, blurRadius: 14),
                  Shadow(color: c.cyan.withValues(alpha: .7), blurRadius: 22),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeVenuePanel extends StatelessWidget {
  const _TimeVenuePanel({required this.match});

  final CricketMatch match;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final (venueName, city) = _splitVenue(match.venue);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: c.card2.withValues(alpha: .42),
        border: Border.all(color: c.border.withValues(alpha: .5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _InfoBlock(
              icon: Icons.access_time_rounded,
              primary: _timeLine(match),
              secondary: '(Local Time)',
              maxPrimaryLines: 2,
            ),
          ),
          Container(
            width: 1,
            height: 36,
            margin: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  c.border.withValues(alpha: .7),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          Expanded(
            child: _InfoBlock(
              icon: Icons.location_on_outlined,
              primary: venueName.isEmpty ? 'Venue TBC' : venueName,
              secondary: city,
              maxPrimaryLines: 2,
            ),
          ),
        ],
      ),
    );
  }

  String _timeLine(CricketMatch match) {
    final dt = match.startDateTime;
    if (dt == null) {
      return match.statusText.isNotEmpty ? match.statusText : match.startTime;
    }
    final local = dt.toLocal();
    const months = [
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
    var hour = local.hour % 12;
    if (hour == 0) hour = 12;
    final ampm = local.hour >= 12 ? 'PM' : 'AM';
    final mm = local.minute.toString().padLeft(2, '0');
    return '${months[local.month - 1]} ${local.day} • '
        '${hour.toString().padLeft(2, '0')}:$mm $ampm';
  }

  (String, String) _splitVenue(String venue) {
    final v = venue.trim();
    if (v.isEmpty) return ('', '');
    final idx = v.lastIndexOf(',');
    if (idx <= 0 || idx >= v.length - 1) return (v, '');
    return (v.substring(0, idx).trim(), v.substring(idx + 1).trim());
  }
}

class _InfoBlock extends StatelessWidget {
  const _InfoBlock({
    required this.icon,
    required this.primary,
    required this.secondary,
    this.maxPrimaryLines = 1,
  });

  final IconData icon;
  final String primary;
  final String secondary;
  final int maxPrimaryLines;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: c.cyan, size: 16),
        const SizedBox(width: 7),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                primary,
                maxLines: maxPrimaryLines,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: c.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                  height: 1.2,
                ),
              ),
              if (secondary.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  secondary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.muted,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Skeleton loading
// ---------------------------------------------------------------------------

class _ScheduleSkeletonList extends StatelessWidget {
  const _ScheduleSkeletonList();

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Column(
      children: [
        for (var i = 0; i < 3; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Container(
              height: 168,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                color: c.card.withValues(alpha: .5),
                border: Border.all(color: c.border.withValues(alpha: .5)),
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// State card
// ---------------------------------------------------------------------------

class _ScheduleStateCard extends StatelessWidget {
  const _ScheduleStateCard({
    required this.icon,
    required this.title,
    required this.message,
    required this.onRetry,
  });

  final IconData icon;
  final String title;
  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.cyan.withValues(alpha: .12),
              border: Border.all(color: c.cyan.withValues(alpha: .3)),
            ),
            child: Icon(icon, color: c.cyan, size: 30),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: c.text, fontWeight: FontWeight.w900, fontSize: 17),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: c.muted, height: 1.4),
          ),
          const SizedBox(height: 16),
          GradientButton(
            label: 'Retry',
            icon: Icons.refresh_rounded,
            onTap: () => onRetry(),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom sheets
// ---------------------------------------------------------------------------

class _SheetShell extends StatelessWidget {
  const _SheetShell({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(14),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: c.isDark
                ? [
                    const Color(0xff0a1929).withValues(alpha: .99),
                    const Color(0xff0f2744).withValues(alpha: .99),
                  ]
                : [
                    c.card,
                    c.card2,
                  ],
          ),
          border: Border.all(color: c.cyan.withValues(alpha: .32)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: c.text,
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                    ),
                  ),
                ),
                InkWell(
                  onTap: () => Navigator.pop(context),
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.close_rounded, color: c.muted, size: 22),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _SearchSheet extends StatefulWidget {
  const _SearchSheet({required this.initial, required this.onChanged});

  final String initial;
  final ValueChanged<String> onChanged;

  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: _SheetShell(
        title: 'Search Schedule',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              style: TextStyle(color: c.text, fontWeight: FontWeight.w600),
              cursorColor: c.cyan,
              onChanged: widget.onChanged,
              decoration: InputDecoration(
                hintText: 'Search team, series or venue',
                hintStyle: TextStyle(color: c.muted),
                prefixIcon: Icon(Icons.search_rounded, color: c.cyan),
                filled: true,
                fillColor: c.card2.withValues(alpha: .5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: c.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: c.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: c.cyan),
                ),
              ),
            ),
            const SizedBox(height: 14),
            GradientButton(
              label: 'Done',
              icon: Icons.check_rounded,
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterSheet extends StatelessWidget {
  const _FilterSheet({
    required this.filters,
    required this.selected,
    required this.onSelect,
  });

  final List<_CategoryFilter> filters;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return _SheetShell(
      title: 'Filter by Category',
      child: Column(
        children: [
          for (var i = 0; i < filters.length; i++)
            _SheetOption(
              icon: filters[i].icon,
              label: filters[i].label,
              selected: i == selected,
              onTap: () => onSelect(i),
            ),
        ],
      ),
    );
  }
}

class _SortSheet extends StatelessWidget {
  const _SortSheet({required this.selected, required this.onSelect});

  final _Sort selected;
  final ValueChanged<_Sort> onSelect;

  @override
  Widget build(BuildContext context) {
    const options = [
      (_Sort.time, 'Time', Icons.access_time_rounded),
      (_Sort.series, 'Series', Icons.emoji_events_rounded),
      (_Sort.type, 'Match Type', Icons.sports_cricket_rounded),
    ];
    return _SheetShell(
      title: 'Sort Matches',
      child: Column(
        children: [
          for (final o in options)
            _SheetOption(
              icon: o.$3,
              label: o.$2,
              selected: o.$1 == selected,
              onTap: () => onSelect(o.$1),
            ),
        ],
      ),
    );
  }
}

class _SheetOption extends StatelessWidget {
  const _SheetOption({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: selected ? c.cyan.withValues(alpha: .1) : Colors.transparent,
          border: Border.all(
            color: selected ? c.cyan.withValues(alpha: .7) : c.border,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: selected ? c.cyan : c.muted, size: 19),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: c.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 14.5,
                ),
              ),
            ),
            if (selected)
              Icon(Icons.check_circle_rounded, color: c.cyan, size: 20),
          ],
        ),
      ),
    );
  }
}
