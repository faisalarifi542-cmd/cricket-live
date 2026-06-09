import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:cricpro_flutter/app_theme.dart';
import 'package:cricpro_flutter/components.dart';

/// Premium CricPro Series artwork assets + shared visual building blocks.
///
/// Everything here is purely presentational — it carries no data/network
/// logic. The Series screens compose these widgets so the whole module shares
/// the finished Home screen's dark-navy / cyan-glow / glassmorphism language.

// ---------------------------------------------------------------------------
// Asset catalogue
// ---------------------------------------------------------------------------

class SAsset {
  static const _bg = 'assets/images/series/backgrounds';
  static const _fx = 'assets/images/series/effects';
  static const _venue = 'assets/images/series/venues';
  static const _ph = 'assets/images/series/placeholders';
  static const _home = 'assets/images/home';

  // Backgrounds.
  static const screenBg = '$_bg/series_screen_background.png';
  static const topBackdrop = '$_bg/series_page_top_backdrop.png';
  static const featuredCarouselBg = '$_bg/series_featured_carousel_bg.png';
  static const detailHeroBg = '$_bg/series_detail_hero_bg.png';
  static const matchCardBg = '$_bg/series_match_card_bg.png';
  static const listCardBg = '$_bg/series_list_card_bg.png';
  static const overviewPanelBg = '$_bg/series_overview_panel_bg.png';
  static const statsTableBg = '$_bg/series_stats_table_bg.png';
  static const squadSectionBg = '$_bg/series_squad_section_bg.png';
  static const emptyStateBg = '$_bg/series_empty_state_bg.png';

  // Effects.
  static const vsUnderGlowStrong = '$_fx/vs_under_glow_strong.png';
  static const vsUnderGlowSoft = '$_fx/vs_under_glow_soft.png';
  static const vsLightStreak = '$_fx/vs_light_streak.png';
  static const centerVsSpotlight = '$_fx/center_vs_spotlight.png';
  static const neonCardTopEdge = '$_fx/neon_card_top_edge.png';
  static const cyanParticles = '$_fx/cyan_particles_overlay.png';
  static const glassNoise = '$_fx/glass_noise_overlay.png';

  // Placeholders.
  static const trophyPlaceholder = '$_ph/series_trophy_placeholder.png';

  // Home reuse (shared stadium atmosphere).
  static const homeStadiumBackdrop =
      '$_home/futuristic_stadium_ui_backdrop.png';

  /// Resolves a city/venue name to one of the bundled venue thumbnails,
  /// falling back to the generic stadium image.
  static String venueFor(String venue) {
    final v = venue.toLowerCase();
    if (v.contains('indore') || v.contains('holkar')) {
      return '$_venue/venue_indore.png';
    }
    if (v.contains('delhi') || v.contains('jaitley') || v.contains('kotla')) {
      return '$_venue/venue_delhi.png';
    }
    if (v.contains('mumbai') ||
        v.contains('wankhede') ||
        v.contains('brabourne')) {
      return '$_venue/venue_mumbai.png';
    }
    if (v.contains('bengaluru') ||
        v.contains('bangalore') ||
        v.contains('chinnaswamy')) {
      return '$_venue/venue_bengaluru.png';
    }
    return '$_venue/venue_generic.png';
  }
}

// ---------------------------------------------------------------------------
// Soft radial glow orb (floodlight / accent), ported from Home.
// ---------------------------------------------------------------------------

class GlowOrb extends StatelessWidget {
  const GlowOrb({
    super.key,
    required this.color,
    required this.size,
    required this.alpha,
  });

  final Color color;
  final double size;
  final double alpha;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: alpha),
              color.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}

