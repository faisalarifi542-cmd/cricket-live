import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:cricpro_flutter/app_theme.dart';
import 'package:cricpro_flutter/api_models.dart';
import 'package:cricpro_flutter/services/remote_assets_service.dart';
import 'package:cricpro_flutter/services/team_logo_resolver.dart';
import 'package:cricpro_flutter/services/analytics_service.dart';
import 'package:cricpro_flutter/models.dart';
import 'package:cricpro_flutter/widgets/responsive.dart';

export 'widgets/responsive.dart'
    show
        TapScale,
        FadeUp,
        StaggeredColumn,
        CountUpText,
        PulseDot,
        ScrollableSegmentedTabs,
        InfoListTile,
        ResponsiveStatTile,
        computeGridChildWidth;

enum AppTab { home, matches, schedule, series, more }

/// A stadium-atmosphere background image with built-in light-mode treatment.
///
/// In dark mode it renders the (dark night-stadium) art at full strength. In
/// light mode it lowers opacity and screen-blends a white tint so the dark
/// photo becomes a faint ice-blue texture instead of bleeding through as a
/// grey scrim. Use this anywhere a stadium `Image.asset` sits behind content;
/// pair it with `c.stadiumOverlayColors` / `c.heroOverlayColors` for the fade.
class StadiumImage extends StatelessWidget {
  const StadiumImage(
    this.asset, {
    super.key,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.topCenter,
    this.hero = false,
    this.lightAsset,
    this.remoteKey,
  });

  final String asset;
  final BoxFit fit;
  final Alignment alignment;

  /// When true uses the stronger `heroImageOpacity` (stadium art inside cards);
  /// otherwise the fainter backdrop opacity used behind headers.
  final bool hero;

  /// Optional admin-managed remote asset key (e.g. 'home_hero_bg_dark'). When a
  /// URL is configured for this key in [RemoteAssetsService], the network image
  /// is used with the SAME opacity/tint/blend treatment; on any failure
  /// (offline, 404, decode) it falls back to the bundled [asset] rendering, so
  /// the UI is never blank and the design is unchanged.
  final String? remoteKey;

  /// Optional purpose-built *clean* light-mode artwork. The shipped
  /// `assets/images/light_mode/*` PNGs are already bright ice-blue with no dark
  /// scrim, so in light mode we render this asset at FULL opacity with NO tint
  /// or blend (the old approach of dimming the dark stadium photo always left a
  /// faint grey wash). Falls back to [LightAsset] auto-mapping, then to the
  /// dimmed dark art if nothing matches.
  final String? lightAsset;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;

    // Resolve an admin-managed remote URL for this key+theme, if any.
    final remoteUrl = remoteKey == null
        ? null
        : RemoteAssetsService.instance.urlFor(remoteKey!, isDark: c.isDark);

    // Light mode: prefer the clean, purpose-built ice-blue asset rendered at
    // full strength — this is what makes cards genuinely bright/white instead
    // of a dimmed grey scrim.
    if (!c.isDark) {
      final clean = lightAsset ?? LightAsset.forStadium(asset, hero: hero);
      if (clean != null) {
        final localLight = Image.asset(
          clean,
          fit: fit,
          alignment: alignment,
          // Pure background texture — never announced by a screen reader.
          excludeFromSemantics: true,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        );
        return Opacity(
          // The clean assets are already bright ice-blue (no dark scrim), so we
          // render them strong — this gives the visible stadium texture the
          // target shows inside cards and behind headers (vs flat white).
          opacity: hero ? .92 : .8,
          child: _maybeNetwork(remoteUrl, localLight),
        );
      }
    }

    final localDark = Image.asset(
      asset,
      fit: fit,
      alignment: alignment,
      color: c.stadiumImageTint,
      colorBlendMode: c.stadiumImageBlend,
      // Pure background texture — never announced by a screen reader.
      excludeFromSemantics: true,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
    return Opacity(
      opacity: hero ? c.heroImageOpacity : c.stadiumImageOpacity,
      child: _maybeNetwork(
        remoteUrl,
        localDark,
        color: c.stadiumImageTint,
        colorBlendMode: c.stadiumImageBlend,
      ),
    );
  }

