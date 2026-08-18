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
    if (listEquals(newIds, _seatedIds)) {
      return; // identical order — nothing to do.
    }
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
        if (waiting) {
          return Padding(
            padding: EdgeInsets.symmetric(horizontal: m.heroMargin),
            child: _HeroSkeleton(height: baseHeight),
          );
        }
        if (snapshot.hasError && matches.isEmpty) {
          return Padding(
            padding: EdgeInsets.symmetric(horizontal: m.heroMargin),
            child: CricOfflineCard(onRetry: widget.onRetry, compact: true),
          );
        }
        if (matches.isEmpty) {
          return Padding(
            padding: EdgeInsets.symmetric(horizontal: m.heroMargin),
            child: _HeroEmpty(height: baseHeight),
          );
        }
        final items = matches.take(5).toList(growable: false);
        // The hero height is now content-driven (see _HeroMetrics.of): it
        // already accounts for the team column's intrinsic min height and a
        // safety allowance, so a multi-innings (Test) card no longer needs a
        // separate +30 boost — the height is correct for both single and
        // multi-innings content.
        final heroHeight = baseHeight;

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
            // The PageView viewport is inset by the small hero margin on each
            // side (the ListView is full-bleed), so the active card spans almost
            // the whole screen with only a thin peek of its neighbours.
            Padding(
              padding: EdgeInsets.symmetric(horizontal: m.heroMargin),
              child: SizedBox(
                height: heroHeight,
                child: PageView.builder(
                  controller: _controller,
                  itemCount: itemCount,
                  clipBehavior: Clip.none,
                  onPageChanged: (v) {
                    final ri = _loop ? v % items.length : v;
                    setState(() {
                      _current = ri;
                      if (ri >= 0 && ri < items.length) {
                        _currentId = items[ri].id;
                      }
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
                          diff =
                              (_controller!.page ?? index.toDouble()) - index;
                        }
                        // Keep neighbours nearly full-size: the carousel's
                        // measured 4-8px exposure must not be erased by a
                        // dramatic scale-down at the viewport edge.
                        final scale = (1 - diff.abs() * 0.01).clamp(0.985, 1.0);
                        final opacity = (1 - diff.abs() * 0.4).clamp(0.6, 1.0);
                        return Opacity(
                          opacity: opacity,
                          child: Transform.scale(scale: scale, child: child),
                        );
                      },
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: m.gutter),
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
            ),
            // Small-screen spacing pass (#5): give the carousel dots more
            // separation from the card on compact phones so they don't read as
            // attached to it. Larger phones keep the tighter 14px.
            SizedBox(height: m.small ? 20 : 14),
            if (widget.showDots)
              _CarouselDots(count: items.length, active: _current),
          ],
        );
      },
    );
  }
}

/// Hero aspect ratio (width ÷ height). The premium target is a landscape hero;
/// this is the AUTHORITATIVE geometry at text scale 1.0 — height is derived from
/// the rendered card width, not from content. Content is bounded to fit inside
/// it. Central of the 1.32–1.38 target band.
const double kHeroAspect = 1.34;

/// Active-card width at/below which the compact hero layout engages (shorter CTA,
/// forced single-line venue, smaller emblem floor). Keyed off the RESOLVED card
/// width — not raw screen width — so split-screen / desktop windows / constrained
/// parents pick the layout from the actual constraints they render at.
/// 350 (was 340) so 372-wide compact phones (~349px resolved card) get the
/// compact treatment too — they share the same crowding constraints as the
/// 352-class devices.
const double kCompactHeroCardWidth = 350.0;

/// Public, immutable snapshot of the hero's width-derived geometry. Exposed so
/// tests can assert the aspect contract — and that ordinary content never drives
/// the height — using the SAME calculation production renders with (via
/// [calculateHomeHeroDiagnostics]). Not consumed at runtime beyond being produced
/// inside [_HeroMetrics].
@immutable
class HomeHeroLayoutDiagnostics {
  const HomeHeroLayoutDiagnostics({
    required this.cardWidth,
    required this.aspectHeight,
    required this.contentFloor,
    required this.finalHeight,
    required this.logoSize,
    required this.scoreSize,
    required this.vsWidth,
    required this.ctaHeight,
  });

  /// Rendered active-card width (screen − margins, × viewportFraction − gutters).
  final double cardWidth;

  /// Height purely from `cardWidth / kHeroAspect` (the landscape contract).
  final double aspectHeight;

  /// Minimum height the bounded chrome needs (overflow safety only).
  final double contentFloor;

  /// `max(aspectHeight, contentFloor)`, clamped — the height the card renders at.
  final double finalHeight;
  final double logoSize;
  final double scoreSize;
  final double vsWidth;
  final double ctaHeight;

  /// True when the content floor (not the width-derived aspect) decided the
  /// height. Expected ONLY under accessibility text scaling / inflated font
  /// metrics, or on physically narrow cards where the bounded minimum content
  /// cannot fit a `kHeroAspect` box — never for ordinary data on a roomy card.
  bool get contentFloorActivated => contentFloor > aspectHeight + 0.5;

  double get ratio => finalHeight <= 0 ? 0 : cardWidth / finalHeight;
}

/// Resolved hero geometry + element sizes for one card width. The SINGLE source
/// of truth: both [_HeroMetrics.of] (production) and [calculateHomeHeroDiagnostics]
/// (tests) call [_heroGeom], so rendered layout and asserted geometry can never
/// diverge.
class _HeroGeom {
  const _HeroGeom({
    required this.cardWidth,
    required this.aspectHeight,
    required this.contentFloor,
    required this.finalHeight,
    required this.compact,
    required this.logo,
    required this.code,
    required this.score,
    required this.overs,
    required this.vsW,
    required this.vsH,
    required this.cta,
    required this.scoreBox,
  });

  final double cardWidth;
  final double aspectHeight;
  final double contentFloor;
  final double finalHeight;
  final bool compact;
  final double logo;
  final double code;
  final double score;
  final double overs;
  final double vsW;
  final double vsH;
  final double cta;
  final double scoreBox;
}

