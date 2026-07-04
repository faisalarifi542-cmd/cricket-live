part of '../home_screen.dart';

class _HeroMatchCarousel extends StatefulWidget {
  const _HeroMatchCarousel({
    required this.future,
    required this.repository,
    required this.onOpenMatch,
    required this.onWatchLive,
    required this.streamEpoch,
    required this.onRetry,
    this.showDots = true,
  });

  final Future<List<CricketMatch>> future;
  final CricketRepository repository;
  final ValueChanged<String> onOpenMatch;
  final ValueChanged<String> onWatchLive;
  final int streamEpoch;
  final VoidCallback onRetry;
  final bool showDots;

  @override
  State<_HeroMatchCarousel> createState() => _HeroMatchCarouselState();
}

class _HeroMatchCarouselState extends State<_HeroMatchCarousel> {
  // Created lazily on first build so the viewportFraction can adapt to the
  // screen width and the controller can start on a middle page for looping.
  PageController? _controller;
  int _current = 0;
  bool _loop = false;

  // The match id currently centred in the carousel. Tracked so that when a
  // silent poll swaps in a fresh hero list (same matches, possibly reordered or
  // with a changed length) we can KEEP the same match visible instead of letting
  // the position-based PageView show whatever now sits at the old page index.
  String? _currentId;

