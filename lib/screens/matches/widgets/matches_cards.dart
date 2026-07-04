part of '../matches_screen.dart';

class _MatchCardShell extends StatelessWidget {
  const _MatchCardShell({
    required this.bg,
    required this.accent,
    required this.onTap,
    required this.child,
    this.remoteKey,
  });

  final String bg;
  final String? remoteKey;
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
          border: Border.all(
              color: c.isDark ? c.cyan.withValues(alpha: .4) : c.border),
          boxShadow: c.heroShadow,
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: StadiumImage(
                bg,
                hero: true,
                alignment: Alignment.center,
                remoteKey: remoteKey,
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
                            Colors.white.withValues(alpha: .26),
                            c.card.withValues(alpha: .18),
                            Colors.white.withValues(alpha: .38),
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
                            Colors.white.withValues(alpha: .30),
                            Colors.transparent,
                          ],
                  ),
                ),
              ),
            ),
            // Compact cyan glow only behind the VS centre — not a full-card fog.
            // Dark-mode only: on white it reads as muddy haze.
            if (c.isDark)
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
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
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
  const _CardTopRow({
    required this.match,
    required this.kind,
    this.badgeLabel,
    this.pulsing,
  });

  final CricketMatch match;
  final _CardKind kind;

  /// Optional override of the badge word (e.g. STUMPS/LUNCH for a paused live
  /// match). When null the kind's default (LIVE/UPCOMING/FINISHED) is used.
  final String? badgeLabel;

  /// Optional override of the live pulsing-dot behaviour.
  final bool? pulsing;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StatusBadge(kind: kind, labelOverride: badgeLabel, pulsing: pulsing),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            shortSeriesTitle(match.series),
            // Allow the title two lines so important comps aren't cut to an
            // ugly one-line "Women's T20 WC 20…"; width is still constrained
            // by Expanded so it can never overflow.
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: c.cyan,
              fontWeight: FontWeight.w800,
              fontSize: 12.5,
              letterSpacing: .1,
              height: 1.15,
            ),
          ),
        ),
        const SizedBox(width: 7),
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Text(
            _dateTimeLabel(match),
            maxLines: 1,
            style: TextStyle(
              color: c.muted,
              fontWeight: FontWeight.w700,
              fontSize: 10.5,
            ),
          ),
        ),
      ],
    );
  }
}