/// Computes hero geometry for a given card width + text scale. Pure — no
/// BuildContext — so tests can drive it directly with the production math.
_HeroGeom _heroGeom({
  required double cardWidth,
  required TextScaler textScaler,
  double fontHeightBoost = 0,
}) {
  final compact = cardWidth <= kCompactHeroCardWidth;

  // Continuous, width-based element sizes (NO small/normal branch that shrinks
  // large phones): floors keep narrow phones readable, caps keep tablets
  // balanced, and a wider card yields visibly bigger emblems/scores/VS.
  // Compact logo tracks width a touch slower (0.178 vs 0.185) so the emblem
  // row stops overflowing up into the date line on 352-class devices — the
  // chrome trims in [_HeroMatchCard] are the primary refinement; the logo
  // tweak is the tiny compact-only pair.
  final logo = (cardWidth * (compact ? 0.178 : 0.185))
      .clamp(compact ? 58.0 : 62.0, 86.0);
  final code = (cardWidth * 0.047).clamp(17.0, 22.0);
  // Score/overs hierarchy refinement: shave the primary score a hair on compact
  // + narrow cards so it stops visually swallowing the block, and lift the overs
  // floor so it reads as a real subordinate label instead of a whisper. Score
  // stays the largest element by a comfortable margin (still the widget-level
  // >= 24 floor asserted by home_score_resilience_test.dart).
  final score =
      (cardWidth * 0.074).clamp(compact ? 24.0 : 26.0, compact ? 30.0 : 34.0);
  final overs = (cardWidth * 0.033).clamp(11.5, 14.0);
  // Compact VS badge is a step smaller (floor 64 vs 68) so the emblems keep a
  // clear horizontal gap to it on 352-class cards.
  final vsW =
      (cardWidth * (compact ? 0.19 : 0.20)).clamp(compact ? 64.0 : 68.0, 94.0);
  final vsH = vsW * 0.85;
  final cta = compact ? 44.0 : 48.0; // honest compact 44 (no hidden hit area)

  // Score slot reserves ONE (current/latest) innings — big primary + overs. The
  // hero no longer stacks a previous-innings row (that lives in Match Details),
  // which is what frees the vertical room for the landscape proportion.
  final scoreBox = score + 2 + overs + 2;

  // Compact cards drop below the landscape band to a taller 1.25 proportion
  // (small-device breathing-room pass): 320–360px phones were squeezing the
  // score→overs→venue→CTA stack into a bottom-heavy block with the overs line
  // grazing the venue. The extra ~16px of height at 328px width is spent on
  // the enlarged overs→venue and venue→CTA gaps below, so the content reads
  // centered instead of crammed. Roomier cards keep the central 1.34 landscape
  // proportion so large/flagship devices are visually unchanged.
  final aspectHeight = cardWidth / (compact ? 1.25 : kHeroAspect);
  // At normal scale the four bounded regions are deliberately engineered to
  // fit the aspect box; ordinary data never changes this value. Accessibility
  // scaling and the explicit font-metric stress fixture may add bounded room.
  final scaledUnit = textScaler.scale(1.0);
  final accessibilityBoost = math.max(0.0, scaledUnit - 1.0) * 118.0;
  final metricBoost = math.max(0.0, fontHeightBoost) * 120.0;
  final contentFloor = aspectHeight + accessibilityBoost + metricBoost;
  final finalHeight =
      math.max(aspectHeight, contentFloor).clamp(220.0, 400.0).toDouble();

  return _HeroGeom(
    cardWidth: cardWidth,
    aspectHeight: aspectHeight,
    contentFloor: contentFloor,
    finalHeight: finalHeight,
    compact: compact,
    logo: logo,
    code: code,
    score: score,
    overs: overs,
    vsW: vsW,
    vsH: vsH,
    cta: cta,
    scoreBox: scoreBox,
  );
}

/// Resolves the active-card width from the screen width using the same margin +
/// viewport-fraction + gutter the carousel lays out with, so geometry math and
/// rendering agree. Shared by production and the diagnostics test hook.
({double cardWidth, double heroMargin, double gutter, double vf})
    _heroCardWidth(double screenWidth) {
  final w = screenWidth;
  // FULL-BLEED carousel: a small outside margin is the only gap to the screen
  // edge; a high viewport fraction leaves just a thin (~4–8px) neighbour peek.
  const heroMargin = 0.0;
  final gutter = w <= 360 ? 3.0 : (w <= 430 ? 2.0 : 4.0);
  final viewportW = w - heroMargin * 2;
  final vf = w >= 600 ? 0.90 : (w <= 430 ? 0.95 : 0.958);
  final cardW = (viewportW * vf) - gutter * 2;
  return (cardWidth: cardW, heroMargin: heroMargin, gutter: gutter, vf: vf);
}

/// Test hook: the production hero geometry for a given card width + text scale,
/// as a public diagnostics snapshot. Lets a widget test assert the aspect
/// contract and the content-floor invariant without reaching into private types.
@visibleForTesting
HomeHeroLayoutDiagnostics calculateHomeHeroDiagnostics({
  required double cardWidth,
  TextScaler textScaler = TextScaler.noScaling,
  double fontHeightBoost = 0,
}) {
  final g = _heroGeom(
    cardWidth: cardWidth,
    textScaler: textScaler,
    fontHeightBoost: fontHeightBoost,
  );
  return HomeHeroLayoutDiagnostics(
    cardWidth: g.cardWidth,
    aspectHeight: g.aspectHeight,
    contentFloor: g.contentFloor,
    finalHeight: g.finalHeight,
    logoSize: g.logo,
    scoreSize: g.score,
    vsWidth: g.vsW,
    ctaHeight: g.cta,
  );
}

/// Responsive hero sizing. Height follows the landscape aspect contract
/// ([kHeroAspect]) at text scale 1.0; content is bounded to fit inside it, with
/// a content floor guarding overflow under inflated text metrics.
class _HeroMetrics {
  const _HeroMetrics({
    required this.height,
    required this.cardWidth,
    required this.logoSize,
    required this.scoreSize,
    required this.oversSize,
    required this.codeSize,
    required this.ctaHeight,
    required this.vsWidth,
    required this.vsHeight,
    required this.viewportFraction,
    required this.heroMargin,
    required this.gutter,
    required this.scoreBoxHeight,
    required this.small,
    required this.aspectHeight,
    required this.contentFloor,
  });

  final double height;

  /// Resolved active-card width (screen − margins, × viewportFraction −
  /// gutters). Stored — never re-derived from [aspectHeight], because compact
  /// cards use a taller aspect (1.32) than [kHeroAspect], so
  /// `aspectHeight * kHeroAspect` no longer round-trips to the card width.
  final double cardWidth;
  final double logoSize;
  final double scoreSize;
  final double oversSize;
  final double codeSize;
  final double ctaHeight;
  final double vsWidth;
  final double vsHeight;
  final double viewportFraction;

  /// Outside horizontal gap between the carousel viewport and the screen edge.
  final double heroMargin;

  /// Per-side inner gutter inside each carousel page.
  final double gutter;

  /// Reserved min height for the single-innings score slot (primary + overs).
  final double scoreBoxHeight;

  /// Compact-hero flag (resolved from the CARD width, not the screen): shorter
  /// CTA, single-line venue, smaller emblem floor.
  final bool small;

  /// Height purely from the aspect contract, and the content-floor minimum —
  /// surfaced for the diagnostics test hook.
  final double aspectHeight;
  final double contentFloor;

