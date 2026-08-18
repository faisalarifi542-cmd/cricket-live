part of '../live_player_screen.dart';

class _LivePlayerHeader extends StatelessWidget {
  const _LivePlayerHeader({required this.matchId, this.onShare});

  final String matchId;
  final VoidCallback? onShare;

  void _showCastNotAvailable(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Cast support is coming soon'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: context.cric.card,
      ),
    );
  }

  void _showMoreOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _MoreOptionsSheet(matchId: matchId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Row(
      children: [
        _HeaderActionButton(
          svgAsset: 'assets/images/live_stream/icons/ic_back_white.svg',
          fallback: Icons.arrow_back_rounded,
          onTap: () => Navigator.pop(context),
        ),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: c.cyan,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: c.cyan.withValues(alpha: .7),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Live Stream',
                style: TextStyle(
                  color: c.text,
                  fontWeight: FontWeight.w900,
                  fontSize: context.sp(22),
                ),
              ),
            ],
          ),
        ),
        _HeaderActionButton(
          svgAsset: 'assets/images/live_stream/icons/ic_cast_white.svg',
          fallback: Icons.cast_rounded,
          onTap: () => _showCastNotAvailable(context),
        ),
        const SizedBox(width: 8),
        _HeaderActionButton(
          svgAsset: 'assets/images/live_stream/icons/ic_share_white.svg',
          fallback: Icons.share_rounded,
          onTap: onShare,
        ),
        const SizedBox(width: 8),
        _HeaderActionButton(
          svgAsset:
              'assets/images/live_stream/icons/ic_more_vertical_white.svg',
          fallback: Icons.more_vert_rounded,
          onTap: () => _showMoreOptions(context),
        ),
      ],
    );
  }
}

class _HeaderActionButton extends StatelessWidget {
  const _HeaderActionButton(
      {required this.fallback, this.svgAsset, this.onTap});

  final IconData fallback;
  final String? svgAsset;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.card.withValues(alpha: .55),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: c.cyan.withValues(alpha: .3)),
          boxShadow: [
            BoxShadow(
              color: c.isDark
                  ? Colors.black.withValues(alpha: .25)
                  : const Color(0xff4a7fb5).withValues(alpha: .12),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: svgAsset != null
            ? SvgPicture.asset(
                svgAsset!,
                width: 22,
                height: 22,
                colorFilter: ColorFilter.mode(c.text, BlendMode.srcIn),
                excludeFromSemantics: true,
                placeholderBuilder: (_) =>
                    Icon(fallback, color: c.text, size: 22),
              )
            : Icon(fallback, color: c.text, size: 22),
      ),
    );
  }
}

class _MatchInfoSection extends StatelessWidget {
  const _MatchInfoSection({
    required this.matchId,
    required this.detailFuture,
    required this.liveLineFuture,
  });

  final String matchId;
  final Future<ApiEnvelope<Map<String, dynamic>>>? detailFuture;
  final Future<ApiEnvelope<Map<String, dynamic>>>? liveLineFuture;

  @override
  Widget build(BuildContext context) {
    if (matchId.isEmpty) {
      return const _MatchInfoUnavailable();
    }
    return FutureBuilder<ApiEnvelope<Map<String, dynamic>>>(
      future: detailFuture,
      builder: (context, detailSnapshot) {
        return FutureBuilder<ApiEnvelope<Map<String, dynamic>>>(
          future: liveLineFuture,
          builder: (context, lineSnapshot) {
            final loading =
                detailSnapshot.connectionState == ConnectionState.waiting &&
                    !detailSnapshot.hasData;
            if (loading) {
              return const _MatchInfoSkeleton();
            }
            final detail = apiMap(detailSnapshot.data?.data);
            final liveLine = apiMap(lineSnapshot.data?.data);
            return _MatchInfoCard(
                matchId: matchId, detail: detail, liveLine: liveLine);
          },
        );
      },
    );
  }
}

class _MatchInfoCard extends StatelessWidget {
  const _MatchInfoCard({
    required this.matchId,
    required this.detail,
    required this.liveLine,
  });

