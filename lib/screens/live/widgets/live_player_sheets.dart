part of '../live_player_screen.dart';

class _FullscreenVideoPage extends StatefulWidget {
  const _FullscreenVideoPage({
    required this.controller,
    required this.stream,
    required this.qualities,
    required this.selectedQuality,
    required this.videoFit,
    required this.isLiveContent,
    required this.isMuted,
    required this.onQualitySelected,
    required this.onFitChanged,
    required this.onGoLive,
    required this.onToggleMute,
    required this.onSeekBackward,
    required this.onSeekForward,
  });

  final VideoPlayerController controller;
  final StreamSource stream;
  final List<HlsQuality> qualities;
  final HlsQuality? selectedQuality;
  final BoxFit videoFit;
  final bool isLiveContent;
  final bool isMuted;
  final ValueChanged<HlsQuality> onQualitySelected;
  final ValueChanged<BoxFit> onFitChanged;
  final VoidCallback onGoLive;
  final VoidCallback onToggleMute;
  final VoidCallback onSeekBackward;
  final VoidCallback onSeekForward;

  @override
  State<_FullscreenVideoPage> createState() => _FullscreenVideoPageState();
}

class _FullscreenVideoPageState extends State<_FullscreenVideoPage> {
  late BoxFit _fit = widget.videoFit;
  bool _controlsVisible = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    // True fullscreen: force landscape and hide the status/navigation bars
    // using immersive sticky mode so the phone chrome never shows over video.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _scheduleHideControls();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    // Restore portrait + system UI when leaving fullscreen.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    super.dispose();
  }

  void _scheduleHideControls() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHideControls();
  }

  Future<void> _exit() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    if (mounted) Navigator.pop(context);
  }

  void _cycleFit() {
    final next = switch (_fit) {
      BoxFit.contain => BoxFit.cover,
      BoxFit.cover => BoxFit.fill,
      _ => BoxFit.contain,
    };
    setState(() => _fit = next);
    widget.onFitChanged(next);
    _scheduleHideControls();
    final label = switch (next) {
      BoxFit.cover => 'Fill',
      BoxFit.fill => 'Stretch',
      _ => 'Fit',
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(label),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 900),
      ),
    );
  }

  void _openQuality() {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: _QualitySelectorPanel(
          selectedStream: widget.stream,
          qualities: widget.qualities,
          selectedQuality: widget.selectedQuality,
          landscape: true,
          onQualitySelected: (quality) {
            Navigator.pop(context);
            widget.onQualitySelected(quality);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exit();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: ValueListenableBuilder<VideoPlayerValue>(
          valueListenable: widget.controller,
          builder: (context, value, _) {
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleControls,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Center(
                    child:
                        _VideoContent(controller: widget.controller, fit: _fit),
                  ),
                  // Dim layer + controls only while visible.
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 220),
                    opacity: _controlsVisible ? 1 : 0,
                    child: IgnorePointer(
                      ignoring: !_controlsVisible,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.black.withValues(alpha: .45),
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: .55),
                                ],
                              ),
                            ),
                          ),
                          SafeArea(
                            child: Stack(
                              children: [
                                Positioned(
                                  left: 8,
                                  top: 8,
                                  child: _FullscreenIconButton(
                                    icon: Icons.close_rounded,
                                    onTap: _exit,
                                    tooltip: 'Exit fullscreen',
                                  ),
                                ),
                                Positioned(
                                  right: 8,
                                  top: 8,
                                  child: _FullscreenIconButton(
                                    icon: _fitIcon(_fit),
                                    onTap: _cycleFit,
                                    tooltip: 'Change video fit',
                                  ),
                                ),
                                // Center play/pause with cyan glow (same style
                                // as the portrait player).
                                Center(
                                  child: GestureDetector(
                                    onTap: () {
                                      value.isPlaying
                                          ? widget.controller.pause()
                                          : widget.controller.play();
                                      _scheduleHideControls();
                                    },
                                    child: Container(
                                      width: 66,
                                      height: 66,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color:
                                            Colors.black.withValues(alpha: .42),
                                        border: Border.all(
                                          color: c.cyan.withValues(alpha: .55),
                                          width: 1.5,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color:
                                                c.cyan.withValues(alpha: .25),
                                            blurRadius: 18,
                                            spreadRadius: 1,
                                          ),
                                        ],
                                      ),
                                      child: Icon(
                                        value.isPlaying
                                            ? Icons.pause_rounded
                                            : Icons.play_arrow_rounded,
                                        color: Colors.white,
                                        size: 38,
                                      ),
                                    ),
                                  ),
                                ),
                                // Bottom-left LIVE badge.
                                if (widget.isLiveContent)
                                  Positioned(
                                    left: 16,
                                    bottom: 84,
                                    child: _PlayerPill(
                                      label: 'LIVE',
                                      color: value.isPlaying ? c.live : c.card2,
                                      icon: Icons.circle,
                                    ),
                                  ),
                                // Bottom glass control bar — same design as
                                // the portrait player, adapted to landscape.
                                Positioned(
                                  left: 16,
                                  right: 16,
                                  bottom: 14,
                                  child: _PortraitPlayerControls(
                                    controller: widget.controller,
                                    playing: value.isPlaying,
                                    isLiveContent: widget.isLiveContent,
                                    isMuted: widget.isMuted,
                                    onToggleMute: widget.onToggleMute,
                                    onSettings: _openQuality,
                                    onFullscreen: _exit,
                                    onSeekBackward: widget.onSeekBackward,
                                    onSeekForward: widget.onSeekForward,
                                    fullscreenIcon:
                                        Icons.fullscreen_exit_rounded,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _FullscreenIconButton extends StatelessWidget {
  const _FullscreenIconButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;

  /// Accessible name for this icon-only overlay control.
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: .45),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white24),
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
        ),
      ),
    );
  }
}