  HomeHeroLayoutDiagnostics get diagnostics => HomeHeroLayoutDiagnostics(
        cardWidth: cardWidth,
        aspectHeight: aspectHeight,
        contentFloor: contentFloor,
        finalHeight: height,
        logoSize: logoSize,
        scoreSize: scoreSize,
        vsWidth: vsWidth,
        ctaHeight: ctaHeight,
      );

  static _HeroMetrics of(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final geomW = _heroCardWidth(w);
    final g = _heroGeom(
      cardWidth: geomW.cardWidth,
      textScaler: MediaQuery.textScalerOf(context),
    );

    return _HeroMetrics(
      height: g.finalHeight,
      cardWidth: geomW.cardWidth,
      logoSize: g.logo,
      scoreSize: g.score,
      oversSize: g.overs,
      codeSize: g.code,
      ctaHeight: g.cta,
      vsWidth: g.vsW,
      vsHeight: g.vsH,
      viewportFraction: geomW.vf,
      heroMargin: geomW.heroMargin,
      gutter: geomW.gutter,
      scoreBoxHeight: g.scoreBox,
      small: g.compact,
      aspectHeight: g.aspectHeight,
      contentFloor: g.contentFloor,
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
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == active ? 20 : 5,
            height: 5,
            decoration: BoxDecoration(
              color: i == active ? c.cyan : c.dotInactive,
              borderRadius: BorderRadius.circular(99),
              boxShadow: i == active
                  ? [
                      BoxShadow(
                          color: c.cyan.withValues(alpha: .38), blurRadius: 5)
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
    final small = metrics.small;
    final effLogo = metrics.logoSize;
    // Reserved MIN height for the score slot (primary score + overs). The hero
    // renders only the CURRENT/latest innings large (no stacked previous-innings
    // row — that lives in Match Details), which is what frees the vertical room
    // for the landscape aspect. Both sides share this reserve so a "Yet to bat"
    // side never pulls the VS or the opposing score off the shared baseline.
    final scoreBoxHeight = metrics.scoreBoxHeight;
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
    // Upcoming heroes never render a score: the score slot the team columns
    // reserve for live/finished states is reclaimed so the team row's real
    // height shrinks — this is what restores the visible breathing room
    // between the date row and the emblem row on compact phones (§B). The
    // full start date/time already lives in the date row above.
    final hasScores = live || finished;
    final effScoreBox = hasScores ? scoreBoxHeight : 0.0;
    // Honest team-row reserve: with scores it needs the full score slot PLUS
    // the emblem ring's border+padding (~3.5px beyond logoSize) and the code
    // row — the +12 slack covers that ring chrome and real-device font metric
    // inflation, so the column never reports a fractional bottom overflow.
    // An upcoming row is emblem + code OR the centre VS + "Starts Soon" pill
    // column, whichever is taller (VS badge + 5px gap + the 28px pill slot +
    // 3px slack). Reclaiming the unused score slot is what gives the date row
    // its breathing room: the Expanded centres this shorter row, so the
    // recovered height splits evenly above and below the emblems.
    final teamRowHeight = hasScores
        ? metrics.logoSize + metrics.codeSize + effScoreBox + 12
        : math.max(
            metrics.logoSize + metrics.codeSize + 8,
            metrics.vsHeight + 36,
          );
    return TapScale(
      onTap: onTap,
      borderRadius: 26,
      child: Container(
        key: ValueKey('home-hero-card-${match.id}'),
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
            Positioned.fill(
              child: ColoredBox(
                color: c.isDark
                    ? const Color(0xff020b18).withValues(alpha: .60)
                    : Colors.white.withValues(alpha: .08),
              ),
            ),
            // Home-local darker stadium treatment (Part 13): the base art has a
            // bright orange horizon directly behind the score/previous-innings
            // rows. A stronger dark navy gradient — deeper top + bottom + a
            // controlled mid-band — reduces the orange saturation and keeps the
            // floodlights subtle while scores stay readable without text glow.
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
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, -.05),
                      radius: .46,
                      colors: [
                        c.cyan.withValues(alpha: c.isDark ? .10 : .04),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // Extra mid-band scrim behind the team/score area so a bright
            // horizon never competes with the primary score text.
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        c.isDark
                            ? const Color(0xff031126).withValues(alpha: .44)
                            : Colors.white.withValues(alpha: .18),
                        c.isDark
                            ? const Color(0xff020b18).withValues(alpha: .56)
                            : Colors.white.withValues(alpha: .26),
                        Colors.transparent,
                      ],
                      stops: const [0.18, 0.40, 0.62, 0.80],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              // Compact vertical padding tightened 7→6 (small-screen spacing
              // pass): reclaimed chrome keeps a visible date→emblem gap on
              // 352-class phones without touching content sizes.
              padding:
                  EdgeInsets.fromLTRB(14, small ? 6 : 9, 14, small ? 6 : 9),
              child: Column(
                mainAxisSize: MainAxisSize.max,
                children: [
                  // Top row: category badge (LIVE/UPCOMING/FINISHED) + series
                  // title + star. Fixed height so a 1- vs 2-line title never
                  // shifts the layout below it (stable header region, §5). The
                  // badge shows the match STATE category — a live match reads red
                  // "LIVE" even at stumps; the session phase lives in the pill.
                  SizedBox(
                    height: small ? 32 : 37,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _StatusBadge(
                            label: live
                                ? 'LIVE'
                                : finished
                                    ? 'FINISHED'
                                    : 'UPCOMING',
                            color: live
                                ? c.live
                                : finished
                                    ? c.success
                                    : c.cyan,
                            live: live),
                        // Slightly more horizontal breathing room after the
                        // status badge so the flexible two-line competition
                        // title starts clear of the pill (§C).
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            _heroTitle(match),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            // Centred so a title wrapping to a second line stays
                            // centred (consistent with every other match card).
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: c.cyan,
                              fontWeight: FontWeight.w800,
                              fontSize: small ? 13.5 : 15,
                              height: 1.15,
                            ),
                          ),
                        ),
                        // Fixed gap + fixed-width favorite button, inset from the
                        // card edge so a long two-line title never collides with
                        // the star (§C).
                        const SizedBox(width: 10),
                        _HeroStarButton(small: small),
                      ],
                    ),
                  ),
                  SizedBox(height: small ? 1 : 5),
                  // Date • time line, with a leading calendar icon (§5).
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.calendar_month_rounded,
                          color: c.cyan, size: small ? 12.5 : 13.5),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          _heroDateLine(match),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: c.text,
                            fontWeight: FontWeight.w700,
                            fontSize: small ? 12.5 : 13.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  // Explicit separation between the bottom of the date/time row
                  // and the top of the emblem/VS row (§B): 14px on compact (the
                  // emblem row no longer overflows up into it after the chrome
                  // trims), 12px elsewhere. It is reclaimed from the flexible
                  // Expanded below, so the hero outer height/aspect is unchanged.
                  SizedBox(height: small ? 14 : 12),
                  // Teams + scores fill the middle. Both team columns share the
                  // SAME fixed logo, code and score-box height, so each side's
                  // block has an identical intrinsic size and the shared
                  // FittedBox scales them by the SAME factor — the two logos /
                  // codes / score blocks always land on the same baseline (the
                  // batting-vs-bowling misalignment fix). The VS badge is
                  // centred between them.
                  Expanded(
                    child: OverflowBox(
                      alignment: Alignment.center,
                      minHeight: teamRowHeight,
                      maxHeight: teamRowHeight,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Left team — bounded flex ≈ 36% (§7).
                          Expanded(
                            flex: 36,
                            child: _HeroTeamBlock(
                              name: match.teamA,
                              short: match.teamAShort,
                              logo: match.teamALogo,
                              accent: c.cyan,
                              logoSize: effLogo,
                              codeSize: metrics.codeSize,
                              scoreSize: metrics.scoreSize,
                              oversSize: metrics.oversSize,
                              scoreBoxHeight: effScoreBox,
                              innings: (live || finished)
                                  ? match.teamAInnings
                                  : const <InningsScore>[],
                              live: live,
                              currentInningsIndex: match
                                  .currentScoredIndexForTeam(isTeamA: true),
                              showInningsOrdinal:
                                  match.teamAInnings.length > 1 ||
                                      match.teamBInnings.length > 1,
                              // "Yet to bat" only while live and this innings has
                              // not started — never for upcoming matches.
                              placeholder: (live && match.teamAInnings.isEmpty)
                                  ? 'Yet to bat'
                                  : '',
                            ),
                          ),
                          // Centre column ≈ 28% (§7): a larger VS visual, then a
                          // green LIVE pill, then a neutral phase pill when in a
                          // break. The pills live WITH the scores so they never
                          // consume a separate full-width row.
                          Expanded(
                            flex: 28,
                            child: _HeroCenterColumn(
                              small: small,
                              status: status,
                              note: note,
                              match: match,
                              vsWidth: metrics.vsWidth,
                              vsHeight: metrics.vsHeight,
                            ),
                          ),
                          // Right team — bounded flex ≈ 36% (§7).
                          Expanded(
                            flex: 36,
                            child: _HeroTeamBlock(
                              name: match.teamB,
                              short: match.teamBShort,
                              logo: match.teamBLogo,
                              accent: c.warning,
                              logoSize: effLogo,
                              codeSize: metrics.codeSize,
                              scoreSize: metrics.scoreSize,
                              oversSize: metrics.oversSize,
                              scoreBoxHeight: effScoreBox,
                              innings: (live || finished)
                                  ? match.teamBInnings
                                  : const <InningsScore>[],
                              live: live,
                              currentInningsIndex: match
                                  .currentScoredIndexForTeam(isTeamA: false),
                              showInningsOrdinal:
                                  match.teamAInnings.length > 1 ||
                                      match.teamBInnings.length > 1,
                              // "Yet to bat" only while live and this innings has
                              // not started — never for upcoming matches.
                              placeholder: (live && match.teamBInnings.isEmpty)
                                  ? 'Yet to bat'
                                  : '',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Reserved gap under overs so the OVERS line always sits above
                  // the venue row on narrow devices (352px class). Widened on
                  // compact (6→11) with the taller 1.25 aspect so the venue never
                  // appears connected to the overs row — the two read as clearly
                  // separate lines with breathing room on 320–360px phones.
                  SizedBox(height: small ? 11 : 8),
                  // Venue divider + row (§11). One line (premium + fits the
                  // landscape aspect); the FULL untruncated venue is exposed to
                  // accessibility via Semantics even when the visible text
                  // ellipsises. On compact cards the decorative divider is
                  // dropped — spacing alone separates the score block from the
                  // venue, and the 1px line could graze the overs text.
                  if (!small) ...[
                    const _HeroVenueDivider(),
                    const SizedBox(height: 8),
                  ],
                  Builder(builder: (context) {
                    final full = match.venue.trim().isEmpty
                        ? 'Venue TBC'
                        : match.venue.trim();
                    return Semantics(
                      container: true,
                      label: full,
                      child: ExcludeSemantics(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.location_on_outlined,
                                color: c.cyan, size: small ? 15 : 16.5),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                full,
                                maxLines: small ? 1 : 2,
                                textAlign: TextAlign.center,
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
                      ),
                    );
                  }),
                  // Top margin above the CTA. Widened on compact (6→13) so the
                  // Match Center button reads as visually separated from the
                  // venue row instead of butting up against it (§3).
                  SizedBox(height: small ? 13 : 10),
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

/// Thin cyan gradient divider between the score content and the venue row, for
/// a clean broadcast-style separation (§11). Restrained — no glow.
class _HeroVenueDivider extends StatelessWidget {
  const _HeroVenueDivider();

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.transparent,
            c.cyan.withValues(alpha: c.isDark ? .22 : .18),
            Colors.transparent,
          ],
        ),
      ),
    );
  }
}

