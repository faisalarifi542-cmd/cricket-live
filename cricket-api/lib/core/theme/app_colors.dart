import 'package:flutter/material.dart';

class AppColors {
  static const Color primaryBg = Color(0xFF000D26);
  static const Color cardBg = Color(0xFF071A35);
  static const Color cardBg2 = Color(0xFF0B2347);
  static const Color borderColor = Color(0xFF1C3A63);
  static const Color cyan = Color(0xFF21E6E6);
  static const Color blue = Color(0xFF2D7DFF);
  static const Color green = Color(0xFF25E07A);
  static const Color red = Color(0xFFFF3B4E);
  static const Color orange = Color(0xFFFF7A18);
  static const Color purple = Color(0xFF9B5CFF);
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFFB7C5D9);
  static const Color textMuted = Color(0xFF7E8DA8);

  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF000D26),
      Color(0xFF061A3D),
      Color(0xFF020B1F),
    ],
  );

  static LinearGradient cardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      const Color(0xFF092044).withOpacity(0.95),
      const Color(0xFF06172F).withOpacity(0.95),
    ],
  );

  static Border cardBorder = Border.all(
    color: const Color(0xFF2A5B8F).withOpacity(0.55),
    width: 1,
  );

  static List<BoxShadow> glowShadow = [
    BoxShadow(
      color: const Color(0xFF00E5FF).withOpacity(0.08),
      blurRadius: 18,
      offset: const Offset(0, 8),
    ),
  ];
}
