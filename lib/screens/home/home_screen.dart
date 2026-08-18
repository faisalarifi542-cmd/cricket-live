import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../app_theme.dart';
import '../../components.dart';
import '../../models/cricket_match.dart';
import '../../models/home_feed.dart';
import '../../repositories/cricket_repository.dart';
import '../../upcoming_sort.dart';
import '../../utils/match_classification.dart';
import '../../utils/match_status.dart';
import '../../utils/score_presentation.dart';
import '../../utils/team_format.dart';
import '../../services/favorite_countries_service.dart';
import 'package:cricpro_flutter/services/analytics_service.dart';
import 'home_hero_order.dart';
import 'home_score_rules.dart';

part 'home_card_metrics.dart';
part 'widgets/home_header.dart';
part 'widgets/home_hero.dart';
part 'widgets/home_match_cards.dart';
part 'widgets/home_actions.dart';
part 'widgets/home_featured.dart';

/// Temporary verification logging for the Home live-score refresh path. Guarded
/// so it is a no-op in release builds (compiles out under `kReleaseMode`). Logs
/// are tagged `CricProHomePoll` / `CricProHomeHero` / `CricProHomeCard` so they
/// can be filtered in logcat. Never logs URLs/keys/headers.
const bool _kHomeDebug = kDebugMode;

/// Premium CricPro Home artwork assets (copied into assets/images/home/).
class _HAsset {
  static const _base = 'assets/images/home';

  /// Faint stadium atmosphere behind the whole screen / header.
  static const stadiumBackdrop = '$_base/futuristic_stadium_ui_backdrop.webp';

  /// Hero (featured) match carousel background — premium featured card art.
  static const heroBg = '$_base/home_top_featured_card.webp';

  /// Main list match card background — clean live card art.
  static const liveCardBg = '$_base/list_match_card_bg_live_clean.webp';
}

/// Single authoritative selected-filter for the Home main-matches region.
///
/// The segmented-control highlight, the section heading, the list data source
/// and the "View All" destination must ALL derive from this one value so they
/// can never disagree (the forbidden "Live highlighted / Upcoming heading /
/// upcoming cards" state).
///
/// The user's selection is ALWAYS honoured: tapping Live keeps Live selected
/// even when zero live matches loaded — the region then renders the dedicated
/// Live empty state (with a switch-to-Upcoming CTA) instead of silently
/// re-resolving to Upcoming. The previous auto-fallback made the Live tab feel
/// non-clickable whenever nothing was live.
///
/// `0 = Live`, `1 = Upcoming`, `2 = Finished`.
@visibleForTesting
int homeResolvedTab({required int selectedTab, required bool liveLoadedEmpty}) {
  return selectedTab;
}

