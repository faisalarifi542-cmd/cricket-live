import 'package:flutter/material.dart';

class CricColors extends ThemeExtension<CricColors> {
  const CricColors({
    required this.bg,
    required this.bg2,
    required this.card,
    required this.card2,
    required this.border,
    required this.text,
    required this.muted,
    required this.primary,
    required this.cyan,
    required this.live,
    required this.success,
    required this.warning,
    required this.nav,
  });

  final Color bg;
  final Color bg2;
  final Color card;
  final Color card2;
  final Color border;
  final Color text;
  final Color muted;
  final Color primary;
  final Color cyan;
  final Color live;
  final Color success;
  final Color warning;
  final Color nav;

  bool get isDark => bg.computeLuminance() < .2;
  LinearGradient get primaryGradient => LinearGradient(
      colors: [cyan, primary],
      begin: Alignment.centerLeft,
      end: Alignment.centerRight);
  LinearGradient get bgGradient => LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: isDark
          ? const [Color(0xff020b1b), Color(0xff03142a), Color(0xff061c36)]
          : [bg, bg2, card2]);
  LinearGradient get cardGradient => LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [card.withValues(alpha: .98), card2.withValues(alpha: .96)]);

  // ── Light-mode-aware design tokens ─────────────────────────────────

  /// Soft card shadow for PremiumCard / elevated surfaces.
  List<BoxShadow> get cardShadow => isDark
      ? [
          BoxShadow(
            color: Colors.black.withValues(alpha: .28),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: cyan.withValues(alpha: .05),
            blurRadius: 18,
          ),
        ]
      : [
          BoxShadow(
            color: const Color(0xff4a7fb5).withValues(alpha: .10),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: cyan.withValues(alpha: .06),
            blurRadius: 16,
          ),
        ];

  /// Heavy shadow for hero / featured cards.
  List<BoxShadow> get heroShadow => isDark
      ? [
          BoxShadow(
            color: cyan.withValues(alpha: .18),
            blurRadius: 22,
            spreadRadius: -8,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: .38),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ]
      : [
          BoxShadow(
            color: const Color(0xff4a7fb5).withValues(alpha: .13),
            blurRadius: 22,
            spreadRadius: -4,
          ),
          BoxShadow(
            color: cyan.withValues(alpha: .08),
            blurRadius: 16,
          ),
        ];

  /// Stadium backdrop overlay gradient (top fade for readability).
  List<Color> get stadiumOverlayColors => isDark
      ? [
          const Color(0xff04132a).withValues(alpha: .30),
          const Color(0xff04101f).withValues(alpha: .58),
          bg.withValues(alpha: .90),
          bg,
        ]
      : [
          Colors.white.withValues(alpha: .25),
          Colors.white.withValues(alpha: .55),
          bg.withValues(alpha: .88),
          bg,
        ];

  /// Hero card image overlay (keeps stadium art visible + text readable).
  List<Color> get heroOverlayColors => isDark
      ? [
          const Color(0xff031126).withValues(alpha: .16),
          const Color(0xff031126).withValues(alpha: .20),
          const Color(0xff031126).withValues(alpha: .48),
        ]
      : [
          Colors.white.withValues(alpha: .30),
          Colors.white.withValues(alpha: .45),
          Colors.white.withValues(alpha: .72),
        ];

  /// Match card stadium overlay for list cards.
  List<Color> get matchCardOverlayColors => isDark
      ? [
          const Color(0xff031126).withValues(alpha: .45),
          const Color(0xff031126).withValues(alpha: .78),
        ]
      : [
          Colors.white.withValues(alpha: .50),
          Colors.white.withValues(alpha: .82),
        ];

  /// Inactive carousel dot color.
  Color get dotInactive => isDark
      ? const Color(0xff3a5780).withValues(alpha: .7)
      : const Color(0xffb0c8e8).withValues(alpha: .8);

  /// Semi-transparent text on image surfaces (venue, date on hero).
  Color get onImageText => isDark
      ? Colors.white.withValues(alpha: .88)
      : text.withValues(alpha: .78);

  /// Faint white-tint used for icon button backgrounds in dark mode
  /// or a subtle blue-tint in light mode.
  Color get subtleSurface => isDark
      ? Colors.white.withValues(alpha: .02)
      : const Color(0xffe8f0fa).withValues(alpha: .6);

  @override
  CricColors copyWith({
    Color? bg,
    Color? bg2,
    Color? card,
    Color? card2,
    Color? border,
    Color? text,
    Color? muted,
    Color? primary,
    Color? cyan,
    Color? live,
    Color? success,
    Color? warning,
    Color? nav,
  }) =>
      CricColors(
        bg: bg ?? this.bg,
        bg2: bg2 ?? this.bg2,
        card: card ?? this.card,
        card2: card2 ?? this.card2,
        border: border ?? this.border,
        text: text ?? this.text,
        muted: muted ?? this.muted,
        primary: primary ?? this.primary,
        cyan: cyan ?? this.cyan,
        live: live ?? this.live,
        success: success ?? this.success,
        warning: warning ?? this.warning,
        nav: nav ?? this.nav,
      );

  @override
  CricColors lerp(ThemeExtension<CricColors>? other, double t) {
    if (other is! CricColors) return this;
    return CricColors(
      bg: Color.lerp(bg, other.bg, t)!,
      bg2: Color.lerp(bg2, other.bg2, t)!,
      card: Color.lerp(card, other.card, t)!,
      card2: Color.lerp(card2, other.card2, t)!,
      border: Color.lerp(border, other.border, t)!,
      text: Color.lerp(text, other.text, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      cyan: Color.lerp(cyan, other.cyan, t)!,
      live: Color.lerp(live, other.live, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      nav: Color.lerp(nav, other.nav, t)!,
    );
  }
}

const lightCric = CricColors(
  bg: Color(0xffeef5fc),
  bg2: Color(0xffe4effa),
  card: Color(0xffffffff),
  card2: Color(0xfff4f9ff),
  border: Color(0xffc9ddf3),
  text: Color(0xff0a1e3d),
  muted: Color(0xff5e7a9a),
  primary: Color(0xff007bff),
  cyan: Color(0xff00c8f0),
  live: Color(0xffff2d45),
  success: Color(0xff1aae62),
  warning: Color(0xffffc83d),
  nav: Color(0xfffbfdff),
);

const darkCric = CricColors(
  bg: Color(0xff020b1b),
  bg2: Color(0xff061c36),
  card: Color(0xff071b35),
  card2: Color(0xff0a2748),
  border: Color(0xff1b4266),
  text: Color(0xffffffff),
  muted: Color(0xffb9c7d8),
  primary: Color(0xff007bff),
  cyan: Color(0xff00d9ff),
  live: Color(0xffff2d45),
  success: Color(0xff38f28b),
  warning: Color(0xffffc83d),
  nav: Color(0xff071528),
);

ThemeData cricTheme(bool dark) {
  final c = dark ? darkCric : lightCric;
  return ThemeData(
    useMaterial3: true,
    brightness: dark ? Brightness.dark : Brightness.light,
    scaffoldBackgroundColor: c.bg,
    fontFamily: 'Roboto',
    colorScheme: ColorScheme.fromSeed(
      seedColor: c.primary,
      brightness: dark ? Brightness.dark : Brightness.light,
    ),
    splashFactory: InkRipple.splashFactory,
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: c.cyan,
      selectionColor: c.cyan.withValues(alpha: .25),
      selectionHandleColor: c.cyan,
    ),
    extensions: [c],
  );
}

