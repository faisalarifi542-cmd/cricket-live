import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'package:cricpro_flutter/models/ad_config.dart';
import 'package:cricpro_flutter/services/ad_service.dart';

class NativeAdCard extends StatefulWidget {
  const NativeAdCard({super.key, required this.placement});

  final AdPlacement placement;

  @override
  State<NativeAdCard> createState() => _NativeAdCardState();
}

class _NativeAdCardState extends State<NativeAdCard> {
  NativeAd? _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    if (kIsWeb || !AdService.instance.config.nativeFor(widget.placement)) return;
    final unitId = AdService.instance.nativeUnitId();
    if (unitId == null || unitId.isEmpty) return;
    _ad = NativeAd(
      adUnitId: unitId,
      factoryId: 'cricproNative',
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, _) {
          ad.dispose();
          if (mounted) setState(() => _ad = null);
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (!_loaded || ad == null) return const SizedBox.shrink();
    return SizedBox(
      height: 120,
      child: AdWidget(ad: ad),
    );
  }
}