/// Date • time line shown under the hero title, e.g. `9 Jun 2026 • 07:00 AM`.
String _heroDateLine(CricketMatch match) {
  final dt = match.startDateTime?.toLocal();
  if (dt == null) {
    // Never render a raw epoch `startTime` (e.g. 1782073800000) in the hero.
    return looksLikeRawTimestamp(match.startTime) ? '' : match.startTime;
  }
  return '${dt.day} ${_months[dt.month - 1]} ${dt.year} • ${_clock(dt)}';
}

/// Centre status pill label for an UPCOMING hero match. Deliberately a SHORT,
/// complete label ("Starts Soon") — the centre column under VS is ~28% of the
/// card width, so the previous "Starts Jun 22 • 02:30 AM" note truncated to
/// "Starts J..." on compact phones (§2). The full local date/time already
/// renders in the hero date row above, so the pill never repeats it.
String _heroUpcomingNote(CricketMatch match) => 'Starts Soon';

/// Small outlined star button in the hero top-right (favourite, visual only
/// for now — favourites are not yet wired).
class _HeroStarButton extends StatelessWidget {
  const _HeroStarButton({this.small = false});

  final bool small;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    // Compact star is a step smaller (30 vs 34) so it clears a two-line series
    // title inside the tightened 32px compact header row.
    final d = small ? 30.0 : 38.0;
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
          color: c.text.withValues(alpha: .9), size: small ? 17 : 21),
    );
  }
}

