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
  LinearGradient get primaryGradient =>
      LinearGradient(colors: [cyan, primary], begin: Alignment.centerLeft, end: Alignment.centerRight);
  LinearGradient get bgGradient => const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xff020b1b), Color(0xff03142a), Color(0xff061c36)]);
  LinearGradient get cardGradient => LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [card.withValues(alpha: .98), card2.withValues(alpha: .96)]);

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
  bg: Color(0xffeff6ff),
  bg2: Color(0xffe5f0ff),
  card: Color(0xffffffff),
  card2: Color(0xfff5faff),
  border: Color(0xffd3e3f8),
  text: Color(0xff061a35),
  muted: Color(0xff6f84a1),
  primary: Color(0xff007bff),
  cyan: Color(0xff00d9ff),
  live: Color(0xffff2d45),
  success: Color(0xff21b96d),
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

extension CtxTheme on BuildContext {
  CricColors get cric => Theme.of(this).extension<CricColors>()!;
  double get w => MediaQuery.sizeOf(this).width;

  double get horizontalPadding {
    if (w <= 360) return 18;
    if (w <= 430) return 24;
    return 30;
  }

  double get mainBottomPadding => 108 + MediaQuery.paddingOf(this).bottom;
  double get detailBottomPadding => 32 + MediaQuery.paddingOf(this).bottom;

  double sp(double value) {
    if (w <= 360) return value * .88;
    if (w <= 390) return value * .94;
    if (w >= 720) return value * 1.05;
    return value;
  }
}