  /// Renders the admin remote image at [url] with the same fit/alignment/tint,
  /// falling back to [local] while loading and on ANY error. When [url] is null
  /// (no remote configured) it just returns [local].
  Widget _maybeNetwork(
    String? url,
    Widget local, {
    Color? color,
    BlendMode? colorBlendMode,
  }) {
    if (url == null || url.isEmpty) return local;
    // `CachedNetworkImage` exposes no `excludeFromSemantics`, so the decorative
    // exclusion is applied by wrapping (the bundled-asset branches above set the
    // flag directly). Keeps stadium backdrops silent for screen readers.
    return ExcludeSemantics(
      child: CachedNetworkImage(
        imageUrl: url,
        fit: fit,
        alignment: alignment,
        color: color,
        colorBlendMode: colorBlendMode,
        // Preserve the original frameBuilder behavior: show the bundled asset
        // while the network image loads, swap in instantly (no fade flash), and
        // fall back to the asset on any error.
        fadeInDuration: Duration.zero,
        placeholder: (context, _) => local,
        errorWidget: (_, __, ___) => local,
      ),
    );
  }
}

/// Converts a logical widget extent into the device-pixel extent an image
/// should be DECODED at, so small avatars/logos never hold a full-resolution
/// bitmap in memory. Clamped so a hairline widget still decodes something
/// legible and a huge one does not decode absurdly large.
int _decodeExtent(BuildContext context, double logicalExtent) {
  final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 2.0;
  return (logicalExtent * dpr).round().clamp(48, 1024);
}

/// Central registry of the clean light-mode artwork in
/// `assets/images/light_mode/`. These are bright ice-blue PNGs (no text, no
/// logos, no dark scrim) used to render light-mode backdrops/cards at full
/// strength instead of dimming the dark night-stadium photos.
class LightAsset {
  LightAsset._();

  static const String dir = 'assets/images/light_mode/';

  static const String appBg = '${dir}app_light_bg.webp';
  static const String matchCardBg = '${dir}match_card_stadium_bg.webp';
  static const String scheduleHeaderBg = '${dir}schedule_header_bg.webp';
  static const String seriesHeroBg = '${dir}series_hero_bg.webp';
  static const String heroStadiumBg = '${dir}hero_stadium_bg.webp';
  static const String matchCardOverlay = '${dir}match_card_overlay_1080x520.webp';
  static const String glassCardOverlay = '${dir}glass_card_overlay_1080x560.webp';
  static const String segmentedTabsBg = '${dir}segmented_tabs_bg_1080x180.webp';
  static const String filterChipsBg = '${dir}filter_chips_bg_1080x160.webp';
  static const String activeTabPill = '${dir}active_tab_pill.webp';
  static const String primaryButton = '${dir}primary_button.webp';
  static const String vsChipBg = '${dir}vs_chip_bg.webp';
  static const String screenEdgeGlow = '${dir}screen_edge_glow_overlay.webp';
  static const String stadiumLines = '${dir}stadium_lines_overlay.webp';
  static const String statusLiveBadge = '${dir}status_live_badge_bg.webp';
  static const String statusResultBadge = '${dir}status_result_badge_bg.webp';

  /// Maps an arbitrary dark stadium asset path to the clean light equivalent.
  /// [hero] selects the in-card art (match/hero card) vs the header backdrop.
  /// Returns null when no light treatment should be applied.
  static String? forStadium(String darkAsset, {required bool hero}) {
    final a = darkAsset.toLowerCase();
    if (a.contains('schedule')) return scheduleHeaderBg;
    if (a.contains('series')) return seriesHeroBg;
    if (a.contains('match')) return matchCardBg;
    // Default: hero/feature cards use the hero stadium, headers use it too.
    return hero ? heroStadiumBg : heroStadiumBg;
  }
}
String tabLabel(AppTab tab) => switch (tab) {
      AppTab.home => 'Home',
      AppTab.matches => 'Matches',
      AppTab.schedule => 'Schedule',
      AppTab.series => 'Series',
      AppTab.more => 'More',
    };

IconData tabIcon(AppTab tab) => switch (tab) {
      AppTab.home => Icons.home_rounded,
      AppTab.matches => Icons.sports_cricket_rounded,
      AppTab.schedule => Icons.calendar_month_rounded,
      AppTab.series => Icons.emoji_events_rounded,
      AppTab.more => Icons.more_horiz_rounded,
    };