enum _CardKind { live, upcoming, finished }

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.kind, this.labelOverride, this.pulsing});

  final _CardKind kind;

  /// When set, overrides the default badge word (e.g. `STUMPS`/`LUNCH`/`TEA`
  /// for a paused live match) while keeping the kind's color/glow behaviour.
  final String? labelOverride;

  /// When false, suppresses the pulsing live dot for a paused live match
  /// (stumps/lunch/tea/…) so the badge does not read "live now" while the note
  /// says "Day 1 Stumps". Defaults to pulsing for a live kind.
  final bool? pulsing;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final (defaultLabel, color, filled) = switch (kind) {
      _CardKind.live => ('LIVE', c.live, true),
      _CardKind.upcoming => ('UPCOMING', c.cyan, false),
      _CardKind.finished => ('FINISHED', c.success, true),
    };
    final label = labelOverride ?? defaultLabel;
    final showDot = (pulsing ?? (kind == _CardKind.live)) && kind == _CardKind.live;
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
          if (showDot) ...[
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
    this.innings = const <InningsScore>[],
    this.live = false,
    this.currentInningsIndex = -1,
  });

  final String name;
  final String short;
  final String? logo;
  final Color accent;
  final List<InningsScore> innings;
  final bool live;
  final int currentInningsIndex;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final code = teamCodeOf(short, name);
    final upper = code;
    final isPlaceholder = upper == 'TBC' || upper == 'TBD' || upper.isEmpty;
    // Secondary line uses the women-compacted name and is hidden when it just
    // echoes the code, so compact cards aren't cluttered by "New Zealand Women"
    // sitting under "NZ W".
    final displayName = shortenTeamName(compactTeamName(name));
    final showName = !isPlaceholder &&
        displayName.isNotEmpty &&
        displayName.toUpperCase() != upper.toUpperCase();
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
        if (showName) ...[
          const SizedBox(height: 1),
          Text(
            displayName,
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
        if (innings.any((i) => i.hasRuns)) ...[
          const SizedBox(height: 4),
          // Compact professional score — single line `218/10` for limited-overs,
          // or, for a Test, stacked `1st 362/10` / `2nd 391/10` rows with a
          // readable `87.1 • 96.2 ov` line beneath (never truncated/ellipsized).
          TeamScoreView(
            innings: innings,
            mode: innings.where((i) => i.hasRuns).length > 1
                ? ScoreDisplayMode.cardMultiInnings
                : ScoreDisplayMode.cardLimitedOvers,
            mainSize: 22,
            oversSize: 14,
            live: live,
            currentInningsIndex: currentInningsIndex,
            color: live ? (c.isDark ? Colors.white : c.text) : c.text,
            compactOvers: true,
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

  static const double visualWidth = 100;
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
    final short = shortVenue(venue);
    final text = short.isEmpty ? 'Venue TBC' : short;
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
            // Allow up to 2 lines so a long stadium name (e.g. "KSCA Hubli
            // Cricket Ground") wraps instead of truncating mid-word to "KSCA
            // Hubli Cricket Gro…" — the venue row shares width with the CTA
            // button, so one line cuts too aggressively.
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: c.muted,
              fontWeight: FontWeight.w600,
              fontSize: 12,
              height: 1.2,
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
    // No playable stream → hide Watch Live completely and let View Match take
    // the full width (matches the target spec; never show a dead/dimmed button).
    final showWatch = watchState != _WatchState.none;
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
          if (showWatch) ...[
            Expanded(child: _watchSegment(c)),
            Container(width: 1, color: c.cyan.withValues(alpha: .3)),
          ],
          Expanded(
            child: _DualSegment(
              label: 'Match Center',
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
    // Single source of truth for the badge + phase note, so a paused live match
    // (stumps/lunch/tea/…) shows STUMPS/LUNCH/TEA instead of a generic LIVE
    // while the note says "Day 1 Stumps" — no more contradictory labels.
    final status = MatchStatusDisplay.of(context, match);
    final note = status.phaseLabel.isNotEmpty
        ? shortMatchStatus(status.phaseLabel, match, keepUnits: true)
        : '';
    return _MatchCardShell(
      bg: _MAsset.cardBgLive,
      remoteKey: 'match_card_live_bg',
      accent: c.live,
      onTap: onViewMatch,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardTopRow(
            match: match,
            kind: _CardKind.live,
            badgeLabel: status.badge,
            pulsing: status.subPhase == MatchSubPhase.live,
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: _TeamBlock(
                  name: match.teamA,
                  short: match.teamAShort,
                  logo: match.teamALogo,
                  accent: c.cyan,
                  innings: match.teamAInnings,
                  live: true,
                  currentInningsIndex:
                      match.currentScoredIndexForTeam(isTeamA: true),
                ),
              ),
              const _VsCenterpiece(),
              Expanded(
                child: _TeamBlock(
                  name: match.teamB,
                  short: match.teamBShort,
                  logo: match.teamBLogo,
                  accent: c.warning,
                  innings: match.teamBInnings,
                  live: true,
                  currentInningsIndex:
                      match.currentScoredIndexForTeam(isTeamA: false),
                ),
              ),
            ],
          ),
          if (note.isNotEmpty) ...[
            const SizedBox(height: 5),
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
      remoteKey: 'match_card_upcoming_bg',
      accent: c.cyan,
      onTap: onViewMatch,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardTopRow(match: match, kind: _CardKind.upcoming),
          const SizedBox(height: 12),
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
                label: 'Match Center',
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
    } else if (start != null) {
      // Start is known but not in the future (e.g. a stale "upcoming" entry for
      // a match that already began). Show the local start time, NEVER a raw
      // epoch fallback.
      primary = _localStartLabel(start);
    } else {
      // No parsed start: only show the textual fallback if it isn't a raw
      // timestamp/epoch value leaking from the feed.
      final fb = widget.fallback.trim();
      primary = looksLikeRawTimestamp(fb) || fb.isEmpty ? 'Match yet to begin' : fb;
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
    final result = formatResultText(
      match.resultText.isNotEmpty
          ? match.resultText
          : (match.statusText.isNotEmpty ? match.statusText : 'Match finished'),
      match,
    );
    return _MatchCardShell(
      bg: _MAsset.cardBgFinished,
      remoteKey: 'match_card_finished_bg',
      accent: c.success,
      onTap: onViewMatch,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CardTopRow(match: match, kind: _CardKind.finished),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: _TeamBlock(
                  name: match.teamA,
                  short: match.teamAShort,
                  logo: match.teamALogo,
                  accent: c.cyan,
                  innings: match.teamAInnings,
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
                  innings: match.teamBInnings,
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
                label: 'Match Center',
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
        result,
        textAlign: TextAlign.center,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: c.success,
          fontWeight: FontWeight.w800,
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

const _kMonths = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];

/// Local "Jun 22 • 02:30 AM" for a known start [DateTime].
String _localStartLabel(DateTime dt) {
  final l = dt.toLocal();
  var hour = l.hour % 12;
  if (hour == 0) hour = 12;
  final ampm = l.hour >= 12 ? 'PM' : 'AM';
  final mm = l.minute.toString().padLeft(2, '0');
  return '${_kMonths[l.month - 1]} ${l.day} • '
      '${hour.toString().padLeft(2, '0')}:$mm $ampm';
}

/// Formats a match start as "Jun 7 • 03:30 PM" (12-hour), matching the target.
String _dateTimeLabel(CricketMatch match) {
  final dt = match.startDateTime?.toLocal();
  if (dt == null) {
    // Never leak a raw epoch `startTime` into the corner date.
    if (match.statusText.isNotEmpty) return match.statusText;
    return looksLikeRawTimestamp(match.startTime) ? '' : match.startTime;
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
