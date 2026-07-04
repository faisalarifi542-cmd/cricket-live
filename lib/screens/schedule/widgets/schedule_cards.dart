part of '../schedule_screen.dart';

class _ScheduleMatchCard extends StatelessWidget {
  const _ScheduleMatchCard({required this.match, required this.onTap});

  final CricketMatch match;
  final VoidCallback onTap;

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
          border: Border.all(
              color: c.isDark ? c.cyan.withValues(alpha: .3) : c.border),
          boxShadow: c.heroShadow,
        ),
        child: Stack(
          children: [
            // Premium stadium card background.
            const Positioned.fill(
              child: StadiumImage(
                _Asset.matchCardBg,
                hero: true,
                alignment: Alignment.center,
                remoteKey: 'schedule_match_card_bg',
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: c.isDark
                        ? [
                            const Color(0xff0c2c50).withValues(alpha: .68),
                            c.card.withValues(alpha: .74),
                            const Color(0xff06182c).withValues(alpha: .82),
                          ]
                        : [
                            Colors.white.withValues(alpha: .40),
                            Colors.white.withValues(alpha: .50),
                            c.card2.withValues(alpha: .62),
                          ],
                  ),
                ),
              ),
            ),
            // Soft cyan inner highlight at the top edge.
            // Cyan glow layers are dark-mode only — on white they muddy the card
            // and read as the old "dark-inspired" look.
            if (c.isDark)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, -1.4),
                      radius: 1.2,
                      colors: [
                        c.cyan.withValues(alpha: .1),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            // Center spotlight behind the team row / VS so the matchup pops.
            if (c.isDark)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, 0.15),
                      radius: .75,
                      colors: [
                        c.cyan.withValues(alpha: .16),
                        Colors.transparent,
                      ],
                      stops: const [0, 1],
                    ),
                  ),
                ),
              ),
            // Top + bottom cyan edge glow lines for the broadcast-card feel.
            if (c.isDark)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 3,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        c.cyan.withValues(alpha: .65),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            if (c.isDark)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                height: 30,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          c.cyan.withValues(alpha: .18),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Series row: logo + name + status pill.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SeriesBadge(match: match),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              shortSeriesTitle(match.series).toUpperCase(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: c.cyan,
                                fontWeight: FontWeight.w800,
                                fontSize: 11.5,
                                height: 1.2,
                                letterSpacing: .2,
                              ),
                            ),
                            if (match.matchDesc.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(
                                match.matchDesc,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: c.text,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13.5,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _MatchStatusPill(match: match),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Team row with glowing VS badge. Live/finished matches show
                  // the real score (clean multi-innings format) under each code.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: _CardTeam(
                          logoUrl: match.teamALogo,
                          shortName: match.teamAShort,
                          fullName: match.teamA,
                          innings: match.teamAInnings,
                          live: match.isLive,
                          showScore: match.isLive || match.isFinished,
                          currentInningsIndex:
                              match.currentScoredIndexForTeam(isTeamA: true),
                        ),
                      ),
                      const _VsBadge(),
                      Expanded(
                        child: _CardTeam(
                          logoUrl: match.teamBLogo,
                          shortName: match.teamBShort,
                          fullName: match.teamB,
                          innings: match.teamBInnings,
                          live: match.isLive,
                          showScore: match.isLive || match.isFinished,
                          currentInningsIndex:
                              match.currentScoredIndexForTeam(isTeamA: false),
                        ),
                      ),
                    ],
                  ),
                  // Live status / finished result line (e.g. "Day 4 · 2nd
                  // Session · NZ lead by 299 runs").
                  if (_statusLine(match).isNotEmpty) ...[
                    const SizedBox(height: 10),
                    _ScheduleStatusLine(text: _statusLine(match), live: match.isLive),
                  ],
                  const SizedBox(height: 14),
                  // Time + venue split panel.
                  _TimeVenuePanel(match: match),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The live status / finished result line for the card. Empty for upcoming
  /// matches (their info lives in the time/venue panel).
  String _statusLine(CricketMatch match) {
    if (match.isLive) {
      return match.statusText.isNotEmpty ? match.statusText : match.resultText;
    }
    if (match.isFinished) {
      return match.resultText.isNotEmpty ? match.resultText : match.statusText;
    }
    return '';
  }
}