/// Thin glowing cyan line drawn along the top edge of premium cards.
class TopCyanHighlight extends StatelessWidget {
  const TopCyanHighlight({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: 2,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.transparent,
              c.cyan.withValues(alpha: .7),
              c.cyan.withValues(alpha: .85),
              c.cyan.withValues(alpha: .7),
              Colors.transparent,
            ],
            stops: const [0, .25, .5, .75, 1],
          ),
          boxShadow: [
            BoxShadow(color: c.cyan.withValues(alpha: .4), blurRadius: 5),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Premium glass panel — stadium-textured card with cyan border + top glow.
// ---------------------------------------------------------------------------

class PremiumGlassPanel extends StatelessWidget {
  const PremiumGlassPanel({
    super.key,
    required this.child,
    this.bgAsset,
    this.padding = const EdgeInsets.all(16),
    this.radius = 22,
    this.onTap,
    this.borderAlpha = .42,
    this.glow = true,
    this.minHeight,
  });

  final Widget child;
  final String? bgAsset;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final double borderAlpha;
  final bool glow;
  final double? minHeight;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final body = Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        color: c.card.withValues(alpha: .55),
        border:
            Border.all(color: c.cyan.withValues(alpha: borderAlpha), width: 1),
        boxShadow: [
          if (glow)
            BoxShadow(
              color: c.cyan.withValues(alpha: .10),
              blurRadius: 20,
              spreadRadius: -8,
            ),
          BoxShadow(
            color: Colors.black.withValues(alpha: .36),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: minHeight ?? 0),
        child: Stack(
          children: [
            if (bgAsset != null) ...[
              Positioned.fill(
                child: Image.asset(
                  bgAsset!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        const Color(0xff04142b).withValues(alpha: .74),
                        const Color(0xff051226).withValues(alpha: .82),
                        const Color(0xff020a18).withValues(alpha: .9),
                      ],
                      stops: const [0, .5, 1],
                    ),
                  ),
                ),
              ),
            ],
            const TopCyanHighlight(),
            Padding(padding: padding, child: child),
          ],
        ),
      ),
    );
    if (onTap == null) return body;
    return TapScale(onTap: onTap, borderRadius: radius, child: body);
  }
}

/// Glass panel with a titled header row (icon + uppercase title + trailing).
class PremiumSectionPanel extends StatelessWidget {
  const PremiumSectionPanel({
    super.key,
    required this.title,
    required this.child,
    this.icon,
    this.bgAsset,
    this.trailing,
    this.padding = const EdgeInsets.all(16),
  });

  final String title;
  final Widget child;
  final IconData? icon;
  final String? bgAsset;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumGlassPanel(
      bgAsset: bgAsset,
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, color: c.cyan, size: 17),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.text,
                    fontWeight: FontWeight.w900,
                    fontStyle: FontStyle.italic,
                    fontSize: 13.5,
                    letterSpacing: .4,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

/// Small "View All >" pill button used in section headers.
class PremiumViewAll extends StatelessWidget {
  const PremiumViewAll({super.key, required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return TapScale(
      onTap: onTap,
      borderRadius: 999,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: c.cyan.withValues(alpha: .5)),
          color: c.cyan.withValues(alpha: .08),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: c.cyan,
                fontWeight: FontWeight.w800,
                fontSize: 11.5,
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.chevron_right_rounded, color: c.cyan, size: 16),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Premium team / board logo with cyan glow ring.
// ---------------------------------------------------------------------------

class PremiumTeamLogo extends StatelessWidget {
  const PremiumTeamLogo({
    super.key,
    required this.name,
    required this.short,
    required this.logo,
    required this.size,
    this.accent,
  });

  final String name;
  final String short;
  final String? logo;
  final double size;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final code = (short.isEmpty ? name : short).toUpperCase();
    final isPlaceholder = code == 'TBC' || code == 'TBD' || code.isEmpty;
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: c.cyan.withValues(alpha: .35),
            blurRadius: size * .25,
            spreadRadius: -2,
          ),
        ],
      ),
      child: TeamLogoWidget(
        logoUrl: isPlaceholder ? null : logo,
        teamName: name,
        abbreviation: code,
        color: accent ?? c.cyan,
        size: size,
      ),
    );
  }
}

/// A team column: glowing logo + bold short code + optional full name.
class PremiumTeamColumn extends StatelessWidget {
  const PremiumTeamColumn({
    super.key,
    required this.name,
    required this.short,
    required this.logo,
    required this.logoSize,
    this.codeSize = 18,
    this.accent,
    this.showFullName = true,
  });

