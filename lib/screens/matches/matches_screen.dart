import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../app_theme.dart';
import '../../components.dart';
import '../../models/ad_config.dart';
import '../../models/api_response.dart';
import '../../models/cricket_match.dart';
import '../../repositories/cricket_repository.dart';
import '../../widgets/ads/native_ad_card.dart';

/// Premium Matches artwork assets (copied into assets/images/matches/).
class _MAsset {
  static const _base = 'assets/images/matches';
  static const topBg = '$_base/matches_top_bg.png';
  static const cardBg = '$_base/match_card_bg.png';
  static const cardBgLive = '$_base/match_card_bg_live.png';
  static const cardBgUpcoming = '$_base/match_card_bg_upcoming.png';
  static const cardBgFinished = '$_base/match_card_bg_finished.png';
  static const vsStreak = '$_base/vs_light_streak.png';
  static const vsGlow = '$_base/vs_glow_transparent.png';

  static const _icons = '$_base/icons';
  static const iconBatBall = '$_icons/matches_bat_ball.png';
  static const iconAll = '$_icons/category_all.png';
  static const iconInternational = '$_icons/category_international.png';
  static const iconLeague = '$_icons/category_league.png';
  static const iconDomestic = '$_icons/category_domestic.png';
  static const iconWatchLive = '$_icons/watch_live_play.png';
  static const iconViewStats = '$_icons/view_match_stats.png';
  static const iconLocation = '$_icons/location_pin.png';
  static const iconBell = '$_icons/bell.png';
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
    _apiMatches = _loadMatches();
    _configurePolling();
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
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  Future<ApiEnvelope<List<CricketMatch>>> _loadMatches(
      {bool forceRefresh = false}) async {
    final response =
        await _repository.matchesForTab(topTab, forceRefresh: forceRefresh);
    _apiMatchesData = response;
    return response;
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
    final oldOffset =
        _scrollController.hasClients ? _scrollController.offset : null;
    final response = await _loadMatches(forceRefresh: true);
    if (!mounted) return;
    setState(() => _apiMatches = Future.value(response));
    _restoreScroll(oldOffset);
  }

  void _configurePolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
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