/// Centre column of the hero team row (Part 15): a larger VS visual, then a
/// green LIVE-state pill, then a neutral phase pill (Stumps/Lunch/…) when the
/// match is in a break. For a finished match the result pill shows; for an
/// upcoming match the "Starts …" note shows. The pills stay vertically
/// compact so they never push the scores out of the Expanded team row.
class _HeroCenterColumn extends StatelessWidget {
  const _HeroCenterColumn({
    required this.small,
    required this.status,
    required this.note,
    required this.match,
    required this.vsWidth,
    required this.vsHeight,
  });

  final bool small;
  final MatchStatusDisplay status;
  final String note;
  final CricketMatch match;
  final double vsWidth;
  final double vsHeight;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final live = match.isLive;
    // Centralized decision so hero + list cards never disagree: a real break
    // phase (Stumps/Lunch/Tea/Drinks/Rain/Innings Break) overrides the generic
    // LIVE pill as the PRIMARY status. Non-live matches fall back to the
    // note/date-time pill below.
    final pill = homeCenterPillFor(status, match);
    final showNotePill = !live && note.isNotEmpty;
    final notePill = showNotePill ? homeShortStatus(note, match) : '';
    // The centre column is only ~28% of the card width, which is what forced
    // "Starts Jun 22 • 02:30 AM" into "Starts J..." (§2). An UPCOMING hero has
    // no scores beside the pill, so its note pill may take its intrinsic width
    // (bounded) and paint past the column into that empty space — the short
    // "Starts Soon" label then always renders complete. Live/finished pills
    // keep the column-constrained layout (scores flank them).
    final upcoming = !live && !match.isFinished;
    // Compact baseline nudge (§4): when a status pill renders below the VS badge
    // it pulls the badge up off the team-block centre (measured ~6px high on
    // 352-class cards, because the pill adds height only BELOW the badge). Shift
    // the whole centre stack down a few px so the badge lands back on the shared
    // logo/score centre line. Using a paint-only Transform (not a SizedBox) keeps
    // this at zero layout cost, so it can never overflow the tight upcoming hero.
    final nudge = small && (pill != null || showNotePill);
    final column = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _HomeVsBadge(
          width: vsWidth,
          height: vsHeight,
          intensity: 1.0,
        ),
        if (pill != null) ...[
          SizedBox(height: small ? 6 : 8),
          _HeroCenterPill(
            label: pill.label,
            color: pill.isPhase ? c.muted : c.success,
            icon: pill.isPhase ? null : Icons.podcasts_rounded,
            small: small,
          ),
        ],
        if (showNotePill) ...[
          SizedBox(height: small ? 6 : 5),
          if (upcoming)
            // Fixed-height slot; the pill widens beyond the column bounds
            // without triggering debug overflow (OverflowBox, not
            // UnconstrainedBox). 180 comfortably fits "Starts Soon" even under
            // wide test-font metrics; with real device fonts the pill sizes to
            // its ~100px intrinsic width and still clears both emblems on a
            // 352-wide device.
            SizedBox(
              height: 28,
              child: OverflowBox(
                maxWidth: 180,
                maxHeight: 36,
                alignment: Alignment.center,
                child: _HeroCenterPill(
                  label: notePill,
                  color: c.muted,
                  small: small,
                ),
              ),
            )
          else
            _HeroCenterPill(
              label: notePill,
              color: match.isFinished ? c.success : c.muted,
              small: small,
            ),
        ],
      ],
    );
    return nudge
        ? Transform.translate(offset: const Offset(0, 6), child: column)
        : column;
  }
}

/// Centre status pill under the VS badge (e.g. "Innings Break"). When [icon] is
/// supplied it renders a leading glyph (a broadcast icon for the live pill).
class _HeroCenterPill extends StatelessWidget {
  const _HeroCenterPill(
      {required this.label,
      required this.color,
      this.small = false,
      this.icon});

