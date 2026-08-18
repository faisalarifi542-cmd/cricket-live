part of '../live_player_screen.dart';

class _PlayerSurface extends StatelessWidget {
  const _PlayerSurface({
    required this.stream,
    required this.controller,
    required this.initFuture,
    required this.error,
    required this.selectedQuality,
    required this.isMuted,
    required this.isLiveContent,
    required this.videoFit,
    required this.viewers,
    required this.controlsVisible,
    required this.onSurfaceTap,
    required this.onControlInteraction,
    required this.onRetry,
    required this.onFullscreen,
    required this.onSettings,
    required this.onToggleMute,
    required this.onShare,
    required this.onComments,
    required this.onStats,
    required this.onSeekBackward,
    required this.onSeekForward,
  });

  final StreamSource? stream;
  final VideoPlayerController? controller;
  final Future<void>? initFuture;
  final String? error;
  final HlsQuality? selectedQuality;
  final bool isMuted;
  final bool isLiveContent;
  final BoxFit videoFit;
  final String? viewers;

  /// Whether the tap-to-show controls overlay is currently visible.
  final bool controlsVisible;

  /// Tap on the video surface — toggles [controlsVisible].
  final VoidCallback onSurfaceTap;

  /// Called after any control button is pressed so the parent can re-arm the
  /// auto-hide countdown (and keep the controls visible).
  final VoidCallback onControlInteraction;