class PremiumCard extends StatelessWidget {
  const PremiumCard({
    super.key,
    required this.child,
    this.padding,
    this.radius = 26,
    this.height,
    this.onTap,
    this.gradient,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final double? height;
  final VoidCallback? onTap;
  final Gradient? gradient;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final body = AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        gradient: gradient ?? c.cardGradient,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor ?? c.border, width: 1.15),
        boxShadow: c.cardShadow,
      ),
      child: child,
    );
    if (onTap == null) return body;
    return TapScale(
      onTap: onTap,
      borderRadius: radius,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: onTap,
          splashColor: c.cyan.withValues(alpha: .08),
          highlightColor: c.cyan.withValues(alpha: .05),
          child: body,
        ),
      ),
    );
  }
}

class CricLogo extends StatelessWidget {
  const CricLogo({super.key, this.size = 34});
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return RichText(
      text: TextSpan(
        style: TextStyle(
          fontSize: size,
          fontWeight: FontWeight.w900,
          fontStyle: FontStyle.italic,
          letterSpacing: -1.4,
        ),
        children: [
          TextSpan(text: 'CRIC', style: TextStyle(color: c.text)),
          TextSpan(text: 'PRO', style: TextStyle(color: c.cyan)),
        ],
      ),
    );
  }
}

class GlowIconButton extends StatelessWidget {
  const GlowIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.badge,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? badge;

  /// Accessible name (and long-press tooltip) for this icon-only control.
  /// Icon glyphs carry no text, so without this a screen reader announces a
  /// bare "button". Callers should always pass one; it is optional only to
  /// avoid breaking the decorative/no-op usages.
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final button = Stack(
      clipBehavior: Clip.none,
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: c.subtleSurface,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, color: c.text, size: 30),
          ),
        ),
        if (badge != null)
          Positioned(
            right: -1,
            top: -1,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: c.live,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: c.live.withValues(alpha: .45),
                    blurRadius: 12,
                  )
                ],
              ),
              alignment: Alignment.center,
              child: Text(
                badge!,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ),
          )
      ],
    );
    if (tooltip == null) return button;
    // `button: true` + label gives the control a real name and role. The badge
    // count stays readable inside because it is genuine information.
    return Semantics(
      button: true,
      label: tooltip,
      child: Tooltip(message: tooltip!, child: button),
    );
  }
}

class AppHeader extends StatelessWidget {
  const AppHeader({
    super.key,
    this.title,
    this.showLogo = false,
    this.leading,
    this.trailing = const [],
    this.subtitle,
  });

  final String? title;
  final bool showLogo;
  final Widget? leading;
  final List<Widget> trailing;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (leading != null) ...[
              leading!,
              const SizedBox(width: 12),
            ],
            Expanded(
              child: showLogo
                  ? const CricLogo(size: 34)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title ?? '',
                          style: TextStyle(
                            color: c.text,
                            fontWeight: FontWeight.w900,
                            fontSize: context.sp(33),
                            height: .95,
                          ),
                        ),
                        if (subtitle != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              subtitle!,
                              style: TextStyle(
                                color: c.muted,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
            ...trailing,
          ],
        ),
      ],
    );
  }
}

class TeamBadge extends StatelessWidget {
  const TeamBadge(this.team,
      {super.key, this.size = 76, this.borderColor, this.excludeSemantics = false});

  final TeamInfo team;
  final double size;
  final Color? borderColor;

  /// Forwarded to [TeamLogoWidget.excludeSemantics] — set true where the team
  /// name already appears as adjacent text.
  final bool excludeSemantics;

  @override
  Widget build(BuildContext context) {
    return TeamLogoWidget(
      logoUrl: team.asset,
      teamName: team.name,
      abbreviation: team.shortName.isNotEmpty ? team.shortName : team.code,
      color: team.color,
      size: size,
      borderColor: borderColor,
      emoji: team.emoji,
      excludeSemantics: excludeSemantics,
    );
  }
}