  final String name;
  final String short;
  final String? logo;
  final double logoSize;
  final double codeSize;
  final Color? accent;
  final bool showFullName;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final code = (short.isEmpty ? name : short).toUpperCase();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PremiumTeamLogo(
          name: name,
          short: short,
          logo: logo,
          size: logoSize,
          accent: accent,
        ),
        const SizedBox(height: 6),
        Text(
          code,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: c.text,
            fontWeight: FontWeight.w900,
            fontSize: codeSize,
            height: 1,
          ),
        ),
        if (showFullName && name.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .74),
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Premium VS badge — slanted glowing glass chip with under-glow + streak.
// Ported from the finished Home screen, with optional asset under-glow.
// ---------------------------------------------------------------------------

class PremiumVsBadge extends StatelessWidget {
  const PremiumVsBadge({
    super.key,
    required this.width,
    required this.height,
    this.intensity = 1.0,
  });

  final double width;
  final double height;
  final double intensity;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // A. Soft cyan bloom behind the VS.
          Positioned(
            left: -width * 0.45,
            right: -width * 0.45,
            top: -height * 0.55,
            bottom: -height * 0.55,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    c.cyan.withValues(alpha: 0.34 * intensity),
                    c.cyan.withValues(alpha: 0.12 * intensity),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.45, 1.0],
                ),
              ),
            ),
          ),
          // B. Strong light pool directly under the badge.
          Positioned(
            bottom: -height * 0.32,
            child: Container(
              width: width * 1.15,
              height: height * 0.34,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: c.cyan.withValues(alpha: 0.20 * intensity),
                boxShadow: [
                  BoxShadow(
                    color: c.cyan.withValues(alpha: 0.42 * intensity),
                    blurRadius: 20,
                    spreadRadius: 5,
                  ),
                  BoxShadow(
                    color: c.cyan.withValues(alpha: 0.18 * intensity),
                    blurRadius: 34,
                    spreadRadius: 10,
                  ),
                ],
              ),
            ),
          ),
          // C. Diagonal electric streak behind the pill.
          Transform.rotate(
            angle: -0.72,
            child: Container(
              width: width * 1.75,
              height: 4,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(99),
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    c.cyan.withValues(alpha: 0.75 * intensity),
                    Colors.white.withValues(alpha: 0.42 * intensity),
                    c.cyan.withValues(alpha: 0.55 * intensity),
                    Colors.transparent,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: c.cyan.withValues(alpha: 0.35 * intensity),
                    blurRadius: 14,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ),
          // D. The slanted glass pill.
          CustomPaint(
            size: Size(width, height),
            painter: _VsBadgePainter(
              border: c.cyan,
              fill: const Color(0xff071d34).withValues(alpha: .86),
              glow: c.cyan.withValues(alpha: .5 * intensity),
              strokeWidth: 1.5,
            ),
          ),
          Text(
            'VS',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: height * 0.42,
              letterSpacing: .6,
              shadows: [
                Shadow(
                  color: c.cyan.withValues(alpha: .9 * intensity),
                  blurRadius: 10,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VsBadgePainter extends CustomPainter {
  _VsBadgePainter({
    required this.border,
    required this.fill,
    required this.glow,
    this.strokeWidth = 1.6,
  });

  final Color border;
  final Color fill;
  final Color glow;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final slant = size.height * 0.22;
    final pts = <Offset>[
      Offset(slant, 0),
      Offset(size.width, 0),
      Offset(size.width - slant, size.height),
      Offset(0, size.height),
    ];
    final path = _roundedPoly(pts, size.height * 0.26);

    canvas.drawPath(
      path,
      Paint()
        ..color = glow
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawPath(path, Paint()..color = fill);
    canvas.save();
    canvas.clipPath(path);
    final streak = Paint()
      ..color = border.withValues(alpha: .4)
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(size.width * 0.2, size.height + 2),
      Offset(size.width * 0.8, -2),
      streak,
    );
    canvas.restore();
    canvas.drawPath(
      path,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeJoin = StrokeJoin.round,
    );
  }

  Path _roundedPoly(List<Offset> pts, double r) {
    final path = Path();
    final n = pts.length;
    for (var i = 0; i < n; i++) {
      final curr = pts[i];
      final prev = pts[(i - 1 + n) % n];
      final next = pts[(i + 1) % n];
      final toPrev = prev - curr;
      final toNext = next - curr;
      final lPrev = toPrev.distance;
      final lNext = toNext.distance;
      if (lPrev == 0 || lNext == 0) continue;
      final rPrev = math.min(r, lPrev / 2);
      final rNext = math.min(r, lNext / 2);
      final p1 = curr + toPrev * (rPrev / lPrev);
      final p2 = curr + toNext * (rNext / lNext);
      if (i == 0) {
        path.moveTo(p1.dx, p1.dy);
      } else {
        path.lineTo(p1.dx, p1.dy);
      }
      path.quadraticBezierTo(curr.dx, curr.dy, p2.dx, p2.dy);
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant _VsBadgePainter old) =>
      old.border != border ||
      old.fill != fill ||
      old.glow != glow ||
      old.strokeWidth != strokeWidth;
}

// ---------------------------------------------------------------------------
// Status badge pill (LIVE / UPCOMING / COMPLETED) — Home style.
// ---------------------------------------------------------------------------

class SeriesStatusPill extends StatelessWidget {
  const SeriesStatusPill({
    super.key,
    required this.label,
    required this.color,
    this.live = false,
    this.dense = false,
  });

  final String label;
  final Color color;
  final bool live;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 10, vertical: 3.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .85)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (live) ...[
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: dense ? 9.5 : 10,
              letterSpacing: .4,
            ),
          ),
        ],
      ),
    );
  }
}

