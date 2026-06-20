import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:cricpro_flutter/services/remote_assets_service.dart';

/// Drop-in replacement for `Image.asset` that prefers an admin-managed remote
/// asset and falls back to a bundled asset.
///
/// Resolution:
///   1. Look up [assetKey] in [RemoteAssetsService] honoring [isDark].
///   2. If a remote URL exists, load it via [Image.network]. While it loads,
///      and on ANY error (offline, 404, decode failure), show [fallbackAsset].
///   3. If no remote URL is configured, render [fallbackAsset] directly.
///
/// The bundled [fallbackAsset] must always exist in pubspec assets, so the UI
/// never shows a broken image even with no network.
class RemoteOrLocalImage extends StatelessWidget {
  const RemoteOrLocalImage({
    super.key,
    required this.assetKey,
    required this.fallbackAsset,
    required this.isDark,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.color,
    this.colorBlendMode,
    this.opacity,
  });

  /// Admin asset key, e.g. 'live_player_bg_dark'.
  final String assetKey;

  /// Bundled asset path used as fallback, e.g. 'assets/images/.../bg.webp'.
  final String fallbackAsset;

  final bool isDark;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Color? color;
  final BlendMode? colorBlendMode;
  final double? opacity;

  @override
  Widget build(BuildContext context) {
    final remoteUrl = RemoteAssetsService.instance.urlFor(assetKey, isDark: isDark);

    final local = Image.asset(
      fallbackAsset,
      fit: fit,
      width: width,
      height: height,
      color: color,
      colorBlendMode: colorBlendMode,
      opacity: opacity == null ? null : AlwaysStoppedAnimation(opacity!),
    );

    if (remoteUrl == null || remoteUrl.isEmpty) {
      return local;
    }

    final cached = CachedNetworkImage(
      imageUrl: remoteUrl,
      fit: fit,
      width: width,
      height: height,
      color: color,
      colorBlendMode: colorBlendMode,
      // While the network image downloads, show the bundled asset so there is
      // never a blank gap; swap in instantly (no fade flash).
      fadeInDuration: Duration.zero,
      placeholder: (context, _) => local,
      // Any failure (offline, 404, bad bytes) → bundled fallback.
      errorWidget: (context, error, stackTrace) => local,
    );
    // CachedNetworkImage has no `opacity` arg; preserve the original opacity via
    // a wrapping Opacity so the rendered result is identical.
    if (opacity == null) return cached;
    return Opacity(opacity: opacity!, child: cached);
  }
}
