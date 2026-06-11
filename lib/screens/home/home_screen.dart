import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../components.dart';
import '../../models/cricket_match.dart';
import '../../models/home_feed.dart';
import '../../repositories/cricket_repository.dart';

/// Premium CricPro Home artwork assets (copied into assets/images/home/).
class _HAsset {
  static const _base = 'assets/images/home';

  /// Faint stadium atmosphere behind the whole screen / header.
  static const stadiumBackdrop = '$_base/futuristic_stadium_ui_backdrop.png';

  /// Hero (featured) match carousel background — premium featured card art.
  static const heroBg = '$_base/home_top_featured_card.png';

  /// Main list match card background — clean live card art.
  static const liveCardBg = '$_base/list_match_card_bg_live_clean.png';
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.onOpenMatchDetails,
    required this.onOpenSeries,
    required this.onOpenNotifications,
    required this.onOpenFilters,
    required this.onOpenReminders,
    required this.onOpenRanking,
    required this.onWatchLive,
    this.onOpenSeriesDetail,
  });

  /// Invoked with the resolved match id. Pass empty string when the user
  /// taps a section header that doesn't reference a specific match.
  final ValueChanged<String> onOpenMatchDetails;
  final VoidCallback onOpenSeries;

  /// Opens the full Series Details screen for a specific series id. Used by
  /// admin-managed Featured Series cards that carry a real series id. Falls
  /// back to [onOpenSeries] (the series list) when null or the id is empty.
  final ValueChanged<String>? onOpenSeriesDetail;
  final VoidCallback onOpenNotifications;
  final VoidCallback onOpenFilters;
  final VoidCallback onOpenReminders;
  final VoidCallback onOpenRanking;
  final ValueChanged<String> onWatchLive;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int topTab = 0;
  int categoryIndex = 0;

  final CricketRepository _repository = CricketRepository();
  final ScrollController _scrollController = ScrollController();

  late Future<List<CricketMatch>> _heroFuture;
  late Future<List<CricketMatch>> _tabFuture;
  late Future<HomeFeed> _feedFuture;
  List<CricketMatch>? _tabData;

  /// Admin-managed home layout. Starts at safe fallback and is replaced once
  /// the `/app/home` feed resolves.
  HomeLayoutConfig _config = HomeLayoutConfig.fallback;
  bool _appliedDefaults = false;

  Timer? _pollTimer;
  bool _polling = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _feedFuture = _loadFeed();
    _heroFuture = _resolveHero();
    _tabFuture = _loadTabMatches();
    _feedFuture.then(_applyFeedConfig);
    _configurePolling();
  }

  /// Applies the admin layout once the feed resolves: stores the config and,
  /// on first load only, honours the configured default tab and category.
  void _applyFeedConfig(HomeFeed feed) {
    if (!mounted) return;
    setState(() {
      _config = feed.config;
      if (!_appliedDefaults) {
        _appliedDefaults = true;
        final mm = feed.config.mainMatches;
        categoryIndex = mm.defaultCategoryIndex;
        if (mm.defaultTabIndex != topTab) {
          topTab = mm.defaultTabIndex;
          _tabData = null;
          _tabFuture = _loadTabMatches();
          _configurePolling();
        }
      }
    });
  }

  /// Hero list prefers the admin-resolved top-featured matches (manual or
  /// auto). Falls back to the aggregated live/upcoming/recent pool so the
  /// carousel is never empty when matches exist.
  Future<List<CricketMatch>> _resolveHero({bool forceRefresh = false}) async {
    try {
      final feed = await _loadFeed(forceRefresh: forceRefresh);
      if (feed.topFeatured.isNotEmpty) return feed.topFeatured;
    } catch (_) {
      // fall through to aggregation
    }
    return _loadHero(forceRefresh: forceRefresh);
  }

  /// Opens a Featured Series card: the exact Series Details screen when the
  /// entry carries a real series id, otherwise the normal Series list.
  void _openFeaturedSeries(HomeFeaturedSeries series) {
    final id = series.seriesExternalId.trim();
    if (id.isNotEmpty && widget.onOpenSeriesDetail != null) {
      widget.onOpenSeriesDetail!(id);
    } else {
      widget.onOpenSeries();
    }
  }

  /// Builds the home body sections in the admin-configured order, honouring
  /// per-section enable flags. Disabled sections are simply omitted.
  List<Widget> _buildSections() {
    final cfg = _config;
    final children = <Widget>[
      _HomeHeader(onBell: widget.onOpenNotifications),
      const SizedBox(height: 8),
    ];

    for (final key in cfg.sectionOrder) {
      switch (key) {
        case 'topFeatured':
          if (!cfg.topFeatured.enabled) break;
          children.add(_HeroMatchCarousel(
            future: _heroFuture,
            repository: _repository,
            onOpenMatch: widget.onOpenMatchDetails,
            showDots: cfg.topFeatured.showDots,
          ));
          children.add(const SizedBox(height: 14));
          break;
        case 'mainMatches':
          if (!cfg.mainMatches.enabled) break;
          if (cfg.mainMatches.showStatusTabs) {
            children.add(_HomeStatusTabs(selected: topTab, onChanged: _setTopTab));
            children.add(const SizedBox(height: 12));
          }
          if (cfg.mainMatches.showCategoryFilter) {
            children.add(_HomeCategoryFilter(
              selected: categoryIndex,
              onChanged: (i) => setState(() => categoryIndex = i),
              onOpenFilters: widget.onOpenFilters,
            ));
            children.add(const SizedBox(height: 16));
          }
          children.add(_HomeMatchList(
            future: _tabFuture,
            data: _tabData,
            topTab: topTab,
            repository: _repository,
            maxItems: cfg.mainMatches.maxItems,
            showWatchLive: cfg.mainMatches.showWatchLive,
            showViewMatch: cfg.mainMatches.showViewMatch,
            onOpenMatch: widget.onOpenMatchDetails,
            onWatchLive: widget.onWatchLive,
            onReminder: widget.onOpenReminders,
            onSwitchUpcoming: () => _setTopTab(1),
          ));
          break;
        case 'featuredMatches':
          if (!cfg.featuredMatches.enabled) break;
          children.add(_FeaturedMatchesSection(
            future: _feedFuture,
            config: cfg.featuredMatches,
            onOpenMatch: widget.onOpenMatchDetails,
            onSeeAll: () => widget.onOpenMatchDetails(''),
          ));
          break;
        case 'featuredSeries':
          if (!cfg.featuredSeries.enabled) break;
          children.add(_FeaturedSeriesSection(
            future: _feedFuture,
            config: cfg.featuredSeries,
            onSeeAll: widget.onOpenSeries,
            onOpenSeries: _openFeaturedSeries,
          ));
          break;
      }
    }
    return children;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _configurePolling();
    } else {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  // ---------------------------------------------------------------------------
  // Data loading
  // ---------------------------------------------------------------------------

  /// Loads the `/app/home` feed for the new bottom showcase sections
  /// (Featured Matches + admin-managed Featured Series). Failures degrade to
  /// an empty feed so the sections hide cleanly without breaking the screen.
  Future<HomeFeed> _loadFeed({bool forceRefresh = false}) async {
    try {
      final res = await _repository.home(forceRefresh: forceRefresh);
      return HomeFeed.fromJson(res.data);
    } catch (_) {
      return HomeFeed.empty;
    }
  }

  /// Featured / hero matches are independent of the selected tab. We aggregate
  /// unique matches from every source (live + upcoming + recent + schedule)
  /// so the carousel reliably shows multiple cards with side peeks and several
  /// dots, instead of a single tiny card.
  Future<List<CricketMatch>> _loadHero({bool forceRefresh = false}) async {
    final items = <CricketMatch>[];
    final seen = <String>{};

    void addAll(List<CricketMatch> list) {
      for (final m in list) {
        if (m.id.isEmpty) continue;
        if (items.length >= 5) return;
        if (seen.add(m.id)) items.add(m);
      }
    }

    Future<List<CricketMatch>> safeTab(int tab) async {
      try {
        final res =
            await _repository.matchesForTab(tab, forceRefresh: forceRefresh);
        return res.data;
      } catch (_) {
        return const <CricketMatch>[];
      }
    }

    // Live first (most important), then upcoming, then recent.
    addAll(await safeTab(0));
    if (items.length < 5) addAll(await safeTab(1));
    if (items.length < 5) addAll(await safeTab(2));
    if (items.length < 5) {
      try {
        final sched = await _repository.scheduleMatches(
            type: 'upcoming', forceRefresh: forceRefresh);
        addAll(sched.data);
      } catch (_) {
        // ignore — already have whatever we could gather
      }
    }
    return items.take(5).toList(growable: false);
  }

  /// Matches for the selected tab. The Upcoming tab falls back to the
  /// schedule (upcoming) endpoint used by the Schedule screen so Home never
  /// shows a false "empty" state when fixtures exist elsewhere.
  Future<List<CricketMatch>> _loadTabMatches(
      {bool forceRefresh = false}) async {
    final tab = topTab;
    try {
      final res =
          await _repository.matchesForTab(tab, forceRefresh: forceRefresh);
      if (res.data.isNotEmpty) {
        _tabData = res.data;
        return res.data;
      }
    } catch (_) {
      // fall through
    }
    if (tab == 1) {
      try {
        final sched = await _repository.scheduleMatches(
            type: 'upcoming', forceRefresh: forceRefresh);
        _tabData = sched.data;
        return sched.data;
      } catch (_) {
        // fall through
      }
    }
    _tabData = const <CricketMatch>[];
    return const <CricketMatch>[];
  }

  void _setTopTab(int value) {
    if (value == topTab) return;
    setState(() {
      topTab = value;
      _tabData = null;
      _tabFuture = _loadTabMatches();
    });
    _configurePolling();
  }

  Future<void> _refresh() async {
    final oldOffset =
        _scrollController.hasClients ? _scrollController.offset : null;
    _tabData = null;
    final tab = await _loadTabMatches(forceRefresh: true);
    if (!mounted) return;
    setState(() {
      _tabFuture = Future.value(tab);
      _heroFuture = _resolveHero(forceRefresh: true);
      _feedFuture = _loadFeed(forceRefresh: true);
    });
    _feedFuture.then(_applyFeedConfig);
    _restoreScroll(oldOffset);
  }

  void _configurePolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    final interval = switch (topTab) {
      0 => const Duration(seconds: 12),
      1 => const Duration(seconds: 90),
      _ => null,
    };
    if (interval == null) return;
    _pollTimer = Timer.periodic(interval, (_) => _silentPoll());
  }

  Future<void> _silentPoll() async {
    if (_polling || !mounted) return;
    _polling = true;
    final oldOffset =
        _scrollController.hasClients ? _scrollController.offset : null;
    try {
      final previous = _tabData;
      final fresh = await _loadTabMatches(forceRefresh: true);
      if (!mounted) return;
      final changed = previous == null ||
          jsonEncode(previous.map(_refreshKey).toList()) !=
              jsonEncode(fresh.map(_refreshKey).toList());
      if (changed) {
        setState(() => _tabFuture = Future.value(fresh));
        _heroFuture = _loadHero(forceRefresh: true);
        _restoreScroll(oldOffset);
      }
    } finally {
      _polling = false;
    }
  }

  String _refreshKey(CricketMatch m) =>
      m.id + m.statusText + m.teamAScoreText + m.teamBScoreText;

  void _restoreScroll(double? oldOffset) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (oldOffset != null && _scrollController.hasClients) {
        _scrollController.jumpTo(oldOffset.clamp(
          _scrollController.position.minScrollExtent,
          _scrollController.position.maxScrollExtent,
        ));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      decoration: BoxDecoration(gradient: c.bgGradient),
      child: Stack(
        children: [
          // Stadium atmosphere behind the top of the screen.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 420,
            child: IgnorePointer(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const StadiumImage(
                    _HAsset.stadiumBackdrop,
                    alignment: Alignment.topCenter,
                  ),
                  // Left floodlight glow.
                  Positioned(
                    top: -40,
                    left: -70,
                    child: _GlowOrb(color: c.cyan, size: 220, alpha: .2),
                  ),
                  // Right floodlight glow.
                  Positioned(
                    top: 10,
                    right: -80,
                    child: _GlowOrb(color: c.primary, size: 240, alpha: .18),
                  ),
                  // Readability gradient — keeps the stadium visible while
                  // fading cleanly into the page background.
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: c.stadiumOverlayColors,
                        stops: const [0, .5, .85, 1],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            child: RefreshIndicator(
              onRefresh: _refresh,
              color: c.cyan,
              child: ListView(
                controller: _scrollController,
                padding: EdgeInsets.fromLTRB(
                  context.horizontalPadding,
                  8,
                  context.horizontalPadding,
                  context.mainBottomPadding + 84,
                ),
                children: _buildSections(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.onBell});

  final VoidCallback onBell;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final logoSize = context.w <= 400 ? 30.0 : 33.0;
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 0),
      child: SizedBox(
        height: 46,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            RichText(
            text: TextSpan(
              style: TextStyle(
                fontSize: logoSize,
                fontWeight: FontWeight.w900,
                fontStyle: FontStyle.italic,
                letterSpacing: -1,
                height: 1,
              ),
              children: [
                TextSpan(text: 'CRIC', style: TextStyle(color: c.text)),
                TextSpan(
                  text: 'PRO',
                  style: TextStyle(
                    color: c.cyan,
                    shadows: [
                      Shadow(
                          color: c.cyan.withValues(alpha: .6), blurRadius: 16),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          _NotificationButton(onTap: onBell),
          ],
        ),
      ),
    );
  }
}

class _NotificationButton extends StatelessWidget {
  const _NotificationButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c.card.withValues(alpha: .42),
                border: Border.all(
                    color: c.cyan.withValues(alpha: .75), width: 1.3),
                boxShadow: [
                  BoxShadow(
                    color: c.cyan.withValues(alpha: .24),
                    blurRadius: 16,
                    spreadRadius: -3,
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Icon(Icons.notifications_none_rounded,
                  color: c.text, size: 22),
            ),
            // Notification dot.
            Positioned(
              top: 9,
              right: 10,
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: c.cyan,
                  shape: BoxShape.circle,
                  border: Border.all(color: c.bg, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                        color: c.cyan.withValues(alpha: .85), blurRadius: 7),
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

// ---------------------------------------------------------------------------
// Hero (featured) match carousel
// ---------------------------------------------------------------------------

class _HeroMatchCarousel extends StatefulWidget {
  const _HeroMatchCarousel({
    required this.future,
    required this.repository,
    required this.onOpenMatch,
    this.showDots = true,
  });

  final Future<List<CricketMatch>> future;
  final CricketRepository repository;
  final ValueChanged<String> onOpenMatch;
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

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final phone = context.w <= 430;
    final heroHeight = phone ? 190.0 : 206.0;
    return FutureBuilder<List<CricketMatch>>(
      future: widget.future,
      builder: (context, snapshot) {
        final matches = snapshot.data ?? const <CricketMatch>[];
        final waiting = snapshot.connectionState == ConnectionState.waiting &&
            matches.isEmpty;
        if (waiting) return _HeroSkeleton(height: heroHeight);
        if (matches.isEmpty) return _HeroEmpty(height: heroHeight);
        final items = matches.take(5).toList(growable: false);

        // Loop only when there is more than one item, so both left and right
        // neighbours are visible like the target.
        _loop = items.length > 1;
        _controller ??= PageController(
          viewportFraction: phone ? 0.82 : 0.78,
          initialPage: _loop ? items.length * 1000 : 0,
        );

        final itemCount = _loop ? items.length * 2000 : items.length;
        return Column(
          children: [
            SizedBox(
              height: heroHeight,
              child: PageView.builder(
                controller: _controller,
                itemCount: itemCount,
                clipBehavior: Clip.none,
                onPageChanged: (v) =>
                    setState(() => _current = _loop ? v % items.length : v),
                itemBuilder: (context, index) {
                  final realIndex = _loop ? index % items.length : index;
                  return AnimatedBuilder(
                    animation: _controller!,
                    builder: (context, child) {
                      double diff = 0;
                      if (_controller!.position.haveDimensions) {
                        diff = (_controller!.page ?? index.toDouble()) - index;
                      }
                      final scale = (1 - diff.abs() * 0.07).clamp(0.9, 1.0);
                      final opacity = (1 - diff.abs() * 0.45).clamp(0.55, 1.0);
                      return Opacity(
                        opacity: opacity,
                        child: Transform.scale(scale: scale, child: child),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: _HeroMatchCard(
                        match: items[realIndex],
                        onTap: () => widget.onOpenMatch(items[realIndex].id),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 6),
            if (widget.showDots)
              _CarouselDots(count: items.length, active: _current),
          ],
        );
      },
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
  const _HeroMatchCard({required this.match, required this.onTap});

  final CricketMatch match;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final phone = context.w <= 430;
    final live = match.isLive;
    final finished = match.isFinished;
    final (label, color) = live
        ? ('LIVE', c.live)
        : finished
            ? ('FINISHED', c.success)
            : ('UPCOMING', c.cyan);
    final logoSize = phone ? 46.0 : 52.0;
    final codeSize = phone ? 16.0 : 18.0;
    return TapScale(
      onTap: onTap,
      borderRadius: 24,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: c.cyan.withValues(alpha: .6), width: 1.3),
          boxShadow: c.heroShadow,
        ),
        child: Stack(
          children: [
            const Positioned.fill(
              child: StadiumImage(
                _HAsset.heroBg,
                hero: true,
                alignment: Alignment.center,
              ),
            ),
            // Light overlay only — keep the stadium and floodlights visible.
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
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: Column(
                mainAxisSize: MainAxisSize.max,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _StatusBadge(label: label, color: color, live: live),
                  ),
                  const SizedBox(height: 6),
                  // Premium white match title (2 lines max, no early ellipsis).
                  Text(
                    _heroTitle(match),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: c.text,
                      fontWeight: FontWeight.w800,
                      fontSize: phone ? 15 : 16,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Team row fills the remaining space so the venue row always
                  // fits inside the fixed hero height (no overflow).
                  Expanded(
                    child: Center(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: _HomeTeamBlock(
                              name: match.teamA,
                              short: match.teamAShort,
                              logo: match.teamALogo,
                              accent: c.cyan,
                              logoSize: logoSize,
                              codeSize: codeSize,
                            ),
                          ),
                          _HomeVsBadge(
                            width: phone ? 52 : 58,
                            height: phone ? 36 : 40,
                            intensity: 1.0,
                          ),
                          Expanded(
                            child: _HomeTeamBlock(
                              name: match.teamB,
                              short: match.teamBShort,
                              logo: match.teamBLogo,
                              accent: c.warning,
                              logoSize: logoSize,
                              codeSize: codeSize,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.location_on_outlined, color: c.cyan, size: 13),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          match.venue.isEmpty ? 'Venue TBC' : match.venue,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: c.onImageText,
                            fontWeight: FontWeight.w600,
                            fontSize: phone ? 11 : 11.5,
                          ),
                        ),
                      ),
                    ],
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
          color: c.card.withValues(alpha: .5),
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
          color: c.card.withValues(alpha: .5),
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

class _HomeStatusTabs extends StatelessWidget {
  const _HomeStatusTabs({required this.selected, required this.onChanged});

  final int selected;
  final ValueChanged<int> onChanged;

  static const _tabs = <(String, IconData)>[
    ('Live', Icons.podcasts_rounded),
    ('Upcoming', Icons.calendar_month_rounded),
    ('Finished', Icons.verified_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      height: 50,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.card.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: c.cyan.withValues(alpha: .4)),
        boxShadow: [
          BoxShadow(
            color: c.isDark
                ? Colors.black.withValues(alpha: .28)
                : const Color(0xff4a7fb5).withValues(alpha: .08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          for (var i = 0; i < _tabs.length; i++) ...[
            if (i != 0)
              Container(
                width: 1,
                height: 20,
                color: i == selected || (i - 1) == selected
                    ? Colors.transparent
                    : c.cyan.withValues(alpha: .22),
              ),
            Expanded(
              child: _StatusTab(
                label: _tabs[i].$1,
                icon: _tabs[i].$2,
                selected: i == selected,
                onTap: () => onChanged(i),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusTab extends StatelessWidget {
  const _StatusTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        height: 40,
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xff35e2ff), Color(0xff0a86ff)],
                )
              : null,
          borderRadius: BorderRadius.circular(22),
          border: selected
              ? Border.all(color: c.cyan.withValues(alpha: .95), width: 1.2)
              : null,
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: c.cyan.withValues(alpha: .5),
                    blurRadius: 16,
                    spreadRadius: -2,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: selected ? Colors.white : c.muted),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? Colors.white : c.muted,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  fontSize: selected ? 13.5 : 12.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Match list
// ---------------------------------------------------------------------------

class _HomeMatchList extends StatelessWidget {
  const _HomeMatchList({
    required this.future,
    required this.data,
    required this.topTab,
    required this.repository,
    required this.onOpenMatch,
    required this.onWatchLive,
    required this.onReminder,
    required this.onSwitchUpcoming,
    this.maxItems = 12,
    this.showWatchLive = true,
    this.showViewMatch = true,
  });

  final Future<List<CricketMatch>> future;
  final List<CricketMatch>? data;
  final int topTab;
  final CricketRepository repository;
  final ValueChanged<String> onOpenMatch;
  final ValueChanged<String> onWatchLive;
  final VoidCallback onReminder;
  final VoidCallback onSwitchUpcoming;
  final int maxItems;
  final bool showWatchLive;
  final bool showViewMatch;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<CricketMatch>>(
      future: future,
      builder: (context, snapshot) {
        final raw = data ?? snapshot.data ?? const <CricketMatch>[];
        final waiting = data == null &&
            snapshot.connectionState == ConnectionState.waiting &&
            raw.isEmpty;
        if (waiting) {
          return const Column(
            children: [
              _CardSkeleton(),
              SizedBox(height: 16),
              _CardSkeleton(),
            ],
          );
        }
        final matches = raw;
        if (matches.isEmpty) {
          return _HomeEmptyState(
            topTab: topTab,
            onSwitchUpcoming: onSwitchUpcoming,
          );
        }
        return Column(
          children: [
            for (final match in matches.take(maxItems))
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _HomeMatchCard(
                  match: match,
                  repository: repository,
                  showWatchLive: showWatchLive,
                  showViewMatch: showViewMatch,
                  onOpenMatch: onOpenMatch,
                  onWatchLive: onWatchLive,
                  onReminder: onReminder,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Dispatches to the correct premium card variant by match status.
class _HomeMatchCard extends StatelessWidget {
  const _HomeMatchCard({
    required this.match,
    required this.repository,
    required this.onOpenMatch,
    required this.onWatchLive,
    required this.onReminder,
    this.showWatchLive = true,
    this.showViewMatch = true,
  });

  final CricketMatch match;
  final CricketRepository repository;
  final ValueChanged<String> onOpenMatch;
  final ValueChanged<String> onWatchLive;
  final VoidCallback onReminder;
  final bool showWatchLive;
  final bool showViewMatch;

  @override
  Widget build(BuildContext context) {
    if (match.isLive) {
      return _HomeLiveMatchCard(
        match: match,
        repository: repository,
        showWatchLive: showWatchLive,
        showViewMatch: showViewMatch,
        onOpenMatch: onOpenMatch,
        onWatchLive: onWatchLive,
      );
    }
    if (match.isFinished) {
      return _HomeFinishedMatchCard(
        match: match,
        showViewMatch: showViewMatch,
        onOpenMatch: onOpenMatch,
      );
    }
    return _HomeUpcomingMatchCard(
      match: match,
      showViewMatch: showViewMatch,
      onOpenMatch: onOpenMatch,
      onReminder: onReminder,
    );
  }
}

// ---------------------------------------------------------------------------
// Shared premium card scaffold
// ---------------------------------------------------------------------------

class _HomeCardShell extends StatelessWidget {
  const _HomeCardShell({
    required this.bgAsset,
    required this.onTap,
    required this.child,
    this.minHeight,
  });

  final String bgAsset;
  final VoidCallback onTap;
  final Widget child;
  final double? minHeight;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return TapScale(
      onTap: onTap,
      borderRadius: 22,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: c.cyan.withValues(alpha: .42), width: 1),
          boxShadow: c.heroShadow,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight ?? 0),
          child: Stack(
            children: [
              Positioned.fill(
                child: StadiumImage(
                  bgAsset,
                  hero: true,
                  alignment: Alignment.center,
                ),
              ),
              // Stadium visible with a clean dark overlay for readable text.
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: c.matchCardOverlayColors.length >= 3
                          ? c.matchCardOverlayColors
                          : [
                              c.matchCardOverlayColors.first,
                              Color.lerp(c.matchCardOverlayColors.first, c.matchCardOverlayColors.last, .5)!,
                              c.matchCardOverlayColors.last,
                            ],
                      stops: const [0, .45, 1],
                    ),
                  ),
                ),
              ),
              // Subtle cyan glow centred behind the VS badge only.
              Positioned.fill(
                child: Align(
                  alignment: const Alignment(0, -0.12),
                  child: _GlowOrb(color: c.cyan, size: 70, alpha: .045),
                ),
              ),
              const _TopCyanHighlight(),
              // Non-positioned content: lets the Stack grow taller than
              // minHeight when the live score/venue/action bar need the room,
              // preventing the bottom overflow.
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: child,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopCyanHighlight extends StatelessWidget {
  const _TopCyanHighlight();

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: 2,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.transparent,
              c.cyan.withValues(alpha: .7),
              c.cyan.withValues(alpha: .8),
              c.cyan.withValues(alpha: .7),
              Colors.transparent,
            ],
            stops: const [0, .25, .5, .75, 1],
          ),
          boxShadow: [
            BoxShadow(color: c.cyan.withValues(alpha: .4), blurRadius: 5),
          ],
        ),
      ),
    );
  }
}

/// Reusable soft radial glow used for floodlights and card accents.
class _GlowOrb extends StatelessWidget {
  const _GlowOrb({
    required this.color,
    required this.size,
    required this.alpha,
  });

  final Color color;
  final double size;
  final double alpha;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: alpha),
              color.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}

/// Top row shared by all list cards: status badge + centered title + star.
class _CardTopRow extends StatelessWidget {
  const _CardTopRow({
    required this.label,
    required this.color,
    required this.live,
    required this.title,
    this.titleColor,
  });

  final String label;
  final Color color;
  final bool live;
  final String title;
  final Color? titleColor;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _StatusBadge(label: label, color: color, live: live, dense: true),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: titleColor ?? c.text,
              fontWeight: FontWeight.w800,
              fontSize: 14,
              height: 1.15,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Icon(Icons.star_border_rounded,
            color: c.text.withValues(alpha: .85), size: 22),
      ],
    );
  }
}

/// Small centered status pill (e.g. `LIVE NOW`, `UPCOMING`) shown under VS.
class _CenterPill extends StatelessWidget {
  const _CenterPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .7)),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: .3), blurRadius: 9, spreadRadius: -3),
        ],
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 10.5,
          letterSpacing: .5,
        ),
      ),
    );
  }
}

/// Hairline divider used between the team block and the metadata row.
class _CardDivider extends StatelessWidget {
  const _CardDivider();

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      height: 1,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.transparent,
            c.cyan.withValues(alpha: .28),
            Colors.transparent,
          ],
        ),
      ),
    );
  }
}

/// Three-column metadata row: venue | date/time | match type.
class _CardMetaRow extends StatelessWidget {
  const _CardMetaRow({required this.match});

  final CricketMatch match;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Row(
      children: [
        Expanded(
          child: _item(
            c,
            Icons.location_on_outlined,
            match.venue.isEmpty ? 'Venue TBC' : match.venue,
            MainAxisAlignment.start,
          ),
        ),
        _div(c),
        Expanded(
          child: _item(
            c,
            Icons.calendar_month_rounded,
            _cardDateTime(match),
            MainAxisAlignment.center,
          ),
        ),
        _div(c),
        Expanded(
          child: _item(
            c,
            Icons.desktop_windows_outlined,
            match.matchDesc.isEmpty ? 'Match' : match.matchDesc,
            MainAxisAlignment.end,
          ),
        ),
      ],
    );
  }

  Widget _div(CricColors c) => Container(
        width: 1,
        height: 16,
        color: c.cyan.withValues(alpha: .22),
      );

  Widget _item(
    CricColors c,
    IconData icon,
    String text,
    MainAxisAlignment align,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        mainAxisAlignment: align,
        children: [
          Icon(icon, color: c.cyan, size: 13),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.onImageText,
                fontWeight: FontWeight.w600,
                fontSize: 10.8,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CardTeamRow extends StatelessWidget {
  const _CardTeamRow({
    required this.match,
    this.showScore = false,
    this.centerPill,
  });

  final CricketMatch match;
  final bool showScore;

  /// Optional status pill (e.g. `LIVE NOW`, `UPCOMING`) centred under the VS
  /// badge, matching the premium target layout.
  final Widget? centerPill;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final phone = context.w <= 430;
    final logoSize = phone ? 46.0 : 52.0;
    final codeSize = phone ? 20.0 : 21.0;
    final scoreColor = match.isLive ? c.live : c.cyan;
    final vsHeight = phone ? 34.0 : 36.0;
    // Anchor everything to the top so both team logos share the exact same Y
    // (and therefore the same vertical centre/baseline) even when one side has
    // a score and the other doesn't. The VS column is nudged down so the badge
    // centres on the logos.
    final vsTopInset = (logoSize / 2) - (vsHeight / 2);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _HomeTeamBlock(
            name: match.teamA,
            short: match.teamAShort,
            logo: match.teamALogo,
            accent: c.cyan,
            logoSize: logoSize,
            codeSize: codeSize,
            showFullName: true,
            scoreColor: scoreColor,
            score: showScore ? match.teamAScoreText : null,
          ),
        ),
        Padding(
          padding: EdgeInsets.only(top: vsTopInset > 0 ? vsTopInset : 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _HomeVsBadge(
                width: phone ? 50 : 54,
                height: vsHeight,
                intensity: 0.9,
              ),
              if (centerPill != null) ...[
                const SizedBox(height: 8),
                centerPill!,
              ],
            ],
          ),
        ),
        Expanded(
          child: _HomeTeamBlock(
            name: match.teamB,
            short: match.teamBShort,
            logo: match.teamBLogo,
            accent: c.warning,
            logoSize: logoSize,
            codeSize: codeSize,
            showFullName: true,
            scoreColor: scoreColor,
            score: showScore ? match.teamBScoreText : null,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Live match card
// ---------------------------------------------------------------------------

class _HomeLiveMatchCard extends StatelessWidget {
  const _HomeLiveMatchCard({
    required this.match,
    required this.repository,
    required this.onOpenMatch,
    required this.onWatchLive,
    this.showWatchLive = true,
    this.showViewMatch = true,
  });

  final CricketMatch match;
  final CricketRepository repository;
  final ValueChanged<String> onOpenMatch;
  final ValueChanged<String> onWatchLive;
  final bool showWatchLive;
  final bool showViewMatch;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final note = match.statusText.isNotEmpty
        ? match.statusText
        : (match.resultText.isNotEmpty ? match.resultText : '');
    return _HomeCardShell(
      bgAsset: _HAsset.liveCardBg,
      onTap: () => onOpenMatch(match.id),
      minHeight: context.w <= 430 ? 196 : 214,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _CardTopRow(
            label: 'LIVE',
            color: c.live,
            live: true,
            title: _heroTitle(match),
            titleColor: c.cyan,
          ),
          const SizedBox(height: 6),
          // Full team names + scores, with a centred LIVE NOW pill under VS.
          _CardTeamRow(
            match: match,
            showScore: true,
            centerPill: _CenterPill(label: 'LIVE NOW', color: c.cyan),
          ),
          if (note.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              note,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: c.onImageText,
                fontWeight: FontWeight.w600,
                fontSize: 11.5,
              ),
            ),
          ],
          const SizedBox(height: 8),
          const _CardDivider(),
          const SizedBox(height: 7),
          _CardMetaRow(match: match),
          const SizedBox(height: 9),
          _LiveActionBar(
            match: match,
            repository: repository,
            showWatchLive: showWatchLive,
            showViewMatch: showViewMatch,
            onWatchLive: onWatchLive,
            onViewMatch: onOpenMatch,
          ),
        ],
      ),
    );
  }
}