  final String label;
  final Color color;
  final bool small;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    // Text reads as a near-white tinted toward the accent, so a green live pill
    // shows green-white text and a cyan pill stays cyan-white.
    final textColor =
        Color.alphaBlend(color.withValues(alpha: .30), Colors.white);
    return Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: EdgeInsets.symmetric(
          horizontal: icon != null ? 12.5 : (small ? 11 : 15),
          vertical: small ? 7 : 5),
      decoration: BoxDecoration(
        color: const Color(0xff05172b).withValues(alpha: .9),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: color, size: small ? 12.5 : 14),
            const SizedBox(width: 5),
          ],
          // Scale-to-fit, NEVER mid-word ellipsis: the hero centre column is
          // only ~28% of the card, which used to cut long phase labels into
          // fragments like "halts pl…". A long label now shrinks to fit whole;
          // short labels render at full size unchanged.
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                softWrap: false,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: textColor,
                  fontWeight: FontWeight.w800,
                  fontSize: small ? 11 : 12.5,
                  letterSpacing: .3,
                ),
              ),
            ),
          ),
        ],
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
        // Full-width premium bar (target): the CTA spans the hero content width
        // with the label centred and the arrow parked near the right edge.
        height: height,
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
          borderRadius: BorderRadius.circular(18),
          // Subtle inner top highlight for a glassy, premium sheen.
          border: Border.all(
            color: Colors.white.withValues(alpha: .15),
            width: 1,
          ),
          boxShadow: c.isDark
              ? [
                  BoxShadow(
                    color: glow.withValues(alpha: .30),
                    blurRadius: 14,
                    spreadRadius: -4,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              left: 12,
              right: 12,
              top: 1,
              child: Container(
                height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      Colors.white.withValues(alpha: .28),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            // Centred label (+ leading icon for Watch Live).
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (watchLive) ...[
                  Icon(icon, color: Colors.white, size: compact ? 19 : 21),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: compact ? 14.5 : 15.5,
                    letterSpacing: .2,
                  ),
                ),
              ],
            ),
            // Arrow parked near the right edge (Match Center variant only —
            // Watch Live already carries a leading play glyph).
            if (!watchLive)
              Positioned(
                right: 16,
                child: Icon(icon, color: Colors.white, size: compact ? 20 : 22),
              ),
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
    required this.oversSize,
    required this.scoreBoxHeight,
    this.innings = const <InningsScore>[],
    this.placeholder = '',
    this.live = false,
    this.currentInningsIndex = -1,
    this.showInningsOrdinal = false,
  });

  final String name;
  final String short;
  final String? logo;
  final Color accent;
  final double logoSize;
  final double codeSize;
  final double scoreSize;
  final double oversSize;
  final double scoreBoxHeight;
  final List<InningsScore> innings;
  final String placeholder;
  final bool live;
  final int currentInningsIndex;
  final bool showInningsOrdinal;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final code = homeTeamCode(short, name);
    final isPlaceholder = code == 'TBC' || code == 'TBD' || code.isEmpty;
    final scored = homeRealInnings(innings);
    final hasScore = scored.isNotEmpty;
    final currentIdx = hasScore
        ? TeamScorePresentation(scored).resolveCurrentIndex(
            currentInningsIndex,
            live: live,
          )
        : -1;
    final primaryIdx = currentIdx >= 0 ? currentIdx : scored.length - 1;
    final showInningsLabel = showInningsOrdinal && primaryIdx >= 0;
    final globalInnings =
        showInningsLabel ? scored[primaryIdx].inningsNumber : null;
    final teamInningsOrdinal = globalInnings == null
        ? primaryIdx + 1
        : ((globalInnings + 1) ~/ 2).clamp(1, 9);

    // NO whole-column FittedBox: wrapping logo+code+score together crushed the
    // text on small devices. Each sub-element is individually bounded — the score
    // stays a large single primary (current/latest innings only; the hero drops
    // the previous-innings row so the card fits the landscape aspect), and only
    // an over-long team code scales inside its own one-line box.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border:
                Border.all(color: accent.withValues(alpha: .9), width: 2.75),
            boxShadow: c.isDark
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: .30),
                      blurRadius: 14,
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
            size: math.max(1, logoSize - 6),
          ),
        ),
        const SizedBox(height: 2),
        // Team code: one line, scale-down only within its own bounded box so a
        // 2–5 char code never wraps and never bleeds into the VS column.
        SizedBox(
          width: logoSize + 28,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  code,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    color: c.text,
                    fontWeight: FontWeight.w900,
                    fontSize: codeSize.clamp(16.0, 22.0),
                    height: 1,
                  ),
                ),
                if (showInningsLabel) ...[
                  const SizedBox(width: 4),
                  _InningsChip(
                    label:
                        '${TeamScorePresentation.ordinal(teamInningsOrdinal)} Inn',
                    fontSize: oversSize.clamp(8.5, 10.0),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 1),
        // Reserved score slot: fixed min-height so a missing/"Yet to bat" side
        // keeps the same height as a scoring side and never moves the VS or the
        // opposing team vertically. Sits naturally in the column — the old
        // compact -14 upward offset is gone (it pulled the score into the team
        // code and the overs into the venue on 352-class cards).
        ConstrainedBox(
          constraints: BoxConstraints(minHeight: scoreBoxHeight),
          child: (hasScore || placeholder.isNotEmpty)
              ? HomeScoreColumn(
                  innings: innings,
                  mainSize: scoreSize,
                  oversSize: oversSize,
                  live: live,
                  currentInningsIndex: currentInningsIndex,
                  placeholder: placeholder,
                  heroPrimaryOnly: true,
                  // Hero primary score reads premium near-white on dark, for
                  // BOTH live and finished matches — never the bright cyan the
                  // default (`live:false → cyan`) would give a finished hero
                  // (§D). Team code stays white, overs stay muted below.
                  color: c.isDark ? const Color(0xffF2F7FF) : null,
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }
}

/// Home-local score renderer that matches the premium target's labeled layout:
///   • single innings → big `220/10` with an uppercase `42.5 OVERS` label;
///   • multi-innings (Test) → stacked labeled rows
///       `1st Inn 295/10 • 84.4 OV`
///       `2nd Inn 81/2 • 33.0 OV`   (current innings brighter + `*`).
///
/// Deliberately NOT the shared [TeamScoreView]: the shared renderer strips
/// `1st/2nd` labels and uses a lowercase `ov` unit everywhere (asserted by the
/// score/overs tests), so the target's labeled + uppercase style lives here,
/// Home-only, leaving the shared renderer and its tests untouched. Reuses
/// [InningsScore.scoreText]/`.oversText` and [TeamScorePresentation.ordinal] so
/// no score/ordinal formatting is reinvented.
class HomeScoreColumn extends StatelessWidget {
  const HomeScoreColumn({
    super.key,
    required this.innings,
    required this.mainSize,
    required this.oversSize,
    this.live = false,
    this.currentInningsIndex = -1,
    this.color,
    this.placeholder = '',
    this.showMissingDash = false,
    this.heroPrimarySecondary = false,
    this.heroPrimaryOnly = false,
  });

  final List<InningsScore> innings;
  final double mainSize;
  final double oversSize;
  final bool live;
  final int currentInningsIndex;

  /// Score color. Defaults to white when [live] (dark) / cyan otherwise —
  /// mirrors the shared renderer so the two never diverge.
  final Color? color;

  /// When true, a team with no real score renders a muted `—` in the reserved
  /// score slot instead of collapsing — so the opposing (scored) column can
  /// never pull the row up or grow to fill the gap (list-card balance).
  final bool showMissingDash;

  /// Data-aware hero hierarchy: instead of stacking N equally-small innings
  /// rows (which the double-FittedBox then crushes on a small device), render
  /// the CURRENT/latest innings as a LARGE primary score (`154/1*` + `42.0 OV`)
  /// and only the immediately-previous innings as ONE compact labeled secondary
  /// row (`[1st Inn] 285/10 • 74.5 OV`). Keeps the primary score the largest
  /// element even for a Test. Used by the hero; list cards keep the stacked
  /// labeled rows.
  final bool heroPrimarySecondary;

  /// Hero landscape layout: render ONLY the current/latest innings as a single
  /// large primary score + overs — no previous-innings row at all. The premium
  /// hero is a wide, short card; the earlier innings live in Match Details. Takes
  /// precedence over [heroPrimarySecondary] when both are set.
  final bool heroPrimaryOnly;

  /// Shown when there is no score yet (e.g. `Yet to bat`). Empty hides it.
  final String placeholder;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    // Only REAL batted innings render as a score — a fabricated all-zero
    // placeholder (backend `0/0 (0.0)`) is treated as MISSING, never `0/0`.
    final scored = homeRealInnings(innings);
    final mainColor =
        color ?? (live ? (c.isDark ? Colors.white : c.text) : c.cyan);
    // Overs read as a clearly SUBORDINATE label beneath the near-white primary
    // score (§D): a muted cool blue-grey on dark, not the near-white the score
    // uses, so the two never compete for the same visual weight.
    final ovColor =
        c.isDark ? const Color(0xffAFC4DE).withValues(alpha: .82) : c.muted;
    final labelColor = c.onImageText.withValues(alpha: c.isDark ? .70 : .66);

    if (scored.isEmpty) {
      // Prefer an explicit caller placeholder ("Yet to bat"); else, when the
      // caller reserves the slot, a muted `—`; else nothing.
      final text =
          placeholder.isNotEmpty ? placeholder : (showMissingDash ? '—' : '');
      if (text.isEmpty) return const SizedBox.shrink();
      // A real "Yet to bat" placeholder reads brighter than a bare `—` dash so
      // it occupies the score slot clearly (target keeps it legible, not faint).
      final isDash = text == '—';
      return Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: isDash
              ? labelColor
              : c.onImageText.withValues(alpha: c.isDark ? .95 : .90),
          fontWeight: isDash ? FontWeight.w600 : FontWeight.w700,
          fontSize: oversSize.clamp(11.0, 14.5),
          letterSpacing: .2,
        ),
      );
    }

    // Resolve which real innings is the current/primary one (batting side, else
    // latest). Used by both the single-line and primary+secondary layouts.
    final currentIdx = TeamScorePresentation(scored).resolveCurrentIndex(
      currentInningsIndex,
      live: live,
    );
    final dim = mainColor.withValues(alpha: .62);

    // Renders ONE large primary score line + its overs (the "big" score). Never
    // wrapped in a FittedBox by itself here — the caller bounds the width; only
    // an individual over-long score string scales inside its own line.
    //
    // The overs slot is RESERVED (fixed min-height) rather than conditionally
    // inserted, so a poll that momentarily returns an empty/`0.0` overs value
    // does not collapse the block — that vertical collapse-and-restore reads as
    // a flicker on a live match. The label itself still hides via visibility
    // (a rendered empty line would double-print zeros); the row height stays.
    Widget primaryBlock(InningsScore inn, {bool starred = false}) {
      final overs = inn.oversText.trim();
      final showOvers = homeOversPlayed(overs);
      final oversFont = oversSize.clamp(11.0, 14.0);
      // Reserved overs-line height: font size + a small padding for descender
      // + the leading gap; matches the visible line's natural extent so
      // toggling `showOvers` never resizes the parent Column.
      final reservedOversHeight = oversFont + 6;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              inn.scoreText + (starred ? '*' : ''),
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                color: mainColor,
                fontWeight: FontWeight.w900,
                // Primary score stays the largest hero element (>= 24 on small).
                // Softened upper cap after the compact refinement so the hero
                // score no longer visually dominates the whole card.
                fontSize: mainSize.clamp(24.0, 34.0),
                height: 1.02,
                letterSpacing: .2,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          SizedBox(
            height: reservedOversHeight,
            child: showOvers
                ? Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '$overs OVERS'.toUpperCase(),
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                          color: ovColor,
                          fontWeight: FontWeight.w700,
                          // Overs is a subordinate label but must read premium;
                          // wider range so the compact hero + list cards both
                          // get a visibly stronger overs line.
                          fontSize: oversFont,
                          letterSpacing: .8,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      );
    }

    // One compact labeled secondary row: `[1st Inn] 285/10 • 74.5 OV`.
    Widget secondaryRow(InningsScore inn, int ordinalOneBased,
        {double topGap = 4}) {
      final overs = inn.oversText.trim();
      final showRowOvers = homeOversPlayed(overs);
      final labelFont = oversSize.clamp(9.0, 11.0);
      return Padding(
        padding: EdgeInsets.only(top: topGap),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _InningsChip(
                label: '${TeamScorePresentation.ordinal(ordinalOneBased)} Inn',
                fontSize: labelFont,
              ),
              const SizedBox(width: 6),
              Text.rich(
                TextSpan(children: [
                  TextSpan(
                    text: inn.scoreText,
                    style: TextStyle(
                      color: dim,
                      fontWeight: FontWeight.w800,
                      fontSize: oversSize.clamp(10.5, 12.0),
                      letterSpacing: .2,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (showRowOvers)
                    TextSpan(
                      text: ' • $overs OV',
                      style: TextStyle(
                        color: ovColor.withValues(alpha: .85),
                        fontWeight: FontWeight.w600,
                        fontSize: labelFont + 1,
                        letterSpacing: .2,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                ]),
                maxLines: 1,
                softWrap: false,
              ),
            ],
          ),
        ),
      );
    }

    // Single real innings: big primary score + uppercase `42.5 OVERS`.
    if (scored.length == 1) {
      return primaryBlock(scored.first,
          starred: live && currentIdx == 0 && scored.length > 1);
    }

    // Landscape Home hero: current/latest innings only. The compact innings
    // label is rendered beside the team code by [_HeroTeamBlock], so history is
    // never compressed into a second row here.
    if (heroPrimaryOnly) {
      final primaryI = currentIdx >= 0 ? currentIdx : scored.length - 1;
      return primaryBlock(
        scored[primaryI],
        starred: live && currentIdx == primaryI,
      );
    }

    // Hero (data-aware): CURRENT innings big + ONE compact previous row, so a
    // Test hero keeps a large readable primary score instead of two tiny rows.
    if (heroPrimarySecondary) {
      final primaryI = currentIdx >= 0 ? currentIdx : scored.length - 1;
      final primary = scored[primaryI];
      // The most recent OTHER real innings (prefer the one just before primary).
      final prevI = primaryI > 0 ? primaryI - 1 : null;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          primaryBlock(primary, starred: live && currentIdx == primaryI),
          if (prevI != null) secondaryRow(scored[prevI], prevI + 1),
        ],
      );
    }

    // List-card multi-innings: stacked labeled rows (compact cards have room).
    final scoreFont = mainSize.clamp(13.0, 17.0);
    final labelFont = oversSize.clamp(9.5, 11.5);
    final rows = <Widget>[];
    for (var i = 0; i < scored.length; i++) {
      final inn = scored[i];
      final isCurrent = i == currentIdx;
      final rowColor =
          (live && currentIdx >= 0 && !isCurrent) ? dim : mainColor;
      final overs = inn.oversText.trim();
      final showRowOvers =
          overs.isNotEmpty && (double.tryParse(overs) ?? 1) > 0;
      rows.add(Padding(
        padding: EdgeInsets.only(top: i == 0 ? 0 : 5),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _InningsChip(
                label: '${TeamScorePresentation.ordinal(i + 1)} Inn',
                fontSize: labelFont,
              ),
              const SizedBox(width: 7),
              Text.rich(
                TextSpan(children: [
                  TextSpan(
                    text: inn.scoreText + (isCurrent ? '*' : ''),
                    style: TextStyle(
                      color: rowColor,
                      fontWeight: FontWeight.w900,
                      fontSize: scoreFont,
                      letterSpacing: .2,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (showRowOvers)
                    TextSpan(
                      text: ' • $overs OV',
                      style: TextStyle(
                        color: ovColor,
                        fontWeight: FontWeight.w700,
                        fontSize: labelFont + 1.5,
                        letterSpacing: .3,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                ]),
                maxLines: 1,
                softWrap: false,
              ),
            ],
          ),
        ),
      ));
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: rows,
    );
  }
}

