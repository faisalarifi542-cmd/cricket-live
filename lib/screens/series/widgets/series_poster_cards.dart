import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:cricpro_flutter/app_theme.dart';
import 'package:cricpro_flutter/components.dart';
import 'package:cricpro_flutter/screens/series/series_components.dart';
import 'package:cricpro_flutter/screens/series/series_new_assets.dart';
import 'package:cricpro_flutter/utils/team_format.dart';

/// CricPro Series list poster cards — rebuilt on the **new** clean reusable
/// asset kit (`assets/images/series/new/`).
///
/// Composition rules (per the asset README/manifest + design brief):
///  • per-type background art (`auto_extracted/sheet*_asset_01.png` — purple
///    tournament panel / castle bilateral panel / cyber league stadium) shown
///    `BoxFit.cover`, with a subtle dark gradient for text contrast,
///  • a core neon border-glow frame on top (`core_clean_assets/*_border_glow`)
///    for the cyan card edge,
///  • REAL team logos (admin → provider → initials, via [TeamLogoWidget])
///    clipped INSIDE the decorative ring PNGs — logos are never baked into art,
///  • core status pills / CTA buttons / chips as base layers with Flutter text.
///
/// Responsive via [LayoutBuilder] + a [_Metrics] breakpoint set
/// (compact ≤360 / regular 361–430 / large >430). No backend/data/filter logic
/// is touched here — visual redesign only.

// ===========================================================================
// Variant model (unchanged classification — visual only)
// ===========================================================================

enum SeriesPosterVariant {
  tournament,
  bilateralUpcoming,
  bilateralOngoing,
  bilateralCompleted,
  league,
}

bool _isLeague(SeriesView s) =>
    s.category == SeriesCategory.league || s.category == SeriesCategory.domestic;

bool _isCompetition(SeriesView s) {
  if (_isLeague(s)) return true;
  final name = s.name.toLowerCase();
  if (name.contains('tour of')) return false;
  return RegExp(
    r'world cup|champions trophy|asia cup|tri-?series|t20 world|'
    r'world championship|qualifier|championship|\btrophy\b|\bcup\b|league',
  ).hasMatch(name);
}

SeriesPosterVariant resolveSeriesPosterVariant(SeriesView s) {
  if (s.status == SeriesStatus.completed) {
    if (_isCompetition(s)) {
      return _isLeague(s)
          ? SeriesPosterVariant.league
          : SeriesPosterVariant.tournament;
    }
    return SeriesPosterVariant.bilateralCompleted;
  }
  if (_isLeague(s)) return SeriesPosterVariant.league;
  if (_isCompetition(s)) return SeriesPosterVariant.tournament;
  if (s.status == SeriesStatus.ongoing) {
    return SeriesPosterVariant.bilateralOngoing;
  }
  return SeriesPosterVariant.bilateralUpcoming;
}

bool _isShowableTeam(SeriesTeamRef t) {
  final hasLogo = (t.logoUrl ?? '').trim().isNotEmpty;
  final hasCode = !isPlaceholderText(t.shortName) || !isPlaceholderText(t.name);
  return hasLogo || hasCode;
}

(Color, bool, String, String) _statusStyle(
    BuildContext context, SeriesStatus status) {
  final c = context.cric;
  return switch (status) {
    SeriesStatus.ongoing => (
        c.success,
        true,
        'Ongoing',
        SeriesNewAssets.statusOngoing
      ),
    SeriesStatus.upcoming => (
        c.cyan,
        false,
        'Upcoming',
        SeriesNewAssets.statusUpcoming
      ),
    SeriesStatus.completed => (
        c.muted,
        false,
        'Completed',
        SeriesNewAssets.statusCompleted
      ),
    SeriesStatus.unknown => (
        c.muted,
        false,
        'TBD',
        SeriesNewAssets.statusUpcoming
      ),
  };
}

// ===========================================================================
// Responsive metrics
// ===========================================================================

class _Metrics {
  const _Metrics({
    required this.pad,
    required this.title,
    required this.meta,
    required this.ctaH,
    required this.statusH,
    required this.starSize,
    required this.bilatRing,
    required this.stripRing,
    required this.tournamentH,
    required this.leagueH,
    required this.bilateralH,
    required this.completedH,
    required this.hero,
    required this.heroRing,
  });

  final double pad;
  final double title;
  final double meta;
  final double ctaH;
  final double statusH;
  final double starSize;
  final double bilatRing;
  final double stripRing;
  final double tournamentH;
  final double leagueH;
  final double bilateralH;
  final double completedH;
  final double hero;
  final double heroRing;
}

