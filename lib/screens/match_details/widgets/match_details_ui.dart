import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:cricpro_flutter/app_theme.dart';
import 'package:cricpro_flutter/components.dart';
import 'package:cricpro_flutter/models/cricket_match.dart';
import 'package:cricpro_flutter/utils/match_status.dart';
import 'package:cricpro_flutter/utils/team_format.dart';
import 'package:cricpro_flutter/widgets/remote_or_local_image.dart';
import 'package:cricpro_flutter/widgets/team_score_view.dart';

/// Premium shared building blocks for the Match Details module. Purely
/// presentational — no data/network logic. Matches the finished Home / Series
/// design language: deep navy, cyan neon, glassmorphism, stadium atmosphere.

// ---------------------------------------------------------------------------
// Asset catalogue
// ---------------------------------------------------------------------------

class MDAsset {
  static const _bg = 'assets/images/match_details/backgrounds';
  static const _ov = 'assets/images/match_details/overlays';
  static const _badge = 'assets/images/match_details/badges';
  static const _balls = 'assets/images/match_details/balls';
  static const _icon = 'assets/images/match_details/icons';

  static const heroBg = '$_bg/stadium_score_header_bg.webp';

  static const teamRing = '$_ov/team_logo_ring.webp';
  static const vsGlow = '$_ov/vs_under_glow.webp';
  static const vsStreak = '$_ov/vs_light_streak.webp';
  static const topEdgeGlow = '$_ov/cyan_top_edge_glow.webp';

  static const vsBadge = '$_badge/vs_badge_premium.webp';

  // Premium section / tab icons (line-art PNGs sized for this module).
  static const icBack = '$_icon/back_arrow.webp';
  static const icFilter = '$_icon/filter_sliders.webp';
  static const icUpdated = '$_icon/updated.webp';
  static const icRefresh = '$_icon/refresh.webp';
  static const icVenue = '$_icon/venue.webp';
  static const icLocationPin = '$_icon/location_pin.webp';
  static const icCurrentBatters = '$_icon/current_batters.webp';
  static const icCurrentBowler = '$_icon/current_bowler.webp';
  static const icPartnership = '$_icon/partnership.webp';
  static const icLastWicket = '$_icon/last_wicket.webp';
  static const icRecentOver = '$_icon/recent_over.webp';
  static const icRunRate = '$_icon/run_rate.webp';
  static const icViewMore = '$_icon/view_more.webp';
  static const icExpandDown = '$_icon/expand_down.webp';
  static const icBatting = '$_icon/batting.webp';
  static const icBowling = '$_icon/bowling.webp';
  static const icFallWickets = '$_icon/fall_wickets.webp';

  static const tabInfo = '$_icon/tab_info.webp';
  static const tabLive = '$_icon/tab_live.webp';
  static const tabScorecard = '$_icon/tab_scorecard.webp';
  static const tabSquad = '$_icon/tab_squad.webp';
  static const tabCommentary = '$_icon/tab_commentary.webp';
  static const tabOvers = '$_icon/tab_overs.webp';

  static String ball(String label, {bool wicket = false}) {
    if (wicket) return '$_balls/ball_wicket.webp';
    switch (label.trim().toLowerCase()) {
      case '0':
      case '.':
      case 'dot':
        return '$_balls/ball_dot.webp';
      case '1':
        return '$_balls/ball_1.webp';
      case '2':
        return '$_balls/ball_2.webp';
      case '3':
        return '$_balls/ball_3.webp';
      case '4':
        return '$_balls/ball_4.webp';
      case '6':
        return '$_balls/ball_6.webp';
      case 'w':
        return '$_balls/ball_wicket.webp';
      default:
        return '$_balls/ball_dot.webp';
    }
  }
}

/// Renders a premium PNG icon from the match-details icon set, with a graceful
/// fallback to a Material icon if the asset is missing or fails to decode.
///
/// By default the PNG is shown at its natural colours (these are pre-styled
/// neon/line icons). Pass [tint] to recolour monochrome glyphs (used for the
/// state-aware tab bar). The Material [fallback] always uses [tint] (or cyan).
class MDIcon extends StatelessWidget {
  const MDIcon(
    this.asset, {
    super.key,
    required this.fallback,
    this.size = 16,
    this.tint,
  });

