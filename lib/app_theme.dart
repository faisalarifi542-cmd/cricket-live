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
  LinearGradient get primaryGradient => LinearGradient(colors: [cyan, primary]);
  LinearGradient get bgGradient => LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [bg, bg2]);

  @override
  CricColors copyWith(
          {Color? bg,
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
          Color? nav}) =>
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
  bg: Color(0xfff4faff),
  bg2: Color(0xfff0f7ff),
  card: Colors.white,
  card2: Color(0xfff9fcff),
  border: Color(0xffddeaf7),
  text: Color(0xff061a35),
  muted: Color(0xff6b7c99),
  primary: Color(0xff147dff),
  cyan: Color(0xff22d3ee),
  live: Color(0xffff304f),
  success: Color(0xff16a34a),
  warning: Color(0xffffa500),
  nav: Colors.white,
);
const darkCric = CricColors(
  bg: Color(0xff031225),
  bg2: Color(0xff041426),
  card: Color(0xff09213d),
  card2: Color(0xff0c294a),
  border: Color(0xff1d4268),
  text: Color(0xffffffff),
  muted: Color(0xffa9b8cf),
  primary: Color(0xff147dff),
  cyan: Color(0xff22d3ee),
  live: Color(0xffff304f),
  success: Color(0xff4ade80),
  warning: Color(0xffffa500),
  nav: Color(0xff051729),
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
        brightness: dark ? Brightness.dark : Brightness.light),
    extensions: [c],
  );
}

extension CtxTheme on BuildContext {
  CricColors get cric => Theme.of(this).extension<CricColors>()!;
  double get w => MediaQuery.sizeOf(this).width;
  double get horizontalPadding {
    if (w <= 390) return 20;
    return 24;
  }

  double get mainBottomPadding => 120 + MediaQuery.paddingOf(this).bottom;
  double get detailBottomPadding => 32 + MediaQuery.paddingOf(this).bottom;
  double sp(double value) {
    if (w <= 360) return value * .90;
    if (w <= 390) return value * .95;
    return value;
  }
}