_Metrics _metricsFor(double w) {
  if (w <= 360) {
    return const _Metrics(
      pad: 14,
      title: 18,
      meta: 12.5,
      ctaH: 40,
      statusH: 26,
      starSize: 24,
      bilatRing: 74,
      stripRing: 34,
      tournamentH: 222,
      leagueH: 206,
      bilateralH: 190,
      completedH: 182,
      hero: 176,
      heroRing: 80,
    );
  }
  if (w <= 430) {
    return const _Metrics(
      pad: 16,
      title: 19.5,
      meta: 13,
      ctaH: 42,
      statusH: 28,
      starSize: 25,
      bilatRing: 82,
      stripRing: 36,
      tournamentH: 232,
      leagueH: 214,
      bilateralH: 198,
      completedH: 190,
      hero: 188,
      heroRing: 90,
    );
  }
  return const _Metrics(
    pad: 18,
    title: 21,
    meta: 13.5,
    ctaH: 44,
    statusH: 30,
    starSize: 26,
    bilatRing: 90,
    stripRing: 38,
    tournamentH: 242,
    leagueH: 222,
    bilateralH: 206,
    completedH: 198,
    hero: 200,
    heroRing: 100,
  );
}

// ===========================================================================
// Team logo ring (decorative ring PNG clipping a REAL team logo)
// ===========================================================================

/// A premium circular team badge: a real [TeamLogoWidget] (admin → provider →
/// local flag → initials priority) clipped to a circle that fills the ring's
/// inner hole, with the decorative neon [ring] PNG drawn ON TOP so the rim/glow
/// frames the logo. Falls back to a Flutter-drawn cyan rim if the ring asset is
/// missing, and never renders an empty disc (shows [fallback] — e.g. a "+N" or
/// trophy — otherwise nothing).
class SeriesLogoRing extends StatelessWidget {
  const SeriesLogoRing({
    super.key,
    required this.size,
    required this.ring,
    this.team,
    this.accent,
    this.fallback,
    this.logoRatio = 0.78,
  });

  /// Outer diameter (includes the asset's glow margin).
  final double size;

  /// Decorative ring PNG asset path.
  final String ring;
  final SeriesTeamRef? team;
  final Color? accent;
  final Widget? fallback;

  /// Inner logo diameter as a fraction of [size] (the ring's clear hole).
  final double logoRatio;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final ac = accent ?? c.cyan;
    final showable = team != null && _isShowableTeam(team!);
    if (!showable && fallback == null) return const SizedBox.shrink();
    final logoD = size * logoRatio;

