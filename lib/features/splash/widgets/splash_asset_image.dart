import 'package:flutter/material.dart';

/// Renders a bundled local splash image only. No network, no remote fallback,
/// and no admin/config asset selection happens in the splash path.
class SplashLocalImage extends StatelessWidget {
  const SplashLocalImage({
    super.key,
    required this.assetPath,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.cacheWidth,
    this.cacheHeight,
  });

  final String assetPath;
  final BoxFit fit;
  final Alignment alignment;
  final int? cacheWidth;
  final int? cacheHeight;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      assetPath,
      fit: fit,
      alignment: alignment,
      cacheWidth: cacheWidth,
      cacheHeight: cacheHeight,
      gaplessPlayback: true,
      errorBuilder: (context, error, stack) => const SizedBox.shrink(),
    );
  }
}
