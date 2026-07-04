import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../app_theme.dart';
import '../../components.dart';
import 'package:cricpro_flutter/services/analytics_service.dart';
import '../../models/ad_config.dart';
import '../../models/api_response.dart';
import '../../models/cricket_match.dart';
import '../../repositories/cricket_repository.dart';
import '../../upcoming_sort.dart';
import '../../utils/match_classification.dart';
import '../../utils/match_status.dart';
import '../../utils/team_format.dart';
import '../../widgets/ads/native_ad_card.dart';
import '../../widgets/team_score_view.dart';

part 'widgets/matches_header.dart';
part 'widgets/matches_cards.dart';

/// Premium Matches artwork assets (copied into assets/images/matches/).
class _MAsset {
  static const _base = 'assets/images/matches';
  static const topBg = '$_base/matches_top_bg.webp';
  static const cardBgLive = '$_base/match_card_bg_live.webp';
  static const cardBgUpcoming = '$_base/match_card_bg_upcoming.webp';
  static const cardBgFinished = '$_base/match_card_bg_finished.webp';
  static const vsStreak = '$_base/vs_light_streak.webp';
  static const vsGlow = '$_base/vs_glow_transparent.webp';

  static const _icons = '$_base/icons';
  static const iconBatBall = '$_icons/matches_bat_ball.webp';
  static const iconAll = '$_icons/category_all.webp';
  static const iconInternational = '$_icons/category_international.webp';
  static const iconLeague = '$_icons/category_league.webp';
  static const iconDomestic = '$_icons/category_domestic.webp';
  static const iconWatchLive = '$_icons/watch_live_play.webp';
  static const iconViewStats = '$_icons/view_match_stats.webp';
  static const iconLocation = '$_icons/location_pin.webp';
}

/// Draws a "light-on-black" RGB texture (e.g. the VS light streak, which has
/// no alpha channel) with [BlendMode.screen] so the dark background drops out
/// and only the light contributes — an additive glow over whatever is behind.
class _BlendImage extends StatefulWidget {
  const _BlendImage(this.asset, {this.width, this.height, this.opacity = 1.0});

  final String asset;
  final double? width;
  final double? height;
  final double opacity;

  @override
  State<_BlendImage> createState() => _BlendImageState();
}

class _BlendImageState extends State<_BlendImage> {
  static final Map<String, ui.Image> _cache = {};
  ui.Image? _image;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cached = _cache[widget.asset];
    if (cached != null) {
      _image = cached;
      return;
    }
    try {
      final data = await rootBundle.load(widget.asset);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      _cache[widget.asset] = frame.image;
      if (mounted) setState(() => _image = frame.image);
    } catch (_) {
      // Asset missing/undecodable — render nothing (graceful).
    }
  }

  @override
  Widget build(BuildContext context) {
    final img = _image;
    final size = Size(
      widget.width ?? (img?.width.toDouble() ?? 0),
      widget.height ?? (img?.height.toDouble() ?? 0),
    );
    if (img == null) return SizedBox(width: size.width, height: size.height);
    return CustomPaint(
      size: size,
      painter: _BlendPainter(img, widget.opacity),
    );
  }
}

class _BlendPainter extends CustomPainter {
  _BlendPainter(this.image, this.opacity);

  final ui.Image image;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..blendMode = BlendMode.screen
      ..filterQuality = FilterQuality.high
      ..color = Color.fromRGBO(255, 255, 255, opacity.clamp(0.0, 1.0));
    final src =
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    canvas.drawImageRect(image, src, Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(_BlendPainter old) =>
      old.image != image || old.opacity != opacity;
}

/// Premium Matches screen — stadium-atmosphere header with the CricPro
/// wordmark, a glassy status-tab switcher, category chips, and status-specific
/// match cards (live / upcoming / finished) with a glowing VS centerpiece and
/// premium action buttons. Backed by real repository data.
class MatchesScreen extends StatefulWidget {
  const MatchesScreen({
    super.key,
    required this.onOpenMatch,
    required this.onOpenFilters,
    required this.onOpenReminders,
    required this.onOpenSeries,
    required this.onWatchLive,
    this.initialTopTab = 0,
  });