/// Resolves stream availability and renders the action bar.
///
/// Watch Live is shown only when a playable stream actually exists. To avoid a
/// flash where the button "disappears" while the async check runs, we seed an
/// optimistic value from the match's embedded stream flags and then reconcile
/// it with the authoritative `/match/:id/streams` result.
class _LiveActionBar extends StatefulWidget {
  const _LiveActionBar({
    required this.match,
    required this.repository,
    required this.onWatchLive,
    required this.onViewMatch,
    this.showWatchLive = true,
    this.showViewMatch = true,
  });

  final CricketMatch match;
  final CricketRepository repository;
  final ValueChanged<String> onWatchLive;
  final ValueChanged<String> onViewMatch;
  final bool showWatchLive;
  final bool showViewMatch;

  @override
  State<_LiveActionBar> createState() => _LiveActionBarState();
}

class _LiveActionBarState extends State<_LiveActionBar> {
  /// True/false once resolved; starts from the optimistic embedded-flag guess.
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    _enabled = _optimistic;
    _resolve();
  }

  @override
  void didUpdateWidget(covariant _LiveActionBar old) {
    super.didUpdateWidget(old);
    if (old.match.id != widget.match.id) {
      _enabled = _optimistic;
      _resolve();
    }
  }

  /// Best guess before the authoritative check returns: trust positive
  /// embedded flags so a clearly-streamable live match shows the button
  /// immediately instead of flickering in.
  bool get _optimistic =>
      widget.match.id.isNotEmpty &&
      widget.match.hasStreamInfo &&
      widget.match.watchLiveEnabled &&
      widget.match.hasLiveStream;

  Future<void> _resolve() async {
    if (widget.match.id.isEmpty) {
      if (mounted && _enabled) setState(() => _enabled = false);
      return;
    }
    try {
      final result =
          await widget.repository.shouldShowWatchLiveForMatch(widget.match);
      if (mounted && result != _enabled) setState(() => _enabled = result);
    } catch (_) {
      // Keep the optimistic value on transient errors so a valid stream is
      // not hidden by a flaky check.
    }
  }

  @override
  Widget build(BuildContext context) {
    // Only surface Watch Live when a playable stream exists, so a LIVE card
    // never shows a confusing dimmed/disabled button. When no stream is
    // available, View Match takes the full width.
    final showWatch = widget.showWatchLive && _enabled;
    return _HomeActionBar(
      onViewMatch: () => widget.onViewMatch(widget.match.id),
      showWatch: showWatch,
      showView: widget.showViewMatch,
      watchEnabled: _enabled,
      onWatchLive: _enabled ? () => widget.onWatchLive(widget.match.id) : null,
    );
  }
}

