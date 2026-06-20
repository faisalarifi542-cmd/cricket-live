import 'package:flutter/material.dart';

/// A cheap radial floodlight glow painted with a [RadialGradient] shader.
///
/// [intensity] (0..1) drives both opacity and radius so the caller can animate
/// the stadium "lights brightening" effect. Wrapped in a [RepaintBoundary] by
/// the splash screen so it does not repaint sibling layers.
class SplashGlowLayer extends StatelessWidget {
  const SplashGlowLayer({
    super.key,
    required this.intensity,
    this.center = const Alignment(0, -0.35),
    this.color = const Color(0xFF38BDF8),
    this.radiusScale = 1.0,
  });

  /// 0 = dark, 1 = fully lit.
  final double intensity;
  final Alignment center;
  final Color color;

  /// Multiplies the glow radius. <1 for tight floodlight pools, >1 for a wide
  /// global wash.
  final double radiusScale;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: CustomPaint(
        painter: _GlowPainter(
          intensity: intensity.clamp(0.0, 1.0),
          center: center,
          color: color,
          radiusScale: radiusScale,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _GlowPainter extends CustomPainter {
  _GlowPainter({
    required this.intensity,
    required this.center,
    required this.color,
    required this.radiusScale,
  });

  final double intensity;
  final Alignment center;
  final Color color;
  final double radiusScale;

  @override
  void paint(Canvas canvas, Size size) {
    if (intensity <= 0) return;
    final c = center.alongSize(size);
    final radius = size.shortestSide * (0.55 + 0.35 * intensity) * radiusScale;
    final rect = Rect.fromCircle(center: c, radius: radius);
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: 0.45 * intensity),
          color.withValues(alpha: 0.18 * intensity),
          color.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(rect);
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(_GlowPainter old) =>
      old.intensity != intensity ||
      old.center != center ||
      old.color != color ||
      old.radiusScale != radiusScale;
}
