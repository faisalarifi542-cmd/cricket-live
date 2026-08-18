import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:cricpro_flutter/features/splash/widgets/splash_asset_image.dart';
import 'package:cricpro_flutter/features/splash/widgets/splash_glow_layer.dart';
import 'package:cricpro_flutter/features/splash/widgets/splash_particle_field.dart';

/// Matches the Android native launch background so startup never flashes white.
const Color kSplashNavy = Color(0xFF060B18);

const Color _kCyan = Color(0xFF5CD0FF);
const String _kComposedSplash = 'assets/splash/splash_composed.webp';

/// Splash dismissal timing.
///
/// The splash is bounded by both a minimum on-screen duration and a hard
/// timeout so the user never sees the two-stage flash from the field video
/// (dark bg + ring at t=0, then artwork at t=~0.8s) and also never gets
/// stranded if the asset fails to decode.
///
/// - The ring/loader are gated on `_imageReady` (see [SplashLocalImage]);
///   they never paint before the artwork does.
/// - Once the image is ready, the animation keeps playing until
///   [_kSplashMinVisible] has elapsed since the splash first painted.
/// - If the image never becomes ready, [_kSplashHardTimeout] dismisses the
///   splash anyway. In that case the ring/loader never appear, so nothing
///   confusing is shown on a dark screen.
const Duration _kSplashMinVisible = Duration(milliseconds: 800);
const Duration _kSplashHardTimeout = Duration(milliseconds: 1600);
const Duration _kSplashAnimationDuration = Duration(milliseconds: 1600);

/// Local-only CricPro splash.
///
/// The visual design is a single optimized composed WebP. This avoids rendering
/// non-transparent overlay bitmaps as visible black/checkerboard rectangles and
/// keeps Android startup fast. Flutter only adds lightweight glow/particle
/// animation over the composed art.
class PremiumSplashScreen extends StatefulWidget {
  const PremiumSplashScreen({
    super.key,
    required this.onFinish,
  });

  final VoidCallback onFinish;

  @override
  State<PremiumSplashScreen> createState() => _PremiumSplashScreenState();
}