  Future<void> _silentPollVisibleTab() async {
    if (_polling || !mounted) return;
    _polling = true;
    final oldOffset =
        _scrollController.hasClients ? _scrollController.offset : null;
    try {
      final previous = _apiMatchesData;
      final response =
          await _repository.matchesForTab(topTab, forceRefresh: true);
      if (!mounted) return;
      final changed = previous == null ||
          jsonEncode(previous.data.map(_matchRefreshKey).toList()) !=
              jsonEncode(response.data.map(_matchRefreshKey).toList());
      _apiMatchesData = response;
      if (changed) {
        setState(() {});
        _restoreScroll(oldOffset);
      }
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
  List<CricketMatch> _applyCategory(List<CricketMatch> items) {
    if (category == 0) return items;
    bool matches(CricketMatch m) {
      final s = '${m.series} ${m.matchDesc}'.toLowerCase();
      return switch (category) {
        1 => RegExp(
                r'(international|tour|world cup|champions|series|t20i|odi|test|trophy|asia cup|bilateral)')
            .hasMatch(s),
        2 => RegExp(
                r'(league|premier|ipl|bbl|psl|cpl|the hundred|blast|super smash|t20 mumbai|ilt20)')
            .hasMatch(s),
        3 => RegExp(
                r'(county|domestic|ranji|shield|cup|division|trophy|first[- ]class|state)')
            .hasMatch(s),
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
                  Image.asset(
                    _MAsset.topBg,
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
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
                  context.mainBottomPadding + 88,
                ),
                children: [
                  _MatchesHeader(onBell: widget.onOpenReminders),
                  const SizedBox(height: 10),
                  _SectionTitleRow(onSeeAll: widget.onOpenSeries),
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
        final apiItems = _apiMatchesData?.data ??
            snapshot.data?.data ??
            const <CricketMatch>[];

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

class _MatchesHeader extends StatelessWidget {
  const _MatchesHeader({required this.onBell});

  final VoidCallback onBell;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // CRICPRO wordmark — rendered as a tight italic RichText so the two
        // halves read as one word (the PNG wordmark has an uneven gap).
        _wordmark(c),
        const Spacer(),
        _BellButton(onTap: onBell),
      ],
    );
  }

  Widget _wordmark(CricColors c) {
    return Transform.rotate(
      angle: -0.04,
      child: RichText(
        text: TextSpan(
          style: const TextStyle(
            fontSize: 36,
            fontWeight: FontWeight.w900,
            fontStyle: FontStyle.italic,
            letterSpacing: -0.5,
            height: 1,
          ),
          children: [
            TextSpan(text: 'CRIC', style: TextStyle(color: c.text)),
            TextSpan(text: 'PRO', style: TextStyle(color: c.cyan)),
          ],
        ),
      ),
    );
  }
}

class _BellButton extends StatelessWidget {
  const _BellButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: c.card.withValues(alpha: .55),
          border: Border.all(color: c.cyan.withValues(alpha: .35)),
          boxShadow: [
            BoxShadow(
              color: c.cyan.withValues(alpha: .16),
              blurRadius: 16,
              spreadRadius: -4,
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Image.asset(
          _MAsset.iconBell,
          width: 21,
          height: 21,
          color: c.text,
          errorBuilder: (_, __, ___) =>
              Icon(Icons.notifications_none_rounded, color: c.text, size: 22),
        ),
      ),
    );
  }
}

class _SectionTitleRow extends StatelessWidget {
  const _SectionTitleRow({required this.onSeeAll});

  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Row(
      children: [
        Image.asset(
          _MAsset.iconBatBall,
          width: 24,
          height: 24,
          color: c.cyan,
          errorBuilder: (_, __, ___) =>
              Icon(Icons.sports_cricket_rounded, color: c.cyan, size: 22),
        ),
        const SizedBox(width: 10),
        Text(
          'Matches',
          style: TextStyle(
            color: c.text,
            fontWeight: FontWeight.w900,
            fontSize: context.sp(22),
          ),
        ),
        const Spacer(),
        GestureDetector(
          onTap: onSeeAll,
          behavior: HitTestBehavior.opaque,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'See All',
                style: TextStyle(
                  color: c.muted,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 3),
              Icon(Icons.chevron_right_rounded, color: c.cyan, size: 20),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Status tabs
// ---------------------------------------------------------------------------

class _StatusTabs extends StatelessWidget {
  const _StatusTabs({required this.selected, required this.onChanged});

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
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: c.card.withValues(alpha: .42),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: c.cyan.withValues(alpha: .3)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < _tabs.length; i++)
            Expanded(
              child: _StatusTab(
                label: _tabs[i].$1,
                icon: _tabs[i].$2,
                selected: i == selected,
                onTap: () => onChanged(i),
              ),
            ),
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
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: selected
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    c.cyan.withValues(alpha: .55),
                    c.primary.withValues(alpha: .42),
                  ],
                )
              : null,
          borderRadius: BorderRadius.circular(20),
          border: selected
              ? Border.all(color: c.cyan.withValues(alpha: .95), width: 1.5)
              : null,
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: c.cyan.withValues(alpha: .42),
                    blurRadius: 18,
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
            Icon(
              icon,
              size: 16,
              color: selected ? Colors.white : c.muted,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? Colors.white : c.muted,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  fontSize: 13.5,
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
// Category chips
// ---------------------------------------------------------------------------

class _CategoryChipsRow extends StatelessWidget {
  const _CategoryChipsRow({
    required this.categories,
    required this.selected,
    required this.onSelect,
  });

  final List<_Category> categories;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 9),
        itemBuilder: (_, i) => _CategoryChip(
          category: categories[i],
          selected: i == selected,
          onTap: () => onSelect(i),
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final _Category category;
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
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          gradient: selected
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    c.cyan.withValues(alpha: .55),
                    c.primary.withValues(alpha: .42),
                  ],
                )
              : null,
          color: selected ? null : c.card.withValues(alpha: .42),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? c.cyan.withValues(alpha: .95)
                : c.cyan.withValues(alpha: .35),
            width: selected ? 1.5 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: c.cyan.withValues(alpha: .4),
                    blurRadius: 15,
                    spreadRadius: -2,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              category.asset,
              width: 16,
              height: 16,
              color: selected ? Colors.white : c.cyan,
              errorBuilder: (_, __, ___) => Icon(
                category.icon,
                size: 15,
                color: selected ? Colors.white : c.cyan,
              ),
            ),
            const SizedBox(width: 7),
            Text(
              category.label,
              style: TextStyle(
                color: selected ? Colors.white : c.text,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Match cards
// ---------------------------------------------------------------------------

/// Shared premium card shell: stadium background, dark overlay, cyan border,
/// edge glow and the standard content padding.
class _MatchCardShell extends StatelessWidget {
  const _MatchCardShell({
    required this.bg,
    required this.accent,
    required this.onTap,
    required this.child,
  });

  final String bg;
  final Color accent;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return TapScale(
      onTap: onTap,
      borderRadius: 20,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: c.cyan.withValues(alpha: .4)),
          boxShadow: c.heroShadow,
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                bg,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Image.asset(
                  _MAsset.cardBg,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
            // Readability overlay — kept very light so the stadium shows.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: c.isDark
                        ? [
                            const Color(0xff0a2240).withValues(alpha: .16),
                            c.card.withValues(alpha: .08),
                            const Color(0xff06182c).withValues(alpha: .32),
                          ]
                        : [
                            Colors.white.withValues(alpha: .30),
                            c.card.withValues(alpha: .20),
                            Colors.white.withValues(alpha: .45),
                          ],
                  ),
                ),
              ),
            ),
            // Bottom-up dark gradient so the score / venue / buttons stay
            // readable over the brighter stadium texture.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.center,
                    colors: c.isDark
                        ? [
                            const Color(0xff041020).withValues(alpha: .48),
                            Colors.transparent,
                          ]
                        : [
                            Colors.white.withValues(alpha: .55),
                            Colors.transparent,
                          ],
                  ),
                ),
              ),
            ),
            // Compact cyan glow only behind the VS centre — not a full-card fog.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.18),
                    radius: .45,
                    colors: [
                      c.cyan.withValues(alpha: .08),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            // Top edge glow line — subtle status tint (red live / green
            // finished / cyan upcoming).
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 2.5,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      accent.withValues(alpha: .42),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(11, 7, 11, 7),
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}