/// Small cyan outlined chip used for the `1st Inn` / `2nd Inn` innings labels in
/// the Home multi-innings score column (matches the premium target's chips).
class _InningsChip extends StatelessWidget {
  const _InningsChip({required this.label, required this.fontSize});

  final String label;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: c.cyan.withValues(alpha: c.isDark ? .12 : .10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.cyan.withValues(alpha: .55), width: 1),
      ),
      child: Text(
        label,
        maxLines: 1,
        softWrap: false,
        style: TextStyle(
          color: c.cyan,
          fontWeight: FontWeight.w800,
          fontSize: fontSize,
          letterSpacing: .2,
        ),
      ),
    );
  }
}

/// High-fidelity hero skeleton that reserves the EXACT final hero geometry:
/// status pill + 2-line title placeholder, two emblem circles + team codes,
/// score placeholders, a VS placeholder, a venue placeholder and a CTA bar.
/// No large rotating loader — a subtle shimmer pulse (respecting reduced
/// motion) so the skeleton reads as a loading hero, not a blank card with a
/// spinner. Same outer size as the loaded [_HeroMatchCard] so there is zero
/// layout movement when content arrives.
class _HeroSkeleton extends StatefulWidget {
  const _HeroSkeleton({required this.height});

  final double height;

  @override
  State<_HeroSkeleton> createState() => _HeroSkeletonState();
}

