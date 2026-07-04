part of '../home_screen.dart';

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
    final small = context.w < 400;
    return Container(
      height: small ? 44 : 50,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.isDark ? c.card.withValues(alpha: .5) : c.card,
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
          boxShadow: selected && c.isDark
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
    required this.onRetry,
    this.maxItems = 12,
    this.excludeIds = const <String>{},
    this.heroPending = false,
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
  final VoidCallback onRetry;
  final int maxItems;

  /// Match ids already shown in the hero carousel. Filtered out so a single
  /// matchId never appears twice on Home.
  final Set<String> excludeIds;

  /// True while the hero carousel is on screen but its match ids are not yet
  /// resolved. Holds the list on a skeleton so a hero-bound match never flashes
  /// here before the exclude set is known.
  final bool heroPending;
  final bool showWatchLive;
  final bool showViewMatch;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<CricketMatch>>(
      future: future,
      builder: (context, snapshot) {
        final raw = data ?? snapshot.data ?? const <CricketMatch>[];
        final waiting = (data == null &&
                snapshot.connectionState == ConnectionState.waiting &&
                raw.isEmpty) ||
            // Hero ids not yet known — skeleton instead of risking a duplicate
            // card for the about-to-be-hero match.
            heroPending;
        if (waiting) {
          return const Column(
            children: [
              _CardSkeleton(),
              SizedBox(height: 16),
              _CardSkeleton(),
            ],
          );
        }
        // Network error / offline — show offline card, not empty-data message.
        if (snapshot.hasError && raw.isEmpty) {
          return CricOfflineCard(onRetry: onRetry, compact: true);
        }
        // Exclude hero matches so no card is duplicated, then cap to maxItems.
        final matches = (excludeIds.isEmpty
                ? raw
                : raw.where((m) => !excludeIds.contains(m.id)))
            .take(maxItems)
            .toList(growable: false);
        if (matches.isEmpty) {
          return _HomeEmptyState(
            topTab: topTab,
            onSwitchUpcoming: onSwitchUpcoming,
          );
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            // Two compact columns only when there is real room. Most phones
            // stay single rich column; 2-up is reserved for wide screens,
            // foldables, tablets, and landscape where a compact grid reads
            // cleanly instead of squeezing card content.
            final twoCol = constraints.maxWidth >= 520;
            if (twoCol) {
              return _HomeMatchGrid(
                matches: matches,
                repository: repository,
                showWatchLive: showWatchLive,
                showViewMatch: showViewMatch,
                onOpenMatch: onOpenMatch,
                onWatchLive: onWatchLive,
                onReminder: onReminder,
              );
            }
            return Column(
              children: [
                for (final match in matches)
                  Padding(
                    // Key by match id so Flutter binds element/scroll state to
                    // the match, not the list position — a silent score poll
                    // that swaps order can't recycle one card's state onto a
                    // different match (no flicker / wrong-card update).
                    key: ValueKey('home-card-${match.id}'),
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
      },
    );
  }
}

/// Two-column grid of compact match cards used on wider layouts. Each cell is
/// the same compact card so both columns share an even height per row.
class _HomeMatchGrid extends StatelessWidget {
  const _HomeMatchGrid({
    required this.matches,
    required this.repository,
    required this.onOpenMatch,
    required this.onWatchLive,
    required this.onReminder,
    this.showWatchLive = true,
    this.showViewMatch = true,
  });

  final List<CricketMatch> matches;
  final CricketRepository repository;
  final ValueChanged<String> onOpenMatch;
  final ValueChanged<String> onWatchLive;
  final VoidCallback onReminder;
  final bool showWatchLive;
  final bool showViewMatch;

  @override
  Widget build(BuildContext context) {
    const gap = 14.0;
    final rows = <Widget>[];
    for (var i = 0; i < matches.length; i += 2) {
      final left = matches[i];
      final right = i + 1 < matches.length ? matches[i + 1] : null;
      rows.add(Padding(
        key: ValueKey('home-grid-${left.id}-${right?.id ?? 'x'}'),
        padding: const EdgeInsets.only(bottom: gap),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _HomeCompactMatchCard(
                  key: ValueKey('home-compact-${left.id}'),
                  match: left,
                  repository: repository,
                  showWatchLive: showWatchLive,
                  showViewMatch: showViewMatch,
                  onOpenMatch: onOpenMatch,
                  onWatchLive: onWatchLive,
                  onReminder: onReminder,
                ),
              ),
              const SizedBox(width: gap),
              Expanded(
                child: right == null
                    ? const SizedBox.shrink()
                    : _HomeCompactMatchCard(
                        key: ValueKey('home-compact-${right.id}'),
                        match: right,
                        repository: repository,
                        showWatchLive: showWatchLive,
                        showViewMatch: showViewMatch,
                        onOpenMatch: onOpenMatch,
                        onWatchLive: onWatchLive,
                        onReminder: onReminder,
                      ),
              ),
            ],
          ),
        ),
      ));
    }
    return Column(children: rows);
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
// Compact match card (2-column grid variant for wider layouts)
// ---------------------------------------------------------------------------

/// A leaner card used inside the 2-column grid. Drops the 3-cell meta row so
/// the content fits comfortably in a half-width cell without overflow, while
/// keeping the premium stadium shell, status, teams+score and action buttons.
class _HomeCompactMatchCard extends StatelessWidget {
  const _HomeCompactMatchCard({
    super.key,
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
    final c = context.cric;
    final live = match.isLive;
    final finished = match.isFinished;
    final (label, color) = live
        ? ('LIVE', c.live)
        : finished
            ? ('FINISHED', c.success)
            : ('UPCOMING', c.cyan);
    final note = live
        ? (match.statusText.isNotEmpty ? match.statusText : match.resultText)
        : finished
            ? (match.resultText.isNotEmpty
                ? match.resultText
                : match.statusText)
            : _cardDateTime(match);
    return _HomeCardShell(
      bgAsset: _HAsset.liveCardBg,
      onTap: () => onOpenMatch(match.id),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Status badge + series title.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StatusBadge(label: label, color: color, live: live, dense: true),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  _heroTitle(match),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.cyan,
                    fontWeight: FontWeight.w800,
                    fontSize: 11.5,
                    height: 1.15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Teams with scores (live/finished) — compact logos.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _CompactTeam(
                  name: match.teamA,
                  short: match.teamAShort,
                  logo: match.teamALogo,
                  accent: c.cyan,
                  innings: (live || finished)
                      ? match.teamAInnings
                      : const <InningsScore>[],
                  scoreColor: live ? null : c.cyan,
                  live: live,
                  currentInningsIndex:
                      match.currentScoredIndexForTeam(isTeamA: true),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: _HomeVsBadge(width: 44, height: 31, intensity: 0.8),
              ),
              Expanded(
                child: _CompactTeam(
                  name: match.teamB,
                  short: match.teamBShort,
                  logo: match.teamBLogo,
                  accent: c.warning,
                  innings: (live || finished)
                      ? match.teamBInnings
                      : const <InningsScore>[],
                  scoreColor: live ? null : c.cyan,
                  live: live,
                  currentInningsIndex:
                      match.currentScoredIndexForTeam(isTeamA: false),
                ),
              ),
            ],
          ),
          if (note.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              homeShortStatus(note, match),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: live ? c.cyan : c.onImageText,
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
            ),
          ],
          const SizedBox(height: 10),
          const _CardDivider(),
          const SizedBox(height: 8),
          // Action bar: live cards resolve real stream availability; others get
          // a single View Match button.
          if (live)
            _LiveActionBar(
              match: match,
              repository: repository,
              showWatchLive: showWatchLive,
              showViewMatch: showViewMatch,
              onWatchLive: onWatchLive,
              onViewMatch: onOpenMatch,
            )
          else
            _HomeActionBar(
              onViewMatch: () => onOpenMatch(match.id),
              showView: showViewMatch,
            ),
        ],
      ),
    );
  }
}