/// Top row shared by all cards: status badge + series name, then date/time.
class _CardTopRow extends StatelessWidget {
  const _CardTopRow({required this.match, required this.kind});

  final CricketMatch match;
  final _CardKind kind;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _StatusBadge(kind: kind),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            match.series,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: c.cyan,
              fontWeight: FontWeight.w800,
              fontSize: 12.5,
              letterSpacing: .1,
            ),
          ),
        ),
        const SizedBox(width: 7),
        Text(
          _dateTimeLabel(match),
          maxLines: 1,
          style: TextStyle(
            color: c.muted,
            fontWeight: FontWeight.w700,
            fontSize: 10.5,
          ),
        ),
      ],
    );
  }
}

enum _CardKind { live, upcoming, finished }

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.kind});

  final _CardKind kind;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final (label, color, filled) = switch (kind) {
      _CardKind.live => ('LIVE', c.live, true),
      _CardKind.upcoming => ('UPCOMING', c.cyan, false),
      _CardKind.finished => ('FINISHED', c.success, true),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color:
            filled ? color.withValues(alpha: .2) : color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: filled ? .85 : .6)),
        boxShadow: kind == _CardKind.live
            ? [BoxShadow(color: color.withValues(alpha: .35), blurRadius: 10)]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (kind == _CardKind.live) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 10.5,
              letterSpacing: .4,
            ),
          ),
        ],
      ),
    );
  }
}