  final String matchId;
  final Map<String, dynamic> detail;
  final Map<String, dynamic> liveLine;

  String _firstNonEmpty(List<String?> values, String fallback) {
    for (final value in values) {
      final v = apiString(value);
      if (v.isNotEmpty) return v;
    }
    return fallback;
  }

  /// Resolves a team logo with the SAME priority/source as the Home Screen,
  /// then falls back to the logo Home already resolved for this match (kept in
  /// [CricketMatch.knownSummary]) when the live detail payload didn't carry one.
  ///
  /// Order: detail logo (admin/backend → Cricbuzz id) → Home-resolved summary
  /// logo (matched by short name, else positional) → null (so [TeamLogoWidget]
  /// applies its own local-flag-asset → initials fallback exactly like Home).
  String? _teamLogo(
    Map<String, dynamic> team,
    String shortName,
    CricketMatch? summary, {
    required bool isTeam2,
  }) {
    final direct = resolveTeamLogoUrl(team);
    if (direct != null && direct.isNotEmpty) return direct;
    if (summary == null) return null;

    final key = shortName.trim().toUpperCase();
    final aShort = summary.teamAShort.trim().toUpperCase();
    final bShort = summary.teamBShort.trim().toUpperCase();
    // Prefer an exact short-name match so a reordered detail can't swap logos.
    if (key.isNotEmpty && key == aShort) return summary.teamALogo;
    if (key.isNotEmpty && key == bShort) return summary.teamBLogo;
    // No name match — fall back positionally (team1→A, team2→B).
    return isTeam2 ? summary.teamBLogo : summary.teamALogo;
  }