  // Ids of the items the controller was last seated against, so we only re-seat
  // when the list identity/order actually changes (not on every score repaint).
  List<String> _seatedIds = const <String>[];

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  /// Re-seats the controller after the items change so the previously-visible
  /// match (by id) stays centred. No animation — a silent re-seat, scheduled
  /// post-frame because the controller's page metrics must exist first. Falls
  /// back to a clamped index when the old match is gone.
  void _reseatForItems(List<CricketMatch> items) {
    final newIds = [for (final m in items) m.id];
    if (listEquals(newIds, _seatedIds)) return; // identical order — nothing to do.
    final prevId = _currentId;
    _seatedIds = newIds;
    if (prevId == null) {
      _currentId = items.isNotEmpty ? items.first.id : null;
      return;
    }
    var target = newIds.indexOf(prevId);
    if (target < 0) {
      // Old match disappeared — clamp to the nearest valid index.
      target = _current.clamp(0, items.length - 1);
      _currentId = items.isEmpty ? null : items[target].id;
    } else {
      _currentId = prevId; // same match still present.
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctrl = _controller;
      if (!mounted || ctrl == null || !ctrl.hasClients) return;
      final page = _loop ? items.length * 1000 + target : target;
      if (ctrl.page?.round() != page) {
        ctrl.jumpToPage(page); // silent — no slide animation.
      }
      if (mounted) setState(() => _current = target);
    });
  }

  @override
  Widget build(BuildContext context) {
    final m = _HeroMetrics.of(context);
    final baseHeight = m.height;
    return FutureBuilder<List<CricketMatch>>(
      future: widget.future,
      builder: (context, snapshot) {
        final matches = snapshot.data ?? const <CricketMatch>[];
        final waiting = snapshot.connectionState == ConnectionState.waiting &&
            matches.isEmpty;
        if (waiting) return _HeroSkeleton(height: baseHeight);
        if (snapshot.hasError && matches.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: CricOfflineCard(onRetry: widget.onRetry, compact: true),
          );
        }
        if (matches.isEmpty) return _HeroEmpty(height: baseHeight);
        final items = matches.take(5).toList(growable: false);
        // A Test / multi-innings card needs two stacked score rows per team, so
        // the hero grows a touch taller when any visible match is multi-innings
        // — the score area gets real vertical room instead of being shrunk.
        final anyMulti = items.any(_heroIsMultiInnings);
        final heroHeight = baseHeight + (anyMulti ? 30 : 0);

        // Loop only when there is more than one item, so both left and right
        // neighbours are visible like the target.
        _loop = items.length > 1;
        _controller ??= PageController(
          viewportFraction: m.viewportFraction,
          initialPage: _loop ? items.length * 1000 : 0,
        );
        // Keep the same match centred when a poll swaps in a fresh/reordered
        // list (no-op when the order is unchanged).
        _reseatForItems(items);

        final itemCount = _loop ? items.length * 2000 : items.length;
        return Column(
          children: [
            SizedBox(
              height: heroHeight,
              child: PageView.builder(
                controller: _controller,
                itemCount: itemCount,
                clipBehavior: Clip.none,
                onPageChanged: (v) {
                  final ri = _loop ? v % items.length : v;
                  setState(() {
                    _current = ri;
                    if (ri >= 0 && ri < items.length) _currentId = items[ri].id;
                  });
                },
                itemBuilder: (context, index) {
                  final realIndex = _loop ? index % items.length : index;
                  return AnimatedBuilder(
                    key: ValueKey(items[realIndex].id),
                    animation: _controller!,
                    builder: (context, child) {
                      double diff = 0;
                      if (_controller!.position.haveDimensions) {
                        diff = (_controller!.page ?? index.toDouble()) - index;
                      }
                      final scale = (1 - diff.abs() * 0.04).clamp(0.95, 1.0);
                      final opacity = (1 - diff.abs() * 0.4).clamp(0.6, 1.0);
                      return Opacity(
                        opacity: opacity,
                        child: Transform.scale(scale: scale, child: child),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: _HeroMatchCard(
                        match: items[realIndex],
                        metrics: m,
                        repository: widget.repository,
                        streamEpoch: widget.streamEpoch,
                        onTap: () => widget.onOpenMatch(items[realIndex].id),
                        onWatchLive: widget.onWatchLive,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            if (widget.showDots)
              _CarouselDots(count: items.length, active: _current),
          ],
        );
      },
    );
  }
}

/// Responsive hero sizing resolved from both the available width and screen
/// height, so the hero stays balanced on short/narrow phones (no zoomed-in,
/// truncated content) and only grows on roomy devices.
class _HeroMetrics {
  const _HeroMetrics({
    required this.height,
    required this.logoSize,
    required this.scoreSize,
    required this.codeSize,
    required this.ctaHeight,
    required this.viewportFraction,
  });

  final double height;
  final double logoSize;
  final double scoreSize;
  final double codeSize;
  final double ctaHeight;
  final double viewportFraction;

  static _HeroMetrics of(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final w = size.width;
    final h = size.height;
    // Treat either a narrow width or a short screen as "small" so a tall-but-
    // narrow phone and a short device both get the compact hero.
    final small = w < 400 || h < 750;
    final wide = w >= 600;
    if (wide) {
      return const _HeroMetrics(
        height: 334,
        logoSize: 76,
        scoreSize: 42,
        codeSize: 25,
        ctaHeight: 48,
        viewportFraction: 0.88,
      );
    }
    if (small) {
      return const _HeroMetrics(
        height: 282,
        logoSize: 56,
        scoreSize: 31,
        codeSize: 20,
        ctaHeight: 44,
        viewportFraction: 0.965,
      );
    }
    // Normal phone.
    return const _HeroMetrics(
      height: 304,
      logoSize: 66,
      scoreSize: 37,
      codeSize: 22,
      ctaHeight: 46,
      viewportFraction: 0.94,
    );
  }
}

class _CarouselDots extends StatelessWidget {
  const _CarouselDots({required this.count, required this.active});

  final int count;
  final int active;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 3.5),
            width: i == active ? 18 : 8,
            height: 8,
            decoration: BoxDecoration(
              color: i == active
                  ? c.cyan
                  : c.dotInactive,
              borderRadius: BorderRadius.circular(99),
              boxShadow: i == active
                  ? [
                      BoxShadow(
                          color: c.cyan.withValues(alpha: .65), blurRadius: 9)
                    ]
                  : null,
            ),
          ),
      ],
    );
  }
}

class _HeroMatchCard extends StatelessWidget {
  const _HeroMatchCard({
    required this.match,
    required this.metrics,
    required this.repository,
    required this.streamEpoch,
    required this.onTap,
    required this.onWatchLive,
  });