/// Section heading for a RESOLVED tab (see [homeResolvedTab]). Kept in lockstep
/// with the segmented-control highlight and the list data so the three never
/// drift apart.
@visibleForTesting
String homeSectionHeading(int resolvedTab) => switch (resolvedTab) {
      0 => 'Live Matches',
      1 => 'Upcoming Matches',
      _ => 'Finished Matches',
    };

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
    this.reentrySignal,
    this.onOpenSchedule,
    this.onOpenMatches,
    this.onOpenSeriesDetail,
  });

  /// Bumped by the host shell when the bottom-nav re-selects the (already
  /// mounted) Home tab, so Home can silently refresh live scores on re-entry.
  final ValueListenable<int>? reentrySignal;

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

  /// Switches the bottom-nav to the Schedule tab (Home Quick Action). Null
  /// falls back to no-op.
  final VoidCallback? onOpenSchedule;

  /// Switches the bottom-nav to the Matches tab (Live Matches "View All").
  final VoidCallback? onOpenMatches;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int topTab = 0;

  /// Bumped on each pull-to-refresh so stream-availability CTAs (hero) re-resolve
  /// against freshly-invalidated data instead of a cached result.
  int _streamEpoch = 0;

  final CricketRepository _repository = CricketRepository();
  final ScrollController _scrollController = ScrollController();

  late Future<List<CricketMatch>> _heroFuture;
  late Future<List<CricketMatch>> _tabFuture;
  late Future<HomeFeed> _feedFuture;

  /// Dedicated merged+sorted upcoming feed for the horizontal Upcoming row and
  /// the Live-empty fallback. Independent of the selected tab so it is always
  /// ready to surface fixtures.
  late Future<List<CricketMatch>> _upcomingFuture;
  List<CricketMatch>? _tabData;

  /// Admin-managed home layout. Starts at safe fallback and is replaced once
  /// the `/app/home` feed resolves.
  HomeLayoutConfig _config = HomeLayoutConfig.fallback;
  bool _appliedDefaults = false;

  /// Match ids excluded from the lower match list. Only the **primary**
  /// (first / currently-featured) hero match is excluded so a single match
  /// never appears as both the lead hero and a list card — while every other
  /// carousel match is still allowed to show below. Excluding all five hero
  /// matches used to hide entire Upcoming sections.
  Set<String> _heroIds = const <String>{};

  /// True once the initial hero future has SETTLED (resolved or failed) at least
  /// once, so [_heroIds] is known. Until then the below match list is held on a
  /// skeleton instead of rendering with an empty exclude set — which is what let
  /// the hero match flash in the list before "moving" into the carousel.
  bool _heroSettled = false;

  /// Completes the moment [_heroSettled] flips to true. Used by the post-frame
  /// startup refresh so a silent poll can't race the initial hero resolution.
  /// Bounded by [_kStartupRefreshGrace] — if the hero never settles (offline
  /// cold start), the refresh still fires so we don't stall in the loading
  /// state forever.
  final Completer<void> _heroSettledCompleter = Completer<void>();
  static const Duration _kStartupRefreshGrace = Duration(milliseconds: 500);

  /// Latest resolved hero matches + a content key, tracked so the silent poll
  /// can refresh a live featured match's score INDEPENDENTLY of the lower
  /// match list. (When the hero match is the only live game it is excluded
  /// from the list, so keying hero refresh off the list left it frozen.)
  List<CricketMatch>? _heroData;
  String _heroKey = '';

  Timer? _pollTimer;
  // Self-healing watchdog: re-arm live polling after a transient network error
  // instead of leaving it cancelled until the user pulls to refresh.
  Timer? _recoveryTimer;
  int _consecutivePollFailures = 0;
  bool _polling = false;
  // Counts silent-poll ticks. The heavy membership refresh (full /matches/live
  // + hero re-resolve, which detects matches starting/finishing) runs only
  // every Nth tick; the cheap /app/live-scores overlay runs every tick so the
  // visible score advances within a ball.
  int _pollTick = 0;
  static const int _kMembershipEveryNTicks = 4;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AnalyticsService.instance.screenView('home');
    _feedFuture = _loadFeed();
    _heroFuture = _resolveHero();
    _tabFuture = _loadTabMatches();
    _upcomingFuture = _loadUpcomingMerged();
    _captureHeroIds(_heroFuture);
    _feedFuture.then(_applyFeedConfig);
    _configurePolling();
    widget.reentrySignal?.addListener(_onReentrySignal);
    // First paint shows the repository's cached snapshot instantly; immediately
    // kick a silent force-refresh after that frame so a live score that moved
    // since the cache was written updates without waiting for the 8s tick or a
    // manual pull-to-refresh. Wait for the hero to settle first (bounded by a
    // 500ms grace) so the immediate poll never races the initial hero-id
    // resolution — this is what let the primary hero flash into the list for
    // one frame before "moving" up into the carousel.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      try {
        await _heroSettledCompleter.future.timeout(_kStartupRefreshGrace);
      } on TimeoutException {
        // Hero taking longer than expected — the immediate refresh is
        // optional (cached data already renders), so proceed anyway.
      }
      if (!mounted) return;
      _kickImmediateRefresh('initState');
    });
  }

  /// Fires a one-shot silent refresh outside the polling cadence. Cheap and
  /// idempotent (reuses [_silentPoll]'s guard), used on first paint, app resume,
  /// and Home-tab re-entry so the score is fresh the moment the user looks.
  void _kickImmediateRefresh(String reason) {
    if (!mounted) return;
    if (_kHomeDebug) {
      debugPrint('CricProHomePoll: immediate refresh ($reason)');
    }
    unawaited(_silentPoll());
  }

  /// Records ONLY the primary hero match id (the first carousel card) so the
  /// main match list excludes just that one. Stale futures are ignored — only
  /// the most recently assigned [_heroFuture] is allowed to update [_heroIds].
  void _captureHeroIds(Future<List<CricketMatch>> future) {
    future.then((matches) {
      if (!mounted || !identical(future, _heroFuture)) return;
      final hadLive = _heroData?.any((m) => m.isLive) ?? false;
      _heroData = matches;
      _heroKey = _heroListKey(matches);
      final hasLive = matches.any((m) => m.isLive);
      final primary = matches
          .map((m) => m.id)
          .firstWhere((id) => id.isNotEmpty, orElse: () => '');
      final ids = primary.isEmpty ? const <String>{} : {primary};
      final wasSettled = _heroSettled;
      if (!_heroSettled ||
          ids.length != _heroIds.length ||
          !ids.containsAll(_heroIds)) {
        setState(() {
          _heroIds = ids;
          _heroSettled = true;
        });
      }
      if (!wasSettled && !_heroSettledCompleter.isCompleted) {
        _heroSettledCompleter.complete();
      }
      // If the hero's live-ness changed (e.g. a featured match just went live
      // while the user sits on the Finished tab), re-arm polling so the hero
      // score keeps updating at the live cadence.
      if (hadLive != hasLive) _configurePolling();
    }).catchError((_) {
      // Hero failed to load — leave the previous ids; nothing to exclude, but
      // unblock the list so it isn't stuck on a skeleton forever.
      if (mounted && !_heroSettled) {
        setState(() => _heroSettled = true);
      }
      if (!_heroSettledCompleter.isCompleted) {
        _heroSettledCompleter.complete();
      }
    });
  }

  /// Content fingerprint of the hero list so a silent poll can tell whether a
  /// featured (often live) match's score/status actually changed.
  String _heroListKey(List<CricketMatch> matches) =>
      jsonEncode(matches.map(_refreshKey).toList());

  /// Applies the admin layout once the feed resolves: stores the config and,
  /// on first load only, honours the configured default tab.
  void _applyFeedConfig(HomeFeed feed) {
    if (!mounted) return;
    setState(() {
      _config = feed.config;
      if (!_appliedDefaults) {
        _appliedDefaults = true;
        final mm = feed.config.mainMatches;
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
  /// Throws on network failure so the hero UI can show offline state.
  ///
  /// CRITICAL: the `/app/home` `topFeaturedMatches` feed is admin-curated and
  /// is frequently cached/stale on the backend, so a featured LIVE match's
  /// score there never advances. We therefore overlay the authoritative fast
  /// `/matches/live` feed on top (matched by id) so a live hero's score tracks
  /// the live endpoint even when `/app/home` is stale. This is the actual fix
  /// for "Home hero score not updating on device".
  Future<List<CricketMatch>> _resolveHero({bool forceRefresh = false}) async {
    try {
      final feed = await _loadFeed(forceRefresh: forceRefresh);
      if (feed.topFeatured.isNotEmpty) {
        final overlaid = await _overlayLiveScores(
          _prioritiseHero(feed.topFeatured),
          forceRefresh: forceRefresh,
        );
        return _orderHeroByStatus(overlaid);
      }
    } catch (_) {
      // Feed failed — try aggregation; if that also fails, let it throw.
    }
    return _orderHeroByStatus(await _loadHero(forceRefresh: forceRefresh));
  }

  /// Orders the hero carousel so Live matches lead, then Upcoming, then
  /// Finished — a STABLE sort, so the admin-curated / favourite order is kept
  /// WITHIN each status bucket (it only re-buckets by status). This prevents a
  /// finished match being the first hero while live/upcoming ones exist, and
  /// when there are no live matches an upcoming match leads (never a finished
  /// one). The live/upcoming/finished section TABS below stay independent.
  // Orders the hero carousel via the shared classifier (status + score + start
  // time): Live first, then Upcoming, then Finished — so a hero flagged
  // "upcoming" that already has a score is never placed before a live match.
  List<CricketMatch> _orderHeroByStatus(List<CricketMatch> list) =>
      orderByPhase(list);

  /// Replaces any hero match with its fresh counterpart from the fast match
  /// feeds (live first, then recent, then upcoming) matched by id, so the
  /// score/status the hero shows comes from the authoritative match endpoints
  /// rather than the slow, often-stale `/app/home` payload. Heroes absent from
  /// every feed are kept as-is. Best-effort: a feed failure is ignored.
  Future<List<CricketMatch>> _overlayLiveScores(
    List<CricketMatch> heroes, {
    bool forceRefresh = false,
  }) async {
    if (heroes.isEmpty) return heroes;
    try {
      // Live is the priority source; recent/upcoming fill ids the live feed
      // doesn't carry (a hero flagged live in /app/home but not yet/again in
      // /matches/live would otherwise stay frozen with an empty score).
      final byId = <String, CricketMatch>{};
      Future<void> indexTab(int tab) async {
        try {
          final res =
              await _repository.matchesForTab(tab, forceRefresh: forceRefresh);
          for (final m in res.data) {
            if (m.id.isEmpty) continue;
            // Don't let a later (recent/upcoming) feed overwrite a live entry.
            byId.putIfAbsent(m.id, () => m);
          }
        } catch (_) {/* one feed failing is fine */}
      }

      await indexTab(0); // live
      await indexTab(2); // recent
      await indexTab(1); // upcoming
      if (byId.isEmpty) return heroes;

      var replaced = 0;
      final merged = [
        for (final h in heroes)
          if (byId[h.id] case final fresh?)
            () {
              replaced++;
              return fresh;
            }()
          else
            h,
      ];
      if (_kHomeDebug) {
        debugPrint('CricProHomeHero: overlaid $replaced/${heroes.length} '
            'hero(es) from match feeds (indexed=${byId.length})');
        for (final h in merged) {
          if (h.isLive &&
              h.teamAScoreText.isEmpty &&
              h.teamBScoreText.isEmpty) {
            debugPrint('CricProHomeHero: WARN hero ${h.id} is LIVE but has '
                'EMPTY score after overlay — not present in match feeds, or '
                'feed score parsed empty (see CricProHomeScoreMap).');
          }
        }
      }
      return merged;
    } catch (_) {
      return heroes; // feeds unavailable — keep admin heroes unchanged.
    }
  }

  /// Floats a favourite-country match to the front of the hero carousel so it
  /// becomes the primary card, WITHOUT breaking cricket-status priority: a live
  /// match always outranks an upcoming/finished one, so a favourite may only
  /// lead when it sits in the highest status bucket already present. Example:
  /// favourite plays tomorrow but an unrelated match is live now -> the live
  /// match stays primary; the favourite is not promoted over it. Within that
  /// top bucket the favourite (soonest, if several) is floated to the front;
  /// the rest of the admin/aggregation order is preserved.
  List<CricketMatch> _prioritiseHero(List<CricketMatch> matches) {
    if (matches.length < 2) return matches;
    if (FavoriteCountriesService.instance.selected.value.isEmpty) {
      return matches;
    }
    // Status bucket: live (0) outranks upcoming (1) outranks finished (2).
    int statusRank(CricketMatch m) => m.isLive ? 0 : (m.isFinished ? 2 : 1);
    // The best status bucket present decides which matches are eligible to
    // lead — favourites never jump a worse bucket over a better one.
    final topBucket = matches.map(statusRank).reduce((a, b) => a < b ? a : b);
    final favsInTopBucket = matches
        .where((m) =>
            statusRank(m) == topBucket &&
            FavoriteCountriesService.instance.isFavoriteMatch(m))
        .toList();
    if (favsInTopBucket.isEmpty) return matches;
    // Among favourites in the same bucket prefer the soonest start time.
    favsInTopBucket.sort((a, b) => UpcomingSort.matchStartTime(a)
        .compareTo(UpcomingSort.matchStartTime(b)));
    final lead = favsInTopBucket.first;
    // Already primary? leave the list untouched (avoids a needless reorder
    // that would otherwise re-seat the carousel on every poll).
    if (matches.first.id == lead.id) return matches;
    final rest = matches.where((m) => m.id != lead.id).toList();
    return [lead, ...rest];
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

  /// Builds the home body in the fixed target layout:
  /// Header → Hero carousel → Live/Upcoming/Finished tabs → Match sections →
  /// Featured Series. The search icon and quick-action cards were removed (the
  /// bottom nav already covers Matches/Schedule/Series/More). Admin per-section
  /// enable flags and ordering are still honoured for the carousel /
  /// main-list / featured-series toggles.
  List<Widget> _buildSections() {
    final cfg = _config;
    final hPad = context.horizontalPadding;
    // Small-device breathing-room pass: on compact phones (≤380px) the
    // section-to-section gaps are widened a few px so headings never sit right
    // on top of their content. Larger phones keep the existing spacing.
    final compact = context.w < 380;
    // The ListView is now full-bleed (no horizontal padding) so the hero
    // carousel can span nearly the full screen width. Every NON-hero section is
    // re-inset to the normal page padding via this helper; the hero carousel
    // instead uses its own small [_HeroMetrics.heroMargin] so it reads as one
    // dominant card with only a thin peek of its neighbours.
    Widget pad(Widget child) => Padding(
          padding: EdgeInsets.symmetric(horizontal: hPad),
          child: child,
        );
    final children = <Widget>[
      pad(_HomeHeader(
        onBell: widget.onOpenNotifications,
      )),
      // Breathing room between the CRICPRO logo row and the hero carousel's
      // cyan-bordered card.
      const SizedBox(height: 22),
    ];

    // 1. Hero carousel — full-bleed (NOT wrapped in `pad`).
    if (cfg.topFeatured.enabled) {
      children.add(_HeroMatchCarousel(
        future: _heroFuture,
        repository: _repository,
        onOpenMatch: widget.onOpenMatchDetails,
        onWatchLive: widget.onWatchLive,
        streamEpoch: _streamEpoch,
        onRetry: _refresh,
        showDots: cfg.topFeatured.showDots,
      ));
      children.add(const SizedBox(height: 22));
    }

    // Single authoritative selected-filter. The segmented-control highlight,
    // the section heading and the main list data source are ALL derived from
    // this one value, so they can never disagree. The user's tap is always
    // honoured — an empty Live tab stays on Live and renders the dedicated
    // Live empty state below (never a silent re-resolve to Upcoming that made
    // the Live tab feel dead).
    final resolvedTab =
        homeResolvedTab(selectedTab: topTab, liveLoadedEmpty: false);

    // 2. Live / Upcoming / Finished segmented control — highlights the RESOLVED
    // tab so the highlight always matches the heading + list below.
    if (cfg.mainMatches.enabled && cfg.mainMatches.showStatusTabs) {
      children.add(
          pad(_HomeStatusTabs(selected: resolvedTab, onChanged: _setTopTab)));
      children.add(const SizedBox(height: 18));
    }

    // 3. Main matches — heading + list both keyed off [resolvedTab]. An empty
    // Live tab renders the polished Live empty state (with a switch-to-Upcoming
    // CTA) under the "Live Matches" heading, so tab / heading / content always
    // agree.
    if (cfg.mainMatches.enabled) {
      children.add(pad(_SectionHeader(
        title: homeSectionHeading(resolvedTab),
        onSeeAll: widget.onOpenMatches ?? () {},
        showSeeAll: widget.onOpenMatches != null,
      )));
      children.add(SizedBox(height: compact ? 20 : 14));
      children.add(pad(_HomeMatchList(
        future: _tabFuture,
        data: _tabData,
        topTab: resolvedTab,
        repository: _repository,
        maxItems: cfg.mainMatches.maxItems,
        excludeIds: _heroIds,
        // Hold the list on a skeleton until the hero ids are known, but only
        // when the carousel is actually on screen (else there's nothing to
        // exclude and we'd skeleton needlessly). Prevents the hero match from
        // flashing in the list before it "moves" into the carousel.
        heroPending: cfg.topFeatured.enabled && !_heroSettled,
        showWatchLive: cfg.mainMatches.showWatchLive,
        showViewMatch: cfg.mainMatches.showViewMatch,
        onOpenMatch: widget.onOpenMatchDetails,
        onWatchLive: widget.onWatchLive,
        onReminder: widget.onOpenReminders,
        onSwitchUpcoming: () => _setTopTab(1),
        onRetry: _refresh,
      )));
    }

    // 4. Upcoming Matches — horizontal scroll teaser row. Shown only on the
    // Live and Finished tabs; hidden whenever Upcoming is the RESOLVED tab
    // (the real Upcoming tab OR the Live→Upcoming fallback) so upcoming content
    // is never duplicated as both the main list and the teaser.
    if (resolvedTab != 1) {
      children.add(pad(_UpcomingMatchesSection(
        future: _upcomingFuture,
        excludeIds: _heroIds,
        topSpacing: compact ? 32 : 26,
        onOpenMatch: widget.onOpenMatchDetails,
        onSeeAll: widget.onOpenSchedule ?? widget.onOpenMatches ?? () {},
      )));
    }

    // "More Upcoming Matches → Schedule" CTA at the end of the Upcoming main
    // list (Home keeps only today/tomorrow; Schedule has the full fixture list).
    // Follows the resolved tab so it appears in the fallback too.
    if (resolvedTab == 1 && widget.onOpenSchedule != null) {
      children
          .add(pad(_MoreUpcomingCta(onOpenSchedule: widget.onOpenSchedule!)));
    }

    // 5. Featured Series — always last.
    if (cfg.featuredSeries.enabled) {
      children.add(pad(_FeaturedSeriesSection(
        future: _feedFuture,
        config: cfg.featuredSeries,
        onSeeAll: widget.onOpenSeries,
        onOpenSeries: _openFeaturedSeries,
      )));
    }
    return children;
  }

  @override
  void dispose() {
    widget.reentrySignal?.removeListener(_onReentrySignal);
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _recoveryTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _configurePolling();
      // App came back to foreground — refresh now instead of waiting for the
      // next tick, so a score that moved while backgrounded is already updated.
      _kickImmediateRefresh('resume');
    } else {
      _pollTimer?.cancel();
      _pollTimer = null;
      _recoveryTimer?.cancel();
      _recoveryTimer = null;
    }
  }

  /// Called when the host shell re-selects the Home tab: silent refresh so the
  /// score is fresh the moment the user returns (no loader, no scroll jump).
  void _onReentrySignal() => _kickImmediateRefresh('tab-reenter');

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
  /// Throws if ALL sources fail (network offline) so hero shows offline state.
  Future<List<CricketMatch>> _loadHero({bool forceRefresh = false}) async {
    final items = <CricketMatch>[];
    final seen = <String>{};
    Object? lastError;

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
      } catch (e) {
        lastError = e;
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
      } catch (e) {
        lastError = e;
      }
    }
    // If we got zero matches and every source threw, propagate the error so
    // the hero FutureBuilder can show an offline card instead of empty state.
    if (items.isEmpty && lastError != null) {
      throw lastError!;
    }
    return _prioritiseHero(items.take(5).toList(growable: false))
        .take(5)
        .toList(growable: false);
  }

  /// Merged + sorted upcoming fixtures for the horizontal Upcoming row and the
  /// Live-empty fallback. Combines `/matches/upcoming` and `/schedule/upcoming`
  /// (deduped) then applies the shared favourite-aware time ordering, so Home
  /// reliably shows several upcoming cards instead of the 2 the matches feed
  /// alone returns. Degrades to an empty list on failure (section hides).
  Future<List<CricketMatch>> _loadUpcomingMerged(
      {bool forceRefresh = false}) async {
    try {
      final res =
          await _repository.upcomingMatchesMerged(forceRefresh: forceRefresh);
      // Home Upcoming is a SHORT teaser: de-dupe, keep only genuine upcoming
      // matches, and window to today + tomorrow (local). The full day-by-day
      // fixture list lives on the Schedule screen (see the "More Upcoming
      // Matches" CTA), so Home never floods with every future Cricbuzz match.
      return UpcomingSort.sortUpcoming(dedupeMatchesById(res.data))
          .where(isUpcomingMatch)
          .where(isTodayOrTomorrowLocal)
          .toList();
    } catch (_) {
      return const <CricketMatch>[];
    }
  }

  /// Matches for the selected tab. The Upcoming tab uses the merged + sorted
  /// upcoming feed (matches + schedule) so Home never shows a false "empty"
  /// state and lists every available fixture in favourite-aware time order.
  /// Throws on network failure so the UI can distinguish offline from empty.
  Future<List<CricketMatch>> _loadTabMatches(
      {bool forceRefresh = false}) async {
    final tab = topTab;
    if (tab == 1) {
      final res =
          await _repository.upcomingMatchesMerged(forceRefresh: forceRefresh);
      // De-dupe by id, then keep only genuinely-upcoming matches so a live/
      // scored match never leaks into the Upcoming list (same rules as Matches).
      final sorted = UpcomingSort.sortUpcoming(dedupeMatchesById(res.data))
          .where(isUpcomingMatch)
          .toList();
      _tabData = sorted;
      return sorted;
    }
    final res =
        await _repository.matchesForTab(tab, forceRefresh: forceRefresh);
    final deduped = dedupeMatchesById(res.data);
    // Keep only matches whose canonical phase matches the selected tab, so the
    // same match can't show in both Live and Finished sections.
    final filtered =
        deduped.where(tab == 0 ? isLiveMatch : isFinishedMatch).toList();
    _tabData = filtered;
    return filtered;
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
    if (!mounted) return;
    // Drop cached stream-availability so a stream the admin just added shows up
    // (Watch Live) on refresh without an app restart, and bump the epoch so the
    // hero/list CTAs re-resolve their availability against fresh data.
    _repository.invalidateStreamAvailability();
    _streamEpoch++;
    final tabFuture = _loadTabMatches(forceRefresh: true);
    setState(() {
      // Assign the Future directly so errors propagate to FutureBuilder
      // (snapshot.hasError = true → offline card shown).
      _tabFuture = tabFuture;
      _heroFuture = _resolveHero(forceRefresh: true);
      _feedFuture = _loadFeed(forceRefresh: true);
      _upcomingFuture = _loadUpcomingMerged(forceRefresh: true);
    });
    _captureHeroIds(_heroFuture);
    _feedFuture.then(_applyFeedConfig);
    _restoreScroll(oldOffset);
    // If polling was paused by an offline back-off, resume it once the network
    // is reachable again (refresh succeeded).
    try {
      await tabFuture;
      if (mounted && _pollTimer == null) _configurePolling();
    } catch (_) {
      // Still offline — leave polling paused; offline card + Retry handles it.
    }
  }

  void _configurePolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _recoveryTimer?.cancel();
    _recoveryTimer = null;
    // A live featured (hero) match must keep updating even when the user is on
    // the Upcoming/Finished tab, so the hero score never freezes. When the hero
    // is live we poll at the fast live cadence regardless of the selected tab.
    final heroLive = _heroData?.any((m) => m.isLive) ?? false;
    // Fast cadence (4s) matches the backend /app/live-scores ~4s cache TTL, so
    // the visible score advances within roughly a ball. The heavy membership
    // refresh is throttled internally (every _kMembershipEveryNTicks ticks), so
    // 4s polling does NOT mean refetching the heavy home feed every 4s.
    final interval = switch (topTab) {
      0 => const Duration(seconds: 4),
      1 => heroLive ? const Duration(seconds: 4) : const Duration(seconds: 90),
      _ => heroLive ? const Duration(seconds: 4) : null,
    };
    if (interval == null) return;
    if (_kHomeDebug) {
      final heroId = _heroData
              ?.map((m) => m.id)
              .firstWhere((id) => id.isNotEmpty, orElse: () => '') ??
          '';
      debugPrint('CricProHomePoll: configure tab=$topTab heroId=$heroId '
          'heroLive=$heroLive interval=${interval.inSeconds}s');
    }
    _pollTimer = Timer.periodic(interval, (_) => _silentPoll());
  }

  /// Re-arm live polling after a transient failure instead of staying paused
  /// until a manual pull-to-refresh. Single-shot with a small backoff.
  void _armRecovery() {
    if (!mounted || _recoveryTimer != null || _pollTimer != null) return;
    // Recover whenever there is something live to keep fresh: the Live tab, or
    // any tab while the featured hero is a live match. Otherwise a transient
    // offline blip would leave polling paused until a manual pull-to-refresh.
    final heroLive = _heroData?.any((m) => m.isLive) ?? false;
    if (topTab != 0 && !heroLive) return;
    final delay = Duration(
      seconds: (8 + 6 * _consecutivePollFailures).clamp(8, 40),
    );
    _recoveryTimer = Timer(delay, () async {
      _recoveryTimer = null;
      if (!mounted) return;
      if (_kHomeDebug) {
        debugPrint('CricProHomePoll: recovery fired '
            'failures=$_consecutivePollFailures delay=${delay.inSeconds}s');
      }
      try {
        if (topTab != 2) {
          final fresh = await _loadTabMatches(forceRefresh: true);
          if (!mounted) return;
          setState(() {
            _tabFuture = Future.value(fresh);
          });
        }
        await _refreshHeroSilently(null);
        if (!mounted) return;
        _consecutivePollFailures = 0;
        _configurePolling();
      } catch (_) {
        _consecutivePollFailures++;
        _armRecovery();
      }
    });
  }

  Future<void> _silentPoll() async {
    if (_polling || !mounted) return;
    _polling = true;
    final oldOffset =
        _scrollController.hasClients ? _scrollController.offset : null;
    try {
      _pollTick++;
      // Membership (matches starting/finishing, hero set changing) shifts slowly
      // — refresh the heavy list/hero only every Nth tick. The first tick always
      // does a full pass so an immediate refresh is complete.
      final doMembership =
          _pollTick == 1 || _pollTick % _kMembershipEveryNTicks == 0;

      // Finished tab (2) data doesn't change second-to-second; when the poll is
      // only running to keep a live hero fresh, skip the wasteful list refetch.
      final refreshTab = topTab != 2;
      if (refreshTab && doMembership) {
        final previous = _tabData;
        final fresh = await _loadTabMatches(forceRefresh: true);
        if (!mounted) return;
        _consecutivePollFailures = 0;
        final prevKey = previous == null
            ? ''
            : jsonEncode(previous.map(_refreshKey).toList());
        final newKey = jsonEncode(fresh.map(_refreshKey).toList());
        final changed = previous == null || prevKey != newKey;
        if (changed) {
          setState(() {
            _tabFuture = Future.value(fresh);
          });
          _restoreScroll(oldOffset);
        }
        if (_kHomeDebug) {
          debugPrint('CricProHomePoll: membership tab=$topTab '
              'listChanged=$changed applied=$changed '
              'prevLen=${previous?.length ?? 0} newLen=${fresh.length}');
        }
      }
      if (doMembership) {
        // The hero (featured) match is excluded from the list, so when it is the
        // only live game the list never changes and its score would otherwise
        // freeze. Repaints only when the hero content actually changed.
        await _refreshHeroSilently(oldOffset);
      }

      // Every tick: cheap live-score overlay from /app/live-scores for every
      // currently-visible live match (list + hero). This is what makes the
      // score advance within a ball without refetching the heavy home feed.
      await _overlayFastLiveScores(oldOffset);
      _consecutivePollFailures = 0;
    } catch (e) {
      // Classify the failure: code bugs (FlutterError, AssertionError) should
      // NOT arm offline recovery — they need a code fix, not a retry.
      final isCodeBug = e is FlutterError || e is AssertionError;
      if (_kHomeDebug) {
        final errType = switch (e) {
          SocketException _ || HttpException _ => 'network',
          TimeoutException _ => 'timeout',
          FormatException _ => 'parse',
          FlutterError _ || AssertionError _ => 'code_bug',
          _ => e.runtimeType.toString(),
        };
        debugPrint('CricProHomePoll: silentPoll FAILED errType=$errType '
            'failures=$_consecutivePollFailures '
            'msg=${e.toString().split('\n').first}');
        if (isCodeBug) {
          debugPrint('CricProHomePoll: CODE BUG — not arming network recovery');
        }
      }
      if (!isCodeBug) {
        _consecutivePollFailures++;
        _pollTimer?.cancel();
        _pollTimer = null;
        _armRecovery();
      } else {
        // Code bug: don't kill polling. The next tick may succeed if the bug
        // was transient (e.g. a race with dispose). If it recurs, the log makes
        // it obvious.
      }
    } finally {
      _polling = false;
    }
  }

  /// Re-resolves the hero carousel and only swaps it in when its content key
  /// changed, so a live featured match's score updates in place without
  /// blinking the carousel or losing the current page.
  /// Keeps the carousel from sliding when a silent poll returns the same set of
  /// matches in a (possibly) different order. If [resolved] has the SAME id set
  /// as the currently-displayed [_heroData], the previous order is preserved and
  /// each card is replaced by its fresh-by-id counterpart (so scores still
  /// update in place). If the membership actually changed (a match started or
  /// finished), the freshly-prioritised [resolved] order is adopted as-is.
  List<CricketMatch> _preserveHeroOrder(List<CricketMatch> resolved) =>
      preserveHeroOrder(_heroData, resolved);

  Future<void> _refreshHeroSilently(double? oldOffset) async {
    try {
      final resolved = await _resolveHero(forceRefresh: true);
      if (!mounted) return;
      // STABILITY: a silent poll must never REORDER the carousel — reordering
      // makes the position-based PageView show a different match under the same
      // page (the "hero slides on score update" bug). When the membership (set
      // of ids) is unchanged, keep the EXISTING visible order and overlay only
      // the fresh score/status by id. Only when matches actually start/finish
      // (membership changed) do we adopt the freshly-prioritised order.
      final freshHero = _preserveHeroOrder(resolved);
      final freshKey = _heroListKey(freshHero);
      if (_kHomeDebug) {
        final oldPrimary =
            _heroData?.isNotEmpty == true ? _heroData!.first : null;
        final newPrimary = freshHero.isNotEmpty ? freshHero.first : null;
        // Show per-hero score detail so empty scores are immediately visible.
        final heroDetails = freshHero
            .map((h) => '${h.id}(${homeTeamCode(h.teamAShort, h.teamA)}'
                ' ${h.teamAScoreText.isEmpty ? "?" : h.teamAScoreText}'
                ' | ${homeTeamCode(h.teamBShort, h.teamB)}'
                ' ${h.teamBScoreText.isEmpty ? "?" : h.teamBScoreText}'
                ' st=${h.status})')
            .join(', ');
        debugPrint('CricProHomeHero: refresh changed=${freshKey != _heroKey} '
            'primaryId=${newPrimary?.id ?? ''} '
            'old=[${oldPrimary?.teamAScoreText.isEmpty == false ? oldPrimary!.teamAScoreText : "empty"}'
            ' | ${oldPrimary?.teamBScoreText.isEmpty == false ? oldPrimary!.teamBScoreText : "empty"}] '
            'new=[${newPrimary?.teamAScoreText.isEmpty == false ? newPrimary!.teamAScoreText : "empty"}'
            ' | ${newPrimary?.teamBScoreText.isEmpty == false ? newPrimary!.teamBScoreText : "empty"}] '
            'statusText=${newPrimary?.statusText ?? ""} '
            'heroes=[$heroDetails]');
      }
      if (freshKey == _heroKey) return; // nothing changed — no repaint.
      _heroData = freshHero;
      _heroKey = freshKey;
      final primary = freshHero
          .map((m) => m.id)
          .firstWhere((id) => id.isNotEmpty, orElse: () => '');
      final ids = primary.isEmpty ? const <String>{} : {primary};
      setState(() {
        _heroFuture = Future.value(freshHero);
        if (!(ids.length == _heroIds.length && ids.containsAll(_heroIds))) {
          _heroIds = ids;
        }
      });
      _restoreScroll(oldOffset);
    } catch (_) {
      // Hero refresh failed — keep the last good hero; the tab poll's recovery
      // path handles the offline back-off.
    }
  }

  /// FAST PATH. Polls the lightweight `/app/live-scores` endpoint for every
  /// currently-visible LIVE match (list cards + hero) and overlays only the
  /// score/status fields onto the existing rich objects via
  /// [CricketMatch.mergeLiveScore]. Heavy metadata (streams, logos, title) is
  /// preserved. Repaints only when the visible score key actually moved, so
  /// there's no blink and scroll/carousel position is kept.
  Future<void> _overlayFastLiveScores(double? oldOffset) async {
    final liveIds = <String>{};
    for (final m in _tabData ?? const <CricketMatch>[]) {
      if (m.isLive && m.id.isNotEmpty) liveIds.add(m.id);
    }
    for (final m in _heroData ?? const <CricketMatch>[]) {
      if (m.isLive && m.id.isNotEmpty) liveIds.add(m.id);
    }
    if (liveIds.isEmpty) return; // nothing live → nothing to fast-poll.

    final res = await _repository.liveScores(liveIds.toList());
    if (!mounted) return;
    final freshById = <String, CricketMatch>{
      for (final m in res.data)
        if (m.id.isNotEmpty) m.id: m,
    };
    if (freshById.isEmpty) return;

    var listChanged = false;
    final tab = _tabData;
    List<CricketMatch>? mergedTab;
    if (tab != null) {
      mergedTab = [
        for (final m in tab)
          if (freshById[m.id] case final fresh?)
            () {
              final merged = m.mergeLiveScore(fresh);
              if (homeVisibleScoreKey(merged) != homeVisibleScoreKey(m)) {
                listChanged = true;
              }
              return merged;
            }()
          else
            m,
      ];
    }

    var heroChanged = false;
    final hero = _heroData;
    List<CricketMatch>? mergedHero;
    if (hero != null) {
      mergedHero = [
        for (final m in hero)
          if (freshById[m.id] case final fresh?)
            () {
              final merged = m.mergeLiveScore(fresh);
              if (homeVisibleScoreKey(merged) != homeVisibleScoreKey(m)) {
                heroChanged = true;
              }
              return merged;
            }()
          else
            m,
      ];
    }

    if (_kHomeDebug) {
      final sample = freshById.values.first;
      debugPrint('CricProHomeLiveScore: ids=${liveIds.toList()} '
          'fetched=${freshById.length} listChanged=$listChanged '
          'heroChanged=$heroChanged applied=${listChanged || heroChanged} '
          'sample=${sample.teamAShort} ${sample.teamAScoreText} | '
          '${sample.teamBShort} ${sample.teamBScoreText} '
          'cacheTtl=${res.meta.ttl}');
    }

    if (!listChanged && !heroChanged) return; // no visible change → no repaint.

    if (heroChanged && mergedHero != null) {
      _heroData = mergedHero;
      _heroKey = _heroListKey(mergedHero);
    }
    if (listChanged && mergedTab != null) {
      _tabData = mergedTab;
    }
    setState(() {
      if (listChanged && mergedTab != null) {
        _tabFuture = Future.value(mergedTab);
      }
      if (heroChanged && mergedHero != null) {
        _heroFuture = Future.value(mergedHero);
      }
    });
    _restoreScroll(oldOffset);
  }

  /// Content fingerprint for a match — delegates to the shared
  /// [homeVisibleScoreKey] so the poll's change-detection uses EXACTLY the
  /// fields the Home widgets render (id, status, statusText, resultText, both
  /// team score strings). Keeping one source of truth prevents the "key omits a
  /// visible field → listChanged=false while the score moved" freeze.
  String _refreshKey(CricketMatch m) => homeVisibleScoreKey(m);

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
                    remoteKey: 'home_backdrop',
                  ),
                  // Left floodlight glow.
                  Positioned(
                    top: -40,
                    left: -70,
                    child: GlowOrb(color: c.cyan, size: 220, alpha: .2),
                  ),
                  // Right floodlight glow.
                  Positioned(
                    top: 10,
                    right: -80,
                    child: GlowOrb(color: c.primary, size: 240, alpha: .18),
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
                  // Top scrim: caps the top band of the backdrop in SOLID page
                  // bg so the bright horizon inside the stadium art can never
                  // read as a line crossing the header. Stays fully opaque
                  // through the status bar + header, then fades into the stadium
                  // just above the hero. (Target header is clean dark navy.)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 230,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            c.bg,
                            c.bg,
                            c.bg.withValues(alpha: .0),
                          ],
                          stops: const [0, .5, 1],
                        ),
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
                // Full-bleed horizontally (0 side padding) so the hero carousel
                // spans nearly the whole screen; every non-hero section re-insets
                // itself to `context.horizontalPadding` via `_buildSections`.
                padding: EdgeInsets.fromLTRB(
                  0,
                  8,
                  0,
                  // Extra comfort gap over the shared floating nav so the LAST
                  // card scrolls fully clear of the bar (never clipped behind
                  // it). The base inset already accounts for the safe area.
                  context.mainScrollBottomInset + 16,
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
