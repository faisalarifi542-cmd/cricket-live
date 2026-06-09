import 'package:flutter/material.dart';

import 'package:cricpro_flutter/app_theme.dart';
import 'package:cricpro_flutter/api_models.dart';
import 'package:cricpro_flutter/components.dart';
import 'package:cricpro_flutter/models/api_response.dart';
import 'package:cricpro_flutter/repositories/cricket_repository.dart';
import 'package:cricpro_flutter/screens/series/series_components.dart';
import 'package:cricpro_flutter/screens/series/series_detail_screen.dart';
import 'package:cricpro_flutter/screens/series/series_premium.dart';

/// Premium CricPro Series screen — shares the finished Home screen's visual
/// language: stadium atmosphere, cyan glow, glassmorphism, featured carousel,
/// Home-style status tabs and category chips, premium series list cards.
///
/// All data wiring (repository, refresh, navigation, loading/error states) is
/// preserved — this is a visual/UX redesign only.
class SeriesListScreen extends StatefulWidget {
  const SeriesListScreen({
    super.key,
    required this.onOpenSeries,
    this.showBack = false,
    this.initialStatus = 0,
  });

  final ValueChanged<String> onOpenSeries;
  final bool showBack;

  /// Initial status filter: 0 = Ongoing, 1 = Upcoming, 2 = Completed.
  final int initialStatus;

  @override
  State<SeriesListScreen> createState() => _SeriesListScreenState();
}

class _SeriesListScreenState extends State<SeriesListScreen> {
  final CricketRepository _repository = CricketRepository();
  late Future<ApiEnvelope<List<ApiSeries>>> _series;

  late int _status = widget.initialStatus;
  int _category = 0; // 0 All, 1 International, 2 League, 3 Domestic

  @override
  void initState() {
    super.initState();
    _series = _repository.seriesList();
  }

  Future<void> _refresh() async {
    setState(() => _series = _repository.seriesList(forceRefresh: true));
    await _series;
  }

