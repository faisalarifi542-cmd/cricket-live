import 'package:flutter/material.dart';

/// Renders a bundled local splash image only. No network, no remote fallback,
/// and no admin/config asset selection happens in the splash path.
///
/// Fires [onFirstFrame] EXACTLY ONCE, on the frame the decoded image first
/// paints. `PremiumSplashScreen` uses this to gate the ring + loader overlays
/// so they never appear on a black pre-splash. If the asset fails to decode,
/// [onFrameError] is called (also exactly once) so the parent can dismiss on
/// the hard timeout without ever showing the overlays.
class SplashLocalImage extends StatefulWidget {
  const SplashLocalImage({
    super.key,
    required this.assetPath,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.cacheWidth,
    this.cacheHeight,
    this.onFirstFrame,
    this.onFrameError,
  });

  final String assetPath;
  final BoxFit fit;
  final Alignment alignment;
  final int? cacheWidth;
  final int? cacheHeight;

  final VoidCallback? onFirstFrame;
  final VoidCallback? onFrameError;

  @override
  State<SplashLocalImage> createState() => _SplashLocalImageState();
}

class _SplashLocalImageState extends State<SplashLocalImage> {
  bool _fired = false;

  void _fireOnce(VoidCallback? cb) {
    if (_fired) return;
    _fired = true;
    if (cb != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        cb();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      widget.assetPath,
      fit: widget.fit,
      alignment: widget.alignment,
      cacheWidth: widget.cacheWidth,
      cacheHeight: widget.cacheHeight,
      gaplessPlayback: true,
      // Fires the first time the image has been decoded and drawn. Used to
      // gate the splash overlays (ring, loader) on "the artwork is on screen".
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) {
          _fireOnce(widget.onFirstFrame);
        }
        return child;
      },
      // Decode failure — collapse to a bare box and let the parent's hard
      // timeout dismiss. Never show the ring/loader on a decode error.
      errorBuilder: (context, error, stack) {
        _fireOnce(widget.onFrameError);
        return const SizedBox.shrink();
      },
    );
  }
}
