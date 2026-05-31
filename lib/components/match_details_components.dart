import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../components.dart';
import '../models.dart';
import '../models/cricket_match.dart';

class MatchDetailHeroCard extends StatelessWidget {
  const MatchDetailHeroCard({
    super.key,
    required this.match,
    this.onWatchLive,
    this.showWatchLive = true,
  });

  final VoidCallback? onWatchLive;
  final bool showWatchLive;

  /// The match this hero card renders. Callers must resolve match data before
  /// rendering the hero (e.g. an empty/loading state should be shown
  /// upstream when summary data is not yet available).
  final CricketMatch match;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final w = context.w;
    final narrow = w <= 400;
    final pad = narrow ? 14.0 : 16.0;
    final badge = narrow ? 56.0 : 78.0;

    final m = match;
    final isLive = m.isLive;
    final isFinished = m.isFinished;
    final statusLabel = isLive ? 'LIVE' : (isFinished ? 'RESULT' : 'UPCOMING');
    final statusColor = isLive ? c.live : (isFinished ? c.success : c.cyan);
    final headline = m.matchDesc.isNotEmpty
        ? m.matchDesc
        : (m.statusText.isNotEmpty ? m.statusText : statusLabel);
    final seriesLine = m.series;
    final leftTeam = TeamInfo(
      code: m.teamAShort.isNotEmpty ? m.teamAShort : 'A',
      name: m.teamA.isNotEmpty ? m.teamA : 'Team A',
      shortName: m.teamAShort.isNotEmpty ? m.teamAShort : 'A',
      color: const Color(0xff22d3ee),
      asset: m.teamALogo,
    );
    final rightTeam = TeamInfo(
      code: m.teamBShort.isNotEmpty ? m.teamBShort : 'B',
      name: m.teamB.isNotEmpty ? m.teamB : 'Team B',
      shortName: m.teamBShort.isNotEmpty ? m.teamBShort : 'B',
      color: const Color(0xfff59e0b),
      asset: m.teamBLogo,
    );
    final showScore = isLive || isFinished;
    final leftScore = m.teamAScoreText;
    final rightScore = m.teamBScoreText;
    final hasAnyScore = leftScore.isNotEmpty || rightScore.isNotEmpty;
    final leftScoreLabel = showScore && hasAnyScore
        ? (leftScore.isNotEmpty ? leftScore : (isLive ? 'Yet to bat' : ''))
        : '';
    final rightScoreLabel = showScore && hasAnyScore
        ? (rightScore.isNotEmpty ? rightScore : (isLive ? 'Yet to bat' : ''))
        : '';
    assert(() {
      debugPrint('MATCH_DETAIL score team1=$leftScore');
      debugPrint('MATCH_DETAIL score team2=$rightScore');
      debugPrint(
          'MATCH_DETAIL hero leftScore=$leftScoreLabel rightScore=$rightScoreLabel');
      return true;
    }());
    final footLine = isFinished
        ? (m.resultText.isNotEmpty ? m.resultText : m.statusText)
        : m.statusText;
    final buttonLabel = showWatchLive
        ? 'Watch Live'
        : (isFinished ? 'View Scorecard' : 'Watch Live');
    final buttonIcon = showWatchLive
        ? Icons.play_circle_fill_rounded
        : (isFinished
            ? Icons.receipt_long_rounded
            : Icons.play_circle_fill_rounded);

    return Container(
      padding: EdgeInsets.all(pad),
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: c.border)),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset('assets/images/stadium_live.png',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    const EmptyOrErrorImage(label: 'Match')),
          ),
          Positioned.fill(
              child: DecoratedBox(
                  decoration: BoxDecoration(
                      gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                Colors.black.withValues(alpha: .18),
                Colors.black.withValues(alpha: .76)
              ])))),
          Column(
            children: [
              Row(
                children: [
                  StatusBadge(
                      label: statusLabel, color: statusColor, filled: true),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(headline,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: .92),
                              fontWeight: FontWeight.w700))),
                ],
              ),
              if (seriesLine.isNotEmpty) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    seriesLine,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: .92),
                        fontWeight: FontWeight.w700,
                        fontSize: context.sp(15)),
                  ),
                ),
              ],
              SizedBox(height: narrow ? 16 : 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                      child: _compactTeam(context, leftTeam, badge,
                          score: leftScoreLabel)),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('VS',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: .88),
                              fontWeight: FontWeight.w800)),

                    ],
                  ),
                  Expanded(
                      child: _compactTeam(context, rightTeam, badge,
                          score: rightScoreLabel)),
                ],
              ),
              SizedBox(height: narrow ? 14 : 20),
              if (footLine.isNotEmpty)
                Text(footLine,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: c.cyan,
                        fontWeight: FontWeight.w700,
                        fontSize: context.sp(13))),
              if (isFinished || showWatchLive) ...[
                const SizedBox(height: 16),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 240),
                  child: GradientButton(
                    label: buttonLabel,
                    icon: buttonIcon,
                    height: 50,
                    onTap: onWatchLive,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _compactTeam(BuildContext context, TeamInfo team, double badge,
      {String score = ''}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TeamBadge(team, size: badge),
        const SizedBox(height: 10),
        Text(
          team.shortName.toUpperCase(),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: context.sp(13)),
        ),
        if (score.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            score,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: context.sp(12.5)),
          ),
        ],
      ],
    );
  }
}
