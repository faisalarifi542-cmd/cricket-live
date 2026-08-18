import 'package:flutter/material.dart';

import 'package:cricpro_flutter/app_theme.dart';
import 'package:cricpro_flutter/api_models.dart';
import 'package:cricpro_flutter/components.dart';
import 'package:cricpro_flutter/models/api_response.dart';
import 'package:cricpro_flutter/repositories/cricket_repository.dart';
import 'package:cricpro_flutter/screens/series/series_components.dart';
import 'package:cricpro_flutter/screens/series/series_detail_screen.dart';
import 'package:cricpro_flutter/screens/series/series_new_assets.dart';
import 'package:cricpro_flutter/screens/series/series_premium.dart';
import 'package:cricpro_flutter/screens/series/widgets/series_poster_cards.dart';

/// Premium CricPro Series screen â€” shares the finished Home screen's visual
/// language: stadium atmosphere, cyan glow, glassmorphism, featured carousel,
/// Home-style status tabs and category chips, premium series list cards.
///
/// All data wiring (repository, refresh, navigation, loading/error states) is
/// preserved â€” this is a visual/UX redesign only.
class SeriesListScreen extends StatefulWidget {
  const SeriesListScreen({
    super.key,
    required this.onOpenSeries,
    this.showBack = false,
    this.initialStatus = 0,
  });

  final ValueChanged<String> onOpenSeries;
  final bool showBack;

  /// Initial filter: 0 = All, 1 = Ongoing, 2 = Upcoming, 3 = Completed.
  final int initialStatus;

  @override
  State<SeriesListScreen> createState() => _SeriesListScreenState();
}

class _SeriesListScreenState extends State<SeriesListScreen> {
  final CricketRepository _repository = CricketRepository();
  late Future<ApiEnvelope<List<ApiSeries>>> _series;
  late Future<ApiEnvelope<Map<String, dynamic>>> _hero;

  // The single visible filter row: 0 All, 1 Ongoing, 2 Upcoming, 3 Completed.
  // The Cricbuzz category (international/domestic/league/women) is still parsed
  // from the backend onto each [SeriesView] for internal use, but it is no
  // longer surfaced as a second chip row â€” the Series screen filters by status
  // only, matching the target design.
  late int _filter = widget.initialStatus;

  @override
  void initState() {
    super.initState();
    _series = _repository.seriesList();
    _hero = _repository.seriesHero();
  }

