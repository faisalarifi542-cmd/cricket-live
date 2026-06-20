part of '../live_player_screen.dart';

class _StreamsSection extends StatelessWidget {
  const _StreamsSection({
    required this.matchId,
    required this.streamsFuture,
    required this.appConfigFuture,
    required this.selectedId,
    required this.onAutoSelect,
    required this.onStreamsLoaded,
    required this.qualityOptions,
    required this.selectedQuality,
    required this.onSelectQuality,
  });

  final String matchId;
  final Future<ApiEnvelope<Map<String, dynamic>>>? streamsFuture;
  final Future<ApiEnvelope<Map<String, dynamic>>>? appConfigFuture;
  final String? selectedId;
  final ValueChanged<StreamSource> onAutoSelect;
  final ValueChanged<List<StreamSource>> onStreamsLoaded;
  final List<HlsQuality> qualityOptions;
  final HlsQuality? selectedQuality;
  final ValueChanged<HlsQuality> onSelectQuality;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    if (matchId.isEmpty) {
      return PremiumCard(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Icon(Icons.live_tv_rounded, color: c.cyan, size: 30),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'No match selected. Tap Watch Live on a live or upcoming match.',
                style: TextStyle(
                    color: c.text, fontWeight: FontWeight.w800, height: 1.35),
              ),
            ),
          ],
        ),
      );
    }

    return FutureBuilder<ApiEnvelope<Map<String, dynamic>>>(
      future: streamsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const _StreamsSkeleton();
        }
        final data = apiMap(snapshot.data?.data);
        final streams = apiList(data['streams'])
            .map(StreamSource.fromJson)
            .where((stream) => stream.url.isNotEmpty)
            .toList();
        streams.sort((a, b) {
          final priority = (a.priority ?? 100).compareTo(b.priority ?? 100);
          if (priority != 0) return priority;
          return a.qualityRank.compareTo(b.qualityRank);
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          onStreamsLoaded(streams);
        });
        if (streams.isEmpty) {
          return _StreamsUnavailable(appConfigFuture: appConfigFuture);
        }
        final selected = streams.where((s) => s.id == selectedId).firstOrNull ??
            streams.first;

        // Auto-select highest priority stream once available
        if (selectedId == null) {
          WidgetsBinding.instance
              .addPostFrameCallback((_) => onAutoSelect(selected));
        }

        // Build the three fixed quality tiers (Full HD / HD / SD).
        final tiers = _buildQualityTiers(qualityOptions);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.card.withValues(alpha: .55),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: c.cyan.withValues(alpha: .35)),
                  ),
                  child: SvgPicture.asset(
                    'assets/images/live_stream/icons/ic_bars_cyan.svg',
                    width: 16,
                    height: 16,
                    colorFilter: ColorFilter.mode(c.cyan, BlendMode.srcIn),
                    placeholderBuilder: (_) =>
                        Icon(Icons.bar_chart_rounded, color: c.cyan, size: 16),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Stream Quality',
                  style: TextStyle(
                    color: c.text,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    letterSpacing: .2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final spacing = constraints.maxWidth < 360 ? 8.0 : 12.0;
                final cardWidth = (constraints.maxWidth - spacing * 2) / 3;
                // Below ~96px per card the 3-up row is too cramped; fall back
                // to a horizontal scroller with a sensible minimum card width.
                final useScroll = cardWidth < 96;

                Widget card(int i) => _QualityTierCard(
                      tier: tiers[i],
                      selected: _isTierSelected(tiers[i], selectedQuality),
                      onTap: tiers[i].quality == null
                          ? null
                          : () => onSelectQuality(tiers[i].quality!),
                    );

                if (useScroll) {
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < tiers.length; i++) ...[
                            SizedBox(width: 120, child: card(i)),
                            if (i != tiers.length - 1) SizedBox(width: spacing),
                          ],
                        ],
                      ),
                    ),
                  );
                }

                // IntrinsicHeight bounds the Row's cross axis so the cards
                // stretch to equal height instead of collapsing inside the
                // unbounded ListView.
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < tiers.length; i++) ...[
                        Expanded(child: card(i)),
                        if (i != tiers.length - 1) SizedBox(width: spacing),
                      ],
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 18),
            const _CompactStreamStatus(),
          ],
        );
      },
    );
  }

  /// Maps available variants into the three fixed display tiers. Each tier maps
  /// directly to its own bucket; a tier with no matching variant renders
  /// disabled/unavailable so the premium 3-card layout is always preserved.
  ///
  /// Variant codes (from the parsed playlist): FHD(720p+), HD(480p),
  /// SD(240p/360p), AUTO(adaptive).
  ///   Full HD ← FHD (720p)
  ///   HD      ← HD  (480p)
  ///   SD      ← SD  (288p)
  static List<_QualityTier> _buildQualityTiers(List<HlsQuality> options) {
    HlsQuality? byCode(String code) =>
        options.where((q) => q.code == code).firstOrNull;

    final fhd = byCode('FHD');
    final hd = byCode('HD');
    final sd = byCode('SD');

    return [
      _QualityTier(
        title: 'Full HD',
        badge: 'FHD',
        resolution: '720p',
        subtitle: 'Best Experience',
        quality: fhd,
      ),
      _QualityTier(
        title: 'HD',
        badge: 'HD',
        resolution: '480p',
        subtitle: 'Good Quality',
        quality: hd,
      ),
      _QualityTier(
        title: 'SD',
        badge: 'SD',
        resolution: '288p',
        subtitle: 'Data Saver',
        quality: sd,
      ),
    ];
  }

  static bool _isTierSelected(_QualityTier tier, HlsQuality? selected) {
    final q = tier.quality;
    if (q == null || selected == null) return false;
    // Match by URL — covers both bucketed card picks and raw variant picks.
    return q.url == selected.url;
  }
}

