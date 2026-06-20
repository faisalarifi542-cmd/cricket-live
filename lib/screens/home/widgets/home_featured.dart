part of '../home_screen.dart';

// ---------------------------------------------------------------------------
// Bottom featured sections (Upcoming Matches + Featured Series)
// ---------------------------------------------------------------------------

class _UpcomingMatchesSection extends StatelessWidget {
  const _UpcomingMatchesSection({
    required this.future,
    required this.onOpenMatch,
    required this.onSeeAll,
    this.excludeIds = const <String>{},
    this.topSpacing = 22,
  });

  final Future<List<CricketMatch>> future;
  final ValueChanged<String> onOpenMatch;
  final VoidCallback onSeeAll;

  /// Match ids already shown as the primary hero — excluded so no card is
  /// duplicated across Home.
  final Set<String> excludeIds;

  /// Gap above the section. Zero when this row is the primary content (no live
  /// matches) so it sits snug under the segmented tabs.
  final double topSpacing;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<CricketMatch>>(
      future: future,
      builder: (context, snapshot) {
        final source = snapshot.data ?? const <CricketMatch>[];
        final matches = source
            .where((m) => !excludeIds.contains(m.id))
            .take(10)
            .toList(growable: false);
        if (matches.isEmpty) return const SizedBox.shrink();
        return Column(
          children: [
            SizedBox(height: topSpacing),
            _SectionHeader(
              title: 'Upcoming Matches',
              showSeeAll: true,
              onSeeAll: onSeeAll,
            ),
            const SizedBox(height: 12),
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
                  'View All',
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
    // Compact horizontal cards — shorter than the rich match cards so the
    // Upcoming row never feels oversized or gets cut at the bottom on small
    // phones. Card width shows ~1.3 cards at 360dp with a clear peek.
    final w = context.w;
    final hp = context.horizontalPadding;
    final cardWidth = ((w - hp * 2) * 0.74).clamp(232.0, 300.0);
    return SizedBox(
      height: 138,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: const EdgeInsets.only(right: 18),
        itemCount: matches.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
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
          border: Border.all(color: c.cyan.withValues(alpha: .2), width: 1),
          boxShadow: c.isDark
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .32),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ]
              : c.heroShadow,
        ),
        child: Stack(
          children: [
            // Stadium background.
            const Positioned.fill(
              child: StadiumImage(
                _HAsset.liveCardBg,
                hero: true,
                alignment: Alignment.center,
                remoteKey: 'match_card_live_bg',
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
              padding: const EdgeInsets.fromLTRB(13, 9, 13, 10),
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
                          _heroTitle(match),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: c.cyan,
                            fontWeight: FontWeight.w700,
                            fontSize: 11.5,
                            height: 1.15,
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
                      const _HomeVsBadge(width: 44, height: 31, intensity: 0.85),
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
                  // Bottom: date/time only (venue omitted to keep the upcoming
                  // card compact).
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.calendar_month_rounded,
                          size: 12, color: c.cyan),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          _cardDateTime(match),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: c.onImageText,
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
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
    final code = homeTeamCode(short, name);
    final isPlaceholder = code == 'TBC' || code == 'TBD' || code.isEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TeamLogoWidget(
          logoUrl: isPlaceholder ? null : logo,
          teamName: name,
          abbreviation: code,
          color: accent,
          size: 36,
        ),
        const SizedBox(height: 5),
        Text(
          code,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: c.text,
            fontWeight: FontWeight.w900,
            fontSize: 14,
            height: 1,
          ),
        ),
        // Code-only on Home mini cards — no long secondary name.
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
    final w = context.w;
    final small = w < 400;
    final wide = w >= 600;
    final height = wide
        ? 176.0
        : small
            ? 134.0
            : 152.0;
    final ctaSize = small ? 40.0 : 44.0;
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
              remoteKey: 'home_hero_bg_dark',
            ),
            if (series.hasImage)
              CachedNetworkImage(
                imageUrl: series.imageUrl,
                fit: BoxFit.cover,
                fadeInDuration: Duration.zero,
                errorWidget: (_, __, ___) => const SizedBox.shrink(),
                placeholder: (context, _) => const SizedBox.shrink(),
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
                                fontSize: small ? 18 : 22,
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
                        width: ctaSize,
                        height: ctaSize,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: c.cyan.withValues(alpha: .16),
                          border: Border.all(
                              color: c.cyan.withValues(alpha: .9), width: 1.4),
                          boxShadow: c.isDark
                              ? [
                                  BoxShadow(
                                    color: c.cyan.withValues(alpha: .4),
                                    blurRadius: 14,
                                    spreadRadius: -2,
                                  ),
                                ]
                              : null,
                        ),
                        alignment: Alignment.center,
                        child: Icon(Icons.arrow_forward_rounded,
                            color: c.cyan, size: small ? 20 : 22),
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

/// Hero card title — prefers the series / tour / tournament name (e.g.
/// "Australia tour of Bangladesh, 2026") so the hero reads like the target,
/// falling back to the match's own title then the derived "TeamA vs TeamB"
/// when no series is known. Generic placeholder titles ("Cricket Match",
/// "Match", "Live Match", ...) are skipped so they don't mask a more useful
/// title.
const _kGenericTitles = <String>{
  'cricket match',
  'match',
  'live match',
  'upcoming match',
  'finished match',
  'tbd',
  'tbc',
  'null',
};

bool _isGenericTitle(String s) =>
    s.isEmpty || _kGenericTitles.contains(s.toLowerCase());

String _heroTitle(CricketMatch match) {
  final series = match.series.trim();
  if (!_isGenericTitle(series)) return homeShortSeriesTitle(series);
  final title = match.title.trim();
  if (!_isGenericTitle(title)) return homeShortSeriesTitle(title);
  // Fallback team-vs-team: use women-spaced codes — "NZ W vs SL W".
  final a = homeTeamCode(match.teamAShort, match.teamA);
  final b = homeTeamCode(match.teamBShort, match.teamB);
  if (a.isNotEmpty && b.isNotEmpty) return '$a vs $b';
  return match.versusTitle;
}

// Team-code / name / status formatting now lives in the app-wide single source
// of truth `lib/utils/team_format.dart` so every screen renders identical codes
// (`NZ W`, `IND A`, `AFG A`). These Home-named wrappers delegate there, keeping
// the existing Home call sites unchanged.
String normalizeWomenTeamName(String name) => compactTeamName(name);
String formatWomenCode(String code) => formatTeamCode(code);
String formatWomenName(String name) => compactTeamName(name);
String homeTeamCode(String short, String name) => teamCodeOf(short, name);
String homeShortSeriesTitle(String title) => shortSeriesTitle(title);
String homeShortStatus(String status, CricketMatch match) =>
    shortMatchStatus(status, match, keepUnits: true);

/// Content fingerprint using the SAME fields the Home UI renders for score,
/// status, and result. If any of these change, the card appearance changes and
/// the UI must repaint. Used by the silent poll to decide `listChanged` and
/// `heroChanged` without false negatives (empty ghost keys).
String homeVisibleScoreKey(CricketMatch m) =>
    '${m.id}|${m.status}|${m.statusText}|${m.resultText}|'
    '${m.teamAScoreText}|${m.teamBScoreText}';

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
