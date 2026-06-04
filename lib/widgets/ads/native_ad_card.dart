import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:cricpro_flutter/models/ad_config.dart';
import 'package:cricpro_flutter/services/ads/ad_adapter.dart';
import 'package:cricpro_flutter/services/ads/ads_manager.dart';

/// Native ad slot.
///
/// Loads an AdMob native ad through the [AdsManager] waterfall and renders it
/// using the platform-registered "cricproNative" factory (Android), which
/// includes a clear "Ad" badge so it never looks like normal content.
///
/// If native ads are disabled, the placement is off, there is no native factory
/// on the platform, or no ad fills, this renders nothing (never a blank box).
class NativeAdCard extends StatefulWidget {
  const NativeAdCard({super.key, required this.placement});

  final AdPlacement placement;

  @override
  State<NativeAdCard> createState() => _NativeAdCardState();
}

class _NativeAdCardState extends State<NativeAdCard> {
  NativeLoadResult _result = NativeLoadResult.empty;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (kIsWeb) return;
    if (!AdsManager.instance.config.nativeFor(widget.placement)) return;
    final result = await AdsManager.instance.loadNative(widget.placement);
    if (!mounted) {
      result.dispose?.call();
      return;
    }
    if (result.loaded) setState(() => _result = result);
  }

  @override
  void dispose() {
    _result.dispose?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final widgetAd = _result.widget;
    if (widgetAd == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: widgetAd,
      ),
    );
  }
}