  final VoidCallback? onRetry;
  final VoidCallback onFullscreen;
  final VoidCallback onSettings;
  final VoidCallback onToggleMute;
  final VoidCallback onShare;
  final VoidCallback onComments;
  final VoidCallback onStats;
  final VoidCallback onSeekBackward;
  final VoidCallback onSeekForward;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final hasStream = stream != null && stream!.url.isNotEmpty;
    final initialized = controller?.value.isInitialized == true;
    final playing = controller?.value.isPlaying == true;
    return PremiumCard(
      padding: EdgeInsets.zero,
      radius: 18,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (initialized)
                _VideoContent(controller: controller!, fit: videoFit)
              else
                RemoteOrLocalImage(
                  assetKey: 'player_surface_bg',
                  fallbackAsset:
                      'assets/images/live_stream/backgrounds/stadium_player_background_clean_16x9.webp',
                  isDark: c.isDark,
                  fit: BoxFit.cover,
                ),
              // Cinematic vignette + dark scrim — POSTER/PLACEHOLDER ONLY.
              // Once the video is initialized these are removed entirely so the
              // live video is never permanently darkened. While the video plays,
              // readability dimming is handled by a lighter scrim that lives
              // inside the auto-hiding chrome below (so it fades with controls).
              if (!initialized) ...[
                Positioned.fill(
                  child: IgnorePointer(
                    child: Image.asset(
                      'assets/images/live_stream/overlays/video_vignette_overlay_16x9.webp',
                      fit: BoxFit.cover,
                      excludeFromSemantics: true,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: .35),
                        Colors.black.withValues(alpha: .45),
                        Colors.black.withValues(alpha: .78),
                      ],
                      stops: const [0.0, 0.45, 1.0],
                    ),
                  ),
                ),
              ],
              if (initFuture != null && !initialized && error == null)
                FutureBuilder<void>(
                  future: initFuture,
                  builder: (context, snapshot) => Center(
                    child: snapshot.hasError
                        ? const SizedBox.shrink()
                        : SizedBox(
                            width: 46,
                            height: 46,
                            child: CircularProgressIndicator(
                              color: c.cyan,
                              strokeWidth: 3,
                            ),
                          ),
                  ),
                ),
              if (!initialized && error == null)
                Center(
                  child: SizedBox(
                    width: 92,
                    height: 92,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Image.asset(
                          'assets/images/live_stream/overlays/neon_play_button.webp',
                          width: 92,
                          height: 92,
                          excludeFromSemantics: true,
                          errorBuilder: (_, __, ___) => Container(
                            width: 84,
                            height: 84,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black.withValues(alpha: .42),
                              border: Border.all(
                                  color: c.cyan.withValues(alpha: .7),
                                  width: 1.6),
                              boxShadow: [
                                BoxShadow(
                                  color: c.cyan.withValues(alpha: .35),
                                  blurRadius: 24,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                          ),
                        ),
                        hasStream
                            ? SvgPicture.asset(
                                'assets/images/live_stream/icons/ic_play_cyan.svg',
                                width: 34,
                                height: 34,
                                colorFilter:
                                    ColorFilter.mode(c.cyan, BlendMode.srcIn),
                                excludeFromSemantics: true,
                                placeholderBuilder: (_) => Icon(
                                    Icons.play_arrow_rounded,
                                    color: c.cyan,
                                    size: 38),
                              )
                            : Icon(Icons.live_tv_rounded,
                                color: Colors.white.withValues(alpha: .65),
                                size: 34),
                      ],
                    ),
                  ),
                ),
              if (error != null)
                _PlayerErrorOverlay(message: error!, onRetry: onRetry),
              // Full-surface tap target to toggle the controls overlay. Sits
              // below the chrome group so visible buttons still receive taps;
              // when controls are hidden the chrome is IgnorePointer and taps
              // fall through here to show them again. Only meaningful once the
              // video is initialized (otherwise there is nothing to toggle).
              if (initialized)
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onSurfaceTap,
                  ),
                ),
              // Auto-hiding chrome: branding/LIVE, viewers/quality pills, the
              // paused center play button and the bottom control bar all fade
              // together after ~3s of inactivity (parent-driven).
              Positioned.fill(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 220),
                  opacity: controlsVisible ? 1 : 0,
                  child: IgnorePointer(
                    ignoring: !controlsVisible,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Readability scrim for the controls — only present once
                        // the video is initialized, and part of the auto-hiding
                        // chrome so it fades out completely when controls hide
                        // (the live video is then shown with no dark tint). Kept
                        // subtle: light top/bottom darkening, clear in the middle.
                        if (initialized)
                          DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.black.withValues(alpha: .28),
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: .38),
                                ],
                                stops: const [0.0, 0.45, 1.0],
                              ),
                            ),
                          ),
                        // Top-left: CricPro branding + LIVE pill (target layout).
                        Positioned(
                          left: 14,
                          top: 12,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.play_circle_fill_rounded,
                                      color: c.cyan, size: 20),
                                  const SizedBox(width: 6),
                                  const CricLogo(size: 16),
                                ],
                              ),
                              if (isLiveContent) ...[
                                const SizedBox(height: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 9, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: c.live,
                                    borderRadius: BorderRadius.circular(999),
                                    boxShadow: [
                                      BoxShadow(
                                        color: c.live.withValues(alpha: .45),
                                        blurRadius: 12,
                                        spreadRadius: -2,
                                      ),
                                    ],
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SizedBox(
                                        width: 6,
                                        height: 6,
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            shape: BoxShape.circle,
                                          ),
                                        ),
                                      ),
                                      SizedBox(width: 5),
                                      Text(
                                        'LIVE',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 10.5,
                                          letterSpacing: .4,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        // Top-right: viewers pill (when available) + quality pill.
                        Positioned(
                          right: 12,
                          top: 10,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (viewers != null && viewers!.isNotEmpty) ...[
                                _PlayerPill(
                                  label: viewers!,
                                  color: c.card2.withValues(alpha: .72),
                                  svgIcon:
                                      'assets/images/live_stream/icons/ic_eye_white.svg',
                                ),
                                const SizedBox(width: 8),
                              ],
                              _PlayerPill(
                                label: selectedQuality?.code.toUpperCase() ??
                                    (stream?.qualityCode.toUpperCase() ?? 'HD'),
                                color: c.card2.withValues(alpha: .72),
                                svgIcon:
                                    'assets/images/live_stream/icons/ic_signal_cyan.svg',
                              ),
                            ],
                          ),
                        ),
                        if (initialized && !playing)
                          Positioned.fill(
                            child: Center(
                              child: GestureDetector(
                                onTap: () {
                                  controller!.play();
                                  onControlInteraction();
                                },
                                child: SizedBox(
                                  width: 88,
                                  height: 88,
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      Image.asset(
                                        'assets/images/live_stream/overlays/neon_play_button.webp',
                                        width: 88,
                                        height: 88,
                                        excludeFromSemantics: true,
                                        errorBuilder: (_, __, ___) => Container(
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: Colors.black
                                                .withValues(alpha: .42),
                                            border: Border.all(
                                                color: c.cyan
                                                    .withValues(alpha: .6),
                                                width: 1.6),
                                            boxShadow: [
                                              BoxShadow(
                                                color: c.cyan
                                                    .withValues(alpha: .35),
                                                blurRadius: 22,
                                                spreadRadius: 2,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      SvgPicture.asset(
                                        'assets/images/live_stream/icons/ic_play_cyan.svg',
                                        width: 30,
                                        height: 30,
                                        colorFilter: ColorFilter.mode(
                                            c.cyan, BlendMode.srcIn),
                                        excludeFromSemantics: true,
                                        placeholderBuilder: (_) => Icon(
                                            Icons.play_arrow_rounded,
                                            color: c.cyan,
                                            size: 36),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        if (initialized)
                          Positioned(
                            left: 10,
                            right: 10,
                            bottom: 10,
                            child: _PortraitPlayerControls(
                              controller: controller!,
                              playing: playing,
                              isLiveContent: isLiveContent,
                              isMuted: isMuted,
                              onAnyInteraction: onControlInteraction,
                              onToggleMute: onToggleMute,
                              onSettings: onSettings,
                              onFullscreen: onFullscreen,
                              onSeekBackward: onSeekBackward,
                              onSeekForward: onSeekForward,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlayerPill extends StatelessWidget {
  const _PlayerPill({
    required this.label,
    required this.color,
    this.icon,
    this.svgIcon,
  });

  final String label;
  final Color color;
  final IconData? icon;
  final String? svgIcon;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.cyan.withValues(alpha: .3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (svgIcon != null)
            SvgPicture.asset(
              svgIcon!,
              width: 12,
              height: 12,
              colorFilter: ColorFilter.mode(c.cyan, BlendMode.srcIn),
              excludeFromSemantics: true,
              placeholderBuilder: (_) => Icon(Icons.signal_cellular_alt_rounded,
                  color: c.cyan, size: 11),
            )
          else if (icon != null)
            Icon(icon, color: Colors.white, size: 10),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 11,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

IconData _fitIcon(BoxFit fit) {
  return switch (fit) {
    BoxFit.cover => Icons.crop_free_rounded,
    BoxFit.fill => Icons.open_in_full_rounded,
    _ => Icons.fit_screen_rounded,
  };
}

class _VideoContent extends StatelessWidget {
  const _VideoContent({required this.controller, required this.fit});

  final VideoPlayerController controller;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final aspect = controller.value.aspectRatio == 0
        ? 16 / 9
        : controller.value.aspectRatio;
    if (fit == BoxFit.fill) {
      return SizedBox.expand(child: VideoPlayer(controller));
    }
    return FittedBox(
      fit: fit,
      child: SizedBox(
        width: aspect * 1000,
        height: 1000,
        child: VideoPlayer(controller),
      ),
    );
  }
}

class _PlayerErrorOverlay extends StatelessWidget {
  const _PlayerErrorOverlay({required this.message, required this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxHeight < 190;
          return Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 14 : 18,
                vertical: compact ? 8 : 14,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: c.warning,
                    size: compact ? 28 : 36,
                  ),
                  SizedBox(height: compact ? 6 : 10),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    maxLines: compact ? 2 : 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.text,
                      fontWeight: FontWeight.w900,
                      height: 1.25,
                      fontSize: compact ? 13 : 15,
                    ),
                  ),
                  if (onRetry != null) ...[
                    SizedBox(height: compact ? 8 : 14),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 170),
                      child: GradientButton(
                        label: 'Retry',
                        icon: Icons.refresh_rounded,
                        height: compact ? 38 : 44,
                        onTap: onRetry,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PortraitPlayerControls extends StatelessWidget {
  const _PortraitPlayerControls({
    required this.controller,
    required this.playing,
    required this.isLiveContent,
    required this.isMuted,
    required this.onToggleMute,
    required this.onSettings,
    required this.onFullscreen,
    required this.onSeekBackward,
    required this.onSeekForward,
    this.onAnyInteraction,
    this.fullscreenIcon = Icons.fullscreen_rounded,
  });

  final VideoPlayerController controller;
  final bool playing;
  final bool isLiveContent;
  final bool isMuted;
  final VoidCallback onToggleMute;
  final VoidCallback onSettings;
  final VoidCallback onFullscreen;
  final VoidCallback onSeekBackward;
  final VoidCallback onSeekForward;

  /// Optional hook fired on every control press so the host can restart its
  /// controls auto-hide countdown. Null in contexts that manage hiding
  /// differently (e.g. the fullscreen page schedules its own).
  final VoidCallback? onAnyInteraction;

  final IconData fullscreenIcon;

  static String _fmtTime(Duration d) {
    final s = d.inSeconds;
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = sec.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    const base = 'assets/images/live_stream/icons';
    final c = context.cric;
    final pos = controller.value.position;
    final dur = controller.value.duration;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Progress line + time labels.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: VideoProgressIndicator(
                  controller,
                  allowScrubbing: !isLiveContent,
                  padding: EdgeInsets.zero,
                  colors: VideoProgressColors(
                    playedColor: c.cyan,
                    bufferedColor: Colors.white24,
                    backgroundColor: Colors.white.withValues(alpha: .14),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(
                    _fmtTime(pos),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .9),
                      fontWeight: FontWeight.w700,
                      fontSize: 11.5,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    dur == Duration.zero ? 'LIVE' : _fmtTime(dur),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .9),
                      fontWeight: FontWeight.w700,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Long glass control bar.
        Container(
          height: 50,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .58),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: .1)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .3),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              _ctrl(
                context,
                svg: playing ? '$base/ic_pause_white.svg' : null,
                fallback:
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                onTap: () {
                  playing ? controller.pause() : controller.play();
                  onAnyInteraction?.call();
                },
              ),
              _divider(c),
              _ctrl(
                context,
                svg: '$base/ic_rewind_white.svg',
                fallback: Icons.replay_10_rounded,
                onTap: () {
                  onSeekBackward();
                  onAnyInteraction?.call();
                },
              ),
              _divider(c),
              _ctrl(
                context,
                svg: '$base/ic_forward_white.svg',
                fallback: Icons.forward_10_rounded,
                onTap: () {
                  onSeekForward();
                  onAnyInteraction?.call();
                },
              ),
              _divider(c),
              _ctrl(
                context,
                svg: '$base/ic_volume_white.svg',
                fallback: isMuted
                    ? Icons.volume_off_rounded
                    : Icons.volume_up_rounded,
                onTap: () {
                  onToggleMute();
                  onAnyInteraction?.call();
                },
              ),
              _divider(c),
              _ctrl(
                context,
                svg: '$base/ic_settings_white.svg',
                fallback: Icons.settings_rounded,
                onTap: onSettings,
              ),
              _divider(c),
              _ctrl(
                context,
                svg: '$base/ic_fullscreen_white.svg',
                fallback: fullscreenIcon,
                onTap: onFullscreen,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _divider(CricColors c) => Container(
        width: 1,
        height: 22,
        color: Colors.white.withValues(alpha: .12),
      );

  Widget _ctrl(
    BuildContext context, {
    String? svg,
    required IconData fallback,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 50,
          child: Center(
            child: svg != null
                ? SvgPicture.asset(
                    svg,
                    width: 20,
                    height: 20,
                    colorFilter:
                        const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                    excludeFromSemantics: true,
                    placeholderBuilder: (_) =>
                        Icon(fallback, color: Colors.white, size: 20),
                  )
                : Icon(fallback, color: Colors.white, size: 22),
          ),
        ),
      ),
    );
  }
}