  /// Invoked with the resolved match id (empty string allowed) when a card
  /// is tapped.
  final ValueChanged<String> onOpenMatch;
  final VoidCallback onOpenFilters;
  final VoidCallback onOpenReminders;
  final VoidCallback onOpenSeries;
  final ValueChanged<String> onWatchLive;

  /// Initial top-tab selection: 0 = Live, 1 = Upcoming, 2 = Finished.
  final int initialTopTab;

  @override
  State<MatchesScreen> createState() => _MatchesScreenState();
}

class _MatchesScreenState extends State<MatchesScreen>
    with WidgetsBindingObserver {
  late int topTab = widget.initialTopTab;
  int category = 0;
  final CricketRepository _repository = CricketRepository();
  final ScrollController _scrollController = ScrollController();
  late Future<ApiEnvelope<List<CricketMatch>>> _apiMatches;
  ApiEnvelope<List<CricketMatch>>? _apiMatchesData;
  Timer? _pollTimer;
  // Self-healing watchdog: re-arm live polling after a transient network error.
  Timer? _recoveryTimer;
  int _consecutivePollFailures = 0;
  bool _polling = false;

  static const _categories = <_Category>[
    _Category('All', _MAsset.iconAll, Icons.apps_rounded),
    _Category('International', _MAsset.iconInternational, Icons.public_rounded),
    _Category('League', _MAsset.iconLeague, Icons.emoji_events_rounded),
    _Category('Domestic', _MAsset.iconDomestic, Icons.shield_rounded),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AnalyticsService.instance.screenView('matches');
    _apiMatches = _loadMatches();
    _configurePolling();
  }

  @override
  void dispose() {
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
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _pollTimer?.cancel();
      _pollTimer = null;
      _recoveryTimer?.cancel();
      _recoveryTimer = null;
    }
  }

  Future<ApiEnvelope<List<CricketMatch>>> _loadMatches(
      {bool forceRefresh = false}) async {
    // Upcoming tab merges /matches/upcoming + /schedule/upcoming (deduped) and
    // applies the shared favourite-aware time ordering, so "All" shows every
    // available fixture — international + league + domestic — instead of the
    // 2 the matches feed alone returns.
    final response = topTab == 1
        ? await _loadUpcomingMerged(forceRefresh: forceRefresh)
        : await _repository.matchesForTab(topTab, forceRefresh: forceRefresh);
    _apiMatchesData = response;
    return response;
  }

  Future<ApiEnvelope<List<CricketMatch>>> _loadUpcomingMerged(
      {bool forceRefresh = false}) async {
    final res =
        await _repository.upcomingMatchesMerged(forceRefresh: forceRefresh);
    return ApiEnvelope(
      data: UpcomingSort.sortUpcoming(res.data),
      meta: res.meta,
    );
  }

  void _setTopTab(int value) {
    if (value == topTab) return;
    setState(() {
      topTab = value;
      _apiMatchesData = null;
      _apiMatches = _loadMatches();
    });
    _configurePolling();
  }

  Future<void> _refresh() async {
    // Manual pull-to-refresh (not auto-poll).
    AnalyticsService.instance.track('pull_refresh', {'screen_name': 'matches'});
    final oldOffset =
        _scrollController.hasClients ? _scrollController.offset : null;
    final response = await _loadMatches(forceRefresh: true);
    if (!mounted) return;
    setState(() => _apiMatches = Future.value(response));
    _restoreScroll(oldOffset);
    // Resume polling if an offline back-off paused it (refresh succeeded).
    if (_pollTimer == null) _configurePolling();
  }