class TeamLogoWidget extends StatelessWidget {
  const TeamLogoWidget({
    super.key,
    this.logoUrl,
    required this.teamName,
    required this.abbreviation,
    required this.color,
    this.size = 76,
    this.borderColor,
    this.emoji,
    this.excludeSemantics = false,
  });

  final String? logoUrl;
  final String teamName;
  final String abbreviation;
  final Color color;
  final double size;
  final Color? borderColor;
  final String? emoji;

  /// Set true where the team name is ALREADY announced by adjacent text (score
  /// rows, points tables, team selectors). The badge then contributes nothing to
  /// the accessibility tree instead of repeating the name a second time.
  ///
  /// Left false where the badge is the only carrier of the team identity (e.g.
  /// logo-only hero columns), in which case it announces "<team> logo".
  final bool excludeSemantics;

  // Standard logo size buckets so the same widget reads consistently across
  // screens. Callers with a responsive/hero size keep computing their own; these
  // name the common FIXED buckets. Keep [miniSize] < 32 (thin border, no glow)
  // and [cardSize] >= 40 (glow) to preserve the existing per-size styling.
  static const double heroSize = 64; // match/series hero
  static const double cardSize = 46; // list match cards, live striker/bowler
  static const double miniSize = 22; // team selectors + points/stats table rows

  @override
  Widget build(BuildContext context) {
    // Single accessibility decision point for every rendering branch below
    // (network logo, local asset/flag, initials circle).
    //
    // The badge is either silent — because the team name is already announced by
    // adjacent text — or announced ONCE as "<team> logo". The inner bitmaps are
    // all `excludeFromSemantics`, so a screen reader never reads the initials
    // glyphs ("IND") or an anonymous "image" node on top of the label.
    if (excludeSemantics) return ExcludeSemantics(child: _buildBadge(context));
    final label =
        teamName.trim().isEmpty ? abbreviation.trim() : teamName.trim();
    if (label.isEmpty) return ExcludeSemantics(child: _buildBadge(context));
    return Semantics(
      container: true,
      image: true,
      label: '$label logo',
      excludeSemantics: true,
      child: _buildBadge(context),
    );
  }

  Widget _buildBadge(BuildContext context) {
    final c = context.cric;
    // Team logo priority is admin-configurable via [TeamLogoResolver]
    // (default admin → local → api → initials). The `logoUrl` passed here has
    // already been order-resolved upstream (resolveCricbuzzImageUrl), so it is
    // either an http URL (admin/api), a local asset path, or null. This widget:
    //   1. shows initials immediately when the admin chose initials-first /
    //      disabled team logos (so no local flag leaks through),
    //   2. otherwise renders the resolved logo, and
    //   3. uses a name-derived local flag only when the order allows `local`
    //      (covers legacy callers that pass a bare name with no resolved URL).
    if (TeamLogoResolver.forcesInitials) return _fallbackCircle(context);

    final flag = TeamLogoResolver.allowsLocalFallback
        ? roundedFlagAsset(name: teamName, shortName: abbreviation)
        : null;
    final logo = _hasLogo ? logoUrl!.trim() : null;
    final hasHttpLogo = logo != null &&
        (logo.startsWith('http://') || logo.startsWith('https://'));

    String? resolved;
    if (hasHttpLogo) {
      resolved = logo; // admin-or-api, already order-resolved server/client-side
    } else if (logo != null) {
      resolved = logo; // a local asset path the resolver already chose
    } else if (flag != null) {
      resolved = flag; // name-derived local flag fallback (legacy callers)
    }
    if (resolved == null) return _fallbackCircle(context);

    final isFlag = resolved == flag || resolved.contains('/flags/');
    final isAsset = !resolved.startsWith('http');
    final fit = isFlag ? BoxFit.cover : BoxFit.contain;
    // When a network logo fails, fall back to the local flag asset (if any)
    // before the neutral initials circle so a broken/old URL never shows a
    // broken-image icon and server outages degrade gracefully.
    Widget networkError() => flag != null
        ? Image.asset(flag, fit: BoxFit.cover,
            excludeFromSemantics: true,
            errorBuilder: (_, __, ___) => _fallbackCircle(context))
        : _fallbackCircle(context);
    final image = isAsset
        ? Image.asset(
            resolved,
            fit: fit,
            // The logo bitmap itself is never announced; the whole badge is
            // labelled once by the [Semantics] wrapper in [build] instead, so a
            // screen reader says "India logo", not "India logo, image".
            excludeFromSemantics: true,
            errorBuilder: (_, __, ___) => _fallbackCircle(context),
          )
        : CachedNetworkImage(
            imageUrl: resolved,
            fit: fit,
            fadeInDuration: Duration.zero,
            // Decode at the circle's on-screen size (device pixels) instead of
            // the provider's full-resolution logo — long lists of team logos
            // otherwise hold many megabytes of oversized bitmaps.
            memCacheWidth: _decodeExtent(context, size),
            memCacheHeight: _decodeExtent(context, size),
            placeholder: (context, _) => _teamLoading(context),
            errorWidget: (_, __, ___) => networkError(),
          );

    final border = borderColor ?? c.cyan.withValues(alpha: .42);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xff0b2138),
        border: Border.all(color: border, width: size < 32 ? 1.3 : 2),
        boxShadow: size >= 40
            ? [
                BoxShadow(
                  color: c.cyan.withValues(alpha: .10),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: ClipOval(
        child: Padding(
          padding: EdgeInsets.all(isFlag ? 0 : size * 0.12),
          child: image,
        ),
      ),
    );
  }

