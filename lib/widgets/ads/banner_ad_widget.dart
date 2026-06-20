import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:cricpro_flutter/models/ad_config.dart';
import 'package:cricpro_flutter/services/ads/ad_adapter.dart';
import 'package:cricpro_flutter/services/ads/ads_manager.dart';

/// Renders a banner for [placement] using the [AdsManager] waterfall. If no
/// network fills (or ads are disabled), it renders nothing — never a blank box.
class BannerAdWidget extends StatefulWidget {
  const BannerAdWidget({super.key, required this.placement});

  final AdPlacement placement;

  @override
  State<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<BannerAdWidget> {
  BannerLoadResult _result = BannerLoadResult.empty;

  @override
  void initState() {
    super.initState();
    AdsManager.instance.configRevision.addListener(_reload);
    _load();
  }

  void _reload() {
    _result.dispose?.call();
    _result = BannerLoadResult.empty;
    _load();
  }

  Future<void> _load() async {
    if (kIsWeb) return;
    final result = await AdsManager.instance.loadBanner(widget.placement);
    if (!mounted) {
      result.dispose?.call();
      return;
    }
    if (result.loaded) setState(() => _result = result);
  }

  @override
  void dispose() {
    AdsManager.instance.configRevision.removeListener(_reload);
    _result.dispose?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final widgetAd = _result.widget;
    if (widgetAd == null) return const SizedBox.shrink();
    return Center(child: widgetAd);
  }
}

/// A sticky bottom banner intended to sit directly above the bottom navigation
/// bar. It only occupies space when an ad actually loads — otherwise it renders
/// nothing, so there is never a blank gap when ads are disabled or unfilled.
///
/// Pass a null [placement] (e.g. for screens without a banner) to render
/// nothing.
class StickyBannerBar extends StatefulWidget {
  const StickyBannerBar({super.key, required this.placement});

  final AdPlacement? placement;

  @override
  State<StickyBannerBar> createState() => _StickyBannerBarState();
}

class _StickyBannerBarState extends State<StickyBannerBar> {
  BannerLoadResult _result = BannerLoadResult.empty;

  @override
  void initState() {
    super.initState();
    AdsManager.instance.configRevision.addListener(_reload);
    _load();
  }

  void _reload() {
    _result.dispose?.call();
    _result = BannerLoadResult.empty;
    _load();
  }

  @override
  void didUpdateWidget(StickyBannerBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.placement != widget.placement) {
      _result.dispose?.call();
      _result = BannerLoadResult.empty;
      _load();
    }
  }

  Future<void> _load() async {
    final placement = widget.placement;
    if (kIsWeb || placement == null) return;
    final result = await AdsManager.instance.loadBanner(placement);
    if (!mounted) {
      result.dispose?.call();
      return;
    }
    if (result.loaded) setState(() => _result = result);
  }

  @override
  void dispose() {
    AdsManager.instance.configRevision.removeListener(_reload);
    _result.dispose?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final widgetAd = _result.widget;
    if (widgetAd == null) return const SizedBox.shrink();
    // An opaque backing + a top hairline divider so the sticky banner reads as
    // a distinct ad strip occupying its OWN reserved height in the bottom bar —
    // it sits above (never over) the scrolling match cards. Because it lives in
    // the Scaffold's bottomNavigationBar with `extendBody:false`, the list body
    // is laid out above it and content can never scroll behind the ad.
    final theme = Theme.of(context);
    return Material(
      color: theme.scaffoldBackgroundColor,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(
              color: theme.dividerColor.withValues(alpha: .35),
              width: .5,
            ),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Center(child: widgetAd),
        ),
      ),
    );
  }
}