  Future<void> _refresh() async {
    setState(() {
      _series = _repository.seriesList(forceRefresh: true);
      _hero = _repository.seriesHero(forceRefresh: true);
    });
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

  /// Opens the series referenced by an admin-managed hero. Routing uses the
  /// hero's explicit series ID; when none is configured we surface a clean
  /// message instead of navigating to the wrong screen.
  void _openHero(SeriesHeroData hero) {
    final id = hero.seriesId.trim();
    if (id.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('Series details are not linked for this banner yet.'),
        ));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SeriesDetailScreen(
        seriesId: id,
        initialSeries: ApiSeries(
          id: id,
          name: hero.title.isNotEmpty ? hero.title : 'Series',
          status: 'Ongoing',
          format: hero.formatText,
        ),
        onOpenReminders: () {},
        onOpenCalendar: () {},
        onOpenPlayer: () {},
      ),
    ));
  }

  /// Maps the status chip index to a [SeriesStatus] facet (null = "All").
  SeriesStatus? get _statusFacet => switch (_filter) {
        1 => SeriesStatus.ongoing,
        2 => SeriesStatus.upcoming,
        3 => SeriesStatus.completed,
        _ => null,
      };

  // The category facet is always "All" now (no category row); status is the
  // only user-facing filter. The result is then sorted into the canonical
  // display order (ongoing → upcoming → completed, with within-section date
  // ordering) so the list never shows an arbitrary backend-payload order.
  List<SeriesView> _filtered(List<SeriesView> all) =>
      sortSeriesByStatus(filterSeries(all, null, _statusFacet));

  /// The hero spotlight series â€” drawn from the currently filtered set so it
  /// never contradicts the active category/status, preferring an ongoing
  /// edition, then upcoming, then simply the first available series.
  /// Up to 5 spotlight series for the hero carousel — ongoing first, then
  /// upcoming, then any remaining — drawn from the active filter so it never
  /// contradicts the visible list.
  List<SeriesView> _featuredList(List<SeriesView> filtered) {
    if (filtered.isEmpty) return const [];
    final ongoing =
        filtered.where((s) => s.status == SeriesStatus.ongoing).toList();
    final upcoming =
        filtered.where((s) => s.status == SeriesStatus.upcoming).toList();
    final rest = filtered
        .where((s) =>
            s.status != SeriesStatus.ongoing &&
            s.status != SeriesStatus.upcoming)
        .toList();
    return [...ongoing, ...upcoming, ...rest].take(5).toList();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: c.bgGradient),
        child: Stack(
          children: [
            // Premium dark gradient screen backdrop (dark mode only — light mode
            // keeps the theme's ice-blue gradient per the app design rules).
            if (c.isDark)
              Positioned.fill(
                child: IgnorePointer(
                  child: Image.asset(
                    SeriesNewAssets.screenBg,
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ),
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
                    const StadiumImage(
                      SAsset.topBackdrop,
                      alignment: Alignment.topCenter,
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
                          colors: c.stadiumOverlayColors,
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
                    12,
                    context.horizontalPadding,
                    widget.showBack
                        ? context.detailBottomPadding
                        : context.mainScrollBottomInset,
                  ),
                  children: [
                    _SeriesHeader(
                      showBack: widget.showBack,
                      onBack: () => Navigator.pop(context),
                      onBell: () {},
                      title: widget.showBack ? 'All Series' : 'Series',
                    ),
                    const SizedBox(height: 20),
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
                              SeriesSkeleton(height: 150),
                              SizedBox(height: 16),
                              SeriesSkeleton(height: 190),
                              SizedBox(height: 14),
                              SeriesSkeleton(height: 190),
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
    final filtered = _filtered(all);
    final featured = _featuredList(filtered);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FutureBuilder<ApiEnvelope<Map<String, dynamic>>>(
          future: _hero,
          builder: (context, snapshot) {
            final admin = SeriesHeroData.fromJson(snapshot.data?.data);
            if (admin != null) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: SeriesFeaturedHeroPoster.fromAdmin(
                  admin,
                  onTap: () => _openHero(admin),
                ),
              );
            }
            if (featured.isNotEmpty) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: SeriesHeroCarousel(
                  pages: [
                    for (final s in featured)
                      SeriesFeaturedHeroPoster.fromSeries(
                        s,
                        onTap: () => _open(s),
                      ),
                  ],
                ),
              );
            }
            return const SizedBox.shrink();
          },
        ),
        // The one and only filter row: All / Ongoing / Upcoming / Completed.
        // Uses the bundled active/inactive chip artwork. (The Cricbuzz category
        // row has been removed per the target design.)
        SeriesFilterChipBar(
          selected: _filter,
          onChanged: (v) => setState(() => _filter = v),
        ),
        const SizedBox(height: 16),
        if (filtered.isEmpty)
          SeriesEmptyState(
            title: 'No ${_emptyLabel}series available',
            message: _emptyHint,
            icon: Icons.event_busy_rounded,
          )
        else
          for (final series in filtered)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: SeriesPosterCard(series: series, onTap: () => _open(series)),
            ),
      ],
    );
  }

  String get _emptyLabel => switch (_filter) {
        1 => 'ongoing ',
        2 => 'upcoming ',
        3 => 'completed ',
        _ => '',
      };

  /// A helpful nudge toward a broader filter when the current status filter is
  /// empty (never shown when matching series exist).
  String get _emptyHint {
    if (_filter == 3) return 'Try the All or Upcoming filter.';
    return 'Try another filter.';
  }
}

// ---------------------------------------------------------------------------
// Header (CRICPRO wordmark + bell, then the section title)
// ---------------------------------------------------------------------------

class _SeriesHeader extends StatelessWidget {
  const _SeriesHeader({
    required this.showBack,
    required this.onBack,
    required this.onBell,
    required this.title,
  });

  final bool showBack;
  final VoidCallback onBack;
  final VoidCallback onBell;
  final String title;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    // Target-scaled CRICPRO wordmark — noticeably larger than the compact
    // Home/Matches header so the Series screen reads as a premium landing.
    final logoSize = context.w <= 360
        ? 34.0
        : context.w <= 430
            ? 37.0
            : 40.0;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6),
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
              // Shared CRICPRO wordmark — same renderer as Home/Matches/More.
              CricLogo(size: logoSize),
              const Spacer(),
              _BellButton(onTap: onBell),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            if (showBack) const SizedBox(width: 38),
            Text(
              title,
              style: TextStyle(
                color: c.text,
                fontWeight: FontWeight.w900,
                fontSize: context.sp(32),
                letterSpacing: -.5,
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
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GlowIconButton(
          icon: Icons.notifications_none_rounded,
          onTap: onTap,
        ),
        Positioned(
          top: 2,
          right: 2,
          child: Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: c.cyan,
              shape: BoxShape.circle,
              border: Border.all(color: c.bg, width: 1.5),
              boxShadow: c.isDark
                  ? [
                      BoxShadow(
                          color: c.cyan.withValues(alpha: .85), blurRadius: 7),
                    ]
                  : null,
            ),
          ),
        ),
      ],
    );
  }
}