  final String asset;
  final IconData fallback;
  final double size;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final color = tint ?? c.cyan;
    return Image.asset(
      asset,
      width: size,
      height: size,
      color: tint,
      filterQuality: FilterQuality.medium,
      excludeFromSemantics: true,
      errorBuilder: (_, __, ___) => Icon(fallback, size: size, color: color),
    );
  }
}

// ---------------------------------------------------------------------------
// Glow helpers
// ---------------------------------------------------------------------------

class MDTopGlow extends StatelessWidget {
  const MDTopGlow({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    // Neon top strip is dark-mode only — keep light cards clean white.
    if (!c.isDark) return const SizedBox.shrink();
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
// Glass panel — rounded dark-glass card with cyan border + soft glow.
// ---------------------------------------------------------------------------

class MDGlassPanel extends StatelessWidget {
  const MDGlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 18,
    this.borderAlpha = .22,
    this.bgAsset,
    this.onTap,
    this.topGlow = false,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double borderAlpha;
  final String? bgAsset;
  final VoidCallback? onTap;
  final bool topGlow;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final body = Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        color: c.isDark ? c.card.withValues(alpha: .6) : c.card,
        border:
            Border.all(color: c.cyan.withValues(alpha: borderAlpha), width: 1),
        boxShadow: c.isDark
            ? [
                BoxShadow(
                  color: c.cyan.withValues(alpha: .06),
                  blurRadius: 18,
                  spreadRadius: -8,
                ),
                ...c.heroShadow.skip(1),
              ]
            : c.cardShadow,
      ),
      child: Stack(
        children: [
          if (bgAsset != null) ...[
            Positioned.fill(
              child: Image.asset(
                bgAsset!,
                fit: BoxFit.cover,
                excludeFromSemantics: true,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: c.isDark
                      ? const Color(0xff04142b).withValues(alpha: .68)
                      : Colors.white.withValues(alpha: .55),
                ),
              ),
            ),
          ],
          if (topGlow) const MDTopGlow(),
          Padding(padding: padding, child: child),
        ],
      ),
    );
    if (onTap == null) return body;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(radius),
      child: body,
    );
  }
}

// ---------------------------------------------------------------------------
// Section header (cyan icon + italic title + optional trailing)
// ---------------------------------------------------------------------------

class MDSectionHeader extends StatelessWidget {
  const MDSectionHeader({
    super.key,
    required this.title,
    this.icon,
    this.trailing,
  });

  final String title;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Row(
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
    );
  }
}

/// Small outlined "View All" / "View More" pill button.
class MDViewMore extends StatelessWidget {
  const MDViewMore({super.key, required this.label, this.icon, this.onTap});

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
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
            Icon(icon ?? Icons.chevron_right_rounded, color: c.cyan, size: 16),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Status pill (LIVE etc.)
// ---------------------------------------------------------------------------

class MDStatusPill extends StatelessWidget {
  const MDStatusPill({
    super.key,
    required this.label,
    required this.color,
    this.live = false,
  });