/// Simple info bottom sheet used for "Live Commentary" (coming soon) and other
/// short messages. Keeps the premium dark/cyan style with no overflow.
class _InfoSheet extends StatelessWidget {
  const _InfoSheet({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: c.isDark
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xff0a1929).withValues(alpha: .98),
                    const Color(0xff0f2744).withValues(alpha: .98),
                  ],
                )
              : c.cardGradient,
          border: Border.all(color: c.cyan.withValues(alpha: .35)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: c.primaryGradient,
                boxShadow: [
                  BoxShadow(
                    color: c.cyan.withValues(alpha: .34),
                    blurRadius: 18,
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 26),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: c.text,
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: c.muted,
                fontWeight: FontWeight.w600,
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Live match stats bottom sheet. Surfaces the score/status data already
/// fetched for the match. Falls back gracefully when fields are missing.
class _StatsSheet extends StatelessWidget {
  const _StatsSheet({required this.detail, required this.liveLine});

  final Map<String, dynamic> detail;
  final Map<String, dynamic>? liveLine;

  String _teamLabel(Map<String, dynamic> team) {
    return apiString(
      team['short_name'] ?? team['shortName'] ?? team['name'],
      'TBD',
    );
  }

  String _teamScore(Map<String, dynamic> team) {
    final innings = apiList(team['innings']);
    if (innings.isEmpty) return '—';
    final first = apiMap(innings.first);
    final runs = apiInt(first['runs']);
    if (runs == null) return '—';
    final wickets = apiInt(first['wickets']);
    final overs = apiString(first['overs']);
    final score = wickets == null ? '$runs' : '$runs/$wickets';
    final overs2 = normalizeOversText(overs);
    return overs2.isEmpty ? score : '$score ($overs2)';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final team1 = apiMap(detail['team1']);
    final team2 = apiMap(detail['team2']);
    final status = apiString(
      detail['status_text'] ??
          liveLine?['statusText'] ??
          liveLine?['status'] ??
          detail['status'],
      'Match details will update shortly.',
    );
    final rows = <List<String>>[
      [_teamLabel(team1), _teamScore(team1)],
      [_teamLabel(team2), _teamScore(team2)],
    ];

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(16),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .7,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: c.isDark
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xff0a1929).withValues(alpha: .98),
                    const Color(0xff0f2744).withValues(alpha: .98),
                  ],
                )
              : c.cardGradient,
          border: Border.all(color: c.cyan.withValues(alpha: .35)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
              child: Row(
                children: [
                  Icon(Icons.bar_chart_rounded, color: c.cyan, size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Match Stats',
                      style: TextStyle(
                        color: c.text,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Close',
                    icon: Icon(Icons.close_rounded, color: c.text),
                  ),
                ],
              ),
            ),
            Divider(color: c.border.withValues(alpha: .35), height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final row in rows) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: c.card2.withValues(alpha: .42),
                          borderRadius: BorderRadius.circular(14),
                          border:
                              Border.all(color: c.border.withValues(alpha: .3)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                row[0],
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: c.text,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              row[1],
                              style: TextStyle(
                                color: c.cyan,
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      status,
                      style: TextStyle(
                        color: c.muted,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        height: 1.4,
                      ),
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

// More Options Bottom Sheet
class _MoreOptionsSheet extends StatelessWidget {
  const _MoreOptionsSheet({required this.matchId});

  final String matchId;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: c.isDark
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xff0a1929).withValues(alpha: .98),
                  const Color(0xff0f2744).withValues(alpha: .98),
                ],
              )
            : c.cardGradient,
        border: Border.all(color: c.cyan.withValues(alpha: .35)),
        boxShadow: [
          BoxShadow(
            color: c.isDark
                ? Colors.black.withValues(alpha: .6)
                : const Color(0xff4a7fb5).withValues(alpha: .18),
            blurRadius: 40,
            spreadRadius: 4,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: c.border.withValues(alpha: .4)),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: c.primaryGradient,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.more_horiz_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'More Options',
                    style: TextStyle(
                      color: c.text,
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                    ),
                  ),
                ),
                InkWell(
                  onTap: () => Navigator.pop(context),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: c.card2,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.close_rounded, color: c.text, size: 20),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _MoreOption(
                  icon: Icons.info_outline_rounded,
                  label: 'Stream Info',
                  onTap: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Stream info for match $matchId'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                _MoreOption(
                  icon: Icons.refresh_rounded,
                  label: 'Refresh Stream',
                  onTap: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Refreshing stream...'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                _MoreOption(
                  icon: Icons.report_outlined,
                  label: 'Report Issue',
                  onTap: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Report issue feature coming soon'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MoreOption extends StatelessWidget {
  const _MoreOption({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: c.card2.withValues(alpha: .3),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.border.withValues(alpha: .25)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: c.cyan.withValues(alpha: .15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: c.cyan, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: c.text,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, color: c.muted, size: 18),
          ],
        ),
      ),
    );
  }
}