    final Widget core = showable
        ? ClipOval(
            child: SizedBox(
              width: logoD,
              height: logoD,
              child: TeamLogoWidget(
                logoUrl: team!.logoUrl,
                teamName: team!.name,
                abbreviation:
                    team!.shortName.isNotEmpty ? team!.shortName : team!.name,
                color: ac,
                size: logoD,
                // Transparent inner border so the flag fills the disc; the ring
                // asset below is the visible frame.
                borderColor: Colors.transparent,
              ),
            ),
          )
        : Container(
            width: logoD,
            height: logoD,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Color(0xff071a30),
            ),
            alignment: Alignment.center,
            child: fallback,
          );

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          core,
          // Decorative ring on top of the logo edge.
          IgnorePointer(
            child: Image.asset(
              ring,
              width: size,
              height: size,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: ac.withValues(alpha: .95),
                    width: (size * .05).clamp(1.6, 3.0),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: ac.withValues(alpha: .4),
                      blurRadius: size * .12,
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

/// Two team rings (bilateral / completed tour) with a connector arc behind and
/// a small shield emblem seated between them — matching the target.
class SeriesLogoRingPair extends StatelessWidget {
  const SeriesLogoRingPair({
    super.key,
    required this.left,
    required this.right,
    required this.ring,
    required this.completed,
  });

  final SeriesTeamRef? left;
  final SeriesTeamRef? right;
  final double ring;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    if (left == null) return const SizedBox.shrink();
    if (right == null) {
      return SeriesLogoRing(
          size: ring, ring: SeriesNewAssets.ringBlueGlow, team: left);
    }
    // Slight overlap reads as a connected pair (target). The shield sits low in
    // the seam so it never covers a flag face.
    final overlap = ring * .16;
    final width = ring * 2 - overlap;
    final shield = (ring * .42).clamp(22.0, 34.0);
    final accentR = completed ? c.warning : const Color(0xffff8a3d);
    return SizedBox(
      width: width,
      height: ring,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // Cyan connector arc behind the rings.
          Positioned(
            left: ring * .32,
            right: ring * .32,
            top: ring * .28,
            child: Image.asset(
              SeriesNewAssets.bilateralConnector,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Container(
                height: 3,
                decoration: BoxDecoration(
                  color: c.cyan.withValues(alpha: .55),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            child: SeriesLogoRing(
              size: ring,
              ring: SeriesNewAssets.ringBlueGlow,
              team: left,
              accent: c.cyan,
            ),
          ),
          Positioned(
            right: 0,
            child: SeriesLogoRing(
              size: ring,
              ring: SeriesNewAssets.ringOrangeGreenGlow,
              team: right,
              accent: accentR,
            ),
          ),
          // Shield emblem tucked low in the seam.
          Positioned(
            top: ring * .52,
            child: Image.asset(
              SeriesNewAssets.bilateralShield,
              width: shield,
              height: shield,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Container(
                width: shield,
                height: shield,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xff04101f),
                  border: Border.all(
                    color: (completed ? c.warning : c.cyan)
                        .withValues(alpha: .9),
                    width: 1.4,
                  ),
                ),
                alignment: Alignment.center,
                child: Icon(
                  completed
                      ? Icons.emoji_events_rounded
                      : Icons.shield_outlined,
                  color: completed ? c.warning : c.cyan,
                  size: shield * .54,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Horizontal strip of small ring logos (real teams only) + a "+N" overflow
/// ring. Never renders an empty ring.
class SeriesLogoRingRow extends StatelessWidget {
  const SeriesLogoRingRow({
    super.key,
    required this.teams,
    required this.totalCount,
    required this.ring,
  });

  final List<SeriesTeamRef> teams;
  final int totalCount;
  final double ring;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    const maxShown = 5;
    final shown = teams.where(_isShowableTeam).take(maxShown).toList();
    if (shown.isEmpty) return const SizedBox.shrink();
    final extra = (totalCount > shown.length)
        ? totalCount - shown.length
        : (teams.length > shown.length ? teams.length - shown.length : 0);
    final children = <Widget>[];
    for (var i = 0; i < shown.length; i++) {
      children.add(Padding(
        padding: EdgeInsets.only(left: i == 0 ? 0 : ring * .12),
        child: SeriesLogoRing(
          size: ring,
          ring: SeriesNewAssets.ringSmall,
          team: shown[i],
          accent: c.cyan,
          logoRatio: 0.86,
        ),
      ));
    }
    if (extra > 0) {
      children.add(Padding(
        padding: EdgeInsets.only(left: ring * .12),
        child: SeriesLogoRing(
          size: ring,
          ring: SeriesNewAssets.ringSmall,
          accent: c.cyan,
          logoRatio: 0.86,
          fallback: Text(
            '+$extra',
            style: TextStyle(
              color: c.cyan,
              fontWeight: FontWeight.w900,
              fontSize: ring * .3,
            ),
          ),
        ),
      ));
    }
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

// ===========================================================================
// Reusable components (status pill, CTA button, meta row, star, frame)
// ===========================================================================

/// Status pill rendered on a core base PNG with a Flutter status dot + label.
class SeriesStatusPillImg extends StatelessWidget {
  const SeriesStatusPillImg({
    super.key,
    required this.label,
    required this.color,
    required this.live,
    required this.height,
    required this.asset,
  });

  final String label;
  final Color color;
  final bool live;
  final double height;
  final String asset;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: EdgeInsets.symmetric(horizontal: height * .5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(height),
        image: DecorationImage(image: AssetImage(asset), fit: BoxFit.fill),
        // Fallback fill (shows if the asset is transparent / fails) keeps the
        // pill readable.
        color: const Color(0xff04101f).withValues(alpha: .35),
      ),
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: height * .26,
            height: height * .26,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: live
                  ? [BoxShadow(color: color.withValues(alpha: .8), blurRadius: 6)]
                  : null,
            ),
          ),
          SizedBox(width: height * .24),
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: height * .4,
              letterSpacing: .3,
            ),
          ),
        ],
      ),
    );
  }
}

enum SeriesCtaStyle { primary, secondary, disabled }

/// CTA pill rendered on a core button base PNG with a Flutter label + chevron.
class SeriesCtaButton extends StatelessWidget {
  const SeriesCtaButton({
    super.key,
    required this.label,
    required this.onTap,
    required this.height,
    this.style = SeriesCtaStyle.primary,
  });

  final String label;
  final VoidCallback onTap;
  final double height;
  final SeriesCtaStyle style;

  String get _asset => switch (style) {
        SeriesCtaStyle.primary => SeriesNewAssets.buttonPrimary,
        SeriesCtaStyle.secondary => SeriesNewAssets.buttonSecondary,
        SeriesCtaStyle.disabled => SeriesNewAssets.buttonDisabled,
      };

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final dim = style == SeriesCtaStyle.disabled;
    final textColor =
        dim ? Colors.white.withValues(alpha: .72) : Colors.white;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: height,
        padding: EdgeInsets.symmetric(horizontal: height * .5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(height),
          image: DecorationImage(image: AssetImage(_asset), fit: BoxFit.fill),
          // Fallback gradient/border if the base PNG is unavailable.
          gradient: style == SeriesCtaStyle.primary
              ? const LinearGradient(
                  colors: [Color(0xff35e2ff), Color(0xff0a86ff)])
              : null,
          color: style == SeriesCtaStyle.secondary
              ? const Color(0xff04101f).withValues(alpha: .4)
              : (dim ? const Color(0xff121826).withValues(alpha: .5) : null),
          border: style == SeriesCtaStyle.primary
              ? null
              : Border.all(color: c.cyan.withValues(alpha: dim ? .3 : .6)),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.w800,
                fontSize: height * .38,
              ),
            ),
            SizedBox(width: height * .14),
            Image.asset(
              SeriesNewAssets.chevronRight,
              height: height * .42,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Icon(Icons.chevron_right_rounded,
                  color: textColor, size: height * .54),
            ),
          ],
        ),
      ),
    );
  }
}