  _ScoreLine _formatScore(dynamic team) {
    final t = apiMap(team);
    final innings = apiList(t['innings']);
    if (innings.isEmpty) return const _ScoreLine();

    // Build a per-innings "runs/wickets" string. For Test / multi-innings
    // matches we join both innings with " & " (e.g. "226 & 145/3") and show
    // overs only for the latest innings so the card stays compact.
    String inningScore(Map<String, dynamic> inn) {
      final runs = apiInt(inn['runs']);
      if (runs == null) return '';
      final wickets = apiInt(inn['wickets']);
      // A fully bowled-out innings (10 wickets) is conventionally shown as the
      // run total only in the combined Test view, but we keep runs/wkts to stay
      // faithful to the backend; callers decide compactness.
      return wickets == null ? '$runs' : '$runs/$wickets';
    }

    final parts = <String>[];
    for (final raw in innings) {
      final s = inningScore(apiMap(raw));
      if (s.isNotEmpty) parts.add(s);
    }
    if (parts.isEmpty) return const _ScoreLine();

    final latest = apiMap(innings.last);
    final overs = normalizeOversText(latest['overs']);
    return _ScoreLine(score: parts.join(' & '), overs: overs);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final narrow = context.w < 390;
    final team1 = apiMap(detail['team1']);
    final team2 = apiMap(detail['team2']);
    final status = apiString(detail['status']).toLowerCase();
    final isLive = status == 'live' || status == 'inprogress';
    final isCompleted = status == 'completed' || status == 'finished';
    final badge = isLive
        ? 'LIVE'
        : isCompleted
            ? 'RESULT'
            : 'UPCOMING';
    final badgeColor = isLive
        ? c.live
        : isCompleted
            ? c.success
            : c.cyan;
    final t1Name = _firstNonEmpty(
      [
        team1['short_name']?.toString(),
        team1['shortName']?.toString(),
        team1['name']?.toString(),
      ],
      'TBD',
    );
    final t2Name = _firstNonEmpty(
      [
        team2['short_name']?.toString(),
        team2['shortName']?.toString(),
        team2['name']?.toString(),
      ],
      'TBD',
    );
    final t1Full = apiString(team1['name'], t1Name);
    final t2Full = apiString(team2['name'], t2Name);
    final t1Score = _formatScore(team1);
    final t2Score = _formatScore(team2);

    // Logo resolution must match the Home Screen exactly. The live `/match/:id`
    // detail can omit the team `imageId`/`logo_url` (the miniscore team block
    // carries no logo), which makes franchise teams with no local flag asset
    // (e.g. SFU/LAKR) fall back to initials here even though Home shows the real
    // logo. To stay consistent we resolve in this order and reuse the SAME logo
    // the Home list already resolved for this match via the shared summary
    // registry. `_teamLogo` maps detail team1→teamA / team2→teamB, matching by
    // short name when present so a reordered detail can't pick the wrong logo.
    final summary = CricketMatch.knownSummary(matchId);
    final t1Logo = _teamLogo(team1, t1Name, summary, isTeam2: false);
    final t2Logo = _teamLogo(team2, t2Name, summary, isTeam2: true);
    final statusText = _firstNonEmpty(
      [
        detail['status_text']?.toString(),
        liveLine['statusText']?.toString(),
        liveLine['status']?.toString(),
      ],
      'Match details will update shortly.',
    );
    final start = apiDate(detail['start_time'] ?? detail['startTime']);
    final contextText = start != null && !isLive && !isCompleted
        ? 'Match starts at ${_formatStart(start)}'
        : statusText;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: narrow ? 14 : 16,
        vertical: narrow ? 12 : 14,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: c.isDark
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xff071528),
                  Color(0xff0a2540),
                  Color(0xff0b2b4a),
                ],
              )
            : c.cardGradient,
        border: Border.all(color: c.cyan.withValues(alpha: .28)),
        boxShadow: [
          BoxShadow(
            color: c.cyan.withValues(alpha: .10),
            blurRadius: 22,
            spreadRadius: -6,
          ),
          BoxShadow(
            color: c.isDark
                ? Colors.black.withValues(alpha: .30)
                : const Color(0xff4a7fb5).withValues(alpha: .12),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(
                color: c.card.withValues(alpha: .5),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: badgeColor.withValues(alpha: .7)),
              ),
              child: Text(
                isLive ? 'LIVE CRICKET' : badge,
                style: TextStyle(
                  color: badgeColor,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  letterSpacing: .5,
                ),
              ),
            ),
          ),
          SizedBox(height: narrow ? 12 : 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: _TeamRow(
                  name: t1Name,
                  fullName: t1Full,
                  score: t1Score,
                  logoUrl: t1Logo,
                  isStriker:
                      apiString(liveLine['battingTeam']?.toString()) == t1Name,
                  logoLeading: true,
                ),
              ),
              _VsMedallion(narrow: narrow),
              Expanded(
                child: _TeamRow(
                  name: t2Name,
                  fullName: t2Full,
                  score: t2Score,
                  logoUrl: t2Logo,
                  isStriker:
                      apiString(liveLine['battingTeam']?.toString()) == t2Name,
                  logoLeading: false,
                ),
              ),
            ],
          ),
          SizedBox(height: narrow ? 10 : 12),
          Text(
            contextText,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: c.cyan,
              fontWeight: FontWeight.w800,
              fontSize: narrow ? 12 : 13,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }

  static String _formatStart(DateTime date) {
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
      'Dec',
    ];
    final utc = date.toUtc();
    final hour = utc.hour.toString().padLeft(2, '0');
    final minute = utc.minute.toString().padLeft(2, '0');
    return '${utc.day} ${months[utc.month - 1]}, $hour:$minute GMT';
  }
}

class _ScoreLine {
  const _ScoreLine({this.score, this.overs});

  final String? score;
  final String? overs;
}

class _LiveBadge extends StatefulWidget {
  const _LiveBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  State<_LiveBadge> createState() => _LiveBadgeState();
}

class _LiveBadgeState extends State<_LiveBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  bool get _isLive => widget.label.toUpperCase() == 'LIVE';

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: widget.color,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: widget.color.withValues(alpha: .32),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isLive) ...[
            AnimatedBuilder(
              animation: _pulse,
              builder: (context, _) => Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color:
                      Colors.white.withValues(alpha: .65 + .35 * _pulse.value),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            widget.label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 11.5,
              letterSpacing: .4,
            ),
          ),
        ],
      ),
    );
  }
}