// ---------------------------------------------------------------------------
// Upcoming match card
// ---------------------------------------------------------------------------

class _HomeUpcomingMatchCard extends StatelessWidget {
  const _HomeUpcomingMatchCard({
    required this.match,
    required this.onOpenMatch,
    required this.onReminder,
    this.showViewMatch = true,
  });

  final CricketMatch match;
  final ValueChanged<String> onOpenMatch;
  final VoidCallback onReminder;
  final bool showViewMatch;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return _HomeCardShell(
      bgAsset: _HAsset.liveCardBg,
      onTap: () => onOpenMatch(match.id),
      minHeight: context.w <= 430 ? 190 : 208,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _CardTopRow(
            label: 'UPCOMING',
            color: c.cyan,
            live: false,
            title: match.versusTitle,
          ),
          const SizedBox(height: 6),
          _CardTeamRow(
            match: match,
            centerPill: _CenterPill(label: 'UPCOMING', color: c.cyan),
          ),
          const SizedBox(height: 8),
          const _CardDivider(),
          const SizedBox(height: 7),
          _CardMetaRow(match: match),
          const SizedBox(height: 9),
          _HomeActionBar(
            onViewMatch: () => onOpenMatch(match.id),
            showView: showViewMatch,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Finished match card
// ---------------------------------------------------------------------------

class _HomeFinishedMatchCard extends StatelessWidget {
  const _HomeFinishedMatchCard(
      {required this.match, required this.onOpenMatch, this.showViewMatch = true});

  final CricketMatch match;
  final ValueChanged<String> onOpenMatch;
  final bool showViewMatch;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final result = match.resultText.isNotEmpty
        ? match.resultText
        : (match.statusText.isNotEmpty ? match.statusText : 'Match finished');
    return _HomeCardShell(
      bgAsset: _HAsset.liveCardBg,
      onTap: () => onOpenMatch(match.id),
      minHeight: context.w <= 430 ? 196 : 214,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _CardTopRow(
            label: 'FINISHED',
            color: c.success,
            live: false,
            title: match.versusTitle,
          ),
          const SizedBox(height: 6),
          _CardTeamRow(
            match: match,
            showScore: true,
            centerPill: _CenterPill(label: result, color: c.success),
          ),
          const SizedBox(height: 8),
          const _CardDivider(),
          const SizedBox(height: 7),
          _CardMetaRow(match: match),
          const SizedBox(height: 9),
          _HomeActionBar(
            onViewMatch: () => onOpenMatch(match.id),
            showView: showViewMatch,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Team block
// ---------------------------------------------------------------------------

class _HomeTeamBlock extends StatelessWidget {
  const _HomeTeamBlock({
    required this.name,
    required this.short,
    required this.logo,
    required this.accent,
    required this.logoSize,
    this.codeSize = 23,
    this.score,
    this.showFullName = true,
    this.scoreColor,
  });

  final String name;
  final String short;
  final String? logo;
  final Color accent;
  final double logoSize;
  final double codeSize;
  final String? score;
  final bool showFullName;
  final Color? scoreColor;

  /// Strips a leading team short-name from a score string and lowercases the
  /// overs unit, e.g. "IND 564/8 (127.0 OV)" -> "564/8 (127.0 ov)".
  static String _cleanTeamScore(String score, String shortName) {
    var s = score.trim();
    if (shortName.isNotEmpty &&
        s.toUpperCase().startsWith(shortName.toUpperCase())) {
      s = s.substring(shortName.length).trim();
    }
    return s.replaceAll('OV', 'ov');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final phone = context.w <= 430;
    final code = (short.isEmpty ? name : short).toUpperCase();
    final isPlaceholder = code == 'TBC' || code == 'TBD' || code.isEmpty;
    final hasScore = score != null && score!.isNotEmpty;
    final sColor = scoreColor ?? c.cyan;

    String? scoreMain;
    String? scoreOvers;
    if (hasScore) {
      final cleaned = _cleanTeamScore(score!, code);
      final open = cleaned.indexOf('(');
      if (open > 0) {
        scoreMain = cleaned.substring(0, open).trim();
        scoreOvers = cleaned.substring(open).trim();
      } else {
        scoreMain = cleaned;
      }
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: c.cyan.withValues(alpha: .35),
                blurRadius: 14,
                spreadRadius: -2,
              ),
            ],
          ),
          child: TeamLogoWidget(
            logoUrl: isPlaceholder ? null : logo,
            teamName: name,
            abbreviation: code,
            color: accent,
            size: logoSize,
          ),
        ),
        const SizedBox(height: 4),
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
        if (showFullName) ...[
          const SizedBox(height: 1),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: c.onImageText,
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
          ),
        ],
        if (scoreMain != null) ...[
          const SizedBox(height: 3),
          Text(
            scoreMain,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: sColor,
              fontWeight: FontWeight.w900,
              fontSize: phone ? 18 : 19,
              height: 1.0,
              letterSpacing: 0.2,
            ),
          ),
          if (scoreOvers != null) ...[
            const SizedBox(height: 1),
            Text(
              scoreOvers,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: sColor.withValues(alpha: 0.86),
                fontWeight: FontWeight.w700,
                fontSize: phone ? 12 : 12.5,
                height: 1.05,
              ),
            ),
          ],
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// VS badge — slanted glowing glass pill with diagonal streak
// ---------------------------------------------------------------------------

class _HomeVsBadge extends StatelessWidget {
  const _HomeVsBadge({
    required this.width,
    required this.height,
    this.intensity = 1.0,
  });

  final double width;
  final double height;
  final double intensity;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // A. Soft cyan bloom behind the VS.
          Positioned(
            left: -width * 0.45,
            right: -width * 0.45,
            top: -height * 0.55,
            bottom: -height * 0.55,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    c.cyan.withValues(alpha: 0.34 * intensity),
                    c.cyan.withValues(alpha: 0.12 * intensity),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.45, 1.0],
                ),
              ),
            ),
          ),
          // B. Stronger light pool / glow directly under the badge, using a
          // blurred boxShadow so it blooms clearly below the VS.
          Positioned(
            bottom: -height * 0.32,
            child: Container(
              width: width * 1.15,
              height: height * 0.34,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: c.cyan.withValues(alpha: 0.20 * intensity),
                boxShadow: [
                  BoxShadow(
                    color: c.cyan.withValues(alpha: 0.42 * intensity),
                    blurRadius: 20,
                    spreadRadius: 5,
                  ),
                  BoxShadow(
                    color: c.cyan.withValues(alpha: 0.18 * intensity),
                    blurRadius: 34,
                    spreadRadius: 10,
                  ),
                ],
              ),
            ),
          ),
          // C. Diagonal electric streak behind the pill.
          Transform.rotate(
            angle: -0.72,
            child: Container(
              width: width * 1.75,
              height: 4,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(99),
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    c.cyan.withValues(alpha: 0.75 * intensity),
                    Colors.white.withValues(alpha: 0.42 * intensity),
                    c.cyan.withValues(alpha: 0.55 * intensity),
                    Colors.transparent,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: c.cyan.withValues(alpha: 0.35 * intensity),
                    blurRadius: 14,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ),
          // The slanted glass pill.
          CustomPaint(
            size: Size(width, height),
            painter: _VsBadgePainter(
              border: c.cyan,
              fill: const Color(0xff071d34).withValues(alpha: .86),
              glow: c.cyan.withValues(alpha: .5 * intensity),
              strokeWidth: 1.5,
            ),
          ),
          Text(
            'VS',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: height * 0.42,
              letterSpacing: .6,
              shadows: [
                Shadow(
                    color: c.cyan.withValues(alpha: .9 * intensity),
                    blurRadius: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VsBadgePainter extends CustomPainter {
  _VsBadgePainter({
    required this.border,
    required this.fill,
    required this.glow,
    this.strokeWidth = 1.6,
  });

  final Color border;
  final Color fill;
  final Color glow;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final slant = size.height * 0.22;
    // Slanted parallelogram with rounded corners.
    final pts = <Offset>[
      Offset(slant, 0),
      Offset(size.width, 0),
      Offset(size.width - slant, size.height),
      Offset(0, size.height),
    ];
    final path = _roundedPoly(pts, size.height * 0.26);

    // Soft cyan glow halo around the pill edge.
    canvas.drawPath(
      path,
      Paint()
        ..color = glow
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    // Glass fill.
    canvas.drawPath(path, Paint()..color = fill);
    // Inner highlight streak.
    canvas.save();
    canvas.clipPath(path);
    final streak = Paint()
      ..color = border.withValues(alpha: .4)
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(size.width * 0.2, size.height + 2),
      Offset(size.width * 0.8, -2),
      streak,
    );
    canvas.restore();
    // Cyan border.
    canvas.drawPath(
      path,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeJoin = StrokeJoin.round,
    );
  }

  /// Builds a closed path through [pts] with rounded corners of radius [r].
  Path _roundedPoly(List<Offset> pts, double r) {
    final path = Path();
    final n = pts.length;
    for (var i = 0; i < n; i++) {
      final curr = pts[i];
      final prev = pts[(i - 1 + n) % n];
      final next = pts[(i + 1) % n];
      final toPrev = prev - curr;
      final toNext = next - curr;
      final lPrev = toPrev.distance;
      final lNext = toNext.distance;
      if (lPrev == 0 || lNext == 0) continue;
      final rPrev = math.min(r, lPrev / 2);
      final rNext = math.min(r, lNext / 2);
      final p1 = curr + toPrev * (rPrev / lPrev);
      final p2 = curr + toNext * (rNext / lNext);
      if (i == 0) {
        path.moveTo(p1.dx, p1.dy);
      } else {
        path.lineTo(p1.dx, p1.dy);
      }
      path.quadraticBezierTo(curr.dx, curr.dy, p2.dx, p2.dy);
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant _VsBadgePainter old) =>
      old.border != border ||
      old.fill != fill ||
      old.glow != glow ||
      old.strokeWidth != strokeWidth;
}

// ---------------------------------------------------------------------------
// Action bar
// ---------------------------------------------------------------------------

class _HomeActionBar extends StatelessWidget {
  const _HomeActionBar({
    required this.onViewMatch,
    this.onWatchLive,
    this.watchEnabled = false,
    this.showWatch = false,
    this.showView = true,
  });

  final VoidCallback onViewMatch;

  /// Whether to render the Watch Live button at all. Live cards always set
  /// this true (kept visible even when disabled); Upcoming/Finished leave it
  /// false so only the full-width View Match button shows.
  final bool showWatch;
  final VoidCallback? onWatchLive;
  final bool watchEnabled;
  final bool showView;

  @override
  Widget build(BuildContext context) {
    // Nothing to show — collapse the bar entirely.
    if (!showWatch && !showView) return const SizedBox.shrink();
    final watchBtn = showWatch
        ? Opacity(
            opacity: watchEnabled ? 1 : 0.55,
            child: _FilledActionButton(
              icon: Icons.podcasts_rounded,
              label: 'Watch Live',
              onTap: watchEnabled ? onWatchLive : null,
            ),
          )
        : null;
    final viewBtn = showView
        ? _OutlinedActionButton(
            icon: Icons.bar_chart_rounded,
            label: 'View Match',
            trailingChevron: true,
            onTap: onViewMatch,
          )
        : null;

    if (watchBtn != null && viewBtn != null) {
      return Row(
        children: [
          Expanded(child: watchBtn),
          const SizedBox(width: 10),
          Expanded(child: viewBtn),
        ],
      );
    }
    return watchBtn ?? viewBtn ?? const SizedBox.shrink();
  }
}

/// Large filled gradient action button (Watch Live).
class _FilledActionButton extends StatelessWidget {
  const _FilledActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xff35e2ff), Color(0xff0a86ff)],
          ),
          borderRadius: BorderRadius.circular(13),
          boxShadow: [
            BoxShadow(
              color: c.cyan.withValues(alpha: .45),
              blurRadius: 16,
              spreadRadius: -3,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: Colors.white),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Large outlined action button (View Match).
class _OutlinedActionButton extends StatelessWidget {
  const _OutlinedActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailingChevron = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool trailingChevron;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          color: c.card.withValues(alpha: .35),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: c.cyan.withValues(alpha: .6), width: 1.2),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c.cyan.withValues(alpha: .16),
                border: Border.all(color: c.cyan.withValues(alpha: .55)),
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 13, color: c.cyan),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: c.text,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ),
            if (trailingChevron) ...[
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, size: 19, color: c.cyan),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Status badge
// ---------------------------------------------------------------------------

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.label,
    required this.color,
    required this.live,
    this.dense = false,
  });

  final String label;
  final Color color;
  final bool live;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .85)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (live) ...[
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: dense ? 9.5 : 10,
              letterSpacing: .4,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state + skeleton
// ---------------------------------------------------------------------------

class _HomeEmptyState extends StatelessWidget {
  const _HomeEmptyState({required this.topTab, required this.onSwitchUpcoming});

  final int topTab;
  final VoidCallback onSwitchUpcoming;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final message = switch (topTab) {
      0 => 'No live matches right now',
      1 => 'No upcoming matches',
      _ => 'No finished matches',
    };
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 20),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: c.card.withValues(alpha: .45),
        border: Border.all(color: c.cyan.withValues(alpha: .3)),
      ),
      child: Column(
        children: [
          Icon(Icons.sports_cricket_rounded, color: c.cyan, size: 30),
          const SizedBox(height: 10),
          Text(
            message,
            style: TextStyle(color: c.text, fontWeight: FontWeight.w800),
          ),
          if (topTab == 0) ...[
            const SizedBox(height: 6),
            GestureDetector(
              onTap: onSwitchUpcoming,
              behavior: HitTestBehavior.opaque,
              child: Text(
                'View upcoming fixtures',
                style: TextStyle(
                  color: c.cyan,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CardSkeleton extends StatelessWidget {
  const _CardSkeleton();

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      height: 210,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: c.card.withValues(alpha: .5),
        border: Border.all(color: c.cyan.withValues(alpha: .22)),
      ),
      alignment: Alignment.center,
      child: CircularProgressIndicator(color: c.cyan),
    );
  }
}

// ---------------------------------------------------------------------------
// Category filter row (All / International / League / Domestic + filter icon)
// ---------------------------------------------------------------------------

class _HomeCategoryFilter extends StatelessWidget {
  const _HomeCategoryFilter({
    required this.selected,
    required this.onChanged,
    required this.onOpenFilters,
  });

  final int selected;
  final ValueChanged<int> onChanged;
  final VoidCallback onOpenFilters;

  static const _labels = ['All', 'International', 'League', 'Domestic'];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(right: 8),
        itemCount: _labels.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index == _labels.length) {
            return _filterChip(
              context,
              icon: Icons.tune_rounded,
              label: null,
              active: false,
              onTap: onOpenFilters,
            );
          }
          return _filterChip(
            context,
            icon: index == 0 ? Icons.grid_view_rounded : null,
            label: _labels[index],
            active: index == selected,
            onTap: () => onChanged(index),
          );
        },
      ),
    );
  }

  Widget _filterChip(
    BuildContext context, {
    IconData? icon,
    String? label,
    required bool active,
    required VoidCallback onTap,
  }) {
    final c = context.cric;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 36,
        alignment: Alignment.center,
        padding: EdgeInsets.symmetric(
          horizontal: label != null ? 15 : 11,
        ),
        decoration: BoxDecoration(
          color: active
              ? c.cyan.withValues(alpha: .18)
              : c.card.withValues(alpha: .4),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active
                ? c.cyan.withValues(alpha: .8)
                : c.cyan.withValues(alpha: .25),
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: c.cyan.withValues(alpha: .28),
                    blurRadius: 12,
                    spreadRadius: -3,
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon,
                  size: 15, color: active ? c.cyan : c.muted),
              if (label != null) const SizedBox(width: 6),
            ],
            if (label != null)
              Text(
                label,
                style: TextStyle(
                  color: active ? c.cyan : c.muted,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                  fontSize: 12.5,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom featured sections (Featured Matches + Featured Series)
// ---------------------------------------------------------------------------

class _FeaturedMatchesSection extends StatelessWidget {
  const _FeaturedMatchesSection({
    required this.future,
    required this.config,
    required this.onOpenMatch,
    required this.onSeeAll,
  });

  final Future<HomeFeed> future;
  final FeaturedSectionConfig config;
  final ValueChanged<String> onOpenMatch;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<HomeFeed>(
      future: future,
      builder: (context, snapshot) {
        final feed = snapshot.data ?? HomeFeed.empty;
        final matches = (feed.featuredMatches.isNotEmpty
                ? feed.featuredMatches
                : [...feed.liveMatches, ...feed.upcomingMatches])
            .take(config.maxItems)
            .toList(growable: false);
        if (matches.isEmpty) return const SizedBox.shrink();
        return Column(
          children: [
            const SizedBox(height: 20),
            _SectionHeader(
              title: config.title,
              showSeeAll: config.showSeeAll,
              onSeeAll: onSeeAll,
            ),
            const SizedBox(height: 10),
            _FeaturedMatchesRow(matches: matches, onOpenMatch: onOpenMatch),
          ],
        );
      },
    );
  }
}

class _FeaturedSeriesSection extends StatelessWidget {
  const _FeaturedSeriesSection({
    required this.future,
    required this.config,
    required this.onSeeAll,
    required this.onOpenSeries,
  });

  final Future<HomeFeed> future;
  final FeaturedSectionConfig config;
  final VoidCallback onSeeAll;
  final ValueChanged<HomeFeaturedSeries> onOpenSeries;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<HomeFeed>(
      future: future,
      builder: (context, snapshot) {
        final feed = snapshot.data ?? HomeFeed.empty;
        final series =
            feed.featuredSeries.take(config.maxItems).toList(growable: false);
        if (series.isEmpty) return const SizedBox.shrink();
        return Column(
          children: [
            const SizedBox(height: 20),
            _SectionHeader(
              title: config.title,
              showSeeAll: config.showSeeAll,
              onSeeAll: onSeeAll,
            ),
            const SizedBox(height: 10),
            _FeaturedSeriesRow(series: series, onOpenSeries: onOpenSeries),
          ],
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.onSeeAll,
    this.showSeeAll = true,
  });

  final String title;
  final VoidCallback onSeeAll;
  final bool showSeeAll;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Row(
      children: [
        Text(
          title,
          style: TextStyle(
            color: c.text,
            fontWeight: FontWeight.w900,
            fontSize: 16,
          ),
        ),
        const Spacer(),
        if (showSeeAll)
          GestureDetector(
            onTap: onSeeAll,
            behavior: HitTestBehavior.opaque,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'See All',
                  style: TextStyle(
                    color: c.cyan,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(Icons.chevron_right_rounded, color: c.cyan, size: 18),
              ],
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Featured Matches horizontal row (compact cards)
// ---------------------------------------------------------------------------

class _FeaturedMatchesRow extends StatelessWidget {
  const _FeaturedMatchesRow({
    required this.matches,
    required this.onOpenMatch,
  });

  final List<CricketMatch> matches;
  final ValueChanged<String> onOpenMatch;

  @override
  Widget build(BuildContext context) {
    // Card width tuned so ~1.25–1.35 cards show at 360dp: the first card is
    // comfortably sized and the next card peeks ~25–35% (a clear, premium
    // preview), never a tiny sliver. A trailing inset keeps the last card off
    // the screen edge.
    final w = context.w;
    final hp = context.horizontalPadding;
    final cardWidth = ((w - hp * 2) * 0.78).clamp(248.0, 340.0);
    return SizedBox(
      height: 172,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: const EdgeInsets.only(right: 18),
        itemCount: matches.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          return SizedBox(
            width: cardWidth,
            child: _FeaturedMatchMini(
              match: matches[index],
              onTap: () => onOpenMatch(matches[index].id),
            ),
          );
        },
      ),
    );
  }
}

class _FeaturedMatchMini extends StatelessWidget {
  const _FeaturedMatchMini({required this.match, required this.onTap});

  final CricketMatch match;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final (label, color) = match.isLive
        ? ('LIVE', c.live)
        : match.isFinished
            ? ('FINISHED', c.success)
            : ('UPCOMING', c.cyan);
    return TapScale(
      onTap: onTap,
      borderRadius: 16,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.cyan.withValues(alpha: .38), width: 1),
          boxShadow: c.heroShadow,
        ),
        child: Stack(
          children: [
            // Stadium background.
            const Positioned.fill(
              child: StadiumImage(
                _HAsset.liveCardBg,
                hero: true,
                alignment: Alignment.center,
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: c.matchCardOverlayColors,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(13, 11, 13, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Top: status badge + series title (title gets full width and
                  // up to 2 lines so it never clips too early).
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: _StatusBadge(
                            label: label,
                            color: color,
                            live: match.isLive,
                            dense: true),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          match.series.isEmpty
                              ? match.versusTitle
                              : match.series,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: c.text,
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                            height: 1.18,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  // Middle: logos + VS + codes.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: _MiniTeam(
                          name: match.teamA,
                          short: match.teamAShort,
                          logo: match.teamALogo,
                          accent: c.cyan,
                        ),
                      ),
                      const _HomeVsBadge(width: 48, height: 33, intensity: 0.85),
                      Expanded(
                        child: _MiniTeam(
                          name: match.teamB,
                          short: match.teamBShort,
                          logo: match.teamBLogo,
                          accent: c.warning,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  // Bottom: date + venue.
                  Row(
                    children: [
                      Icon(Icons.calendar_month_rounded,
                          size: 12, color: c.cyan),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          _cardDateTime(match),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: c.onImageText,
                            fontWeight: FontWeight.w600,
                            fontSize: 10.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.location_on_outlined,
                          size: 12, color: c.cyan),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          match.venue.isEmpty ? 'Venue TBC' : match.venue,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: c.onImageText,
                            fontWeight: FontWeight.w600,
                            fontSize: 10.5,
                          ),
                        ),
                      ),
                    ],
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

/// Compact team block (logo + code) used inside Featured Matches cards.
class _MiniTeam extends StatelessWidget {
  const _MiniTeam({
    required this.name,
    required this.short,
    required this.logo,
    required this.accent,
  });

  final String name;
  final String short;
  final String? logo;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final code = (short.isEmpty ? name : short).toUpperCase();
    final isPlaceholder = code == 'TBC' || code == 'TBD' || code.isEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TeamLogoWidget(
          logoUrl: isPlaceholder ? null : logo,
          teamName: name,
          abbreviation: code,
          color: accent,
          size: 46,
        ),
        const SizedBox(height: 6),
        Text(
          code,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: c.text,
            fontWeight: FontWeight.w900,
            fontSize: 15,
            height: 1,
          ),
        ),
        if (name.isNotEmpty && name.toUpperCase() != code) ...[
          const SizedBox(height: 2),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: c.onImageText,
              fontWeight: FontWeight.w600,
              fontSize: 10,
              height: 1,
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Featured Series horizontal row (admin-managed manual cards)
// ---------------------------------------------------------------------------

class _FeaturedSeriesRow extends StatelessWidget {
  const _FeaturedSeriesRow({
    required this.series,
    required this.onOpenSeries,
  });

  final List<HomeFeaturedSeries> series;
  final ValueChanged<HomeFeaturedSeries> onOpenSeries;

  @override
  Widget build(BuildContext context) {
    // Premium full-width cinematic cards, stacked vertically. The target shows
    // one prominent banner; when admins add several, each gets the same
    // full-bleed treatment.
    return Column(
      children: [
        for (var i = 0; i < series.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == series.length - 1 ? 0 : 14),
            child: _FeaturedSeriesCard(
              series: series[i],
              onTap: () => onOpenSeries(series[i]),
            ),
          ),
      ],
    );
  }
}

class _FeaturedSeriesCard extends StatelessWidget {
  const _FeaturedSeriesCard({required this.series, required this.onTap});

  final HomeFeaturedSeries series;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final phone = context.w <= 430;
    final height = phone ? 150.0 : 168.0;
    return TapScale(
      onTap: onTap,
      borderRadius: 18,
      child: Container(
        height: height,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: c.cyan.withValues(alpha: .4), width: 1),
          boxShadow: c.heroShadow,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Premium stadium fallback — always present so the image area is
            // never empty; the admin poster paints over it when available.
            const StadiumImage(
              _HAsset.heroBg,
              hero: true,
              alignment: Alignment.center,
            ),
            if (series.hasImage)
              Image.network(
                series.imageUrl,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return const SizedBox.shrink();
                },
              ),
            // Strong left-to-right + bottom gradient so the title/date/location
            // stay readable over any poster.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: c.isDark
                      ? const [
                          Color(0xF2020B18),
                          Color(0xB3020B18),
                          Color(0x40020B18),
                        ]
                      : [
                          Colors.white.withValues(alpha: .92),
                          Colors.white.withValues(alpha: .72),
                          Colors.white.withValues(alpha: .35),
                        ],
                  stops: const [0, .55, 1],
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: c.isDark
                      ? [
                          Colors.black.withValues(alpha: .12),
                          Colors.black.withValues(alpha: .66),
                        ]
                      : [
                          Colors.white.withValues(alpha: .10),
                          Colors.white.withValues(alpha: .55),
                        ],
                  stops: const [.35, 1],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 15, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Optional "ODI SERIES"-style chip from the subtitle.
                  if (series.subtitle.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: c.cyan.withValues(alpha: .2),
                        borderRadius: BorderRadius.circular(999),
                        border:
                            Border.all(color: c.cyan.withValues(alpha: .75)),
                      ),
                      child: Text(
                        series.subtitle.toUpperCase(),
                        style: TextStyle(
                          color: c.cyan,
                          fontWeight: FontWeight.w800,
                          fontSize: 10,
                          letterSpacing: .6,
                        ),
                      ),
                    ),
                  const Spacer(),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              series.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: phone ? 19 : 22,
                                height: 1.1,
                                shadows: [
                                  Shadow(
                                    color: Colors.black.withValues(alpha: .6),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 7),
                            Row(
                              children: [
                                if (series.dateRange.isNotEmpty) ...[
                                  Icon(Icons.calendar_month_rounded,
                                      size: 13, color: c.cyan),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      series.dateRange,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color:
                                            Colors.white.withValues(alpha: .9),
                                        fontWeight: FontWeight.w600,
                                        fontSize: 11.5,
                                      ),
                                    ),
                                  ),
                                ],
                                if (series.dateRange.isNotEmpty &&
                                    series.location.isNotEmpty)
                                  const SizedBox(width: 12),
                                if (series.location.isNotEmpty) ...[
                                  Icon(Icons.location_on_outlined,
                                      size: 13, color: c.cyan),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      series.location,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color:
                                            Colors.white.withValues(alpha: .9),
                                        fontWeight: FontWeight.w600,
                                        fontSize: 11.5,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Circular arrow button with subtle cyan glow, vertically
                      // aligned with the title/meta block.
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: c.cyan.withValues(alpha: .16),
                          border: Border.all(
                              color: c.cyan.withValues(alpha: .9), width: 1.4),
                          boxShadow: [
                            BoxShadow(
                              color: c.cyan.withValues(alpha: .4),
                              blurRadius: 14,
                              spreadRadius: -2,
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: Icon(Icons.arrow_forward_rounded,
                            color: c.cyan, size: 22),
                      ),
                    ],
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

// ---------------------------------------------------------------------------
// Date helpers
// ---------------------------------------------------------------------------

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Hero card title — prefers the match's own title (e.g. "Afghanistan vs
/// India - Test Live Stream"), falling back to the series name then the
/// derived "TeamA vs TeamB" so the carousel is never blank.
String _heroTitle(CricketMatch match) {
  if (match.title.trim().isNotEmpty) return match.title.trim();
  if (match.series.trim().isNotEmpty) return match.series.trim();
  return match.versusTitle;
}

/// List card: `Jun 6 • 06:00 AM`.
String _cardDateTime(CricketMatch match) {
  final dt = match.startDateTime?.toLocal();
  if (dt == null) {
    return match.statusText.isNotEmpty ? match.statusText : match.startTime;
  }
  return '${_months[dt.month - 1]} ${dt.day} • ${_clock(dt)}';
}

String _clock(DateTime dt) {
  var hour = dt.hour % 12;
  if (hour == 0) hour = 12;
  final ampm = dt.hour >= 12 ? 'PM' : 'AM';
  final mm = dt.minute.toString().padLeft(2, '0');
  return '${hour.toString().padLeft(2, '0')}:$mm $ampm';
}