/// Metadata row: Flutter icon + label, separated by thin vertical dividers.
class SeriesMetaRow extends StatelessWidget {
  const SeriesMetaRow({super.key, required this.items, required this.fontSize});

  /// Each item: (icon, label).
  final List<(IconData, String)> items;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    if (items.isEmpty) return const SizedBox.shrink();
    final iconSize = fontSize * 1.2;
    final children = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      if (i != 0) {
        children.add(Container(
          width: 1,
          height: fontSize * 1.35,
          margin: const EdgeInsets.symmetric(horizontal: 7),
          color: Colors.white.withValues(alpha: .22),
        ));
      }
      children.add(Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(items[i].$1, size: iconSize, color: c.cyan.withValues(alpha: .9)),
          const SizedBox(width: 4),
          Text(
            items[i].$2,
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .92),
              fontWeight: FontWeight.w600,
              fontSize: fontSize,
            ),
          ),
        ],
      ));
    }
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

class _PosterFavoriteStar extends StatefulWidget {
  const _PosterFavoriteStar({required this.seriesId, required this.size});

  final String seriesId;
  final double size;

  @override
  State<_PosterFavoriteStar> createState() => _PosterFavoriteStarState();
}

class _PosterFavoriteStarState extends State<_PosterFavoriteStar> {
  bool _on = false;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return GestureDetector(
      onTap: () => setState(() => _on = !_on),
      behavior: HitTestBehavior.opaque,
      child: _on
          ? Icon(Icons.star_rounded, size: widget.size, color: c.warning)
          : Image.asset(
              SeriesNewAssets.favoriteStar,
              width: widget.size,
              height: widget.size,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Icon(
                Icons.star_border_rounded,
                size: widget.size,
                color: Colors.white.withValues(alpha: .85),
              ),
            ),
    );
  }
}

/// Per-type background art + dark gradient (for text contrast) + neon border
/// Smooth Flutter-drawn cyan border + un-clipped outer glow, with the per-type
/// background art clipped inside a rounded rect. The border/radius are drawn by
/// Flutter (not a stretched border PNG) so card edges are always crisp — never
/// "sliced". A directional dark scrim keeps text readable over busy art.
class SeriesBorderFrame extends StatelessWidget {
  const SeriesBorderFrame({
    super.key,
    required this.background,
    required this.height,
    required this.onTap,
    required this.child,
    this.tint,
    this.completed = false,
    this.contentSide = SeriesContentSide.right,
  });

  final String background;
  final double height;
  final VoidCallback onTap;
  final Widget child;
  final Color? tint;
  final bool completed;
  final SeriesContentSide contentSide;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    const radius = 24.0;
    final border = completed
        ? c.cyan.withValues(alpha: .32)
        : c.cyan.withValues(alpha: .62);
    // Darken the side where the text sits; keep the art side clearer.
    final (begin, end) = contentSide == SeriesContentSide.right
        ? (const Alignment(1, 0), const Alignment(-1, 0))
        : (const Alignment(-1, 0), const Alignment(1, 0));
    return TapScale(
      onTap: onTap,
      borderRadius: radius,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          // Outer glow is OUTSIDE the clip so it never gets sliced.
          boxShadow: c.isDark
              ? [
                  BoxShadow(
                    color: c.cyan.withValues(alpha: completed ? .12 : .22),
                    blurRadius: 18,
                    spreadRadius: -2,
                  ),
                  const BoxShadow(
                    color: Color(0x66000000),
                    blurRadius: 14,
                    offset: Offset(0, 8),
                  ),
                ]
              : c.cardShadow,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Stack(
            children: [
              Positioned.fill(
                child: Image.asset(
                  background,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => ColoredBox(
                      color: c.isDark ? c.card : const Color(0xff0a1e3d)),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: begin,
                      end: end,
                      colors: const [Color(0xE6030B17), Color(0x4D030B17)],
                    ),
                  ),
                ),
              ),
              if (tint != null)
                Positioned.fill(child: ColoredBox(color: tint!)),
              child,
              // Crisp cyan edge on top of everything (inside the clip).
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(radius),
                      border: Border.all(color: border, width: 1.2),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum SeriesContentSide { left, right }

// ===========================================================================
// Public entry — resolves variant → card widget
// ===========================================================================

class SeriesPosterCard extends StatelessWidget {
  const SeriesPosterCard({super.key, required this.series, required this.onTap});

  final SeriesView series;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (series.status == SeriesStatus.completed) {
      return CompletedSeriesCard(series: series, onTap: onTap);
    }
    switch (resolveSeriesPosterVariant(series)) {
      case SeriesPosterVariant.league:
        return LeagueSeriesCard(series: series, onTap: onTap);
      case SeriesPosterVariant.tournament:
        return TournamentSeriesCard(series: series, onTap: onTap);
      case SeriesPosterVariant.bilateralOngoing:
      case SeriesPosterVariant.bilateralUpcoming:
      case SeriesPosterVariant.bilateralCompleted:
        return BilateralSeriesCard(series: series, onTap: onTap);
    }
  }
}

/// Tournament poster (multi-team cup) — trophy art left, content right.
class TournamentSeriesCard extends StatelessWidget {
  const TournamentSeriesCard(
      {super.key, required this.series, required this.onTap});
  final SeriesView series;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) =>
      _CompetitionPosterCard(series: series, onTap: onTap, league: false);
}