  final CricketMatch match;
  final _HeroMetrics metrics;
  final CricketRepository repository;
  final int streamEpoch;
  final VoidCallback onTap;
  final ValueChanged<String> onWatchLive;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final live = match.isLive;
    final finished = match.isFinished;
    // Single source of truth for the badge + phase label, so the badge and the
    // center note never contradict (no generic "LIVE" while "Day 1: Stumps").
    final status = MatchStatusDisplay.of(context, match);
    final small = metrics.height < 320;
    // Slightly smaller, consistent logos across BOTH columns (premium, less
    // dominant). Test trims a touch more so the two stacked score rows fit
    // cleanly without scaling the logo down per-side (the old inconsistency).
    final heroMulti = _heroIsMultiInnings(match);
    final effLogo = heroMulti ? metrics.logoSize * 0.86 : metrics.logoSize;
    // A SHARED, fixed score-area height for BOTH columns so each block has the
    // same intrinsic size and the per-side FittedBox scales them identically —
    // keeping the two sides perfectly aligned whether a side shows a score,
    // stacked Test rows, or "Yet to bat". Test reserves room for two rows.
    final scoreBoxHeight = heroMulti ? (small ? 50.0 : 56.0) : (small ? 52.0 : 58.0);
    // Centre status note — driven by the shared status display so it matches the
    // badge. For a live stoppage this reads "Day 1 Stumps"/"Innings break"/…;
    // for a finished match, the result text; for upcoming, a LOCAL "Starts …"
    // note (matches the local date/time line above — the GMT vs local mismatch
    // the screenshots flagged).
    final note = live
        ? status.phaseLabel
        : finished
            ? status.phaseLabel
            : _heroUpcomingNote(match);
    return TapScale(
      onTap: onTap,
      borderRadius: 26,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: c.cyan.withValues(alpha: .55), width: 1.4),
          boxShadow: c.heroShadow,
        ),
        child: Stack(
          children: [
            const Positioned.fill(
              child: StadiumImage(
                _HAsset.heroBg,
                hero: true,
                alignment: Alignment.center,
                remoteKey: 'home_hero_bg_dark',
              ),
            ),
            // Readability overlay — keep the stadium visible at top, deepen
            // toward the bottom where the CTA sits.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: c.heroOverlayColors,
                    stops: const [0, .5, 1],
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(14, small ? 11 : 14, 14, small ? 12 : 16),
              child: Column(
                mainAxisSize: MainAxisSize.max,
                children: [
                  // Top row: LIVE badge + series title + star.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _StatusBadge(
                          label: status.badge,
                          color: status.color,
                          // Suppress the pulsing dot for a stoppage (stumps/lunch/
                          // tea/…) so the badge does not read "live now" while
                          // the note says "Day 1 Stumps".
                          live: status.subPhase == MatchSubPhase.live),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _heroTitle(match),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: c.cyan,
                            fontWeight: FontWeight.w800,
                            fontSize: small ? 13.5 : 15,
                            height: 1.15,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _HeroStarButton(small: small),
                    ],
                  ),
                  SizedBox(height: small ? 5 : 8),
                  // Date • time line.
                  Text(
                    _heroDateLine(match),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.text,
                      fontWeight: FontWeight.w700,
                      fontSize: small ? 12.5 : 14,
                    ),
                  ),
                  // Teams + scores fill the middle. Both team columns share the
                  // SAME fixed logo, code and score-box height, so each side's
                  // block has an identical intrinsic size and the shared
                  // FittedBox scales them by the SAME factor — the two logos /
                  // codes / score blocks always land on the same baseline (the
                  // batting-vs-bowling misalignment fix). The VS badge is
                  // centred between them.
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: _HeroTeamBlock(
                            name: match.teamA,
                            short: match.teamAShort,
                            logo: match.teamALogo,
                            accent: c.cyan,
                            logoSize: effLogo,
                            codeSize: metrics.codeSize,
                            scoreSize: metrics.scoreSize,
                            scoreBoxHeight: scoreBoxHeight,
                            innings: (live || finished)
                                ? match.teamAInnings
                                : const <InningsScore>[],
                            live: live,
                            currentInningsIndex: match.currentScoredIndexForTeam(
                                isTeamA: true),
                            // "Yet to bat" only while live and this innings has
                            // not started — never for upcoming matches.
                            placeholder:
                                (live && match.teamAInnings.isEmpty)
                                    ? 'Yet to bat'
                                    : '',
                          ),
                        ),
                        _HomeVsBadge(
                          width: small ? 46 : 54,
                          height: small ? 38 : 44,
                          intensity: 1.0,
                        ),
                        Expanded(
                          child: _HeroTeamBlock(
                            name: match.teamB,
                            short: match.teamBShort,
                            logo: match.teamBLogo,
                            accent: c.warning,
                            logoSize: effLogo,
                            codeSize: metrics.codeSize,
                            scoreSize: metrics.scoreSize,
                            scoreBoxHeight: scoreBoxHeight,
                            innings: (live || finished)
                                ? match.teamBInnings
                                : const <InningsScore>[],
                            live: live,
                            currentInningsIndex: match.currentScoredIndexForTeam(
                                isTeamA: false),
                            // "Yet to bat" only while live and this innings has
                            // not started — never for upcoming matches.
                            placeholder:
                                (live && match.teamBInnings.isEmpty)
                                    ? 'Yet to bat'
                                    : '',
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Status note — its own centered row so it never overlaps the
                  // team scores (the device bug). Long text ellipsis here; team
                  // scores never do.
                  if (note.isNotEmpty) ...[
                    SizedBox(height: small ? 4 : 6),
                    _HeroCenterPill(
                        label: homeShortStatus(note, match),
                        color: c.cyan,
                        small: small),
                    SizedBox(height: small ? 8 : 10),
                  ],
                  // Venue.
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.location_on_outlined, color: c.cyan, size: 15),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          shortVenue(match.venue).isEmpty
                              ? 'Venue TBC'
                              : shortVenue(match.venue),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: c.onImageText,
                            fontWeight: FontWeight.w600,
                            fontSize: small ? 11.5 : 12.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: small ? 8 : 12),
                  // CTA — "Watch Live" when an admin stream is available for this
                  // match, otherwise "Match Center". Defaults to Match Center and
                  // upgrades once availability resolves, so it never flickers.
                  _HeroCtaButton(
                    match: match,
                    repository: repository,
                    streamEpoch: streamEpoch,
                    height: metrics.ctaHeight,
                    onOpenMatch: onTap,
                    onWatchLive: () => onWatchLive(match.id),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// True when either team has batted more than once (Test / first-class), so the
/// hero should reserve room for two stacked score rows per team.
bool _heroIsMultiInnings(CricketMatch m) =>
    m.teamAInnings.where((i) => i.hasRuns).length > 1 ||
    m.teamBInnings.where((i) => i.hasRuns).length > 1;

/// Date • time line shown under the hero title, e.g. `9 Jun 2026 • 07:00 AM`.
String _heroDateLine(CricketMatch match) {
  final dt = match.startDateTime?.toLocal();
  if (dt == null) {
    // Never render a raw epoch `startTime` (e.g. 1782073800000) in the hero.
    return looksLikeRawTimestamp(match.startTime) ? '' : match.startTime;
  }
  return '${dt.day} ${_months[dt.month - 1]} ${dt.year} • ${_clock(dt)}';
}

/// Centre status note for an UPCOMING hero match, in the user's LOCAL time so it
/// agrees with [_heroDateLine] above — e.g. `Starts Jun 22 • 02:30 AM`. Never
/// shows a GMT time. Falls back to the provider status only when no start time
/// is available.
String _heroUpcomingNote(CricketMatch match) {
  final dt = match.startDateTime?.toLocal();
  if (dt == null) {
    return match.statusText.isNotEmpty ? match.statusText : 'Upcoming';
  }
  return 'Starts ${_months[dt.month - 1]} ${dt.day} • ${_clock(dt)}';
}

/// Small outlined star button in the hero top-right (favourite, visual only
/// for now — favourites are not yet wired).
class _HeroStarButton extends StatelessWidget {
  const _HeroStarButton({this.small = false});

  final bool small;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final d = small ? 32.0 : 36.0;
    return Container(
      width: d,
      height: d,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: c.isDark ? Colors.black.withValues(alpha: .28) : c.card,
        border: Border.all(color: c.cyan.withValues(alpha: .55), width: 1.2),
      ),
      alignment: Alignment.center,
      child: Icon(Icons.star_border_rounded,
          color: c.text.withValues(alpha: .9), size: small ? 18 : 20),
    );
  }
}