  bool get _hasLogo => logoUrl != null && logoUrl!.trim().isNotEmpty;

  /// Premium gradient circle used only when no real logo is available.
  Widget _fallbackCircle(BuildContext context) {
    final c = context.cric;
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: c.isDark
              ? [
                  color.withValues(alpha: .34),
                  const Color(0xff08213d).withValues(alpha: .96),
                ]
              : [
                  color.withValues(alpha: .18),
                  const Color(0xff1a3d60).withValues(alpha: .80),
                ],
        ),
        border: Border.all(
          color: borderColor ?? (c.isDark ? Colors.white.withValues(alpha: .62) : c.border),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: .18),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: _teamFallback(context),
    );
  }

  Widget _teamLoading(BuildContext context) {
    final c = context.cric;
    return Center(
      child: SizedBox(
        width: size * .32,
        height: size * .32,
        child: CircularProgressIndicator(
          strokeWidth: 2.2,
          valueColor: AlwaysStoppedAnimation<Color>(c.cyan),
        ),
      ),
    );
  }

  Widget _teamFallback(BuildContext context) {
    final initials = safeTeamInitials(
      abbreviation.isNotEmpty ? abbreviation : teamName,
    );
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: EdgeInsets.all(size * 0.15),
          child: Text(
            emoji ?? initials,
            style: TextStyle(
              fontSize: size * .42,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

/// Unified player avatar used everywhere a player photo appears (squads,
/// player profile, rankings, top performers, scorecard rows, …).
///
/// The backend resolves the correct image URL ahead of time according to the
/// admin/provider/initials priority and per-player override, so this widget
/// only has to:
///   1. show the resolved network image when present,
///   2. fall back to clean initials,
/// and NEVER display a broken-image icon (a failed/empty URL → initials).
class PlayerAvatarWidget extends StatelessWidget {
  const PlayerAvatarWidget({
    super.key,
    required this.name,
    this.imageUrl,
    this.size = 56,
    this.borderColor,
    this.accent,
    this.excludeSemantics = false,
  });

  final String name;
  final String? imageUrl;
  final double size;
  final Color? borderColor;

  /// Optional accent used to tint the initials fallback gradient.
  final Color? accent;

  /// Set true where the player name is ALREADY announced by adjacent text
  /// (squad rows, batting/bowling tables, commentary). The avatar then adds
  /// nothing to the accessibility tree instead of repeating the name.
  final bool excludeSemantics;

  bool get _hasImage {
    final u = imageUrl?.trim();
    return u != null && u.isNotEmpty && u.startsWith('http');
  }

  static String _initials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    // One accessibility decision for both branches (network photo / initials).
    // The initials glyphs are decorative shorthand for the name, so they are
    // never read out on their own.
    if (excludeSemantics) return ExcludeSemantics(child: _buildAvatar(context));
    final label = name.trim();
    if (label.isEmpty) return ExcludeSemantics(child: _buildAvatar(context));
    return Semantics(
      container: true,
      image: true,
      label: label,
      excludeSemantics: true,
      child: _buildAvatar(context),
    );
  }

  Widget _buildAvatar(BuildContext context) {
    final c = context.cric;
    final border = borderColor ?? c.cyan.withValues(alpha: .45);
    final tint = accent ?? c.cyan;
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: c.isDark
              ? [
                  tint.withValues(alpha: .22),
                  const Color(0xff071726),
                ]
              : [
                  tint.withValues(alpha: .12),
                  const Color(0xff1a3d60).withValues(alpha: .75),
                ],
        ),
        border: Border.all(color: border, width: size < 32 ? 1.2 : 2),
      ),
      child: _hasImage
          ? CachedNetworkImage(
              imageUrl: imageUrl!.trim(),
              // Key by URL so a changed image always rebuilds a fresh element
              // and never shows a stale (previous player's) frame.
              key: ValueKey(imageUrl!.trim()),
              fit: BoxFit.cover,
              fadeInDuration: Duration.zero,
              // Decode to the avatar's on-screen size, not the source photo's.
              memCacheWidth: _decodeExtent(context, size),
              memCacheHeight: _decodeExtent(context, size),
              placeholder: (context, _) => _initialsBox(context),
              errorWidget: (_, __, ___) => _initialsBox(context),
            )
          : _initialsBox(context),
    );
  }

  Widget _initialsBox(BuildContext context) {
    final c = context.cric;
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: EdgeInsets.all(size * 0.18),
          child: Text(
            _initials(name),
            style: TextStyle(
              color: c.text,
              fontWeight: FontWeight.w900,
              fontSize: size * .36,
            ),
          ),
        ),
      ),
    );
  }
}