/// League / franchise poster — cyber stadium + neon batsman + logo strip.
class LeagueSeriesCard extends StatelessWidget {
  const LeagueSeriesCard({super.key, required this.series, required this.onTap});
  final SeriesView series;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) =>
      _CompetitionPosterCard(series: series, onTap: onTap, league: true);
}

/// Two-team tour poster — title left, two team rings right.
class BilateralSeriesCard extends StatelessWidget {
  const BilateralSeriesCard(
      {super.key, required this.series, required this.onTap});
  final SeriesView series;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) =>
      _BilateralPosterCard(series: series, onTap: onTap, completed: false);
}

/// Completed series — muted poster; competition vs bilateral composition.
class CompletedSeriesCard extends StatelessWidget {
  const CompletedSeriesCard(
      {super.key, required this.series, required this.onTap});
  final SeriesView series;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    // Completed series ALWAYS use the compact, dimmed completed design — never
    // the league/batsman or tall tournament composition (per target).
    return _BilateralPosterCard(series: series, onTap: onTap, completed: true);
  }
}

// ---------------------------------------------------------------------------
// Tournament / league card
// ---------------------------------------------------------------------------

class _CompetitionPosterCard extends StatelessWidget {
  const _CompetitionPosterCard({
    required this.series,
    required this.onTap,
    required this.league,
  });

  final SeriesView series;
  final VoidCallback onTap;
  final bool league;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final (statusColor, isLive, statusLabel, statusAsset) =
        _statusStyle(context, series.status);
    final completed = series.status == SeriesStatus.completed;
    final m = _metricsFor(context.w);
    return SeriesBorderFrame(
      background:
          league ? SeriesNewAssets.leagueBg : SeriesNewAssets.tournamentBg,
      height: league ? m.leagueH : m.tournamentH,
      onTap: onTap,
      completed: completed,
      // League art lives on the RIGHT (neon batsman); tournament trophy on the
      // LEFT — so content (and its scrim) goes the opposite way.
      contentSide: league ? SeriesContentSide.left : SeriesContentSide.right,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final teams = series.teams.where(_isShowableTeam).toList();
          final artW = constraints.maxWidth * (league ? .30 : .36);
          final art = league
              ? _SideArt(
                  asset: SeriesNewAssets.leagueBatsman,
                  width: artW,
                  align: Alignment.bottomRight,
                  fallbackIcon: Icons.sports_cricket_rounded,
                  pad: EdgeInsets.only(top: m.pad, bottom: m.pad * .4),
                )
              : _SideArt(
                  // Use the CLEAN core gold-laurel trophy (the extracted silver
                  // sheet trophy has rough/jagged edges).
                  asset: SeriesNewAssets.trophyGold,
                  width: artW,
                  align: Alignment.center,
                  fallbackIcon: Icons.emoji_events_rounded,
                  pad: EdgeInsets.symmetric(vertical: m.pad * 1.2),
                );
          final content = Padding(
            padding: EdgeInsets.fromLTRB(m.pad, m.pad * .7, m.pad, m.pad * .7),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    SeriesStatusPillImg(
                      label: statusLabel,
                      color: statusColor,
                      live: isLive,
                      height: m.statusH,
                      asset: statusAsset,
                    ),
                    const Spacer(),
                    _PosterFavoriteStar(seriesId: series.id, size: m.starSize),
                  ],
                ),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: m.pad * .5),
                      Text(
                        series.cleanName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: m.title,
                          height: 1.12,
                        ),
                      ),
                      if (teams.length >= 2) ...[
                        SizedBox(height: m.pad * .55),
                        SeriesLogoRingRow(
                          teams: teams,
                          totalCount: series.teamCount,
                          ring: m.stripRing,
                        ),
                      ],
                      const Spacer(),
                      SeriesMetaRow(fontSize: m.meta, items: _meta()),
                    ],
                  ),
                ),
                Row(
                  children: [
                    Flexible(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            league
                                ? Icons.shield_rounded
                                : Icons.emoji_events_rounded,
                            size: m.meta * 1.2,
                            color: c.warning,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              league ? 'League' : 'Tournament',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: .9),
                                fontWeight: FontWeight.w700,
                                fontSize: m.meta,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: SeriesCtaButton(
                          label: completed ? 'View Series' : 'Explore Series',
                          onTap: onTap,
                          height: m.ctaH,
                          style: completed
                              ? SeriesCtaStyle.disabled
                              : SeriesCtaStyle.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );

          // Side art on its zone; content padded clear of it.
          return Stack(
            children: [
              Positioned(
                top: 0,
                bottom: 0,
                left: league ? null : 0,
                right: league ? 0 : null,
                width: artW,
                child: art,
              ),
              Padding(
                padding: EdgeInsets.only(
                  left: league ? 0 : artW,
                  right: league ? artW : 0,
                ),
                child: content,
              ),
            ],
          );
        },
      ),
    );
  }

  List<(IconData, String)> _meta() {
    final date = series.shortDateRange;
    final matchLine = series.matchCount != null && series.matchCount! > 0
        ? '${series.matchCount} Matches'
        : series.formatSummary;
    final teamCount = series.teamCount;
    return [
      if (date.isNotEmpty) (Icons.calendar_today_rounded, date),
      if (matchLine.isNotEmpty) (Icons.sports_cricket_rounded, matchLine),
      if (teamCount >= 3) (Icons.groups_rounded, '$teamCount Teams'),
    ];
  }
}

