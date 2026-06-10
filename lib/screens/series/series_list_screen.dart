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

  /// Initial filter: 0 = All, 1 = Ongoing, 2 = Upcoming, 3 = Completed.
  final int initialStatus;

  @override
  State<SeriesListScreen> createState() => _SeriesListScreenState();
}

class _SeriesListScreenState extends State<SeriesListScreen> {
  final CricketRepository _repository = CricketRepository();
  late Future<ApiEnvelope<List<ApiSeries>>> _series;
  late Future<ApiEnvelope<Map<String, dynamic>>> _hero;

  // Single filter row matching the target: 0 All, 1 Ongoing, 2 Upcoming,
  // 3 Completed.
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

  List<SeriesView> _filtered(List<SeriesView> all) {
    return switch (_filter) {
      1 => all
          .where((s) => s.status == SeriesStatus.ongoing)
          .toList(growable: false),
      2 => all
          .where((s) => s.status == SeriesStatus.upcoming)
          .toList(growable: false),
      3 => all
          .where((s) => s.status == SeriesStatus.completed)
          .toList(growable: false),
      _ => all,
    };
  }

  /// The hero spotlight series — prefers an ongoing edition, then upcoming,
  /// then simply the first available series.
  SeriesView? _featured(List<SeriesView> all) {
    if (all.isEmpty) return null;
    final ongoing = all.where((s) => s.status == SeriesStatus.ongoing);
    if (ongoing.isNotEmpty) return ongoing.first;
    final upcoming = all.where((s) => s.status == SeriesStatus.upcoming);
    if (upcoming.isNotEmpty) return upcoming.first;
    return all.first;
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
    final derived = _featured(all);
    final filtered = _filtered(all);
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
                child: _SeriesHeroBanner.fromAdmin(
                  admin,
                  onTap: () => _openHero(admin),
                ),
              );
            }
            if (derived != null) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: _SeriesHeroBanner.fromSeries(
                  derived,
                  onTap: () => _open(derived),
                ),
              );
            }
            return const SizedBox.shrink();
          },
        ),
        SeriesCategoryChips(
          items: const [
            ('All', Icons.grid_view_rounded),
            ('Ongoing', Icons.play_circle_fill_rounded),
            ('Upcoming', Icons.calendar_month_rounded),
            ('Completed', Icons.check_circle_rounded),
          ],
          selected: _filter,
          onChanged: (v) => setState(() => _filter = v),
        ),
        const SizedBox(height: 16),
        if (filtered.isEmpty)
          SeriesEmptyState(
            title: 'No ${_emptyLabel}series',
            message:
                'There are no ${_emptyLabel}series right now. Try another '
                'filter.',
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

  String get _emptyLabel => switch (_filter) {
        1 => 'ongoing ',
        2 => 'upcoming ',
        3 => 'completed ',
        _ => '',
      };
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
        const SizedBox(height: 14),
        Row(
          children: [
            if (showBack) const SizedBox(width: 38),
            Text(
              title,
              style: TextStyle(
                color: c.text,
                fontWeight: FontWeight.w900,
                fontSize: context.sp(26),
                letterSpacing: -.3,
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
// Featured series hero banner (single, static — matches the target)
// ---------------------------------------------------------------------------

class _SeriesHeroBanner extends StatelessWidget {
  const _SeriesHeroBanner({
    required this.small,
    required this.big,
    required this.formatText,
    required this.left,
    required this.right,
    required this.onTap,
    this.backgroundImage,
  });

  /// Builds the hero from an admin-managed configuration.
  factory _SeriesHeroBanner.fromAdmin(
    SeriesHeroData hero, {
    required VoidCallback onTap,
  }) {
    final (small, big) = _splitSeriesTitle(hero.title);
    return _SeriesHeroBanner(
      small: hero.subtitle.isNotEmpty ? hero.subtitle : small,
      big: big,
      formatText: hero.formatText,
      left: hero.teamA,
      right: hero.teamB,
      backgroundImage: hero.backgroundImage,
      onTap: onTap,
    );
  }

  /// Builds the hero from a series derived from the live `/series` list — the
  /// fallback used only when no admin hero is configured.
  factory _SeriesHeroBanner.fromSeries(
    SeriesView series, {
    required VoidCallback onTap,
  }) {
    final (small, big) = _splitSeriesTitle(series.cleanName);
    return _SeriesHeroBanner(
      small: small,
      big: big,
      formatText: series.formatSummary,
      left: series.teams.isNotEmpty ? series.teams.first : null,
      right: series.teams.length > 1 ? series.teams[1] : null,
      onTap: onTap,
    );
  }

  final String small;
  final String big;
  final String formatText;
  final SeriesTeamRef? left;
  final SeriesTeamRef? right;
  final String? backgroundImage;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final phone = context.w <= 430;
    final tight = context.w <= 360;
    final logoSize = tight ? 54.0 : (phone ? 60.0 : 66.0);

    return TapScale(
      onTap: onTap,
      borderRadius: 22,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: c.cyan.withValues(alpha: .6), width: 1.3),
          boxShadow: [
            BoxShadow(
              color: c.cyan.withValues(alpha: .26),
              blurRadius: 30,
              spreadRadius: -6,
            ),
            ...c.heroShadow.skip(1),
          ],
        ),
        child: Stack(
          children: [
            Positioned.fill(child: _HeroBackground(image: backgroundImage)),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: c.heroOverlayColors,
                  ),
                ),
              ),
            ),
            // Soft cyan bloom for extra premium depth.
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, -.2),
                      radius: .9,
                      colors: [
                        c.cyan.withValues(alpha: .12),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const TopCyanHighlight(),
            Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: phone ? 12 : 16, vertical: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _HeroTeamColumn(team: left, size: logoSize, accent: c.cyan),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Trophy crest.
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: c.warning.withValues(alpha: .14),
                            border: Border.all(
                                color: c.warning.withValues(alpha: .55)),
                            boxShadow: [
                              BoxShadow(
                                color: c.warning.withValues(alpha: .3),
                                blurRadius: 12,
                                spreadRadius: -2,
                              ),
                            ],
                          ),
                          child: Icon(Icons.emoji_events_rounded,
                              color: c.warning, size: 19),
                        ),
                        const SizedBox(height: 8),
                        if (small.isNotEmpty)
                          Text(
                            small.toUpperCase(),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: c.onImageText,
                              fontWeight: FontWeight.w700,
                              fontSize: tight ? 10 : 11.5,
                              letterSpacing: .4,
                            ),
                          ),
                        const SizedBox(height: 1),
                        Text(
                          big.toUpperCase(),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: c.cyan,
                            fontWeight: FontWeight.w900,
                            fontSize: tight ? 18 : (phone ? 21 : 23),
                            height: 1.04,
                            shadows: [
                              Shadow(
                                color: c.cyan.withValues(alpha: .5),
                                blurRadius: 14,
                              ),
                            ],
                          ),
                        ),
                        if (formatText.isNotEmpty) ...[
                          const SizedBox(height: 7),
                          Text(
                            formatText,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: .92),
                              fontWeight: FontWeight.w700,
                              fontSize: tight ? 11 : 12.5,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  _HeroTeamColumn(
                      team: right, size: logoSize, accent: c.warning),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Splits "Afghanistan Tour of India 2026" into ("Afghanistan Tour of",
/// "India 2026"). Falls back to ('', title) or a trailing-year split.
(String, String) _splitSeriesTitle(String title) {
  final t = title.trim();
  final m =
      RegExp(r'^(.*\btour of\b)\s+(.*)$', caseSensitive: false).firstMatch(t);
  if (m != null) {
    return (m.group(1)!.trim(), m.group(2)!.trim());
  }
  final ym = RegExp(r'^(.*?)\s+(\d{4}(?:[-/]\d{2,4})?)\s*$').firstMatch(t);
  if (ym != null && ym.group(1)!.trim().isNotEmpty) {
    return (ym.group(1)!.trim(), ym.group(2)!.trim());
  }
  return ('', t);
}

/// Hero background: an admin-uploaded image (network) when configured, falling
/// back through the bundled stadium artwork so the layout never breaks.
class _HeroBackground extends StatelessWidget {
  const _HeroBackground({this.image});

  final String? image;

  @override
  Widget build(BuildContext context) {
    Widget asset() => Image.asset(
          SAsset.detailHeroBg,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Image.asset(
            SAsset.featuredCarouselBg,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Image.asset(
              SAsset.homeStadiumBackdrop,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  const ColoredBox(color: Color(0xff071726)),
            ),
          ),
        );
    final url = image?.trim() ?? '';
    if (url.startsWith('http')) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => asset(),
      );
    }
    return asset();
  }
}

class _HeroTeamColumn extends StatelessWidget {
  const _HeroTeamColumn({
    required this.team,
    required this.size,
    required this.accent,
  });

  final SeriesTeamRef? team;
  final double size;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final t = team;
    final label = (t?.name.isNotEmpty == true
            ? t!.name
            : (t?.shortName ?? 'TBD'))
        .toUpperCase();
    return SizedBox(
      width: size + (context.w <= 360 ? 14 : 22),
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
          const SizedBox(height: 7),
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