/// A single resolved quality tier for the Full HD / HD / SD cards. [quality]
/// is null when no matching variant exists (card renders disabled).
class _QualityTier {
  const _QualityTier({
    required this.title,
    required this.badge,
    required this.resolution,
    required this.subtitle,
    required this.quality,
  });

  final String title;
  final String badge;
  final String resolution;
  final String subtitle;
  final HlsQuality? quality;

  bool get available => quality != null;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class _QualityTierCard extends StatelessWidget {
  const _QualityTierCard({
    required this.tier,
    required this.selected,
    required this.onTap,
  });

  final _QualityTier tier;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final available = tier.available;
    final disabled = !available;

    final borderColor = selected
        ? c.cyan
        : disabled
            ? c.border.withValues(alpha: .35)
            : c.border.withValues(alpha: .7);

    return Opacity(
      opacity: disabled ? .55 : 1,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: selected
                  ? [
                      c.cyan.withValues(alpha: .12),
                      c.isDark
                          ? const Color(0xff0b2b4a).withValues(alpha: .85)
                          : c.card2.withValues(alpha: .95),
                    ]
                  : [
                      c.card2.withValues(alpha: .55),
                      c.card.withValues(alpha: .9),
                    ],
            ),
            border: Border.all(color: borderColor, width: selected ? 1.6 : 1.1),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: c.cyan.withValues(alpha: .22),
                      blurRadius: 16,
                      spreadRadius: -6,
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: selected ? c.cyan : c.card2,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color:
                            selected ? c.cyan : c.border.withValues(alpha: .8),
                      ),
                    ),
                    child: Text(
                      tier.badge,
                      style: TextStyle(
                        color: selected ? Colors.black : c.text,
                        fontWeight: FontWeight.w900,
                        fontSize: 9,
                        letterSpacing: .2,
                      ),
                    ),
                  ),
                  const Spacer(),
                  selected
                      ? SvgPicture.asset(
                          'assets/images/live_stream/icons/ic_check_circle_cyan.svg',
                          width: 16,
                          height: 16,
                          colorFilter:
                              ColorFilter.mode(c.cyan, BlendMode.srcIn),
                          placeholderBuilder: (_) => Icon(
                              Icons.check_circle_rounded,
                              color: c.cyan,
                              size: 15),
                        )
                      : SvgPicture.asset(
                          'assets/images/live_stream/icons/ic_radio_circle_cyan.svg',
                          width: 16,
                          height: 16,
                          colorFilter: ColorFilter.mode(
                              c.muted.withValues(alpha: .7), BlendMode.srcIn),
                          placeholderBuilder: (_) => Icon(
                              Icons.radio_button_unchecked_rounded,
                              color: c.muted.withValues(alpha: .7),
                              size: 15),
                        ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                tier.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: c.text,
                  fontWeight: FontWeight.w900,
                  fontSize: 13.5,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                disabled ? 'N/A' : tier.resolution,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? c.cyan : c.muted,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: disabled
                        ? Icon(Icons.block_rounded, color: c.muted, size: 11)
                        : SvgPicture.asset(
                            'assets/images/live_stream/icons/ic_diamond_outline.svg',
                            width: 11,
                            height: 11,
                            colorFilter: ColorFilter.mode(
                                selected ? c.cyan : c.muted, BlendMode.srcIn),
                            placeholderBuilder: (_) => Icon(
                                Icons.diamond_outlined,
                                color: selected ? c.cyan : c.muted,
                                size: 11),
                          ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      disabled ? 'Unavailable' : tier.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.muted,
                        fontWeight: FontWeight.w600,
                        fontSize: 9.5,
                        height: 1.15,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Premium trust strip used below the real quality/server controls.
class _CompactStreamStatus extends StatelessWidget {
  const _CompactStreamStatus();

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    const base = 'assets/images/live_stream';
    const items = [
      _FeatureItemData(
        svg: '$base/icons/ic_lightning_cyan.svg',
        title: 'Low Latency',
        subtitle: 'Live at real speed',
      ),
      _FeatureItemData(
        svg: '$base/icons/ic_signal_cyan.svg',
        title: 'Adaptive Streaming',
        subtitle: 'Smooth on any network',
      ),
      _FeatureItemData(
        svg: '$base/icons/ic_lock_cyan.svg',
        title: 'Secure Stream',
        subtitle: 'Protected & Encrypted',
      ),
      _FeatureItemData(
        svg: '$base/icons/ic_monitor_pulse_cyan.svg',
        title: 'Stable Playback',
        subtitle: 'No buffering experience',
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Feature strip — 4 equal items + dividers over the glass overlay.
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: c.isDark
                ? c.card2.withValues(alpha: .4)
                : c.card.withValues(alpha: .9),
            border: Border.all(color: c.cyan.withValues(alpha: .2)),
          ),
          child: Stack(
            children: [
              if (c.isDark)
                Positioned.fill(
                  child: Image.asset(
                    '$base/overlays/feature_strip_glass.webp',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    for (var i = 0; i < items.length; i++) ...[
                      Expanded(child: _StreamFeatureChip(data: items[i])),
                      if (i != items.length - 1)
                        Container(
                          width: 1,
                          height: 38,
                          color: c.cyan.withValues(alpha: .18),
                        ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Secure & encrypted info card.
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: c.isDark
                ? c.card.withValues(alpha: .55)
                : c.card.withValues(alpha: .95),
            border: Border.all(color: c.cyan.withValues(alpha: .24)),
            boxShadow: [
              BoxShadow(
                color: c.cyan.withValues(alpha: .08),
                blurRadius: 18,
                spreadRadius: -8,
              ),
            ],
          ),
          child: Stack(
            children: [
              if (c.isDark)
                Positioned.fill(
                  child: Image.asset(
                    '$base/overlays/secure_info_card_glass.webp',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    SizedBox(
                      width: 44,
                      height: 44,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Image.asset(
                            '$base/overlays/blue_icon_badge_glow.webp',
                            width: 44,
                            height: 44,
                            errorBuilder: (_, __, ___) => Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: c.primaryGradient,
                              ),
                            ),
                          ),
                          SvgPicture.asset(
                            '$base/icons/ic_shield_lock_cyan.svg',
                            width: 22,
                            height: 22,
                            colorFilter:
                                ColorFilter.mode(c.cyan, BlendMode.srcIn),
                            placeholderBuilder: (_) => const Icon(
                                Icons.lock_rounded,
                                color: Colors.white,
                                size: 20),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'This is a secure & encrypted stream',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: c.text,
                              fontWeight: FontWeight.w900,
                              fontSize: 13.5,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Your privacy and data are protected.',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: c.muted,
                              fontWeight: FontWeight.w600,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    SvgPicture.asset(
                      '$base/icons/ic_chevron_right.svg',
                      width: 18,
                      height: 18,
                      colorFilter: ColorFilter.mode(
                          c.muted.withValues(alpha: .9), BlendMode.srcIn),
                      placeholderBuilder: (_) => Icon(
                          Icons.chevron_right_rounded,
                          color: c.muted,
                          size: 20),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FeatureItemData {
  const _FeatureItemData({
    required this.svg,
    required this.title,
    required this.subtitle,
  });

  final String svg;
  final String title;
  final String subtitle;
}

class _StreamFeatureChip extends StatelessWidget {
  const _StreamFeatureChip({required this.data});

  final _FeatureItemData data;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset(
            data.svg,
            width: 19,
            height: 19,
            colorFilter: ColorFilter.mode(c.cyan, BlendMode.srcIn),
            placeholderBuilder: (_) =>
                Icon(Icons.bolt_rounded, color: c.cyan, size: 18),
          ),
          const SizedBox(height: 6),
          Text(
            data.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: c.text,
              fontWeight: FontWeight.w800,
              fontSize: 10,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            data.subtitle,
            maxLines: 2,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: c.muted,
              fontWeight: FontWeight.w600,
              fontSize: 9,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _StreamsSkeleton extends StatelessWidget {
  const _StreamsSkeleton();

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: 160,
          height: 18,
          decoration: BoxDecoration(
            color: c.card2,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        const SizedBox(height: 14),
        for (var i = 0; i < 3; i++) ...[
          Container(
            height: 76,
            decoration: BoxDecoration(
              color: c.card2,
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _StreamsUnavailable extends StatelessWidget {
  const _StreamsUnavailable({required this.appConfigFuture});

  final Future<ApiEnvelope<Map<String, dynamic>>>? appConfigFuture;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return FutureBuilder<ApiEnvelope<Map<String, dynamic>>>(
      future: appConfigFuture,
      builder: (context, snapshot) {
        final config = AppConfig.fromJson(snapshot.data?.data);
        final message = config.streamUnavailableMessage;
        return PremiumCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: c.cyan.withValues(alpha: .12),
                    ),
                    alignment: Alignment.center,
                    child: Icon(Icons.schedule_rounded, color: c.cyan),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'Stream not live yet',
                      style: TextStyle(
                        color: c.text,
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                message,
                style: TextStyle(
                  color: c.muted,
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