/// Centre status pill under the VS badge (e.g. "Innings Break").
class _HeroCenterPill extends StatelessWidget {
  const _HeroCenterPill(
      {required this.label, required this.color, this.small = false});

  final String label;
  final Color color;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xff05172b).withValues(alpha: .9),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .5)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: const Color(0xffd6f6ff),
          fontWeight: FontWeight.w800,
          fontSize: small ? 10.5 : 11.5,
          letterSpacing: .3,
        ),
      ),
    );
  }
}

/// Hero CTA that shows "Watch Live" when an admin stream is available for the
/// match, otherwise "Match Center". The availability check is cached per match
/// id so it never re-runs (or flickers) on score-poll repaints. Defaults to
/// Match Center and only upgrades to Watch Live once availability resolves true,
/// so a false Watch Live button is never shown.
class _HeroCtaButton extends StatefulWidget {
  const _HeroCtaButton({
    required this.match,
    required this.repository,
    required this.streamEpoch,
    required this.height,
    required this.onOpenMatch,
    required this.onWatchLive,
  });

  final CricketMatch match;
  final CricketRepository repository;
  final int streamEpoch;
  final double height;
  final VoidCallback onOpenMatch;
  final VoidCallback onWatchLive;

  @override
  State<_HeroCtaButton> createState() => _HeroCtaButtonState();
}