/// Side artwork (trophy / neon batsman) positioned over the card art zone.
class _SideArt extends StatelessWidget {
  const _SideArt({
    required this.asset,
    required this.width,
    required this.align,
    required this.fallbackIcon,
    this.pad = EdgeInsets.zero,
  });

  final String asset;
  final double width;
  final Alignment align;
  final IconData fallbackIcon;
  final EdgeInsets pad;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return SizedBox(
      width: width,
      child: Padding(
        padding: pad,
        child: Align(
          alignment: align,
          child: Image.asset(
            asset,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) =>
                Icon(fallbackIcon, color: c.warning, size: width * .6),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bilateral / completed-tour card
// ---------------------------------------------------------------------------

class _BilateralPosterCard extends StatelessWidget {
  const _BilateralPosterCard({
    required this.series,
    required this.onTap,
    required this.completed,
  });

  final SeriesView series;
  final VoidCallback onTap;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    final (statusColor, isLive, statusLabel, statusAsset) =
        _statusStyle(context, series.status);
    final m = _metricsFor(context.w);
    return SeriesBorderFrame(
      background: SeriesNewAssets.bilateralBg,
      height: completed ? m.completedH : m.bilateralH,
      onTap: onTap,
      completed: completed,
      contentSide: SeriesContentSide.left,
      tint: completed ? const Color(0x66120a22) : null,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final teams = series.teams.where(_isShowableTeam).toList();
          final left = teams.isNotEmpty ? teams.first : null;
          final right = teams.length > 1 ? teams[1] : null;
          final ring = completed ? m.bilatRing * .92 : m.bilatRing;
          return Padding(
            padding: EdgeInsets.fromLTRB(m.pad, m.pad * .65, m.pad, m.pad * .65),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    SeriesStatusPillImg(
                      label: statusLabel,
                      color: statusColor,
                      live: isLive,
                      height: m.statusH,
                      asset: statusAsset,
                    ),
                    const Spacer(),
                    _PosterFavoriteStar(seriesId: series.id, size: m.starSize),
                  ],
                ),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          series.cleanName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: m.title,
                            height: 1.14,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SeriesLogoRingPair(
                        left: left,
                        right: right,
                        ring: ring,
                        completed: completed,
                      ),
                    ],
                  ),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: SeriesMetaRow(
                        fontSize: m.meta,
                        items: [
                          if (series.shortDateRange.isNotEmpty)
                            (Icons.calendar_today_rounded,
                                series.shortDateRange),
                          if (series.formatSummary.isNotEmpty)
                            (Icons.sports_cricket_rounded,
                                series.formatSummary),
                          (
                            completed
                                ? Icons.check_circle_rounded
                                : Icons.swap_horiz_rounded,
                            completed ? 'Completed' : 'Bilateral Series'
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: SeriesCtaButton(
                          label: 'View Series',
                          onTap: onTap,
                          height: m.ctaH,
                          style: completed
                              ? SeriesCtaStyle.disabled
                              : SeriesCtaStyle.secondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ===========================================================================
// Filter chip row (always exactly 4: All / Ongoing / Upcoming / Completed)
// ===========================================================================

class SeriesFilterChipBar extends StatefulWidget {
  const SeriesFilterChipBar({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final int selected;
  final ValueChanged<int> onChanged;

  @override
  State<SeriesFilterChipBar> createState() => _SeriesFilterChipBarState();
}

class _SeriesFilterChipBarState extends State<SeriesFilterChipBar> {
  static const _items = <(String, IconData)>[
    ('All', Icons.grid_view_rounded),
    ('Ongoing', Icons.play_circle_fill_rounded),
    ('Upcoming', Icons.calendar_month_rounded),
    ('Completed', Icons.check_circle_rounded),
  ];

  final ScrollController _controller = ScrollController();
  final List<GlobalKey> _keys =
      List.generate(_items.length, (_) => GlobalKey());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureVisible());
  }

  @override
  void didUpdateWidget(covariant SeriesFilterChipBar old) {
    super.didUpdateWidget(old);
    if (old.selected != widget.selected) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _ensureVisible());
    }
  }

  void _ensureVisible() {
    if (!mounted) return;
    final i = widget.selected;
    if (i < 0 || i >= _keys.length) return;
    final ctx = _keys[i].currentContext;
    if (ctx == null) return;
    // Align the selected chip to the LEADING edge (0.0) so a chip is never left
    // half-clipped at the start of the row.
    Scrollable.ensureVisible(ctx,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        alignment: 0.0,
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        clipBehavior: Clip.hardEdge,
        padding: const EdgeInsets.fromLTRB(0, 4, 4, 4),
        itemCount: _items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) => _FilterChip(
          key: _keys[i],
          label: _items[i].$1,
          icon: _items[i].$2,
          selected: i == widget.selected,
          wide: i == 3,
          onTap: () => widget.onChanged(i),
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.wide,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool wide;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final base = selected
        ? SeriesNewAssets.filterActive
        : (wide
            ? SeriesNewAssets.filterInactiveWide
            : SeriesNewAssets.filterInactive);
    return TapScale(
      onTap: onTap,
      borderRadius: 22,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          image: DecorationImage(image: AssetImage(base), fit: BoxFit.fill),
          // Fallbacks if a chip base asset fails to load.
          gradient: selected
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xff35e2ff), Color(0xff0a86ff)],
                )
              : null,
          color: selected
              ? null
              : (c.isDark ? c.card.withValues(alpha: .42) : c.card),
          border: Border.all(
            color: selected
                ? c.cyan.withValues(alpha: .95)
                : c.cyan.withValues(alpha: .35),
            width: 1.1,
          ),
          boxShadow: selected && c.isDark
              ? [
                  BoxShadow(
                    color: c.cyan.withValues(alpha: .3),
                    blurRadius: 12,
                    spreadRadius: -3,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: selected ? Colors.white : c.muted),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : c.muted,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// Featured hero poster (+ carousel)
// ===========================================================================

class SeriesFeaturedHeroPoster extends StatelessWidget {
  const SeriesFeaturedHeroPoster({
    super.key,
    required this.overline,
    required this.mainWord,
    required this.year,
    required this.formatText,
    required this.onTap,
    this.left,
    this.right,
    this.backgroundImage,
    this.status,
    this.twoTeams = true,
    this.teamCountText = '',
  });

  factory SeriesFeaturedHeroPoster.fromAdmin(
    SeriesHeroData hero, {
    required VoidCallback onTap,
  }) {
    final (small, big) = _splitSeriesTitle(hero.title);
    final (word, year) = _splitYear(big);
    final hasTeams = hero.teamA != null || hero.teamB != null;
    return SeriesFeaturedHeroPoster(
      overline: hero.subtitle.isNotEmpty ? hero.subtitle : small,
      mainWord: word,
      year: year,
      formatText: hero.formatText,
      left: hero.teamA,
      right: hero.teamB,
      backgroundImage: hero.backgroundImage,
      twoTeams: hasTeams,
      onTap: onTap,
    );
  }

  factory SeriesFeaturedHeroPoster.fromSeries(
    SeriesView series, {
    required VoidCallback onTap,
  }) {
    final (small, big) = _splitSeriesTitle(series.cleanName);
    final (word, year) = _splitYear(big);
    final variant = resolveSeriesPosterVariant(series);
    final twoTeams = (variant == SeriesPosterVariant.bilateralUpcoming ||
            variant == SeriesPosterVariant.bilateralOngoing ||
            variant == SeriesPosterVariant.bilateralCompleted) &&
        series.isBilateral;
    return SeriesFeaturedHeroPoster(
      overline: small,
      mainWord: word,
      year: year,
      formatText: series.formatSummary,
      left: twoTeams && series.teams.isNotEmpty ? series.teams.first : null,
      right: twoTeams && series.teams.length > 1 ? series.teams[1] : null,
      status: series.status,
      twoTeams: twoTeams,
      teamCountText:
          !twoTeams && series.teamCount >= 3 ? '${series.teamCount} Teams' : '',
      onTap: onTap,
    );
  }

  final String overline;
  final String mainWord;
  final String year;
  final String formatText;
  final SeriesTeamRef? left;
  final SeriesTeamRef? right;
  final String? backgroundImage;
  final SeriesStatus? status;
  final bool twoTeams;
  final String teamCountText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final m = _metricsFor(context.w);
    return TapScale(
      onTap: onTap,
      borderRadius: 30,
      child: SizedBox(
        height: m.hero,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: Stack(
            children: [
              Positioned.fill(child: _HeroBackground(image: backgroundImage)),
              // Soft dark gradient for centre-text legibility.
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x66020812), Color(0xBB020812)],
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: Image.asset(
                    SeriesNewAssets.heroBorder,
                    fit: BoxFit.fill,
                    errorBuilder: (_, __, ___) => DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                            color: c.cyan.withValues(alpha: .55), width: 1.4),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: m.pad, vertical: 12),
                child: Row(
                  children: [
                    if (twoTeams)
                      SeriesLogoRing(
                        size: m.heroRing,
                        ring: SeriesNewAssets.ringBlueGlow,
                        team: left,
                        accent: c.cyan,
                      ),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Image.asset(
                            SeriesNewAssets.trophyGold,
                            height: m.hero * .2,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => Icon(
                                Icons.emoji_events_rounded,
                                color: c.warning,
                                size: m.hero * .18),
                          ),
                          const SizedBox(height: 4),
                          if (overline.isNotEmpty)
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                overline.toUpperCase(),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: m.title * .62,
                                  letterSpacing: .5,
                                ),
                              ),
                            ),
                          // Main subject word (e.g. "BANGLADESH,") must NEVER
                          // truncate — scale it down to fit the centre column.
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              mainWord.toUpperCase(),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              style: TextStyle(
                                color: c.cyan,
                                fontWeight: FontWeight.w900,
                                fontSize: m.title * 1.25,
                                height: 1.02,
                                shadows: [
                                  Shadow(
                                      color: c.cyan.withValues(alpha: .5),
                                      blurRadius: 14),
                                ],
                              ),
                            ),
                          ),
                          if (year.isNotEmpty)
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                year,
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                style: TextStyle(
                                  color: c.cyan.withValues(alpha: .85),
                                  fontWeight: FontWeight.w900,
                                  fontSize: m.title,
                                ),
                              ),
                            ),
                          if (formatText.isNotEmpty ||
                              teamCountText.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            _HeroPill(
                                label: formatText.isNotEmpty
                                    ? formatText
                                    : teamCountText),
                          ],
                        ],
                      ),
                    ),
                    if (twoTeams)
                      SeriesLogoRing(
                        size: m.heroRing,
                        ring: SeriesNewAssets.ringOrangeGreenGlow,
                        team: right,
                        accent: const Color(0xffff8a3d),
                      ),
                  ],
                ),
              ),
              if (status != null)
                Positioned(
                  top: 12,
                  left: 14,
                  child: Builder(builder: (context) {
                    final (col, live, lbl, asset) =
                        _statusStyle(context, status!);
                    return SeriesStatusPillImg(
                      label: lbl,
                      color: col,
                      live: live,
                      height: m.statusH,
                      asset: asset,
                    );
                  }),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Swipeable hero carousel with animated dots — matches the target's top
/// spotlight. Pages are real [SeriesFeaturedHeroPoster]s built from live data.
class SeriesHeroCarousel extends StatefulWidget {
  const SeriesHeroCarousel({super.key, required this.pages});

  final List<SeriesFeaturedHeroPoster> pages;

  @override
  State<SeriesHeroCarousel> createState() => _SeriesHeroCarouselState();
}

class _SeriesHeroCarouselState extends State<SeriesHeroCarousel> {
  late final PageController _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final m = _metricsFor(context.w);
    if (widget.pages.length == 1) {
      return widget.pages.first;
    }
    return Column(
      children: [
        SizedBox(
          height: m.hero,
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.pages.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) => widget.pages[i],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < widget.pages.length; i++)
              _CarouselDot(active: i == _index),
          ],
        ),
      ],
    );
  }
}