/// A team block — large circular logo, short code, full name, optional score.
class _TeamBlock extends StatelessWidget {
  const _TeamBlock({
    required this.name,
    required this.short,
    required this.logo,
    required this.accent,
    this.score,
  });

  final String name;
  final String short;
  final String? logo;
  final Color accent;
  final String? score;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final code = short.isEmpty ? name : short;
    final upper = code.toUpperCase();
    final isPlaceholder = upper == 'TBC' || upper == 'TBD' || upper.isEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: c.cyan.withValues(alpha: .32),
                blurRadius: 16,
                spreadRadius: -2,
              ),
            ],
          ),
          child: TeamLogoWidget(
            logoUrl: isPlaceholder ? null : logo,
            teamName: name,
            abbreviation: code,
            color: accent,
            size: 57,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          upper,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: c.text,
            fontWeight: FontWeight.w900,
            fontSize: 16.5,
            height: 1,
          ),
        ),
        if (name.isNotEmpty && name.toUpperCase() != upper) ...[
          const SizedBox(height: 1),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: c.muted,
              fontWeight: FontWeight.w600,
              fontSize: 10.5,
            ),
          ),
        ],
        if (score != null && score!.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            score!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: c.text,
              fontWeight: FontWeight.w800,
              fontSize: 11,
              height: 1.1,
            ),
          ),
        ],
      ],
    );
  }
}

/// Premium glowing VS centerpiece. The diagonal electric streak + radial glow
/// (from the supplied assets, plus a pure-Flutter bloom) spread wide behind a
/// real Flutter "VS" badge — the badge is drawn in Flutter (not the asset) so
/// it is always large, crisp and on-brand, matching the broadcast target.
class _VsCenterpiece extends StatelessWidget {
  const _VsCenterpiece();

  static const double visualWidth = 124;
  static const double visualHeight = 48;
  static const double badgeWidth = 50;
  static const double badgeHeight = 30;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return SizedBox(
      width: visualWidth,
      height: visualHeight,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // Soft elongated bloom (kept subtle — the diagonal streak carries the
          // energy, not a round teal fog).
          Container(
            width: visualWidth * .85,
            height: 46,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(40),
              gradient: RadialGradient(
                colors: [
                  c.cyan.withValues(alpha: .28),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          // Glow asset (has alpha).
          Image.asset(
            _MAsset.vsGlow,
            width: visualWidth * 1.05,
            height: 70,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
          // Long diagonal electric light streak (RGB no-alpha → screen blend).
          Transform.rotate(
            angle: -0.5,
            child: const _BlendImage(
              _MAsset.vsStreak,
              width: 162,
              height: 36,
              opacity: .95,
            ),
          ),
          // Real Flutter VS badge — flat, compact, slanted dark-glass chip with
          // a bright cyan border and white "VS".
          Transform(
            alignment: Alignment.center,
            transform: Matrix4.skewX(-0.2),
            child: Container(
              width: badgeWidth,
              height: badgeHeight,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xff10385f), Color(0xff05121f)],
                ),
                border: Border.all(
                    color: c.cyan.withValues(alpha: .98), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: c.cyan.withValues(alpha: .6),
                    blurRadius: 12,
                    spreadRadius: -2,
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.skewX(0.2),
                child: Text(
                  'VS',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    letterSpacing: .5,
                    shadows: [
                      Shadow(color: c.cyan, blurRadius: 10),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Venue row: location pin + venue text.
class _VenueRow extends StatelessWidget {
  const _VenueRow({required this.venue});

  final String venue;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final text = venue.trim().isEmpty ? 'Venue TBC' : venue.trim();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Image.asset(
          _MAsset.iconLocation,
          width: 14,
          height: 14,
          color: c.cyan,
          errorBuilder: (_, __, ___) =>
              Icon(Icons.location_on_outlined, color: c.cyan, size: 15),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: c.muted,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }
}

/// Premium outlined action button (icon + label) with cyan glow.
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.onTap,
    this.asset,
    this.icon,
    this.compact = false,
  });

  final String label;
  final VoidCallback onTap;
  final String? asset;
  final IconData? icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 36,
        padding: compact
            ? const EdgeInsets.symmetric(horizontal: 16)
            : EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: c.card2.withValues(alpha: .45),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.cyan.withValues(alpha: .45)),
        ),
        alignment: compact ? null : Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (asset != null)
              Image.asset(
                asset!,
                width: 16,
                height: 16,
                color: c.cyan,
                errorBuilder: (_, __, ___) => Icon(
                  icon ?? Icons.play_arrow_rounded,
                  size: 16,
                  color: c.cyan,
                ),
              )
            else if (icon != null)
              Icon(icon, size: 16, color: c.cyan),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: c.text,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Segmented glass action bar for live cards: Watch Live | View Match, divided
/// by a thin cyan line. The Watch Live segment reflects the stream check —
/// active when a stream exists, a spinner while checking, and dimmed/disabled
/// when no stream is available — so the live card always matches the target.
class _DualActionBar extends StatelessWidget {
  const _DualActionBar({
    required this.watchState,
    required this.onWatchLive,
    required this.onViewMatch,
  });

  final _WatchState watchState;
  final VoidCallback onWatchLive;
  final VoidCallback onViewMatch;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      height: 38,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.card2.withValues(alpha: .42),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.cyan.withValues(alpha: .45)),
      ),
      child: Row(
        children: [
          Expanded(child: _watchSegment(c)),
          Container(width: 1, color: c.cyan.withValues(alpha: .3)),
          Expanded(
            child: _DualSegment(
              label: 'View Match',
              asset: _MAsset.iconViewStats,
              icon: Icons.bar_chart_rounded,
              onTap: onViewMatch,
            ),
          ),
        ],
      ),
    );
  }