class _HeroCtaButtonState extends State<_HeroCtaButton> {
  Future<bool>? _streamFuture;
  String? _resolvedForId;
  int _resolvedEpoch = -1;

  // Watch Live is only meaningful for a live (or about-to-start) match — a
  // finished match never streams, so we skip the lookup entirely for it.
  bool get _eligible => !widget.match.isFinished;

  void _ensureFuture() {
    if (!_eligible) return;
    // Cache the lookup per (match, refresh-epoch): it does NOT re-run on score
    // poll repaints, but DOES re-run after a pull-to-refresh so a newly-added
    // stream is picked up. Force-refresh after a refresh epoch so the lookup
    // bypasses any remaining cache.
    if (_resolvedForId == widget.match.id &&
        _resolvedEpoch == widget.streamEpoch &&
        _streamFuture != null) {
      return;
    }
    _resolvedForId = widget.match.id;
    _resolvedEpoch = widget.streamEpoch;
    _streamFuture = widget.repository.shouldShowWatchLiveForMatch(
      widget.match,
      forceRefresh: widget.streamEpoch > 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_eligible) {
      return _HeroCtaPill(
        height: widget.height,
        label: 'Match Center',
        icon: Icons.chevron_right_rounded,
        watchLive: false,
        onTap: widget.onOpenMatch,
      );
    }
    _ensureFuture();
    return FutureBuilder<bool>(
      future: _streamFuture,
      builder: (context, snapshot) {
        final available = snapshot.data == true;
        if (available) {
          return _HeroCtaPill(
            height: widget.height,
            label: 'Watch Live',
            icon: Icons.play_circle_fill_rounded,
            watchLive: true,
            onTap: widget.onWatchLive,
          );
        }
        return _HeroCtaPill(
          height: widget.height,
          label: 'Match Center',
          icon: Icons.chevron_right_rounded,
          watchLive: false,
          onTap: widget.onOpenMatch,
        );
      },
    );
  }
}

/// Full-width gradient hero CTA pill. Cyan for Match Center, live-red for
/// Watch Live.
class _HeroCtaPill extends StatelessWidget {
  const _HeroCtaPill({
    required this.height,
    required this.label,
    required this.icon,
    required this.watchLive,
    required this.onTap,
  });

  final double height;
  final String label;
  final IconData icon;
  final bool watchLive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final compact = height < 46;
    final colors = watchLive
        ? const [Color(0xffff5a5f), Color(0xffe11d48)]
        : const [Color(0xff35e2ff), Color(0xff0a86ff)];
    final glow = watchLive ? c.live : c.cyan;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: height,
        // Not full-bleed: a centred pill with breathing room on the sides reads
        // more premium and balanced than an edge-to-edge bar.
        constraints: const BoxConstraints(maxWidth: 280),
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: c.isDark
              ? [
                  BoxShadow(
                    color: glow.withValues(alpha: .5),
                    blurRadius: 20,
                    spreadRadius: -4,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (watchLive) ...[
              Icon(icon, color: Colors.white, size: compact ? 19 : 21),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: compact ? 14 : 15,
                ),
              ),
            ] else ...[
              Text(
                label,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: compact ? 14 : 15,
                ),
              ),
              const SizedBox(width: 6),
              Icon(icon, color: Colors.white, size: compact ? 18 : 20),
            ],
          ],
        ),
      ),
    );
  }
}