/// Outlined neutral chip (category label).
class SeriesOutlineChip extends StatelessWidget {
  const SeriesOutlineChip({super.key, required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
      decoration: BoxDecoration(
        color: c.cyan.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.cyan.withValues(alpha: .35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: c.cyan, size: 11),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: c.cyan,
              fontWeight: FontWeight.w800,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Home-style status tab group (Ongoing / Upcoming / Completed).
// ---------------------------------------------------------------------------

class SeriesStatusTabs extends StatelessWidget {
  const SeriesStatusTabs({
    super.key,
    required this.selected,
    required this.onChanged,
    this.tabs = const [
      ('Ongoing', Icons.podcasts_rounded),
      ('Upcoming', Icons.calendar_month_rounded),
      ('Completed', Icons.verified_outlined),
    ],
  });

  final int selected;
  final ValueChanged<int> onChanged;
  final List<(String, IconData)> tabs;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      height: 50,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.card.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: c.cyan.withValues(alpha: .4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .28),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          for (var i = 0; i < tabs.length; i++) ...[
            if (i != 0)
              Container(
                width: 1,
                height: 20,
                color: i == selected || (i - 1) == selected
                    ? Colors.transparent
                    : c.cyan.withValues(alpha: .22),
              ),
            Expanded(
              child: _StatusTab(
                label: tabs[i].$1,
                icon: tabs[i].$2,
                selected: i == selected,
                onTap: () => onChanged(i),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusTab extends StatelessWidget {
  const _StatusTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        height: 40,
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xff35e2ff), Color(0xff0a86ff)],
                )
              : null,
          borderRadius: BorderRadius.circular(22),
          border: selected
              ? Border.all(color: c.cyan.withValues(alpha: .95), width: 1.2)
              : null,
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: c.cyan.withValues(alpha: .5),
                    blurRadius: 16,
                    spreadRadius: -2,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: selected ? Colors.white : c.muted),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? Colors.white : c.muted,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  fontSize: context.w <= 360 ? 11.5 : 12.8,
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
// Category chips (All / International / League / Domestic) — Home style.
// ---------------------------------------------------------------------------

class SeriesCategoryChips extends StatelessWidget {
  const SeriesCategoryChips({
    super.key,
    required this.items,
    required this.selected,
    required this.onChanged,
  });

  final List<(String, IconData)> items;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final tight = context.w <= 393;
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 9),
        itemBuilder: (context, i) {
          final sel = i == selected;
          var label = items[i].$1;
          if (tight && label == 'International') label = 'Intl';
          return TapScale(
            onTap: () => onChanged(i),
            borderRadius: 24,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              padding: EdgeInsets.symmetric(horizontal: tight ? 12 : 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: sel
                    ? const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xff35e2ff), Color(0xff0a86ff)],
                      )
                    : null,
                color: sel ? null : c.card.withValues(alpha: .4),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: sel
                      ? c.cyan.withValues(alpha: .9)
                      : c.cyan.withValues(alpha: .28),
                ),
                boxShadow: sel
                    ? [
                        BoxShadow(
                          color: c.cyan.withValues(alpha: .4),
                          blurRadius: 14,
                          spreadRadius: -3,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    items[i].$2,
                    size: 14,
                    color: sel ? Colors.white : c.muted,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      color: sel ? Colors.white : c.muted,
                      fontWeight: sel ? FontWeight.w800 : FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Detail glass tab bar (Overview / Matches / Squads / Stats) with icons.
// ---------------------------------------------------------------------------

class SeriesGlassTabBar extends StatelessWidget {
  const SeriesGlassTabBar({
    super.key,
    required this.items,
    required this.selected,
    required this.onChanged,
  });

  final List<(String, IconData)> items;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final tight = context.w <= 360;
    return Container(
      height: 52,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.card.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.cyan.withValues(alpha: .4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .28),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i != 0)
              Container(
                width: 1,
                height: 22,
                color: i == selected || (i - 1) == selected
                    ? Colors.transparent
                    : c.cyan.withValues(alpha: .22),
              ),
            Expanded(
              child: _GlassTab(
                label: items[i].$1,
                icon: items[i].$2,
                selected: i == selected,
                compact: tight,
                onTap: () => onChanged(i),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _GlassTab extends StatelessWidget {
  const _GlassTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        height: 44,
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xff35e2ff), Color(0xff0a86ff)],
                )
              : null,
          borderRadius: BorderRadius.circular(14),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: c.cyan.withValues(alpha: .45),
                    blurRadius: 14,
                    spreadRadius: -2,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: selected ? Colors.white : c.muted),
            if (!compact || selected) ...[
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? Colors.white : c.muted,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Premium empty / error state on a stadium backdrop.
// ---------------------------------------------------------------------------

class SeriesEmptyState extends StatelessWidget {
  const SeriesEmptyState({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.emoji_events_outlined,
    this.onRetry,
  });

  final String title;
  final String message;
  final IconData icon;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: c.cyan.withValues(alpha: .32)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .3),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              SAsset.emptyStateBg,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xff04142b).withValues(alpha: .72),
                    const Color(0xff020a18).withValues(alpha: .9),
                  ],
                ),
              ),
            ),
          ),
          const TopCyanHighlight(),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 22),
            child: Column(
              children: [
                Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.cyan.withValues(alpha: .14),
                    border: Border.all(color: c.cyan.withValues(alpha: .5)),
                    boxShadow: [
                      BoxShadow(
                        color: c.cyan.withValues(alpha: .25),
                        blurRadius: 18,
                        spreadRadius: -4,
                      ),
                    ],
                  ),
                  child: Icon(icon, color: c.cyan, size: 30),
                ),
                const SizedBox(height: 14),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: c.text,
                    fontWeight: FontWeight.w900,
                    fontSize: 16.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .72),
                    height: 1.4,
                    fontSize: 13,
                  ),
                ),
                if (onRetry != null) ...[
                  const SizedBox(height: 18),
                  GradientButton(
                    label: 'Retry',
                    icon: Icons.refresh_rounded,
                    onTap: onRetry!,
                    height: 46,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Premium skeleton card used while a section loads.
class SeriesSkeleton extends StatelessWidget {
  const SeriesSkeleton({super.key, this.height = 130});

  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: c.card.withValues(alpha: .5),
        border: Border.all(color: c.cyan.withValues(alpha: .22)),
      ),
      alignment: Alignment.center,
      child: CircularProgressIndicator(color: c.cyan, strokeWidth: 3),
    );
  }
}