  Widget _watchSegment(CricColors c) {
    switch (watchState) {
      case _WatchState.available:
        return _DualSegment(
          label: 'Watch Live',
          asset: _MAsset.iconWatchLive,
          icon: Icons.play_arrow_rounded,
          onTap: onWatchLive,
        );
      case _WatchState.pending:
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 13,
              height: 13,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(c.cyan),
              ),
            ),
            const SizedBox(width: 7),
            Text(
              'Watch Live',
              style: TextStyle(
                color: c.muted,
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
              ),
            ),
          ],
        );
      case _WatchState.none:
        return const Opacity(
          opacity: .4,
          child: _DualSegment(
            label: 'Watch Live',
            asset: _MAsset.iconWatchLive,
            icon: Icons.play_arrow_rounded,
            onTap: null,
          ),
        );
    }
  }
}

class _DualSegment extends StatelessWidget {
  const _DualSegment({
    required this.label,
    required this.asset,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String asset;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            asset,
            width: 15,
            height: 15,
            color: c.cyan,
            errorBuilder: (_, __, ___) => Icon(icon, size: 15, color: c.cyan),
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.text,
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --- Live card -------------------------------------------------------------
/// Resolves (async) whether a Watch Live button should be shown for a live
/// match, then renders the live card. Preserves the original stream-aware
/// behaviour from the previous implementation.
class _StreamAwareLiveCard extends StatelessWidget {
  const _StreamAwareLiveCard({
    required this.match,
    required this.matchId,
    required this.onViewMatch,
    required this.onWatchLive,
  });

  final CricketMatch match;
  final String matchId;
  final VoidCallback onViewMatch;
  final ValueChanged<String> onWatchLive;

  @override
  Widget build(BuildContext context) {
    if (matchId.isEmpty) {
      return _LiveCard(
        match: match,
        watchState: _WatchState.none,
        onViewMatch: onViewMatch,
        onWatchLive: () {},
      );
    }
    final future = match.hasStreamInfo
        ? CricketRepository().shouldShowWatchLiveForMatch(match)
        : CricketRepository().hasPlayableStreams(matchId);
    return FutureBuilder<bool>(
      future: future,
      builder: (context, snapshot) {
        final state = snapshot.connectionState == ConnectionState.waiting
            ? _WatchState.pending
            : (snapshot.data == true
                ? _WatchState.available
                : _WatchState.none);
        return _LiveCard(
          match: match,
          watchState: state,
          onViewMatch: onViewMatch,
          onWatchLive: () => onWatchLive(matchId),
        );
      },
    );
  }
}

enum _WatchState { pending, available, none }

class _LiveCard extends StatelessWidget {
  const _LiveCard({
    required this.match,
    required this.watchState,
    required this.onViewMatch,
    required this.onWatchLive,
  });

  final CricketMatch match;
  final _WatchState watchState;
  final VoidCallback onViewMatch;
  final VoidCallback onWatchLive;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final scoreLine = match.scoreLine;
    final note = match.statusText.isNotEmpty ? match.statusText : '';
    return _MatchCardShell(
      bg: _MAsset.cardBgLive,
      accent: c.live,
      onTap: onViewMatch,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardTopRow(match: match, kind: _CardKind.live),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: _TeamBlock(
                  name: match.teamA,
                  short: match.teamAShort,
                  logo: match.teamALogo,
                  accent: c.cyan,
                ),
              ),
              const _VsCenterpiece(),
              Expanded(
                child: _TeamBlock(
                  name: match.teamB,
                  short: match.teamBShort,
                  logo: match.teamBLogo,
                  accent: c.warning,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          if (scoreLine.isNotEmpty)
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 280),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    scoreLine,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    style: TextStyle(
                      color: c.live,
                      fontWeight: FontWeight.w700,
                      fontSize: 11.5,
                    ),
                  ),
                ),
              ),
            ),
          if (note.isNotEmpty) ...[
            const SizedBox(height: 1),
            Text(
              note,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.muted,
                fontWeight: FontWeight.w600,
                fontSize: 10.5,
              ),
            ),
          ],
          const SizedBox(height: 5),
          _VenueRow(venue: match.venue),
          const SizedBox(height: 5),
          _DualActionBar(
            watchState: watchState,
            onWatchLive: onWatchLive,
            onViewMatch: onViewMatch,
          ),
        ],
      ),
    );
  }
}