class _VsMedallion extends StatefulWidget {
  const _VsMedallion({required this.narrow});

  final bool narrow;

  @override
  State<_VsMedallion> createState() => _VsMedallionState();
}

class _VsMedallionState extends State<_VsMedallion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final narrow = widget.narrow;
    final size = narrow ? 40.0 : 46.0;
    return SizedBox(
      width: narrow ? 50 : 60,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Subtle vertical divider behind the medallion.
          Container(
            width: 1,
            height: 58,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  c.cyan.withValues(alpha: .35),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          // Pulsing cyan glow ring + dark premium center.
          AnimatedBuilder(
            animation: _pulse,
            builder: (context, _) {
              final t = _pulse.value; // 0..1
              return Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xff0b2238), Color(0xff071528)],
                  ),
                  border: Border.all(
                    color: c.cyan.withValues(alpha: .55 + .35 * t),
                    width: 1.6,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: c.cyan.withValues(alpha: .22 + .22 * t),
                      blurRadius: 12 + 8 * t,
                      spreadRadius: 1 + t,
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  'VS',
                  style: TextStyle(
                    color: c.cyan,
                    fontWeight: FontWeight.w900,
                    fontSize: narrow ? 12 : 13,
                    letterSpacing: .5,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _TeamRow extends StatelessWidget {
  const _TeamRow({
    required this.name,
    required this.fullName,
    required this.score,
    required this.logoUrl,
    required this.isStriker,
    required this.logoLeading,
  });

  final String name;
  final String fullName;
  final _ScoreLine score;
  final String? logoUrl;
  final bool isStriker;

  /// When true the logo sits on the left (team 1); when false on the right
  /// (team 2) so both teams mirror outward from the center VS, like the target.
  final bool logoLeading;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final hasScore = apiString(score.score).isNotEmpty;
    final overs = normalizeOversText(score.overs);

    final logo = TeamLogoWidget(
      logoUrl: logoUrl,
      teamName: fullName,
      abbreviation: name,
      color: isStriker ? c.cyan : const Color(0xfff59e0b),
      size: 46,
      borderColor: isStriker ? c.cyan : c.border.withValues(alpha: .6),
      // The team name sits beside the logo in the adjacent info column.
      excludeSemantics: true,
    );

    final info = Column(
      crossAxisAlignment:
          logoLeading ? CrossAxisAlignment.start : CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: c.isDark ? Colors.white : c.text,
            fontWeight: FontWeight.w900,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 2),
        if (hasScore) ...[
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment:
                logoLeading ? Alignment.centerLeft : Alignment.centerRight,
            child: Text(
              apiString(score.score),
              maxLines: 1,
              style: TextStyle(
                color: isStriker
                    ? c.cyan
                    : c.isDark
                        ? Colors.white.withValues(alpha: .95)
                        : c.text,
                fontWeight: FontWeight.w900,
                fontSize: 19,
              ),
            ),
          ),
          if (overs.isNotEmpty)
            Text(
              '($overs)',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.muted,
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
            ),
        ] else
          Container(
            margin: const EdgeInsets.only(top: 4),
            width: 14,
            height: 4,
            decoration: BoxDecoration(
              color: c.border,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
      ],
    );

    final children = logoLeading
        ? [logo, const SizedBox(width: 10), Flexible(child: info)]
        : [Flexible(child: info), const SizedBox(width: 10), logo];

    return Row(
      mainAxisAlignment:
          logoLeading ? MainAxisAlignment.start : MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: children,
    );
  }
}

class _MatchInfoSkeleton extends StatelessWidget {
  const _MatchInfoSkeleton();

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          Container(
            width: 140,
            height: 12,
            decoration: BoxDecoration(
              color: c.card2,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(
              3,
              (_) => Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: c.card2,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: 200,
            height: 12,
            decoration: BoxDecoration(
              color: c.card2,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ],
      ),
    );
  }
}

class _MatchInfoUnavailable extends StatelessWidget {
  const _MatchInfoUnavailable();

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: c.cyan, size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'Open Live Player from a live match card to see streams.',
              style: TextStyle(
                color: c.text,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

