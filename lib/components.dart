import 'package:flutter/material.dart';

import 'package:cricpro_flutter/app_theme.dart';
import 'package:cricpro_flutter/api_models.dart';
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
  });

  final String asset;
  final BoxFit fit;
  final Alignment alignment;

  /// When true uses the stronger `heroImageOpacity` (stadium art inside cards);
  /// otherwise the fainter backdrop opacity used behind headers.
  final bool hero;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Opacity(
      opacity: hero ? c.heroImageOpacity : c.stadiumImageOpacity,
      child: Image.asset(
        asset,
        fit: fit,
        alignment: alignment,
        color: c.stadiumImageTint,
        colorBlendMode: c.stadiumImageBlend,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      ),
    );
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
  });

  final IconData icon;
  final VoidCallback? onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Stack(
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
  const TeamBadge(this.team, {super.key, this.size = 76, this.borderColor});

  final TeamInfo team;
  final double size;
  final Color? borderColor;

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
  });

  final String? logoUrl;
  final String teamName;
  final String abbreviation;
  final Color color;
  final double size;
  final Color? borderColor;
  final String? emoji;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    // Team logo priority (server/admin-first, per CricPro design):
    //   1. Server logo URL — the backend resolves this to the Admin-Panel
    //      uploaded logo when one exists, otherwise the Cricbuzz source logo,
    //      so any http(s) URL here is already "admin → cricbuzz" ordered.
    //   2. Local rounded flag asset (by name/abbr) — only when no server logo.
    //   3. Neutral initials.
    final flag = roundedFlagAsset(name: teamName, shortName: abbreviation);
    final logo = _hasLogo ? logoUrl!.trim() : null;
    final hasHttpLogo = logo != null &&
        (logo.startsWith('http://') || logo.startsWith('https://'));

    String? resolved;
    if (hasHttpLogo) {
      resolved = logo; // admin-or-cricbuzz, resolved server-side
    } else if (flag != null) {
      resolved = flag; // local rounded flag asset
    } else if (logo != null) {
      resolved = logo; // non-http asset path (rare)
    }
    if (resolved == null) return _fallbackCircle(context);

    final isFlag = resolved == flag;
    final isAsset = !resolved.startsWith('http');
    final fit = isFlag ? BoxFit.cover : BoxFit.contain;
    // When a network logo fails, fall back to the local flag asset (if any)
    // before the neutral initials circle so a broken/old URL never shows a
    // broken-image icon and server outages degrade gracefully.
    Widget networkError() => flag != null
        ? Image.asset(flag, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _fallbackCircle(context))
        : _fallbackCircle(context);
    final image = isAsset
        ? Image.asset(
            resolved,
            fit: fit,
            errorBuilder: (_, __, ___) => _fallbackCircle(context),
          )
        : Image.network(
            resolved,
            fit: fit,
            gaplessPlayback: true,
            webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return _teamLoading(context);
            },
            errorBuilder: (_, __, ___) => networkError(),
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
                  color: c.cyan.withValues(alpha: .16),
                  blurRadius: 14,
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
            color: color.withValues(alpha: .28),
            blurRadius: 18,
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
  });

  final String name;
  final String? imageUrl;
  final double size;
  final Color? borderColor;

  /// Optional accent used to tint the initials fallback gradient.
  final Color? accent;

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
          ? Image.network(
              imageUrl!.trim(),
              // Key by URL so a changed image always rebuilds a fresh element
              // and never shows a stale (previous player's) frame.
              key: ValueKey(imageUrl!.trim()),
              fit: BoxFit.cover,
              gaplessPlayback: true,
              webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return _initialsBox(context);
              },
              errorBuilder: (_, __, ___) => _initialsBox(context),
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
  });

  final PlayerInfo player;
  final double size;
  final Color? borderColor;

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
      );
    }
    return Container(
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
        errorBuilder: (_, __, ___) => _initials(context),
      ),
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
        margin: const EdgeInsets.fromLTRB(0, 6, 0, 0),
        padding: EdgeInsets.only(
            bottom: MediaQuery.paddingOf(context).bottom + 10, top: 10),
        decoration: BoxDecoration(
          color: c.nav.withValues(alpha: .96),
          border:
              Border(top: BorderSide(color: c.border.withValues(alpha: .85))),
          boxShadow: [
            BoxShadow(
              color: c.isDark
                  ? Colors.black.withValues(alpha: .35)
                  : const Color(0xff4a7fb5).withValues(alpha: .08),
              blurRadius: 26,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: Row(
          children: AppTab.values.map((tab) {
            final selected = tab == active;
            final color = selected ? c.cyan : c.muted;
            return Expanded(
              child: InkWell(
                onTap: () => onTab(tab),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeOutCubic,
                      width: selected ? 34 : 0,
                      height: 3,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(99),
                        boxShadow: selected
                            ? [
                                BoxShadow(
                                  color: c.cyan.withValues(alpha: .45),
                                  blurRadius: 12,
                                )
                              ]
                            : null,
                      ),
                    ),
                    const SizedBox(height: 10),
                    AnimatedScale(
                      duration: const Duration(milliseconds: 220),
                      scale: selected ? 1.05 : .92,
                      child: Icon(tabIcon(tab), color: color, size: 29),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      tabLabel(tab),
                      style: TextStyle(
                        color: color,
                        fontSize: 13,
                        fontWeight:
                            selected ? FontWeight.w800 : FontWeight.w600,
                      ),
                    ),
                  ],
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
        color: c.card.withValues(alpha: c.isDark ? .20 : .86),
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
                    boxShadow: [
                      BoxShadow(
                        color: c.cyan.withValues(alpha: .22),
                        blurRadius: 18,
                        spreadRadius: 1,
                      ),
                    ],
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
            color: badgeColor.withValues(alpha: .10),
            blurRadius: 14,
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
