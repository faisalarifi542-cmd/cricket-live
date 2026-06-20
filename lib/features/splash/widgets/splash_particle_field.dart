import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Lightweight sparkle particle field painted with a single [CustomPainter].
///
/// No images, no Lottie, no per-particle widgets — just N points twinkling on a
/// looping [AnimationController]. Cheap enough for low-end Android. The splash
/// screen wraps this in a [RepaintBoundary] so only this layer repaints.
class SplashParticleField extends StatefulWidget {
  const SplashParticleField({
    super.key,
    this.particleCount = 28,
    this.color = const Color(0xFF8FD8FF),
    this.opacity = 1.0,
  });

  final int particleCount;
  final Color color;

  /// Master fade for the whole field (drives in/out with the timeline).
  final double opacity;

  @override
  State<SplashParticleField> createState() => _SplashParticleFieldState();
}

class _SplashParticleFieldState extends State<SplashParticleField>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_Particle> _particles;

  @override
  void initState() {
    super.initState();
    // Fixed seed so the layout is stable across rebuilds (no Random() jitter).
    final rng = math.Random(7);
    _particles = List.generate(
      widget.particleCount,
      (i) => _Particle(
        dx: rng.nextDouble(),
        dy: rng.nextDouble(),
        // Subtle stadium sparkles: mostly 1–2.5px dots, only ~1 in 7 a 3px
        // highlight. No big snow-like dots.
        radius: i % 7 == 0
            ? 2.6 + rng.nextDouble() * 0.4
            : 1.0 + rng.nextDouble() * 1.4,
        phase: rng.nextDouble(),
        speed: 0.5 + rng.nextDouble() * 0.9,
        drift: (rng.nextDouble() - 0.5) * 0.04,
      ),
    );
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.opacity <= 0) return const SizedBox.shrink();
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(
            painter: _ParticlePainter(
              particles: _particles,
              t: _controller.value,
              color: widget.color,
              masterOpacity: widget.opacity.clamp(0.0, 1.0),
            ),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

class _Particle {
  const _Particle({
    required this.dx,
    required this.dy,
    required this.radius,
    required this.phase,
    required this.speed,
    required this.drift,
  });

  final double dx; // 0..1 horizontal
  final double dy; // 0..1 vertical
  final double radius;
  final double phase; // 0..1 twinkle offset
  final double speed; // twinkle speed multiplier
  final double drift; // slow upward drift factor
}

class _ParticlePainter extends CustomPainter {
  _ParticlePainter({
    required this.particles,
    required this.t,
    required this.color,
    required this.masterOpacity,
  });

  final List<_Particle> particles;
  final double t; // 0..1 loop
  final Color color;
  final double masterOpacity;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    for (final p in particles) {
      // Twinkle: 0..1..0 sine on the looping clock.
      final tw = (math.sin((t * p.speed + p.phase) * 2 * math.pi) + 1) / 2;
      final alpha = masterOpacity * (0.15 + 0.75 * tw);
      if (alpha <= 0.01) continue;
      // Gentle upward drift that wraps around.
      final y = (p.dy - t * p.drift) % 1.0;
      final offset =
          Offset(p.dx * size.width, (y < 0 ? y + 1 : y) * size.height);
      paint.color = color.withValues(alpha: alpha);
      canvas.drawCircle(offset, p.radius * (0.7 + 0.4 * tw), paint);
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter old) =>
      old.t != t || old.masterOpacity != masterOpacity;
}