// HLS Quality Model
class HlsQuality {
  const HlsQuality({
    required this.label,
    required this.code,
    required this.resolution,
    required this.url,
    required this.rank,
    this.bandwidth,
    this.source = 'hlsVariant',
  });

  final String label;
  final String code;
  final String resolution;
  final String url;
  final int rank;
  final int? bandwidth;
  final String source;
}

// Settings Bottom Sheet
class _QualitySelectorPanel extends StatelessWidget {
  const _QualitySelectorPanel({
    required this.selectedStream,
    required this.qualities,
    required this.selectedQuality,
    required this.landscape,
    required this.onQualitySelected,
  });

  final StreamSource selectedStream;
  final List<HlsQuality> qualities;
  final HlsQuality? selectedQuality;
  final bool landscape;
  final ValueChanged<HlsQuality> onQualitySelected;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final screen = MediaQuery.sizeOf(context);
    // Compact sheet — never covers most of the screen.
    final maxHeight = screen.height * (landscape ? .8 : .55);
    final maxWidth = landscape ? screen.width * .5 : double.infinity;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: maxHeight,
          maxWidth: maxWidth,
          minWidth: landscape ? 320 : 0,
        ),
        child: Container(
          margin: EdgeInsets.all(landscape ? 0 : 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: c.isDark
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xff0a1929).withValues(alpha: .99),
                      const Color(0xff0f2744).withValues(alpha: .99),
                    ],
                  )
                : c.cardGradient,
            border: Border.all(color: c.cyan.withValues(alpha: .3)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .55),
                blurRadius: 28,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Compact header: icon + "Quality" + close.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 10),
                child: Row(
                  children: [
                    Icon(Icons.settings_rounded, color: c.cyan, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Quality',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.text,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () => Navigator.pop(context),
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child:
                            Icon(Icons.close_rounded, color: c.muted, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
              Divider(color: c.border.withValues(alpha: .3), height: 1),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  itemCount: qualities.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final quality = qualities[index];
                    return _QualityOption(
                      quality: quality,
                      selected: selectedQuality == null
                          ? index == 0
                          : selectedQuality!.url == quality.url,
                      onTap: () => onQualitySelected(quality),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QualityOption extends StatelessWidget {
  const _QualityOption({
    required this.quality,
    required this.selected,
    required this.onTap,
  });

  final HlsQuality quality;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? c.cyan.withValues(alpha: .1) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? c.cyan.withValues(alpha: .7) : Colors.transparent,
            width: 1.2,
          ),
        ),
        child: Row(
          children: [
            // Small badge pill (AUTO/FHD/HD/SD).
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: selected ? c.cyan : c.card2,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                quality.code,
                style: TextStyle(
                  color: selected ? Colors.black : c.muted,
                  fontWeight: FontWeight.w900,
                  fontSize: 9,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Row(
                children: [
                  Text(
                    quality.label,
                    style: TextStyle(
                      color: c.text,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    quality.resolution,
                    style: TextStyle(
                      color: selected ? c.cyan : c.muted,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected ? c.cyan : c.muted.withValues(alpha: .6),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}