class _PremiumSplashScreenState extends State<PremiumSplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _main;
  late final AnimationController _pulse;

  late final Animation<double> _imageFade;
  late final Animation<double> _glow;
  late final Animation<double> _logoPulse;
  late final Animation<double> _particles;
  late final Animation<double> _finalPulse;
  late final Animation<double> _loader;

  bool _finished = false;

  /// True once [SplashLocalImage] fires its first decoded frame. The ring
  /// (`_LogoPulsePainter`) and loader (`_SplashLoaderBar`) are conditionally
  /// mounted so they never paint on a black pre-splash.
  bool _imageReady = false;

  /// Backstop that dismisses the splash if the image never decodes.
  Timer? _hardTimeout;
  Timer? _minVisibleTimer;

  @override
  void initState() {
    super.initState();

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarIconBrightness: Brightness.light,
    ));

    _main = AnimationController(
      vsync: this,
      duration: _kSplashAnimationDuration,
    );
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    Animation<double> seg(double begin, double end, Curve curve) =>
        CurvedAnimation(
          parent: _main,
          curve: Interval(begin, end, curve: curve),
        );

    _imageFade = seg(0.00, 0.11, Curves.easeOut);
    _glow = seg(0.07, 0.28, Curves.easeInOut);
    _logoPulse = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.86, end: 1.04)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 60,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.04, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 40,
      ),
    ]).animate(seg(0.12, 0.40, Curves.linear));
    _particles = seg(0.42, 1.00, Curves.easeOut);
    _finalPulse = seg(0.90, 1.00, Curves.easeInOut);
    // Smooth determinate loader line — fills across the splash so the wait reads
    // as progress, not a hang. Eases to full just before the timeline completes.
    _loader = seg(0.18, 0.94, Curves.easeInOut);

    _main.forward();
    // Absolute upper bound. Even if the image asset never decodes we dismiss
    // the splash so the user is never stuck on a dark background.
    _hardTimeout = Timer(_kSplashHardTimeout, _finish);
  }

  /// Called by [SplashLocalImage] on the frame the decoded artwork first
  /// paints. Starts (or completes) the minimum-visible window; the splash is
  /// dismissed the moment `_kSplashMinVisible` has elapsed AFTER this fires.
  void _handleImageReady() {
    if (_finished || !mounted) return;
    if (_imageReady) return;
    setState(() => _imageReady = true);
    _minVisibleTimer?.cancel();
    _minVisibleTimer = Timer(_kSplashMinVisible, _finish);
  }

  /// Called by [SplashLocalImage] when the artwork asset fails to decode.
  /// We deliberately do NOT flip `_imageReady` here — the ring/loader must
  /// never appear on a black background. The hard timeout will dismiss.
  void _handleImageError() {
    // Intentionally empty. The hard timeout owns dismissal in this branch.
  }

  void _finish() {
    if (_finished) return;
    _finished = true;
    _hardTimeout?.cancel();
    _minVisibleTimer?.cancel();
    widget.onFinish();
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
    ));
    _hardTimeout?.cancel();
    _minVisibleTimer?.cancel();
    _main.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: kSplashNavy,
        body: AnimatedBuilder(
          animation: Listenable.merge([_main, _pulse]),
          builder: (context, _) {
            return LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                final h = constraints.maxHeight;
                final logoSize = (w * 0.56).clamp(190.0, 300.0);
                final logoCenterY = h * 0.40;

                return Stack(
                  fit: StackFit.expand,
                  children: [
                    const ColoredBox(color: kSplashNavy),
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: Opacity(
                          opacity: _imageFade.value,
                          child: SplashLocalImage(
                            assetPath: _kComposedSplash,
                            fit: BoxFit.cover,
                            cacheWidth: w.toInt().clamp(360, 900),
                            onFirstFrame: _handleImageReady,
                            onFrameError: _handleImageError,
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            SplashGlowLayer(
                              intensity: _glow.value * 0.65,
                              center: const Alignment(-0.94, -0.45),
                              radiusScale: 0.52,
                            ),
                            SplashGlowLayer(
                              intensity: _glow.value * 0.65,
                              center: const Alignment(0.94, -0.45),
                              radiusScale: 0.52,
                            ),
                            SplashGlowLayer(
                              intensity: (0.25 + 0.22 * _pulse.value) *
                                  _imageFade.value,
                              center: Alignment(0, (logoCenterY / h) * 2 - 1),
                              radiusScale: 0.72,
                            ),
                          ],
                        ),
                      ),
                    ),
                    // Ring pulse — gated on the composed image being on
                    // screen. Prevents the field failure where the ring drew
                    // for ~800 ms on a black background before the artwork
                    // faded in.
                    if (_imageReady)
                      Positioned(
                        left: (w - logoSize * 1.08) / 2,
                        top: logoCenterY - logoSize * 0.54,
                        width: logoSize * 1.08,
                        height: logoSize * 1.08,
                        child: IgnorePointer(
                          child: RepaintBoundary(
                            child: CustomPaint(
                              painter: _LogoPulsePainter(
                                progress: _logoPulse.value,
                                shimmer: _pulse.value,
                              ),
                            ),
                          ),
                        ),
                      ),
                    Positioned.fill(
                      child: SplashParticleField(
                        particleCount: 24,
                        opacity: _particles.value * 0.72,
                      ),
                    ),
                    // Determinate loader line near the bottom — premium, cheap,
                    // and signals progress so a brief init wait never reads as
                    // a frozen/half-loaded splash. Also gated on `_imageReady`
                    // so it never appears alone on a black background.
                    if (_imageReady)
                      Positioned(
                        left: w * 0.5 - (w * 0.22),
                        right: w * 0.5 - (w * 0.22),
                        top: logoCenterY + logoSize * 0.62,
                        child: IgnorePointer(
                          child: Opacity(
                            opacity: _imageFade.value,
                            child: _SplashLoaderBar(
                              progress: _loader.value,
                              shimmer: _pulse.value,
                            ),
                          ),
                        ),
                      ),
                    if (_finalPulse.value > 0)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Opacity(
                            opacity: 0.10 *
                                (1 - (_finalPulse.value - 0.5).abs() * 2)
                                    .clamp(0.0, 1.0),
                            child: const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: RadialGradient(
                                  colors: [_kCyan, Colors.transparent],
                                  radius: 0.9,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _LogoPulsePainter extends CustomPainter {
  const _LogoPulsePainter({
    required this.progress,
    required this.shimmer,
  });

  final double progress;
  final double shimmer;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide * 0.43 * progress;
    final alpha = (0.18 + 0.12 * shimmer).clamp(0.0, 1.0);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10)
      ..color = _kCyan.withValues(alpha: alpha);
    canvas.drawCircle(center, radius, paint);

    final core = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.white.withValues(alpha: 0.20 + 0.12 * shimmer);
    canvas.drawCircle(center, radius * 0.98, core);
  }

  @override
  bool shouldRepaint(_LogoPulsePainter old) =>
      old.progress != progress || old.shimmer != shimmer;
}

/// Lightweight determinate loader line for the splash. Pure-paint (no images,
/// no shaders), so it is effectively free on low-end devices.
class _SplashLoaderBar extends StatelessWidget {
  const _SplashLoaderBar({required this.progress, required this.shimmer});

  final double progress;
  final double shimmer;

  @override
  Widget build(BuildContext context) {
    final p = progress.clamp(0.0, 1.0);
    return SizedBox(
      height: 3,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: Stack(
          children: [
            // Track.
            Positioned.fill(
              child: ColoredBox(color: Colors.white.withValues(alpha: 0.10)),
            ),
            // Fill.
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: p,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _kCyan.withValues(alpha: 0.55),
                      _kCyan.withValues(alpha: 0.55 + 0.30 * shimmer),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _kCyan.withValues(alpha: 0.35 * shimmer),
                      blurRadius: 8,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