class PlayerAvatar extends StatelessWidget {
  const PlayerAvatar({
    super.key,
    required this.player,
    this.size = 62,
    this.borderColor,
    this.excludeSemantics = false,
  });

  final PlayerInfo player;
  final double size;
  final Color? borderColor;

  /// Forwarded to [PlayerAvatarWidget.excludeSemantics] — set true where the
  /// player name already appears as adjacent text.
  final bool excludeSemantics;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final asset = player.asset;
    final isNetwork = asset != null && asset.startsWith('http');
    // Network/no-image cases route through the shared PlayerAvatarWidget so the
    // admin/provider/initials behaviour is identical everywhere. Only local
    // asset paths keep the bespoke asset rendering.
    if (asset == null || isNetwork) {
      return PlayerAvatarWidget(
        name: player.name,
        imageUrl: isNetwork ? asset : null,
        size: size,
        borderColor: borderColor,
        excludeSemantics: excludeSemantics,
      );
    }
    // Local-asset branch: same accessibility contract as PlayerAvatarWidget —
    // silent when the name is adjacent, otherwise announced once as the name.
    final label = player.name.trim();
    final badge = Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: c.card2,
        border: Border.all(color: borderColor ?? c.border, width: 1.2),
      ),
      child: Image.asset(
        asset,
        fit: BoxFit.cover,
        excludeFromSemantics: true,
        errorBuilder: (_, __, ___) => _initials(context),
      ),
    );
    if (excludeSemantics || label.isEmpty) {
      return ExcludeSemantics(child: badge);
    }
    return Semantics(
      container: true,
      image: true,
      label: label,
      excludeSemantics: true,
      child: badge,
    );
  }

  Widget _initials(BuildContext context) {
    final c = context.cric;
    final parts = player.name.split(' ');
    final initials = parts.take(2).map((e) => e[0]).join();
    return Center(
      child: Text(
        initials,
        style: TextStyle(
          color: c.text,
          fontWeight: FontWeight.w900,
          fontSize: size * .28,
        ),
      ),
    );
  }
}

class RankingAvatar extends StatelessWidget {
  const RankingAvatar(
      {super.key, required this.asset, required this.label, this.size = 54});

  final String asset;
  final String label;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: c.border),
        color: c.card2,
      ),
      child: Image.asset(
        asset,
        fit: BoxFit.cover,
        excludeFromSemantics: true,
        errorBuilder: (_, __, ___) => Center(
          child: Text(
            label,
            style: TextStyle(color: c.text, fontWeight: FontWeight.w900),
          ),
        ),
      ),
    );
  }
}