  final String label;
  final Color color;
  final bool live;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
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
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 10,
              letterSpacing: .4,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// VS badge — slanted glowing glass chip (ported from Home).
// ---------------------------------------------------------------------------

class MDVsBadge extends StatelessWidget {
  const MDVsBadge({
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
    // Light mode: no cyan halo (rule 9). Glow layers below scale by `glow`
    // (0 in light); the pill paints a clean blue→cyan gradient instead.
    final glow = c.isDark ? intensity : 0.0;
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
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
                    c.cyan.withValues(alpha: 0.45 * glow),
                    c.cyan.withValues(alpha: 0.16 * glow),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -height * 0.36,
            child: Container(
              width: width * 1.3,
              height: height * 0.4,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: c.cyan.withValues(alpha: 0.26 * glow),
                boxShadow: [
                  BoxShadow(
                    color: c.cyan.withValues(alpha: 0.55 * glow),
                    blurRadius: 26,
                    spreadRadius: 7,
                  ),
                  BoxShadow(
                    color: c.cyan.withValues(alpha: 0.24 * glow),
                    blurRadius: 44,
                    spreadRadius: 14,
                  ),
                ],
              ),
            ),
          ),
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
              ),
            ),
          ),
          CustomPaint(
            size: Size(width, height),
            painter: _VsPainter(
              border: c.isDark ? c.cyan : Colors.white,
              fill: const Color(0xff071d34).withValues(alpha: .88),
              fillGradient: c.isDark
                  ? null
                  : const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xff35e2ff), Color(0xff0a86ff)],
                    ),
              glow: c.cyan.withValues(alpha: .5 * glow),
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
                    color: c.cyan.withValues(alpha: .9 * glow),
                    blurRadius: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VsPainter extends CustomPainter {
  _VsPainter({
    required this.border,
    required this.fill,
    required this.glow,
    this.fillGradient,
  });

  final Color border;
  final Color fill;
  final Color glow;
  final Gradient? fillGradient;

  @override
  void paint(Canvas canvas, Size size) {
    final slant = size.height * 0.22;
    final pts = <Offset>[
      Offset(slant, 0),
      Offset(size.width, 0),
      Offset(size.width - slant, size.height),
      Offset(0, size.height),
    ];
    final path = _rounded(pts, size.height * 0.26);
    canvas.drawPath(
      path,
      Paint()
        ..color = glow
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    final fillPaint = Paint();
    if (fillGradient != null) {
      fillPaint.shader = fillGradient!.createShader(Offset.zero & size);
    } else {
      fillPaint.color = fill;
    }
    canvas.drawPath(path, fillPaint);
    canvas.drawPath(
      path,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.round,
    );
  }

  Path _rounded(List<Offset> pts, double r) {
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
  bool shouldRepaint(covariant _VsPainter old) =>
      old.border != border ||
      old.fill != fill ||
      old.glow != glow ||
      old.fillGradient != fillGradient;
}

// ---------------------------------------------------------------------------
// Team score block (logo ring + code + score + overs)
// ---------------------------------------------------------------------------

class MDTeamScoreBlock extends StatelessWidget {
  const MDTeamScoreBlock({
    super.key,
    required this.name,
    required this.short,
    required this.logo,
    required this.innings,
    required this.accent,
    required this.logoSize,
    this.live = false,
    this.currentInningsIndex = -1,
  });

  final String name;
  final String short;
  final String? logo;
  final List<InningsScore> innings;
  final Color accent;
  final double logoSize;
  final bool live;
  final int currentInningsIndex;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    // Shared formatter so variant suffixes read cleanly: NZW -> "NZ W",
    // SLW -> "SL W", INDA -> "IND A". Plain two-letter codes (WI) untouched.
    final code = formatTeamCode(short.isEmpty ? name : short);
    final isPlaceholder = code == 'TBC' || code == 'TBD' || code.isEmpty;
    final hasScore = innings.any((i) => i.hasRuns);
    final multi = innings.where((i) => i.hasRuns).length > 1;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: c.isDark
                ? [
                    BoxShadow(
                      color: c.cyan.withValues(alpha: .4),
                      blurRadius: logoSize * .28,
                      spreadRadius: -2,
                    ),
                  ]
                : null,
          ),
          child: TeamLogoWidget(
            logoUrl: isPlaceholder ? null : logo,
            teamName: name,
            abbreviation: code,
            color: accent,
            size: logoSize,
            // The team code is rendered right below — don't say it twice.
            excludeSemantics: true,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          code,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: c.text,
            fontWeight: FontWeight.w900,
            fontSize: context.sp(17),
            height: 1,
          ),
        ),
        if (hasScore) ...[
          const SizedBox(height: 4),
          // Centralized professional score: `218/10` / `44.2 ov`, or a Test's
          // stacked `1st 362/10  87.1 ov` / `2nd 391/10  96.2 ov` — both innings
          // always visible and readable, never truncated.
          TeamScoreView(
            innings: innings,
            mode: multi
                ? ScoreDisplayMode.matchDetailsMultiInnings
                : ScoreDisplayMode.matchDetailsLimitedOvers,
            mainSize: context.sp(multi ? 19 : 26),
            oversSize: context.sp(12.5),
            live: live,
            currentInningsIndex: currentInningsIndex,
            color: c.isDark ? Colors.white : c.text,
            oversColor: c.onImageText,
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Premium match hero score card (reused on every tab).
// ---------------------------------------------------------------------------

class MatchHeroScoreCard extends StatelessWidget {
  const MatchHeroScoreCard({super.key, required this.match});

  final CricketMatch match;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final phone = context.w <= 430;
    final logoSize = phone ? 56.0 : 64.0;
    final m = match;
    final isLive = m.isLive;
    final isFinished = m.isFinished;
    // Single source of truth for the badge + status note, so the header never
    // shows a generic LIVE pill alongside "Day 1: Stumps" — a paused live match
    // reads STUMPS/LUNCH/TEA/INN BREAK and the note carries the same phase.
    final status = MatchStatusDisplay.of(context, m);
    final statusLabel = status.badge;
    final statusColor = status.color;
    final rawStatus = status.phaseLabel.isNotEmpty
        ? status.phaseLabel
        : (m.statusText.isNotEmpty
            ? m.statusText
            : (m.resultText.isNotEmpty ? m.resultText : m.series));
    // Shorten long-name equations: "Sri Lanka Women need 150 runs" -> "SL W
    // need 150". Series fallback is left as-is (no team names to compress).
    final statusText = (m.statusText.isNotEmpty || m.resultText.isNotEmpty)
        ? shortMatchStatus(rawStatus, m, keepUnits: true)
        : rawStatus;
    final format = m.matchDesc;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: c.cyan.withValues(alpha: .55), width: 1.2),
        boxShadow: c.isDark
            ? [
                BoxShadow(
                  color: c.cyan.withValues(alpha: .18),
                  blurRadius: 26,
                  spreadRadius: -8,
                ),
                ...c.heroShadow.skip(1),
              ]
            : c.heroShadow,
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: c.isDark
                ? const RemoteOrLocalImage(
                    assetKey: 'match_details_header_bg',
                    fallbackAsset: MDAsset.heroBg,
                    isDark: true,
                    fit: BoxFit.cover,
                  )
                : ColoredBox(
                    color: c.card,
                    child: const StadiumImage(
                      MDAsset.heroBg,
                      hero: true,
                      alignment: Alignment.center,
                      remoteKey: 'match_details_header_bg',
                    ),
                  ),
          ),
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
          const MDTopGlow(),
          Padding(
            padding: EdgeInsets.fromLTRB(phone ? 16 : 18, 10, phone ? 16 : 18, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Badge on its own centered row, then the phase/status note on
                // a dedicated full-width line below. This gives the long Test
                // status ("Day 2: 3rd Session - WI trail by 515") a readable 2
                // lines at 360px instead of squeezing it between two pills — and
                // drops the invisible "balance" pill that used to steal ~48px.
                Center(
                  child: MDStatusPill(
                    label: statusLabel,
                    color: statusColor,
                    // Suppress the pulsing "live now" dot for a stoppage
                    // (stumps/lunch/tea/…) so the pill does not read "live
                    // now" while the note says "Day 1 Stumps".
                    live: status.subPhase == MatchSubPhase.live,
                  ),
                ),
                if (statusText.isNotEmpty) ...[
                  SizedBox(height: phone ? 5 : 6),
                  Text(
                    statusText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: c.isDark
                          ? Colors.white.withValues(alpha: .92)
                          : c.text,
                      fontWeight: FontWeight.w800,
                      fontSize: context.sp(phone ? 11.5 : 12.5),
                      height: 1.25,
                    ),
                  ),
                ],
                if (format.isNotEmpty) ...[
                  SizedBox(height: phone ? 5 : 7),
                  _formatPill(context, format),
                ],
                SizedBox(height: phone ? 8 : 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: MDTeamScoreBlock(
                        name: m.teamA,
                        short: m.teamAShort,
                        logo: m.teamALogo,
                        innings: (isLive || isFinished)
                            ? m.teamAInnings
                            : const <InningsScore>[],
                        accent: c.cyan,
                        logoSize: logoSize,
                        live: isLive,
                        currentInningsIndex:
                            m.currentScoredIndexForTeam(isTeamA: true),
                      ),
                    ),
                    MDVsBadge(
                      width: context.isCompact ? 46 : (phone ? 52 : 60),
                      height: context.isCompact ? 34 : (phone ? 36 : 40),
                    ),
                    Expanded(
                      child: MDTeamScoreBlock(
                        name: m.teamB,
                        short: m.teamBShort,
                        logo: m.teamBLogo,
                        innings: (isLive || isFinished)
                            ? m.teamBInnings
                            : const <InningsScore>[],
                        accent: c.warning,
                        logoSize: logoSize,
                        live: isLive,
                        currentInningsIndex:
                            m.currentScoredIndexForTeam(isTeamA: false),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: phone ? 8 : 12),
                if (_hasVenue(m.venue))
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const MDIcon(MDAsset.icLocationPin,
                          fallback: Icons.location_on_outlined, size: 13),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          m.venue,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: c.onImageText,
                            fontWeight: FontWeight.w600,
                            fontSize: 11.5,
                            height: 1.2,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static bool _hasVenue(String venue) {
    final v = venue.trim().toLowerCase();
    return v.isNotEmpty && v != 'venue tbd' && v != 'venue tbc' && v != 'tbd';
  }

  Widget _formatPill(BuildContext context, String format) {
    final c = context.cric;
    if (format.isEmpty) return const SizedBox.shrink();
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: c.cyan.withValues(alpha: .14),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: c.cyan.withValues(alpha: .55)),
        ),
        child: Text(
          format,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: c.cyan,
            fontWeight: FontWeight.w800,
            fontSize: 11,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Top app bar (back • title • filter button)
// ---------------------------------------------------------------------------

class MatchDetailsTopBar extends StatelessWidget {
  const MatchDetailsTopBar({super.key, required this.onBack, this.onMinimize});

  final VoidCallback onBack;

  /// Tap → open the minimize chooser (in-app bar / floating score). Null hides
  /// the button entirely (e.g. before the match summary has loaded).
  final VoidCallback? onMinimize;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final narrow = context.w <= 360;
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: Row(
        children: [
          GestureDetector(
            onTap: onBack,
            behavior: HitTestBehavior.opaque,
            child: Icon(Icons.arrow_back_rounded, color: c.text, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Match Details',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.text,
                fontWeight: FontWeight.w900,
                fontSize: context.w <= 400 ? 21 : 23,
                letterSpacing: -.3,
              ),
            ),
          ),
          if (onMinimize != null) ...[
            const SizedBox(width: 8),
            _MinimizeButton(onTap: onMinimize!, narrow: narrow),
          ],
        ],
      ),
    );
  }
}

/// Premium labelled "Minimize" pill (icon + text) replacing the old bare "-"
/// circle. Cyan glass in dark mode, clean outline in light mode. Stays compact
/// on 360dp screens (icon only loses its label only below that width).
class _MinimizeButton extends StatelessWidget {
  const _MinimizeButton({required this.onTap, required this.narrow});

  final VoidCallback onTap;
  final bool narrow;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 40,
        padding: EdgeInsets.symmetric(horizontal: narrow ? 12 : 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: c.isDark
              ? LinearGradient(
                  colors: [
                    c.cyan.withValues(alpha: .22),
                    c.cyan.withValues(alpha: .10),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: c.isDark ? null : c.card,
          border: Border.all(
              color: c.isDark ? c.cyan.withValues(alpha: .75) : c.border,
              width: 1.3),
          boxShadow: c.isDark
              ? [
                  BoxShadow(
                    color: c.cyan.withValues(alpha: .24),
                    blurRadius: 16,
                    spreadRadius: -3,
                  ),
                ]
              : c.cardShadow,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.fullscreen_exit_rounded,
                size: 19, color: c.isDark ? c.cyan : c.text),
            const SizedBox(width: 6),
            Text(
              'Minimize',
              style: TextStyle(
                color: c.isDark ? c.cyan : c.text,
                fontWeight: FontWeight.w800,
                fontSize: 13.5,
                letterSpacing: .1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Updated / refresh row
// ---------------------------------------------------------------------------

class MDUpdatedRow extends StatelessWidget {
  const MDUpdatedRow({super.key, required this.label, required this.onRefresh});

  final String label;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Row(
      children: [
        const MDIcon(MDAsset.icUpdated, fallback: Icons.sync_rounded, size: 16),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: c.isDark ? c.onImageText : c.muted,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          ),
        ),
        GestureDetector(
          onTap: onRefresh,
          behavior: HitTestBehavior.opaque,
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.isDark ? c.cyan.withValues(alpha: .1) : c.card,
              border: Border.all(
                  color: c.isDark ? c.cyan.withValues(alpha: .4) : c.border),
              boxShadow: c.isDark ? null : c.cardShadow,
            ),
            alignment: Alignment.center,
            child: const MDIcon(MDAsset.icRefresh,
                fallback: Icons.refresh_rounded, size: 17),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Main tab bar (icon + label, glass, gradient active pill, scrollable)
// ---------------------------------------------------------------------------

class MatchDetailsTabBar extends StatefulWidget {
  const MatchDetailsTabBar({
    super.key,
    required this.items,
    required this.selected,
    required this.onChanged,
  });

  final List<(String, IconData, String)> items;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  State<MatchDetailsTabBar> createState() => _MatchDetailsTabBarState();
}

class _MatchDetailsTabBarState extends State<MatchDetailsTabBar> {
  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: c.isDark ? c.card.withValues(alpha: .4) : c.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: c.cyan.withValues(alpha: .22)),
      ),
      // All tabs share the row equally so the full set fits on a 360px width
      // with no horizontal scrolling and no clipped / half-visible labels.
      child: Row(
        children: [
          for (var i = 0; i < widget.items.length; i++)
            Expanded(child: _tab(context, i)),
        ],
      ),
    );
  }

  Widget _tab(BuildContext context, int i) {
    final c = context.cric;
    final selected = i == widget.selected;
    return GestureDetector(
      onTap: () => widget.onChanged(i),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        height: 36,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xff35e2ff), Color(0xff0a86ff)],
                )
              : null,
          borderRadius: BorderRadius.circular(19),
          boxShadow: selected && c.isDark
              ? [
                  BoxShadow(
                    color: c.cyan.withValues(alpha: .5),
                    blurRadius: 14,
                    spreadRadius: -2,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              widget.items[i].$1,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                color: selected ? Colors.white : c.muted,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                fontSize: 12.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ball chip (uses ball assets with Flutter fallback)
// ---------------------------------------------------------------------------

class MDBallChip extends StatelessWidget {
  const MDBallChip({
    super.key,
    required this.label,
    this.wicket = false,
    this.boundary = false,
    this.size = 34,
    this.type = '',
  });

  final String label;
  final bool wicket;
  final bool boundary;
  final double size;

  /// Server-normalized ball type when known (`wicket`/`six`/`four`/`dot`/
  /// `wide`/`no_ball`/`noball`/`bye`/`leg_bye`/`legbye`/`extra`/`run`). When
  /// empty, the chip falls back to the [label]/[wicket]/[boundary] signals.
  /// Trusting the server type stops a wide (runs:1) being mislabelled "1" and
  /// lets extras get their own colour/label.
  final String type;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final raw = label.trim();
    final t = type.toLowerCase();
    final isMissing = raw.isEmpty && t.isEmpty; // no data for this ball at all
    final isDot = t == 'dot' || raw == '0' || raw == '.' || raw.toLowerCase() == 'dot';
    final isW = wicket || t == 'wicket' || raw.toLowerCase() == 'w';
    final isSix = t == 'six' || raw == '6';
    final isFour = t == 'four' || raw == '4';
    final isWide = t == 'wide';
    final isNoBall = t == 'no_ball' || t == 'noball' || t == 'no-ball';
    final isBye = t == 'bye';
    final isLegBye = t == 'leg_bye' || t == 'legbye' || t == 'leg-bye';
    final isExtra = isWide || isNoBall || isBye || isLegBye || t == 'extra';

    final Color color;
    if (isW) {
      color = const Color(0xffff2d45);
    } else if (isSix) {
      color = const Color(0xff38f28b);
    } else if (isFour || boundary) {
      color = c.cyan;
    } else if (isExtra) {
      color = c.warning; // extras read amber, distinct from runs/dot
    } else if (isDot) {
      color = c.muted;
    } else if (isMissing) {
      color = c.muted.withValues(alpha: .5); // a missing ball is faintest
    } else {
      color = c.cyan; // numbered runs use the cyan accent
    }

    // Short chip text. A MISSING ball (empty result, no type) renders as a
    // dashed `–` so it is never confused with a real DOT ball (`•`).
    final String display;
    if (isMissing) {
      display = '–';
    } else if (isWide) {
      display = 'Wd';
    } else if (isNoBall) {
      display = 'Nb';
    } else if (isBye) {
      display = 'B';
    } else if (isLegBye) {
      display = 'Lb';
    } else if (isExtra) {
      display = '+';
    } else if (isDot) {
      display = '•';
    } else if (isW) {
      display = 'W';
    } else if (raw.isNotEmpty) {
      display = raw;
    } else {
      display = '–';
    }
    final filled = isW || isSix || isFour;

    // Opaque base so the timeline line behind the marker is fully hidden.
    final opaqueBase = c.isDark ? const Color(0xff0a1f33) : c.card;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // Extras use an amber FILLED base so they stand out like W/6/4; a dot
        // keeps the outlined style; a missing ball is a faint dashed outline.
        color: (filled || isExtra) ? color : opaqueBase,
        border: Border.all(
          // A missing ball gets a dashed look via a thinner, fainter border.
          color: isMissing
              ? c.muted.withValues(alpha: .35)
              : color.withValues(alpha: (filled || isExtra) ? 1 : .85),
          width: isMissing ? 1 : 1.6,
        ),
        boxShadow: c.isDark && (filled || isExtra)
            ? [
                BoxShadow(
                  color: color.withValues(alpha: filled ? .5 : .4),
                  blurRadius: filled ? 9 : 7,
                  spreadRadius: -1,
                ),
              ]
            : null,
      ),
      child: isDot
          ? Container(
              width: size * 0.2,
              height: size * 0.2,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c.isDark ? Colors.white : c.muted,
              ),
            )
          : Text(
              display,
              style: TextStyle(
                // Extras are short text on an amber fill → white; a missing
                // ball's `–` reads muted so it stays de-emphasised.
                color: isMissing ? c.muted : Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: size * (isExtra ? .38 : .44),
                height: 1,
              ),
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Player avatar (network image with initials fallback + cyan ring)
// ---------------------------------------------------------------------------

class MDPlayerAvatar extends StatelessWidget {
  const MDPlayerAvatar({
    super.key,
    required this.name,
    this.imageUrl,
    this.size = 40,
    this.accent,
  });

  final String name;
  final String? imageUrl;
  final double size;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final ring = accent ?? c.cyan;
    final hasImage = imageUrl != null && imageUrl!.trim().isNotEmpty;
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            ring.withValues(alpha: .22),
            c.isDark ? const Color(0xff071726) : c.card2,
          ],
        ),
        border: Border.all(color: ring.withValues(alpha: .55), width: 1.6),
      ),
      // Player name is always rendered as text beside this avatar, so the photo
      // (and its initials fallback) add nothing for a screen reader.
      child: ExcludeSemantics(
        child: hasImage
            ? CachedNetworkImage(
                imageUrl: imageUrl!,
                key: ValueKey(imageUrl),
                fit: BoxFit.cover,
                fadeInDuration: Duration.zero,
                placeholder: (context, _) => _initials(context),
                errorWidget: (_, __, ___) => _initials(context),
              )
            : _initials(context),
      ),
    );
  }

  Widget _initials(BuildContext context) {
    final c = context.cric;
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    final initials = parts.isEmpty
        ? '?'
        : parts.length == 1
            ? parts.first.substring(0, 1).toUpperCase()
            : (parts.first[0] + parts.last[0]).toUpperCase();
    return Center(
      child: Text(
        initials,
        style: TextStyle(
          color: c.text,
          fontWeight: FontWeight.w900,
          fontSize: size * .34,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Team selector (flag/logo segmented control) — Scorecard & Squad tabs.
// ---------------------------------------------------------------------------

class MDTeamSelectorItem {
  const MDTeamSelectorItem({
    required this.label,
    required this.name,
    this.logo,
  });
  final String label;
  final String name;
  final String? logo;
}

class MDTeamSelector extends StatelessWidget {
  const MDTeamSelector({
    super.key,
    required this.items,
    required this.selected,
    required this.onChanged,
  });

  final List<MDTeamSelectorItem> items;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      height: 46,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.isDark ? c.card.withValues(alpha: .5) : c.card,
        borderRadius: BorderRadius.circular(15),
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
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(
                    gradient: i == selected
                        ? const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xff35e2ff), Color(0xff0a86ff)],
                          )
                        : null,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: i == selected
                        ? [
                            BoxShadow(
                              color: c.cyan.withValues(alpha: .45),
                              blurRadius: 14,
                              spreadRadius: -2,
                            ),
                          ]
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        TeamLogoWidget(
                          logoUrl: items[i].logo,
                          teamName: items[i].name,
                          abbreviation: items[i].label,
                          color: c.cyan,
                          size: TeamLogoWidget.miniSize,
                          // The tab label beside it already names the team.
                          excludeSemantics: true,
                        ),
                        const SizedBox(width: 7),
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
                              fontSize: 13.5,
                            ),
                          ),
                        ),
                      ],
                    ),
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
// Rounded pill chip (Fall of Wickets / Partnerships)
// ---------------------------------------------------------------------------