/// A premium one-line status/result strip under the team row. Uses a calm dark
/// glass + subtle cyan border (NOT red) — red is reserved for the LIVE pill, so
/// normal state text (lead/trail/session, results) never reads as an alert.
class _ScheduleStatusLine extends StatelessWidget {
  const _ScheduleStatusLine({required this.text, required this.live});

  final String text;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: c.isDark ? c.card2.withValues(alpha: .42) : c.card2,
        border: Border.all(color: c.cyan.withValues(alpha: c.isDark ? .35 : .25)),
      ),
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: c.text,
          fontWeight: FontWeight.w700,
          fontSize: 12.5,
          height: 1.25,
        ),
      ),
    );
  }
}

class _SeriesBadge extends StatelessWidget {
  const _SeriesBadge({required this.match});

  final CricketMatch match;

  /// Derives up to two letters from the series name as the very last fallback
  /// (only used if the tournament logo asset also fails to load).
  String get _initials {
    const skip = {
      'tour',
      'of',
      'the',
      'and',
      'vs',
      'men',
      "men's",
      'women',
      "women's",
      'series',
      'trophy',
      'cup',
      'league',
      'division',
      'one',
      'two',
      'premier',
      'qualifier',
      't20i',
      't20',
      'odi',
      'test',
    };
    final words = match.series
        .replaceAll(RegExp(r'[^A-Za-z ]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty && !skip.contains(w.toLowerCase()))
        .toList();
    if (words.isEmpty) {
      final first = match.series.replaceAll(RegExp(r'[^A-Za-z]'), '');
      return first.isEmpty
          ? ''
          : first.substring(0, first.length.clamp(0, 2)).toUpperCase();
    }
    if (words.length == 1) {
      return words.first
          .substring(0, words.first.length.clamp(0, 2))
          .toUpperCase();
    }
    return (words[0][0] + words[1][0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final logoAsset = _Asset.tournamentLogo(match.series);
    return Container(
      width: 44,
      height: 44,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: c.isDark ? const Color(0xff0e2742) : c.card,
        border: Border.all(color: c.cyan.withValues(alpha: .55), width: 1.3),
        boxShadow: c.isDark
            ? [
                BoxShadow(
                  color: c.cyan.withValues(alpha: .22),
                  blurRadius: 12,
                  spreadRadius: -3,
                ),
              ]
            : c.cardShadow,
      ),
      // Real tournament fallback logo asset, contained with slight padding so
      // the emblem is never cropped. Degrades to an initials badge on failure.
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Image.asset(
          logoAsset,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => _initialsFallback(c),
        ),
      ),
    );
  }

  Widget _initialsFallback(CricColors c) {
    final initials = _initials;
    return Stack(
      fit: StackFit.expand,
      children: [
        const StadiumImage(
          'assets/images/stadium_live.webp',
          hero: true,
          alignment: Alignment.center,
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: c.isDark
                  ? [
                      const Color(0xff0b2238).withValues(alpha: .82),
                      const Color(0xff061528).withValues(alpha: .92),
                    ]
                  : [
                      Colors.white.withValues(alpha: .80),
                      c.card2.withValues(alpha: .90),
                    ],
            ),
          ),
        ),
        Center(
          child: initials.isEmpty
              ? Icon(Icons.emoji_events_rounded, color: c.cyan, size: 16)
              : Text(
                  initials,
                  style: TextStyle(
                    color: c.cyan,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    letterSpacing: .3,
                  ),
                ),
        ),
      ],
    );
  }
}

class _MatchStatusPill extends StatelessWidget {
  const _MatchStatusPill({required this.match});