  void _open(SeriesView series) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SeriesDetailScreen(
        seriesId: series.id,
        initialSeries: ApiSeries(
          id: series.id,
          name: series.name,
          status: series.statusLabel,
          startDate: series.startDate?.toIso8601String(),
          endDate: series.endDate?.toIso8601String(),
          format: series.formats.join(', '),
          country: series.host,
          matchCount: series.matchCount,
        ),
        onOpenReminders: () {},
        onOpenCalendar: () {},
        onOpenPlayer: () {},
      ),
    ));
  }

  SeriesStatus get _wantStatus => switch (_status) {
        0 => SeriesStatus.ongoing,
        1 => SeriesStatus.upcoming,
        _ => SeriesStatus.completed,
      };

  SeriesCategory? get _wantCategory => switch (_category) {
        1 => SeriesCategory.international,
        2 => SeriesCategory.league,
        3 => SeriesCategory.domestic,
        _ => null,
      };

  List<SeriesView> _filtered(List<SeriesView> all) {
    return all.where((s) {
      if (s.status != _wantStatus) return false;
      final cat = _wantCategory;
      if (cat == null) return true;
      // Treat Women as International for the simple 3-category filter.
      if (cat == SeriesCategory.international) {
        return s.category == SeriesCategory.international ||
            s.category == SeriesCategory.women;
      }
      return s.category == cat;
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: c.bgGradient),
        child: Stack(
          children: [
            // Stadium atmosphere behind the top of the screen (Home parity).
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 360,
              child: IgnorePointer(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(
                      SAsset.topBackdrop,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      errorBuilder: (_, __, ___) => Image.asset(
                        SAsset.homeStadiumBackdrop,
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                    Positioned(
                      top: -40,
                      left: -70,
                      child: GlowOrb(color: c.cyan, size: 220, alpha: .2),
                    ),
                    Positioned(
                      top: 10,
                      right: -80,
                      child: GlowOrb(color: c.primary, size: 240, alpha: .18),
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            const Color(0xff04132a).withValues(alpha: .3),
                            const Color(0xff04101f).withValues(alpha: .58),
                            c.bg.withValues(alpha: .9),
                            c.bg,
                          ],
                          stops: const [0, .5, .85, 1],
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
                  padding: EdgeInsets.fromLTRB(
                    context.horizontalPadding,
                    8,
                    context.horizontalPadding,
                    widget.showBack
                        ? context.detailBottomPadding
                        : context.mainBottomPadding + 96,
                  ),
                  children: [
                    _SeriesHeader(
                      showBack: widget.showBack,
                      onBack: () => Navigator.pop(context),
                      onBell: () {},
                      title: widget.showBack ? 'All Series' : 'Series',
                      onSeeAll: widget.showBack ? null : () {},
                    ),
                    const SizedBox(height: 14),
                    FutureBuilder<ApiEnvelope<List<ApiSeries>>>(
                      future: _series,
                      builder: (context, snapshot) {
                        final all = (snapshot.data?.data ?? const <ApiSeries>[])
                            .map(SeriesView.fromApi)
                            .toList();
                        final waiting = snapshot.connectionState ==
                                ConnectionState.waiting &&
                            all.isEmpty;

                        if (waiting) {
                          return const Column(
                            children: [
                              SeriesSkeleton(height: 230),
                              SizedBox(height: 16),
                              SeriesSkeleton(height: 110),
                              SizedBox(height: 12),
                              SeriesSkeleton(height: 110),
                            ],
                          );
                        }
                        if (snapshot.hasError && all.isEmpty) {
                          return SeriesEmptyState(
                            title: 'Unable to load series',
                            message:
                                'Please check your connection and try again.',
                            icon: Icons.cloud_off_rounded,
                            onRetry: () => setState(() => _series =
                                _repository.seriesList(forceRefresh: true)),
                          );
                        }
                        return _buildBody(all);
                      },
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

  Widget _buildBody(List<SeriesView> all) {
    final featured = all.take(5).toList();
    final filtered = _filtered(all);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (featured.isNotEmpty) ...[
          _FeaturedSeriesCarousel(series: featured, onTap: _open),
          const SizedBox(height: 16),
        ],
        SeriesStatusTabs(
          selected: _status,
          onChanged: (v) => setState(() => _status = v),
        ),
        const SizedBox(height: 16),
        SeriesCategoryChips(
          items: const [
            ('All', Icons.grid_view_rounded),
            ('International', Icons.public_rounded),
            ('League', Icons.emoji_events_rounded),
            ('Domestic', Icons.flag_rounded),
          ],
          selected: _category,
          onChanged: (v) => setState(() => _category = v),
        ),
        const SizedBox(height: 16),
        if (filtered.isEmpty)
          SeriesEmptyState(
            title: 'No ${_statusLabel.toLowerCase()} series',
            message:
                'There are no ${_statusLabel.toLowerCase()} series in this '
                'category right now. Try another filter.',
            icon: Icons.event_busy_rounded,
          )
        else
          for (final series in filtered)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: SeriesListCard(series: series, onTap: () => _open(series)),
            ),
      ],
    );
  }

  String get _statusLabel => switch (_status) {
        0 => 'Ongoing',
        1 => 'Upcoming',
        _ => 'Completed',
      };
}

// ---------------------------------------------------------------------------
// Header (CRICPRO wordmark + bell + section row with trophy + See All)
// ---------------------------------------------------------------------------

class _SeriesHeader extends StatelessWidget {
  const _SeriesHeader({
    required this.showBack,
    required this.onBack,
    required this.onBell,
    required this.title,
    required this.onSeeAll,
  });

  final bool showBack;
  final VoidCallback onBack;
  final VoidCallback onBell;
  final String title;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final logoSize = context.w <= 400 ? 30.0 : 33.0;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              if (showBack) ...[
                GestureDetector(
                  onTap: onBack,
                  behavior: HitTestBehavior.opaque,
                  child:
                      Icon(Icons.arrow_back_rounded, color: c.text, size: 26),
                ),
                const SizedBox(width: 12),
              ],
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
                            color: c.cyan.withValues(alpha: .6),
                            blurRadius: 16,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              _BellButton(onTap: onBell),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c.cyan.withValues(alpha: .12),
                border: Border.all(color: c.cyan.withValues(alpha: .45)),
              ),
              child: Icon(Icons.emoji_events_rounded, color: c.cyan, size: 19),
            ),
            const SizedBox(width: 10),
            Text(
              title,
              style: TextStyle(
                color: c.text,
                fontWeight: FontWeight.w900,
                fontSize: context.sp(22),
              ),
            ),
            const Spacer(),
            if (onSeeAll != null)
              GestureDetector(
                onTap: onSeeAll,
                behavior: HitTestBehavior.opaque,
                child: Row(
                  children: [
                    Text(
                      'See All',
                      style: TextStyle(
                        color: c.text.withValues(alpha: .9),
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: c.cyan, size: 20),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _BellButton extends StatelessWidget {
  const _BellButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 48,
        height: 48,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c.card.withValues(alpha: .42),
                border: Border.all(
                    color: c.cyan.withValues(alpha: .75), width: 1.3),
                boxShadow: [
                  BoxShadow(
                    color: c.cyan.withValues(alpha: .24),
                    blurRadius: 16,
                    spreadRadius: -3,
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Icon(Icons.notifications_none_rounded,
                  color: c.text, size: 23),
            ),
            Positioned(
              top: 10,
              right: 11,
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: c.cyan,
                  shape: BoxShape.circle,
                  border: Border.all(color: c.bg, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                        color: c.cyan.withValues(alpha: .85), blurRadius: 7),
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
// Featured series carousel (PageView with side peeks + dots)
// ---------------------------------------------------------------------------

class _FeaturedSeriesCarousel extends StatefulWidget {
  const _FeaturedSeriesCarousel({required this.series, required this.onTap});

  final List<SeriesView> series;
  final ValueChanged<SeriesView> onTap;

  @override
  State<_FeaturedSeriesCarousel> createState() =>
      _FeaturedSeriesCarouselState();
}

class _FeaturedSeriesCarouselState extends State<_FeaturedSeriesCarousel> {
  PageController? _controller;
  int _current = 0;
  bool _loop = false;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final phone = context.w <= 430;
    final height = phone ? 258.0 : 274.0;
    final items = widget.series;
    _loop = items.length > 1;
    _controller ??= PageController(
      viewportFraction: phone ? 0.84 : 0.78,
      initialPage: _loop ? items.length * 1000 : 0,
    );
    final itemCount = _loop ? items.length * 2000 : items.length;
    return Column(
      children: [
        SizedBox(
          height: height,
          child: PageView.builder(
            controller: _controller,
            itemCount: itemCount,
            clipBehavior: Clip.none,
            onPageChanged: (v) =>
                setState(() => _current = _loop ? v % items.length : v),
            itemBuilder: (context, index) {
              final realIndex = _loop ? index % items.length : index;
              return AnimatedBuilder(
                animation: _controller!,
                builder: (context, child) {
                  double diff = 0;
                  if (_controller!.position.haveDimensions) {
                    diff = (_controller!.page ?? index.toDouble()) - index;
                  }
                  final scale = (1 - diff.abs() * 0.07).clamp(0.9, 1.0);
                  final opacity = (1 - diff.abs() * 0.45).clamp(0.55, 1.0);
                  return Opacity(
                    opacity: opacity,
                    child: Transform.scale(scale: scale, child: child),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: _FeaturedSeriesCard(
                    series: items[realIndex],
                    onTap: () => widget.onTap(items[realIndex]),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < items.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 3.5),
                width: i == _current ? 18 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: i == _current
                      ? context.cric.cyan
                      : const Color(0xff3a5780).withValues(alpha: .7),
                  borderRadius: BorderRadius.circular(99),
                  boxShadow: i == _current
                      ? [
                          BoxShadow(
                            color: context.cric.cyan.withValues(alpha: .65),
                            blurRadius: 9,
                          ),
                        ]
                      : null,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _FeaturedSeriesCard extends StatelessWidget {
  const _FeaturedSeriesCard({required this.series, required this.onTap});

  final SeriesView series;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final phone = context.w <= 430;
    final left = series.teams.isNotEmpty ? series.teams.first : null;
    final right = series.teams.length > 1 ? series.teams[1] : null;
    final logoSize = phone ? 50.0 : 56.0;
    return TapScale(
      onTap: onTap,
      borderRadius: 24,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: c.cyan.withValues(alpha: .6), width: 1.3),
          boxShadow: [
            BoxShadow(
              color: c.cyan.withValues(alpha: .18),
              blurRadius: 22,
              spreadRadius: -8,
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: .38),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                SAsset.featuredCarouselBg,
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
                      const Color(0xff031126).withValues(alpha: .26),
                      const Color(0xff031126).withValues(alpha: .34),
                      const Color(0xff031126).withValues(alpha: .58),
                    ],
                    stops: const [0, .5, 1],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: c.cyan.withValues(alpha: .16),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: c.cyan.withValues(alpha: .7)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.star_rounded, color: c.cyan, size: 12),
                          const SizedBox(width: 4),
                          Text(
                            'FEATURED',
                            style: TextStyle(
                              color: c.cyan,
                              fontWeight: FontWeight.w900,
                              fontSize: 10,
                              letterSpacing: .5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    series.categoryLabel.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: c.cyan,
                      fontWeight: FontWeight.w800,
                      fontSize: phone ? 12 : 13,
                      letterSpacing: .6,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    series.cleanName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: c.text,
                      fontWeight: FontWeight.w900,
                      fontSize: phone ? 16.5 : 18,
                      height: 1.08,
                    ),
                  ),
                  if (series.shortDateRange.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      series.shortDateRange.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .9),
                        fontWeight: FontWeight.w700,
                        fontSize: phone ? 11 : 12,
                        letterSpacing: .3,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _CarouselTeam(
                          team: left,
                          accent: c.cyan,
                          logoSize: logoSize,
                        ),
                      ),
                      PremiumVsBadge(
                        width: phone ? 52 : 58,
                        height: phone ? 36 : 40,
                      ),
                      Expanded(
                        child: _CarouselTeam(
                          team: right,
                          accent: c.warning,
                          logoSize: logoSize,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CarouselTeam extends StatelessWidget {
  const _CarouselTeam({
    required this.team,
    required this.accent,
    required this.logoSize,
  });

  final SeriesTeamRef? team;
  final Color accent;
  final double logoSize;

  @override
  Widget build(BuildContext context) {
    final t = team;
    return PremiumTeamColumn(
      name: t?.name ?? 'TBD',
      short: t?.shortName ?? 'TBD',
      logo: t?.logoUrl,
      logoSize: logoSize,
      codeSize: context.w <= 430 ? 16 : 17,
      accent: accent,
    );
  }
}