/// Hero team block — big circular logo with glow ring, code, and big score.
class _HeroTeamBlock extends StatelessWidget {
  const _HeroTeamBlock({
    required this.name,
    required this.short,
    required this.logo,
    required this.accent,
    required this.logoSize,
    required this.codeSize,
    required this.scoreSize,
    required this.scoreBoxHeight,
    this.innings = const <InningsScore>[],
    this.placeholder = '',
    this.live = false,
    this.currentInningsIndex = -1,
  });

  final String name;
  final String short;
  final String? logo;
  final Color accent;
  final double logoSize;
  final double codeSize;
  final double scoreSize;
  final double scoreBoxHeight;
  final List<InningsScore> innings;
  final String placeholder;
  final bool live;
  final int currentInningsIndex;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final code = homeTeamCode(short, name);
    final isPlaceholder = code == 'TBC' || code == 'TBD' || code.isEmpty;
    final scoredCount = innings.where((i) => i.hasRuns).length;
    final hasScore = scoredCount > 0;
    final multi = scoredCount > 1;
    // Multi-innings (Test) uses stacked per-innings rows; the shared preset
    // clamps the row score to the premium 15–18 band and overs to 12–14 (white)
    // so two rows stay compact and readable.
    final mainSize = multi ? scoreSize * 0.50 : scoreSize;
    final oversSize = multi ? scoreSize * 0.40 : scoreSize * 0.46;

    // Both columns share the SAME logo, code and [scoreBoxHeight], so the two
    // blocks have an identical intrinsic size. The single FittedBox(scaleDown)
    // then scales each side by the SAME factor — logos stay the same size and
    // the codes/scores land on the same baseline (alignment fix). The score
    // sits in a fixed-height box (top-anchored) so a "Yet to bat" side reserves
    // the same height as a scoring side and never drops lower/higher.
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.topCenter,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border:
                  Border.all(color: accent.withValues(alpha: .85), width: 2.5),
              boxShadow: c.isDark
                  ? [
                      BoxShadow(
                        color: accent.withValues(alpha: .45),
                        blurRadius: 20,
                        spreadRadius: -2,
                      ),
                    ]
                  : null,
            ),
            padding: const EdgeInsets.all(2),
            child: TeamLogoWidget(
              logoUrl: isPlaceholder ? null : logo,
              teamName: name,
              abbreviation: code,
              color: accent,
              size: logoSize,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            code,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: c.text,
              fontWeight: FontWeight.w900,
              fontSize: codeSize,
              height: 1,
            ),
          ),
          SizedBox(
            height: scoreBoxHeight,
            child: (hasScore || placeholder.isNotEmpty)
                ? Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.topCenter,
                      child: TeamScoreView(
                        innings: innings,
                        mode: multi
                            ? ScoreDisplayMode.heroMultiInnings
                            : ScoreDisplayMode.heroLimitedOvers,
                        mainSize: mainSize,
                        oversSize: oversSize,
                        live: live,
                        currentInningsIndex: currentInningsIndex,
                        placeholder: placeholder,
                      ),
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

class _HeroSkeleton extends StatelessWidget {
  const _HeroSkeleton({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Container(
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: c.isDark ? c.card.withValues(alpha: .5) : c.card,
          border: Border.all(color: c.cyan.withValues(alpha: .3)),
        ),
        alignment: Alignment.center,
        child: CircularProgressIndicator(color: c.cyan),
      ),
    );
  }
}

class _HeroEmpty extends StatelessWidget {
  const _HeroEmpty({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Container(
        height: height,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: c.isDark ? c.card.withValues(alpha: .5) : c.card,
          border: Border.all(color: c.cyan.withValues(alpha: .3)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.sports_cricket_rounded, color: c.cyan, size: 32),
            const SizedBox(height: 10),
            Text(
              'No featured matches right now',
              style: TextStyle(color: c.text, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Status tabs (Live / Upcoming / Finished)
// ---------------------------------------------------------------------------