  void _configurePolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _recoveryTimer?.cancel();
    _recoveryTimer = null;
    final interval = switch (topTab) {
      0 => const Duration(seconds: 10),
      1 => const Duration(seconds: 90),
      _ => null,
    };
    if (kDebugMode) {
      debugPrint(
          '[Polling] Matches tab=$topTab interval=${interval?.inSeconds}s');
    }
    if (interval == null) return;
    _pollTimer = Timer.periodic(interval, (_) => _silentPollVisibleTab());
  }

  /// Re-arm live polling after a transient failure instead of staying paused
  /// until a manual pull-to-refresh. Live tab (0) only.
  void _armRecovery() {
    if (!mounted || _recoveryTimer != null || _pollTimer != null) return;
    if (topTab != 0) return;
    final delay = Duration(
      seconds: (10 + 6 * _consecutivePollFailures).clamp(10, 40),
    );
    _recoveryTimer = Timer(delay, () async {
      _recoveryTimer = null;
      if (!mounted) return;
      try {
        final response = await _loadMatches(forceRefresh: true);
        if (!mounted) return;
        _consecutivePollFailures = 0;
        setState(() {
          _apiMatchesData = response;
          _apiMatches = Future.value(response);
        });
        _configurePolling();
      } catch (_) {
        _consecutivePollFailures++;
        _armRecovery();
      }
    });
  }

  Future<void> _silentPollVisibleTab() async {
    if (_polling || !mounted) return;
    _polling = true;
    final oldOffset =
        _scrollController.hasClients ? _scrollController.offset : null;
    try {
      final previous = _apiMatchesData;
      final response = await _loadMatches(forceRefresh: true);
      if (!mounted) return;
      _consecutivePollFailures = 0;
      final changed = previous == null ||
          jsonEncode(previous.data.map(_matchRefreshKey).toList()) !=
              jsonEncode(response.data.map(_matchRefreshKey).toList());
      _apiMatchesData = response;
      if (changed) {
        setState(() {});
        _restoreScroll(oldOffset);
      }
    } catch (_) {
      // Network failure while polling — pause the fast loop but arm a recovery
      // timer so polling resumes automatically once the network is back.
      _consecutivePollFailures++;
      _pollTimer?.cancel();
      _pollTimer = null;
      _armRecovery();
    } finally {
      _polling = false;
    }
  }

  void _restoreScroll(double? oldOffset) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (oldOffset != null && _scrollController.hasClients) {
        final restoredOffset = oldOffset.clamp(
          _scrollController.position.minScrollExtent,
          _scrollController.position.maxScrollExtent,
        );
        _scrollController.jumpTo(restoredOffset);
      }
    });
  }

  String _matchRefreshKey(CricketMatch match) {
    return [
      match.id,
      match.status,
      match.statusText,
      match.teamAScoreText,
      match.teamBScoreText,
    ].join('|');
  }

  /// Best-effort client-side category filter. The backend schedule does not
  /// expose a reliable category field, so "All" always shows everything and a
  /// specific category only narrows when it still yields matches (otherwise we
  /// keep the full list rather than show a misleading empty state).
  /// Keeps only matches whose canonical phase matches the selected tab
  /// (0 = Live, 1 = Upcoming, 2 = Finished). This is what stops a live match
  /// (it has a score / live status) from also appearing under Upcoming.
  List<CricketMatch> _phaseFilterForTab(List<CricketMatch> items) {
    return switch (topTab) {
      0 => items.where(isLiveMatch).toList(),
      1 => items.where(isUpcomingMatch).toList(),
      2 => items.where(isFinishedMatch).toList(),
      _ => items,
    };
  }

  List<CricketMatch> _applyCategory(List<CricketMatch> items) {
    if (category == 0) return items;
    bool matches(CricketMatch m) {
      // Route through the shared [UpcomingSort] classifier (the same one
      // Schedule and the repository use) so a match buckets the same way on
      // every screen — instead of a divergent inline regex whose token set
      // drifted (e.g. "cup"/"trophy" wrongly matched as Domestic).
      return switch (category) {
        1 => UpcomingSort.isInternationalMatch(m),
        2 => UpcomingSort.isMajorLeague(m),
        3 => UpcomingSort.isDomesticOrOther(m),
        _ => true,
      };
    }

    final filtered = items.where(matches).toList();
    return filtered.isEmpty ? items : filtered;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      decoration: BoxDecoration(gradient: c.bgGradient),
      child: Stack(
        children: [
          // Stadium atmosphere behind the header.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 230,
            child: IgnorePointer(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  const StadiumImage(
                    _MAsset.topBg,
                    alignment: Alignment.topCenter,
                    remoteKey: 'matches_backdrop',
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: c.stadiumOverlayColors,
                        stops: const [0, .4, .85, 1],
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
                  6,
                  context.horizontalPadding,
                  context.mainScrollBottomInset,
                ),
                children: [
                  _MatchesHeader(onBell: widget.onOpenReminders),
                  const SizedBox(height: 10),
                  const _SectionTitleRow(),
                  const SizedBox(height: 12),
                  _StatusTabs(selected: topTab, onChanged: _setTopTab),
                  const SizedBox(height: 11),
                  _CategoryChipsRow(
                    categories: _categories,
                    selected: category,
                    onSelect: (i) => setState(() => category = i),
                  ),
                  const SizedBox(height: 13),
                  _buildList(c),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(CricColors c) {
    return FutureBuilder<ApiEnvelope<List<CricketMatch>>>(
      future: _apiMatches,
      builder: (context, snapshot) {
        final rawItems = _apiMatchesData?.data ??
            snapshot.data?.data ??
            const <CricketMatch>[];
        // Reconcile the feed: de-dupe by id and keep only matches that truly
        // belong to the selected tab's phase, so a match never shows in both
        // Live and Upcoming (the backend feeds can overlap by id).
        final apiItems = _phaseFilterForTab(dedupeMatchesById(rawItems));

        if (_apiMatchesData == null &&
            snapshot.connectionState == ConnectionState.waiting &&
            apiItems.isEmpty) {
          return const _MatchesSkeletonList();
        }

        if (_apiMatchesData == null && snapshot.hasError && apiItems.isEmpty) {
          return _StateCard(
            icon: Icons.cloud_off_rounded,
            title: 'Unable to load matches',
            message: 'Please check your connection and try again.',
            action: 'Retry',
            onAction: () =>
                setState(() => _apiMatches = _loadMatches(forceRefresh: true)),
          );
        }

        final items = _applyCategory(apiItems);

        if (items.isEmpty) {
          return _StateCard(
            icon: topTab == 0
                ? Icons.sports_cricket_rounded
                : Icons.event_busy_rounded,
            title:
                topTab == 0 ? 'No live matches right now' : 'No matches found',
            message: topTab == 0
                ? 'Upcoming fixtures are ready when you want to look ahead.'
                : 'Please refresh or try a different category.',
            action: topTab == 0 ? 'View Upcoming' : 'Refresh',
            onAction: topTab == 0
                ? () => _setTopTab(1)
                : () => setState(
                    () => _apiMatches = _loadMatches(forceRefresh: true)),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < items.length; i++) ...[
              Padding(
                // Key by match id so a silent score-only refresh updates each
                // card in place instead of recycling element state by position.
                key: ValueKey('matches-card-${items[i].id}'),
                padding: const EdgeInsets.only(bottom: 14),
                child: _buildCard(items[i]),
              ),
              if ((i + 1) % 5 == 0)
                const Padding(
                  padding: EdgeInsets.only(bottom: 14),
                  child: NativeAdCard(placement: AdPlacement.matches),
                ),
            ],
          ],
        );
      },
    );
  }

  Widget _buildCard(CricketMatch match) {
    final id = match.id;
    void open() => widget.onOpenMatch(id);
    // Card style is driven by the match's real status only — never by the
    // active tab — so a mixed feed renders each card with its correct style.
    if (match.isFinished) {
      return _FinishedCard(match: match, onViewMatch: open);
    }
    if (match.isLive) {
      return _StreamAwareLiveCard(
        match: match,
        matchId: id,
        onViewMatch: open,
        onWatchLive: widget.onWatchLive,
      );
    }
    return _UpcomingCard(match: match, onViewMatch: open);
  }
}

class _Category {
  const _Category(this.label, this.asset, this.icon);
  final String label;
  final String asset;
  final IconData icon;
}

// ---------------------------------------------------------------------------
// Header + section title
// ---------------------------------------------------------------------------