/// Compact team block (logo + code + optional score) for grid cells. Smaller
/// than [_HomeTeamBlock] so two fit side by side without crowding.
class _CompactTeam extends StatelessWidget {
  const _CompactTeam({
    required this.name,
    required this.short,
    required this.logo,
    required this.accent,
    this.innings = const <InningsScore>[],
    this.scoreColor,
    this.live = false,
    this.currentInningsIndex = -1,
  });

  final String name;
  final String short;
  final String? logo;
  final Color accent;
  final List<InningsScore> innings;
  final Color? scoreColor;
  final bool live;
  final int currentInningsIndex;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final code = homeTeamCode(short, name);
    final isPlaceholder = code == 'TBC' || code == 'TBD' || code.isEmpty;
    final hasScore = innings.any((i) => i.hasRuns);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: accent.withValues(alpha: .8), width: 2),
            boxShadow: c.isDark
                ? [
                    BoxShadow(
                      color: c.cyan.withValues(alpha: .3),
                      blurRadius: 12,
                      spreadRadius: -3,
                    ),
                  ]
                : null,
          ),
          padding: const EdgeInsets.all(1.5),
          child: TeamLogoWidget(
            logoUrl: isPlaceholder ? null : logo,
            teamName: name,
            abbreviation: code,
            color: accent,
            size: 44,
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
            fontSize: 16,
            height: 1,
          ),
        ),
        if (hasScore) ...[
          const SizedBox(height: 3),
          // Centralized professional score for the compact grid cell — single
          // line, scaled to fit, two innings for a Test. Never truncates.
          TeamScoreView(
            innings: innings,
            mode: ScoreDisplayMode.compactCard,
            mainSize: 18,
            oversSize: 13,
            live: live,
            currentInningsIndex: currentInningsIndex,
            color: scoreColor,
            compactOvers: true,
          ),
        ],
      ],
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
          border: Border.all(color: c.cyan.withValues(alpha: .18), width: 1),
          boxShadow: c.isDark
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .34),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ]
              : c.heroShadow,
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
                  remoteKey: 'match_card_live_bg',
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
                  child: GlowOrb(color: c.cyan, size: 56, alpha: .025),
                ),
              ),
              const _TopCyanHighlight(),
              // Non-positioned content: lets the Stack grow taller than
              // minHeight when the live score/venue/action bar need the room,
              // preventing the bottom overflow.
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
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
    // Light mode keeps cards clean white — the neon top strip is dark-mode only.
    if (!c.isDark) return const SizedBox.shrink();
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: 1.5,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.transparent,
              c.cyan.withValues(alpha: .22),
              c.cyan.withValues(alpha: .28),
              c.cyan.withValues(alpha: .22),
              Colors.transparent,
            ],
            stops: const [0, .25, .5, .75, 1],
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
              fontSize: 12.5,
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
        color: const Color(0xff071d33).withValues(alpha: .82),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .55)),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          label,
          maxLines: 1,
          softWrap: false,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w800,
            fontSize: 10.5,
            letterSpacing: .5,
          ),
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