/// Responsive breakpoint buckets used across screens.
///
/// * [compact]  – very narrow Android phones (< 380px). 1 column, smallest
///   paddings, smallest fonts, never side-by-side cards.
/// * [mobile]   – normal phones (380–599px). 1 column with comfortable padding.
/// * [tablet]   – small tablets and large foldables (600–899px). 2 column
///   dashboard allowed.
/// * [desktop]  – ≥ 900px. Full dashboard with up to 3 columns.
enum CricBreak { compact, mobile, tablet, desktop }

extension CtxTheme on BuildContext {
  CricColors get cric =>
      Theme.of(this).extension<CricColors>() ??
      (Theme.of(this).brightness == Brightness.dark ? darkCric : lightCric);
  double get w => MediaQuery.sizeOf(this).width;

  CricBreak get bp {
    if (w < 380) return CricBreak.compact;
    if (w < 600) return CricBreak.mobile;
    if (w < 900) return CricBreak.tablet;
    return CricBreak.desktop;
  }

  bool get isCompact => bp == CricBreak.compact;
  bool get isMobile => bp == CricBreak.compact || bp == CricBreak.mobile;
  bool get isTabletUp => bp == CricBreak.tablet || bp == CricBreak.desktop;

  double get horizontalPadding {
    if (w <= 360) return 16;
    if (w <= 430) return 20;
    return 28;
  }

  /// Bottom padding for the main tabbed screens. With `extendBody:false` the
  /// bottom bar (sticky banner ad + nav) occupies real layout height and the
  /// body sits above it, so content only needs a small breathing-room inset —
  /// never a large reserve to clear a floating nav/ad.
  double get mainBottomPadding => 20;
  double get detailBottomPadding => 32 + MediaQuery.paddingOf(this).bottom;

  double sp(double value) {
    if (w <= 340) return value * .82;
    if (w <= 380) return value * .9;
    if (w <= 430) return value * .96;
    if (w >= 720) return value * 1.05;
    return value;
  }
}