class _HeroSkeletonState extends State<_HeroSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer;

  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    // Respect reduced-motion: a static skeleton instead of the pulse.
    final reduce = MediaQuery.accessibleNavigationOf(context);
    final t = reduce ? 0.5 : _shimmer.value;
    final baseAlpha = c.isDark ? 0.10 : 0.12;
    final pulseAlpha = baseAlpha + 0.06 * (0.5 + 0.5 * t);
    const blockBase = Color(0xff0c2640);
    final block = blockBase.withValues(alpha: c.isDark ? .55 : .30);
    final shimmerColor = c.cyan.withValues(alpha: pulseAlpha);

    Widget pill({double w = 54, double h = 16}) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: block,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: shimmerColor, width: 1),
          ),
        );

    Widget line({double w = double.infinity, double h = 12}) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: block,
            borderRadius: BorderRadius.circular(6),
          ),
        );

    Widget circle(double d) => Container(
          width: d,
          height: d,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: block,
            border: Border.all(color: shimmerColor, width: 2),
          ),
        );

    final m = _HeroMetrics.of(context);
    final small = m.small;
    final logoD = m.logoSize;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: m.gutter),
      child: Container(
        height: widget.height,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          color: c.isDark ? c.card.withValues(alpha: .5) : c.card,
          border: Border.all(color: c.cyan.withValues(alpha: .35), width: 1.4),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(14, small ? 6 : 14, 14, small ? 6 : 16),
          child: Column(
            children: [
              // Header: status pill + title lines + star.
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  pill(w: 46, h: 18),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      line(h: 11, w: double.infinity),
                      const SizedBox(height: 5),
                      line(h: 11, w: 120),
                    ],
                  )),
                  const SizedBox(width: 8),
                  circle(small ? 30 : 36),
                ],
              ),
              SizedBox(height: small ? 5 : 8),
              // Date line.
              line(h: 12, w: 150),
              // Team row fills the middle (same proportions as the loaded card).
              Expanded(
                child: OverflowBox(
                  minHeight: logoD + 62,
                  maxHeight: logoD + 62,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            circle(logoD),
                            const SizedBox(height: 6),
                            line(h: 14, w: 50),
                            const SizedBox(height: 6),
                            line(h: 18, w: 70),
                            const SizedBox(height: 4),
                            line(h: 10, w: 46),
                          ],
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          pill(w: 54, h: 40),
                          const SizedBox(height: 8),
                          pill(w: 40, h: 16),
                        ],
                      ),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            circle(logoD),
                            const SizedBox(height: 6),
                            line(h: 14, w: 50),
                            const SizedBox(height: 6),
                            line(h: 18, w: 70),
                            const SizedBox(height: 4),
                            line(h: 10, w: 46),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: small ? 6 : 8),
              // Venue.
              line(h: 12, w: 160),
              SizedBox(height: small ? 8 : 12),
              // CTA bar.
              Container(
                height: m.ctaHeight + 2,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: block,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: shimmerColor, width: 1),
                ),
              ),
            ],
          ),
        ),
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
// Test host — public widget so widget tests can pump the private hero card at
// exact device dimensions and assert no RenderFlex overflow. NOT used in
// production; kept tiny and side-effect free.
// ---------------------------------------------------------------------------

/// Renders a single [_HeroMatchCard] at the [_HeroMetrics] resolved for the
/// current [MediaQuery] size, wrapped in the same navy background + horizontal
/// padding the real Home screen applies. Used by the 352×856 / 491×912 layout
/// fixture tests.
class HomeHeroCardHost extends StatelessWidget {
  const HomeHeroCardHost({
    super.key,
    required this.match,
    required this.repository,
    required this.streamEpoch,
    this.onOpenMatch = _noopOpen,
    this.onWatchLive = _noopWatch,
  });

  final CricketMatch match;
  final CricketRepository repository;
  final int streamEpoch;
  final ValueChanged<String> onOpenMatch;
  final ValueChanged<String> onWatchLive;

  static void _noopOpen(String _) {}
  static void _noopWatch(String _) {}

  @override
  Widget build(BuildContext context) {
    final m = _HeroMetrics.of(context);
    // The hero height is content-driven (see _HeroMetrics.of) — it already
    // accounts for multi-innings content + a safety allowance, so no separate
    // multi-innings boost is needed here.
    final heroHeight = m.height;
    return ColoredBox(
      color: context.cric.bg,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal:
              (MediaQuery.sizeOf(context).width - m.diagnostics.cardWidth) / 2,
        ),
        child: SizedBox(
          key: const ValueKey('home-hero-card'),
          height: heroHeight,
          child: _HeroMatchCard(
            match: match,
            metrics: m,
            repository: repository,
            streamEpoch: streamEpoch,
            onTap: () => onOpenMatch(match.id),
            onWatchLive: onWatchLive,
          ),
        ),
      ),
    );
  }
}

/// Test-only production carousel host used to measure real PageView/card
/// rectangles. It delegates directly to [_HeroMatchCarousel].
@visibleForTesting
class HomeHeroCarouselHost extends StatelessWidget {
  const HomeHeroCarouselHost({
    super.key,
    required this.matches,
    required this.repository,
  });

  final List<CricketMatch> matches;
  final CricketRepository repository;

  @override
  Widget build(BuildContext context) => _HeroMatchCarousel(
        future: Future<List<CricketMatch>>.value(matches),
        repository: repository,
        onOpenMatch: (_) {},
        onWatchLive: (_) {},
        streamEpoch: 0,
        onRetry: () {},
        showDots: false,
      );
}

// ---------------------------------------------------------------------------
// Status tabs (Live / Upcoming / Finished)
// ---------------------------------------------------------------------------