class MDPillChip extends StatelessWidget {
  const MDPillChip({super.key, required this.text, this.center = false});

  final String text;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      alignment: center ? Alignment.center : null,
      decoration: BoxDecoration(
        color: c.cyan.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.cyan.withValues(alpha: .32)),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: center ? TextAlign.center : TextAlign.start,
        style: TextStyle(
          color: c.text,
          fontWeight: FontWeight.w800,
          fontSize: 12.5,
        ),
      ),
    );
  }
}

class MDRolePill extends StatelessWidget {
  const MDRolePill({super.key, required this.role});

  final String role;

  @override
  Widget build(BuildContext context) {
    final (label, color) = _resolve(role);
    if (label.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .6)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 9,
          letterSpacing: .3,
        ),
      ),
    );
  }

  static (String, Color) _resolve(String role) {
    final r = role.toLowerCase();
    if (r.contains('wk') || r.contains('keeper')) {
      return ('WK', const Color(0xfff59e0b));
    }
    if (r.contains('all') && r.contains('round')) {
      return ('AR', const Color(0xff14b8a6));
    }
    if (r == 'ar') return ('AR', const Color(0xff14b8a6));
    if (r.contains('bowl')) return ('BOWL', const Color(0xff60a5fa));
    if (r.contains('bat') || r == 'batter' || r == 'batsman') {
      return ('BAT', const Color(0xff22d3ee));
    }
    if (r.isEmpty) return ('', const Color(0xff22d3ee));
    return ('BAT', const Color(0xff22d3ee));
  }
}