class BottomNav extends StatelessWidget {
  const BottomNav({super.key, required this.active, required this.onTab});

  final AppTab active;
  final ValueChanged<AppTab> onTab;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(10, 5, 10, 0),
        padding: EdgeInsets.only(
            left: 6,
            right: 6,
            top: 4,
            bottom: MediaQuery.paddingOf(context).bottom > 0 ? 0 : 5),
        decoration: BoxDecoration(
          color: c.nav.withValues(alpha: c.isDark ? .9 : .98),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          border: Border.all(color: c.cyan.withValues(alpha: .22)),
          boxShadow: [
            BoxShadow(
              color: c.isDark
                  ? Colors.black.withValues(alpha: .4)
                  : const Color(0xff4a7fb5).withValues(alpha: .1),
              blurRadius: 28,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: Row(
          children: AppTab.values.map((tab) {
            final selected = tab == active;
            // Inactive icons/labels sit a touch dimmer so the active item reads
            // clearly without the whole bar feeling heavy.
            final color =
                selected ? c.cyan : c.muted.withValues(alpha: .82);
            return Expanded(
              child: InkWell(
                onTap: () => onTab(tab),
                borderRadius: BorderRadius.circular(20),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    color: selected
                        ? c.cyan.withValues(alpha: c.isDark ? .14 : .1)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 240),
                        curve: Curves.easeOutCubic,
                        width: selected ? 26 : 0,
                        height: 3,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(99),
                          boxShadow: selected && c.isDark
                              ? [
                                  BoxShadow(
                                    color: c.cyan.withValues(alpha: .55),
                                    blurRadius: 12,
                                  )
                                ]
                              : null,
                        ),
                      ),
                      const SizedBox(height: 4),
                      AnimatedScale(
                        duration: const Duration(milliseconds: 220),
                        scale: selected ? 1.06 : .94,
                        child: Icon(tabIcon(tab), color: color, size: 22),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        tabLabel(tab),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: color,
                          fontSize: 11.5,
                          fontWeight:
                              selected ? FontWeight.w800 : FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class SegmentedTabs extends StatelessWidget {
  const SegmentedTabs({
    super.key,
    required this.items,
    required this.selected,
    required this.onChanged,
    this.height = 56,
  });

  final List<(String, IconData?)> items;
  final int selected;
  final ValueChanged<int> onChanged;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      height: height,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: c.isDark ? c.card.withValues(alpha: .20) : c.card,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: c.border),
      ),
      child: LayoutBuilder(
        builder: (ctx, constraints) {
          final segWidth = constraints.maxWidth / items.length;
          final indicatorLeft = segWidth * selected.clamp(0, items.length - 1);
          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                left: indicatorLeft,
                top: 0,
                bottom: 0,
                width: segWidth,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: c.primaryGradient,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: c.cyan.withValues(alpha: .65)),
                    boxShadow: c.isDark
                        ? [
                            BoxShadow(
                              color: c.cyan.withValues(alpha: .22),
                              blurRadius: 18,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                ),
              ),
              Row(
                children: [
                  for (var i = 0; i < items.length; i++)
                    Expanded(
                      child: TapScale(
                        onTap: () => onChanged(i),
                        borderRadius: 28,
                        child: Material(
                          type: MaterialType.transparency,
                          child: InkWell(
                            onTap: () => onChanged(i),
                            borderRadius: BorderRadius.circular(28),
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (items[i].$2 != null) ...[
                                      AnimatedSwitcher(
                                        duration:
                                            const Duration(milliseconds: 220),
                                        child: Icon(
                                          items[i].$2,
                                          key: ValueKey(i == selected
                                              ? 'sel-$i'
                                              : 'un-$i'),
                                          color: i == selected
                                              ? Colors.white
                                              : c.muted,
                                          size: 20,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                    Flexible(
                                      child: AnimatedDefaultTextStyle(
                                        duration:
                                            const Duration(milliseconds: 240),
                                        style: TextStyle(
                                          color: i == selected
                                              ? Colors.white
                                              : c.muted,
                                          fontWeight: i == selected
                                              ? FontWeight.w800
                                              : FontWeight.w600,
                                          fontSize: context.sp(14.5),
                                        ),
                                        child: Text(
                                          items[i].$1,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class PillChip extends StatelessWidget {
  const PillChip(this.label, {super.key, this.selected = false, this.onTap});

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          gradient: selected ? c.primaryGradient : null,
          color: selected ? null : (c.isDark ? Colors.white.withValues(alpha: .015) : c.card),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: selected ? c.cyan.withValues(alpha: .7) : c.border,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : c.text,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            fontSize: 14.5,
          ),
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(
    this.title, {
    super.key,
    this.action,
    this.icon,
    this.onAction,
  });

  final String title;
  final String? action;
  final IconData? icon;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, color: c.cyan, size: 25),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: c.text,
              fontWeight: FontWeight.w900,
              fontSize: context.sp(18.5),
            ),
          ),
        ),
        if (action != null)
          InkWell(
            onTap: onAction,
            child: Row(
              children: [
                Text(
                  action!,
                  style: TextStyle(
                    color: c.muted,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: c.muted),
              ],
            ),
          ),
      ],
    );
  }
}

class GradientButton extends StatelessWidget {
  const GradientButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.outlined = false,
    this.height = 56,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool outlined;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return TapScale(
      onTap: onTap,
      borderRadius: 28,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(28),
          splashColor: Colors.white.withValues(alpha: .12),
          highlightColor: Colors.white.withValues(alpha: .04),
          child: Container(
            height: height,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              gradient: outlined ? null : c.primaryGradient,
              color: outlined ? Colors.transparent : null,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: c.cyan, width: outlined ? 1.4 : 1.0),
              boxShadow: outlined
                  ? null
                  : [
                      BoxShadow(
                        color: c.cyan.withValues(alpha: .24),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 15.5,
                    ),
                  ),
                ),
                if (outlined) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward_rounded,
                      color: Colors.white, size: 18),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    this.color,
    this.filled = false,
    this.icon,
  });

  final String label;
  final Color? color;
  final bool filled;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final badgeColor = color ?? c.cyan;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: filled ? badgeColor.withValues(alpha: .18) : Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: badgeColor.withValues(alpha: .7)),
        boxShadow: [
          BoxShadow(
            color: badgeColor.withValues(alpha: .06),
            blurRadius: 12,
          )
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: badgeColor, size: 16),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              color: badgeColor,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class EmptyOrErrorImage extends StatelessWidget {
  const EmptyOrErrorImage(
      {super.key, required this.label, this.icon = Icons.image_rounded});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      color: c.card2,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: c.muted, size: 32),
          const SizedBox(height: 8),
          Text(label,
              style: TextStyle(color: c.muted, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// Premium offline / network-error card. Shows when a request failed due to
/// no internet or an unreachable server. Distinct from empty-data state.
class CricOfflineCard extends StatelessWidget {
  const CricOfflineCard({
    super.key,
    required this.onRetry,
    this.compact = false,
  });

  final VoidCallback onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      padding: EdgeInsets.symmetric(
        vertical: compact ? 20 : 32,
        horizontal: 20,
      ),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: c.isDark ? c.card.withValues(alpha: .45) : c.card,
        border: Border.all(color: c.border.withValues(alpha: .6)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.wifi_off_rounded,
            color: c.muted,
            size: compact ? 26 : 36,
          ),
          SizedBox(height: compact ? 8 : 12),
          Text(
            "You're offline",
            style: TextStyle(
              color: c.text,
              fontWeight: FontWeight.w800,
              fontSize: compact ? 14 : 15,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Check your connection and try again.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: c.muted,
              fontWeight: FontWeight.w600,
              fontSize: 12.5,
            ),
          ),
          SizedBox(height: compact ? 12 : 16),
          GestureDetector(
            onTap: () {
              AnalyticsService.instance
                  .track('retry_after_error', {'error_type': 'offline'});
              onRetry();
            },
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: c.cyan.withValues(alpha: .12),
                border: Border.all(color: c.cyan.withValues(alpha: .7)),
              ),
              child: Text(
                'Retry',
                style: TextStyle(
                  color: c.cyan,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Soft radial glow orb used for floodlights and card accents. Pure decoration,
/// no theme branching — same in light/dark. Consolidated from per-screen copies.
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