class _CarouselDot extends StatelessWidget {
  const _CarouselDot({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      margin: const EdgeInsets.symmetric(horizontal: 3),
      width: active ? 18 : 7,
      height: 7,
      decoration: BoxDecoration(
        color: active ? c.cyan : Colors.white.withValues(alpha: .3),
        borderRadius: BorderRadius.circular(4),
        boxShadow: active && c.isDark
            ? [BoxShadow(color: c.cyan.withValues(alpha: .6), blurRadius: 6)]
            : null,
      ),
    );
  }
}

class _HeroBackground extends StatelessWidget {
  const _HeroBackground({this.image});

  final String? image;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    Widget asset() => Image.asset(
          SeriesNewAssets.tournamentBg,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              ColoredBox(color: c.isDark ? c.card : const Color(0xff0a1e3d)),
        );
    final url = image?.trim() ?? '';
    if (url.startsWith('http')) {
      return CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        fadeInDuration: Duration.zero,
        placeholder: (context, _) => asset(),
        errorWidget: (_, __, ___) => asset(),
      );
    }
    return asset();
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: c.isDark
            ? const Color(0xff04101f).withValues(alpha: .6)
            : c.card.withValues(alpha: .85),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.cyan.withValues(alpha: .5)),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: Colors.white.withValues(alpha: .95),
          fontWeight: FontWeight.w700,
          fontSize: 12.5,
        ),
      ),
    );
  }
}

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

(String, String) _splitYear(String big) {
  final t = big.trim();
  final m = RegExp(r'^(.*?)[, ]\s*(\d{4}(?:[-/]\d{2,4})?)\s*$').firstMatch(t);
  if (m != null && m.group(1)!.trim().isNotEmpty) {
    return (m.group(1)!.trim(), m.group(2)!.trim());
  }
  return (t, '');
}