  final CricketMatch match;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final live = match.isLive;
    final finished = match.isFinished;
    final color = live
        ? c.live
        : finished
            ? c.success
            : c.cyan;
    final label = live
        ? 'LIVE'
        : finished
            ? 'Completed'
            : 'Upcoming';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .6)),
        boxShadow: live
            ? [BoxShadow(color: color.withValues(alpha: .3), blurRadius: 10)]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (live) ...[
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
              fontWeight: FontWeight.w800,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _CardTeam extends StatelessWidget {
  const _CardTeam({
    required this.logoUrl,
    required this.shortName,
    required this.fullName,
    this.innings = const <InningsScore>[],
    this.live = false,
    this.showScore = false,
    this.currentInningsIndex = -1,
  });

  final String? logoUrl;
  final String shortName;
  final String fullName;
  final List<InningsScore> innings;
  final bool live;
  final bool showScore;
  final int currentInningsIndex;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    // Shared formatter: `AFGA` -> `AFG A`, `NZW` -> `NZ W`, etc.
    final upper = teamCodeOf(shortName, fullName);
    final isPlaceholder = upper == 'TBC' || upper == 'TBD' || upper.isEmpty;
    final logo = TeamLogoWidget(
      logoUrl: isPlaceholder ? null : logoUrl,
      teamName: fullName,
      abbreviation: upper,
      color: c.cyan,
      size: 44,
    );
    final scored = innings.where((i) => i.hasRuns).toList();
    // Logo-ABOVE, centred column (same visual language as Home/Matches) so the
    // score uses the FULL team-column width instead of being squeezed beside
    // the logo — this is what was miniaturising the Schedule Test score. The
    // shared `TeamScoreView` (card preset) renders the premium stacked rows.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        logo,
        const SizedBox(height: 7),
        Text(
          upper,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: c.text,
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
        if (showScore && scored.isNotEmpty) ...[
          const SizedBox(height: 4),
          TeamScoreView(
            innings: innings,
            mode: scored.length > 1
                ? ScoreDisplayMode.cardMultiInnings
                : ScoreDisplayMode.cardLimitedOvers,
            mainSize: 18,
            oversSize: 13,
            live: live,
            currentInningsIndex: currentInningsIndex,
            align: CrossAxisAlignment.center,
            textAlign: TextAlign.center,
            color: live ? (c.isDark ? Colors.white : c.text) : c.cyan,
            compactOvers: true,
          ),
        ] else if (showScore && live) ...[
          const SizedBox(height: 4),
          Text(
            'Yet to bat',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: c.muted,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }
}

class _VsBadge extends StatelessWidget {
  const _VsBadge();

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    // Compact layout footprint (so the team text columns keep their width),
    // but the diagonal streak + glow deliberately overflow well beyond it via
    // Clip.none so the VS reads as a wide broadcast centerpiece, not a button.
    return SizedBox(
      width: 46,
      height: 66,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // 1) Big soft radial cyan bloom (pure Flutter) — guarantees a strong
          // glow halo regardless of the asset, behind everything.
          Container(
            width: 150,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  c.cyan.withValues(alpha: .5),
                  c.cyan.withValues(alpha: .16),
                  Colors.transparent,
                ],
                stops: const [0, .42, 1],
              ),
            ),
          ),
          // 2) Radial glow bloom asset (has alpha) behind the slash, stronger.
          Image.asset(
            _Asset.vsGlow,
            width: 168,
            height: 118,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
          // 3) Wide diagonal electric light streak (RGB no-alpha asset → screen
          // blend so the dark background vanishes), rotated like the target and
          // extending far past the badge on both sides.
          Transform.rotate(
            angle: -0.5,
            child: const _BlendImage(
              _Asset.vsStreak,
              width: 210,
              height: 40,
              opacity: 1,
            ),
          ),
          // 4) A second, narrower hot-core streak layered on top for a brighter
          // central slash.
          Transform.rotate(
            angle: -0.5,
            child: const _BlendImage(
              _Asset.vsStreak,
              width: 120,
              height: 18,
              opacity: 1,
            ),
          ),
          // 5) Dark glass VS badge with a bright glowing cyan border. Kept
          // compact — the size comes from the surrounding light, not the chip.
          Container(
            width: 42,
            height: 33,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: c.isDark
                    ? const [Color(0xff0e3155), Color(0xff04101f)]
                    : [c.primary, c.cyan],
              ),
              border:
                  Border.all(color: c.cyan.withValues(alpha: .98), width: 1.6),
              boxShadow: c.isDark
                  ? [
                      BoxShadow(
                        color: c.cyan.withValues(alpha: .8),
                        blurRadius: 22,
                        spreadRadius: -1,
                      ),
                      BoxShadow(
                        color: c.cyan.withValues(alpha: .35),
                        blurRadius: 38,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            alignment: Alignment.center,
            child: Text(
              'VS',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 14,
                letterSpacing: .5,
                shadows: c.isDark
                    ? [
                        Shadow(color: c.cyan, blurRadius: 14),
                        Shadow(color: c.cyan.withValues(alpha: .7), blurRadius: 22),
                      ]
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeVenuePanel extends StatelessWidget {
  const _TimeVenuePanel({required this.match});

  final CricketMatch match;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final (venueName, city) = _splitVenue(match.venue);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: c.isDark ? c.card2.withValues(alpha: .42) : c.card2,
        border: Border.all(color: c.border.withValues(alpha: .5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _InfoBlock(
              icon: Icons.access_time_rounded,
              primary: _timeLine(match),
              // A live (often multi-day) match shows its START date/time here —
              // label it "Started" so it never reads as the selected schedule
              // date. Upcoming matches keep the local-time note.
              secondary: match.isLive ? 'Started' : '(Local Time)',
              maxPrimaryLines: 2,
            ),
          ),
          Container(
            width: 1,
            height: 36,
            margin: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  c.border.withValues(alpha: .7),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          Expanded(
            child: _InfoBlock(
              icon: Icons.location_on_outlined,
              primary: venueName.isEmpty ? 'Venue TBC' : venueName,
              secondary: city,
              maxPrimaryLines: 2,
            ),
          ),
        ],
      ),
    );
  }

  // Routes the card's time line through the shared `formatMatchDateTime` so it
  // shows "Today"/"Tomorrow" exactly like Series Overview and Match Details —
  // fixing the cross-screen inconsistency where the same match read "Today" on
  // Series Overview but "May 30" on Schedule. Falls back to the status/start
  // text when no date is parseable.
  String _timeLine(CricketMatch match) {
    final formatted = formatMatchDateTime(match.startDateTime);
    if (formatted.isNotEmpty) return formatted;
    return match.statusText.isNotEmpty ? match.statusText : match.startTime;
  }

  (String, String) _splitVenue(String venue) {
    final v = venue.trim();
    if (v.isEmpty) return ('', '');
    final idx = v.lastIndexOf(',');
    if (idx <= 0 || idx >= v.length - 1) return (v, '');
    return (v.substring(0, idx).trim(), v.substring(idx + 1).trim());
  }
}

class _InfoBlock extends StatelessWidget {
  const _InfoBlock({
    required this.icon,
    required this.primary,
    required this.secondary,
    this.maxPrimaryLines = 1,
  });

  final IconData icon;
  final String primary;
  final String secondary;
  final int maxPrimaryLines;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: c.cyan, size: 16),
        const SizedBox(width: 7),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                primary,
                maxLines: maxPrimaryLines,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: c.text,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                  height: 1.2,
                ),
              ),
              if (secondary.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  secondary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.muted,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Skeleton loading
// ---------------------------------------------------------------------------

class _ScheduleSkeletonList extends StatelessWidget {
  const _ScheduleSkeletonList();

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Column(
      children: [
        for (var i = 0; i < 3; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Container(
              height: 168,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                color: c.isDark ? c.card.withValues(alpha: .5) : c.card,
                border: Border.all(color: c.border.withValues(alpha: .5)),
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// State card
// ---------------------------------------------------------------------------

class _ScheduleStateCard extends StatelessWidget {
  const _ScheduleStateCard({
    required this.icon,
    required this.title,
    required this.message,
    required this.onRetry,
  });

  final IconData icon;
  final String title;
  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.cyan.withValues(alpha: .12),
              border: Border.all(color: c.cyan.withValues(alpha: .3)),
            ),
            child: Icon(icon, color: c.cyan, size: 30),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: c.text, fontWeight: FontWeight.w900, fontSize: 17),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: c.muted, height: 1.4),
          ),
          const SizedBox(height: 16),
          GradientButton(
            label: 'Retry',
            icon: Icons.refresh_rounded,
            onTap: () => onRetry(),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom sheets
// ---------------------------------------------------------------------------