// --- Upcoming card ---------------------------------------------------------

class _UpcomingCard extends StatelessWidget {
  const _UpcomingCard({required this.match, required this.onViewMatch});

  final CricketMatch match;
  final VoidCallback onViewMatch;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return _MatchCardShell(
      bg: _MAsset.cardBgUpcoming,
      accent: c.cyan,
      onTap: onViewMatch,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardTopRow(match: match, kind: _CardKind.upcoming),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: _TeamBlock(
                  name: match.teamA,
                  short: match.teamAShort,
                  logo: match.teamALogo,
                  accent: c.cyan,
                ),
              ),
              const _VsCenterpiece(),
              Expanded(
                child: _TeamBlock(
                  name: match.teamB,
                  short: match.teamBShort,
                  logo: match.teamBLogo,
                  accent: c.warning,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _Countdown(start: match.startDateTime, fallback: match.startTime),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _VenueRow(venue: match.venue)),
              const SizedBox(width: 10),
              _ActionButton(
                label: 'View Match',
                asset: _MAsset.iconViewStats,
                icon: Icons.bar_chart_rounded,
                onTap: onViewMatch,
                compact: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Live ticking countdown (HHh : MMm : SSs) to the match start, with a
/// "Match yet to begin" subtext. Falls back to the scheduled time text.
class _Countdown extends StatefulWidget {
  const _Countdown({required this.start, required this.fallback});

  final DateTime? start;
  final String fallback;

  @override
  State<_Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<_Countdown> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.start != null) {
      _timer = Timer.periodic(
          const Duration(seconds: 1), (_) => mounted ? setState(() {}) : null);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final start = widget.start?.toLocal();
    final now = DateTime.now();
    String primary;
    if (start != null && start.isAfter(now)) {
      final diff = start.difference(now);
      final h = diff.inHours.toString().padLeft(2, '0');
      final m = (diff.inMinutes % 60).toString().padLeft(2, '0');
      final s = (diff.inSeconds % 60).toString().padLeft(2, '0');
      primary = '${h}h : ${m}m : ${s}s';
    } else {
      primary = widget.fallback.isNotEmpty ? widget.fallback : 'Starting soon';
    }
    return Column(
      children: [
        Text(
          primary,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: c.cyan,
            fontWeight: FontWeight.w900,
            fontSize: 15,
            letterSpacing: .5,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          'Match yet to begin',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: c.muted,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

// --- Finished card ---------------------------------------------------------

class _FinishedCard extends StatelessWidget {
  const _FinishedCard({required this.match, required this.onViewMatch});

  final CricketMatch match;
  final VoidCallback onViewMatch;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final result = match.resultText.isNotEmpty
        ? match.resultText
        : (match.statusText.isNotEmpty ? match.statusText : 'Match finished');
    return _MatchCardShell(
      bg: _MAsset.cardBgFinished,
      accent: c.success,
      onTap: onViewMatch,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardTopRow(match: match, kind: _CardKind.finished),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: _TeamBlock(
                  name: match.teamA,
                  short: match.teamAShort,
                  logo: match.teamALogo,
                  accent: c.cyan,
                  score: match.teamAScoreText,
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                flex: 0,
                child: _ResultBadge(result: result),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _TeamBlock(
                  name: match.teamB,
                  short: match.teamBShort,
                  logo: match.teamBLogo,
                  accent: c.warning,
                  score: match.teamBScoreText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _VenueRow(venue: match.venue)),
              const SizedBox(width: 10),
              _ActionButton(
                label: 'View Match',
                asset: _MAsset.iconViewStats,
                icon: Icons.bar_chart_rounded,
                onTap: onViewMatch,
                compact: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Prominent green result badge for finished matches, e.g. "AUS WON BY 31 RUNS".
class _ResultBadge extends StatelessWidget {
  const _ResultBadge({required this.result});

  final String result;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      constraints: const BoxConstraints(maxWidth: 130),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: c.success.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.success.withValues(alpha: .7)),
        boxShadow: [
          BoxShadow(
            color: c.success.withValues(alpha: .25),
            blurRadius: 14,
            spreadRadius: -2,
          ),
        ],
      ),
      child: Text(
        result.toUpperCase(),
        textAlign: TextAlign.center,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: c.success,
          fontWeight: FontWeight.w900,
          fontSize: 12,
          height: 1.2,
          letterSpacing: .2,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Date helper
// ---------------------------------------------------------------------------

/// Formats a match start as "Jun 7 • 03:30 PM" (12-hour), matching the target.
String _dateTimeLabel(CricketMatch match) {
  final dt = match.startDateTime?.toLocal();
  if (dt == null) {
    return match.statusText.isNotEmpty ? match.statusText : match.startTime;
  }
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];
  var hour = dt.hour % 12;
  if (hour == 0) hour = 12;
  final ampm = dt.hour >= 12 ? 'PM' : 'AM';
  final mm = dt.minute.toString().padLeft(2, '0');
  return '${months[dt.month - 1]} ${dt.day} • '
      '${hour.toString().padLeft(2, '0')}:$mm $ampm';
}

// ---------------------------------------------------------------------------
// Skeleton + state card
// ---------------------------------------------------------------------------

class _MatchesSkeletonList extends StatelessWidget {
  const _MatchesSkeletonList();

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Column(
      children: [
        for (var i = 0; i < 3; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Container(
              height: 210,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                color: c.card.withValues(alpha: .5),
                border: Border.all(color: c.border.withValues(alpha: .5)),
              ),
            ),
          ),
      ],
    );
  }
}

class _StateCard extends StatelessWidget {
  const _StateCard({
    required this.icon,
    required this.title,
    required this.message,
    required this.action,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        children: [
          Icon(icon, color: c.cyan, size: 38),
          const SizedBox(height: 12),
          Text(title,
              style: TextStyle(
                  color: c.text, fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text(message,
              textAlign: TextAlign.center,
              style: TextStyle(color: c.muted, height: 1.4)),
          const SizedBox(height: 16),
          GradientButton(
              label: action, icon: Icons.refresh_rounded, onTap: onAction),
        ],
      ),
    );
  }
}