/// Single clean meta line for Home list cards — one icon + one string, never
/// the 3-column truncated row. Keeps Home cards premium (Home is not Match
/// Details). e.g. `Sabina Park • Jun 15, 02:30 AM` or just `Jun 16 • 03:30 PM`.
class _CardMetaLine extends StatelessWidget {
  const _CardMetaLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: c.cyan, size: 13),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: c.onImageText,
              fontWeight: FontWeight.w600,
              fontSize: 11.5,
            ),
          ),
        ),
      ],
    );
  }
}

/// Builds the clean one-line meta for a live/finished card: `Venue • Date Time`
/// when the venue is short enough, otherwise just the date/time. Upcoming cards
/// use date/time only (handled at the call site).
String _cardMetaText(CricketMatch match) {
  final dt = _cardDateTime(match);
  final venue = match.venue.trim();
  // Only prepend the venue when it is short enough to read on one line; a long
  // venue ("Shere Bangla National Stadium, Dhaka") would just truncate.
  if (venue.isNotEmpty && venue.length <= 16) {
    return '$venue • $dt';
  }
  return dt;
}

/// Three-column metadata row: venue | date/time | match type.
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
    // Live runs read bright white (wicket part is tinted red inside
    // _LiveScoreText); finished/other scores stay cyan.
    final scoreColor = match.isLive ? Colors.white : c.cyan;
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
            innings: showScore ? match.teamAInnings : const <InningsScore>[],
            live: match.isLive,
            currentInningsIndex:
                match.currentScoredIndexForTeam(isTeamA: true),
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
            innings: showScore ? match.teamBInnings : const <InningsScore>[],
            live: match.isLive,
            currentInningsIndex:
                match.currentScoredIndexForTeam(isTeamA: false),
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
    if (_kHomeDebug) {
      debugPrint('CricProHomeCard: live build id=${match.id} '
          'score=[${match.teamAScoreText} | ${match.teamBScoreText}] '
          'status=${match.statusText}');
    }
    // Single source of truth for the badge + phase label, so they can never
    // contradict (no more "LIVE NOW" pill alongside "Day 1: Stumps" text).
    final status = MatchStatusDisplay.of(context, match);
    final phaseLabel = status.phaseLabel.isNotEmpty
        ? homeShortStatus(status.phaseLabel, match)
        : '';
    return _HomeCardShell(
      bgAsset: _HAsset.liveCardBg,
      onTap: () => onOpenMatch(match.id),
      minHeight: context.w <= 430 ? 184 : 200,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _CardTopRow(
            label: status.badge,
            color: status.color,
            // A stoppage (stumps/lunch/tea/…) is still a live match, but the
            // pulsing dot is suppressed so the card does not read "live now".
            live: status.subPhase == MatchSubPhase.live,
            title: _heroTitle(match),
            titleColor: c.cyan,
          ),
          const SizedBox(height: 6),
          // Full team names + scores, with the phase label (e.g. "Day 1
          // Stumps", "Innings break", or the live status note) under VS.
          _CardTeamRow(
            match: match,
            showScore: true,
            centerPill: _CenterPill(label: phaseLabel, color: c.cyan),
          ),
          const SizedBox(height: 8),
          const _CardDivider(),
          const SizedBox(height: 7),
          _CardMetaLine(
              icon: Icons.location_on_outlined, text: _cardMetaText(match)),
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
      minHeight: context.w <= 430 ? 180 : 196,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _CardTopRow(
            label: 'UPCOMING',
            color: c.cyan,
            live: false,
            title: _heroTitle(match),
            titleColor: c.cyan,
          ),
          const SizedBox(height: 6),
          _CardTeamRow(
            match: match,
            centerPill: _CenterPill(label: 'UPCOMING', color: c.cyan),
          ),
          const SizedBox(height: 8),
          const _CardDivider(),
          const SizedBox(height: 7),
          _CardMetaLine(
              icon: Icons.calendar_month_rounded, text: _cardDateTime(match)),
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
    final result = formatResultText(
      match.resultText.isNotEmpty
          ? match.resultText
          : (match.statusText.isNotEmpty ? match.statusText : 'Match finished'),
      match,
    );
    return _HomeCardShell(
      bgAsset: _HAsset.liveCardBg,
      onTap: () => onOpenMatch(match.id),
      minHeight: context.w <= 430 ? 184 : 200,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _CardTopRow(
            label: 'FINISHED',
            color: c.success,
            live: false,
            title: _heroTitle(match),
            titleColor: c.cyan,
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
          _CardMetaLine(
            icon: Icons.calendar_month_rounded,
            text: match.matchDesc.trim().isNotEmpty &&
                    match.matchDesc.trim().length <= 12
                ? '${_cardDateTime(match)} • ${match.matchDesc.trim()}'
                : _cardDateTime(match),
          ),
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
    this.innings = const <InningsScore>[],
    this.showFullName = true,
    this.scoreColor,
    this.live = false,
    this.currentInningsIndex = -1,
  });

  final String name;
  final String short;
  final String? logo;
  final Color accent;
  final double logoSize;
  final double codeSize;
  final List<InningsScore> innings;
  final bool showFullName;
  final Color? scoreColor;
  final bool live;
  final int currentInningsIndex;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final phone = context.w <= 430;
    final code = homeTeamCode(short, name);
    final isPlaceholder = code == 'TBC' || code == 'TBD' || code.isEmpty;
    final hasScore = innings.any((i) => i.hasRuns);
    final multi = innings.where((i) => i.hasRuns).length > 1;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: c.isDark
                ? [
                    BoxShadow(
                      color: c.cyan.withValues(alpha: .35),
                      blurRadius: 14,
                      spreadRadius: -2,
                    ),
                  ]
                : null,
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
        // Home cards are code-first (not Match Details): the full secondary
        // team name is intentionally omitted so cards stay compact and never
        // ellipsis a long name. `showFullName` is retained for API stability.
        if (hasScore) ...[
          const SizedBox(height: 3),
          // Centralized professional score. Single innings → `218/10` / `44.2
          // ov`; Test → `362/10 & 391/10` / `87.1 • 96.2 ov`. Never truncates.
          TeamScoreView(
            innings: innings,
            mode: multi
                ? ScoreDisplayMode.cardMultiInnings
                : ScoreDisplayMode.cardLimitedOvers,
            mainSize: phone ? 20 : 21,
            oversSize: phone ? 12 : 12.5,
            live: live,
            currentInningsIndex: currentInningsIndex,
            color: scoreColor,
            compactOvers: true,
          ),
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
    final light = !c.isDark;
    // Blue→cyan gradient parallelogram in light mode (matches target);
    // dark navy glass in dark mode.
    const lightVsGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xff35e2ff), Color(0xff0a86ff)],
    );
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // A. Soft cyan bloom behind the VS. (dark only)
          if (!light)
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
          // B. Stronger light pool / glow directly under the badge. (dark only)
          if (!light)
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
          // C. Diagonal electric streak behind the pill. (dark only)
          if (!light)
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
          // Light-mode soft blue drop glow under the pill (subtle, not neon).
          if (light)
            Positioned(
              bottom: -height * 0.14,
              child: Container(
                width: width * 0.92,
                height: height * 0.30,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xff1188f7)
                          .withValues(alpha: 0.28 * intensity),
                      blurRadius: 14,
                      spreadRadius: -2,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
              ),
            ),
          // The slanted glass pill.
          CustomPaint(
            size: Size(width, height),
            painter: _VsBadgePainter(
              border:
                  light ? Colors.white.withValues(alpha: .9) : c.cyan,
              fill: const Color(0xff071d34).withValues(alpha: .86),
              fillGradient: light ? lightVsGradient : null,
              glow: light
                  ? Colors.transparent
                  : c.cyan.withValues(alpha: .5 * intensity),
              strokeWidth: light ? 1.0 : 1.5,
            ),
          ),
          Text(
            'VS',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: height * 0.42,
              letterSpacing: .6,
              shadows: light
                  ? null
                  : [
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
    this.fillGradient,
    this.strokeWidth = 1.6,
  });

  final Color border;
  final Color fill;
  final Color glow;
  final Gradient? fillGradient;
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
    // Glass fill — gradient in light mode, flat navy glass in dark.
    final fillPaint = Paint();
    if (fillGradient != null) {
      fillPaint.shader =
          fillGradient!.createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    } else {
      fillPaint.color = fill;
    }
    canvas.drawPath(path, fillPaint);
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
      old.fillGradient != fillGradient ||
      old.strokeWidth != strokeWidth;
}

// ---------------------------------------------------------------------------
// Action bar
// ---------------------------------------------------------------------------

