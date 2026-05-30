import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../components.dart';
import '../models.dart';
import '../models/cricket_match.dart';

class MatchDetailHeroCard extends StatelessWidget {
  const MatchDetailHeroCard({
    super.key,
    this.onWatchLive,
    this.match,
    this.showWatchLive = true,
  });

  final VoidCallback? onWatchLive;
  final bool showWatchLive;

  /// When provided, the hero renders real data from this match. When null
  /// (e.g. demo mode), the hardcoded design preview is shown so the UI
  /// remains complete in storyboards.
  final CricketMatch? match;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final w = context.w;
    final narrow = w <= 400;
    final pad = narrow ? 14.0 : 16.0;
    final badge = narrow ? 56.0 : 78.0;

    final m = match;
    final isLive = m?.isLive ?? true;
    final isFinished = m?.isFinished ?? false;
    final statusLabel = isLive ? 'LIVE' : (isFinished ? 'RESULT' : 'UPCOMING');
    final statusColor = isLive ? c.live : (isFinished ? c.success : c.cyan);
    final headline = m == null
        ? '1st Test • Day 1'
        : (m.matchDesc.isNotEmpty
            ? m.matchDesc
            : (m.statusText.isNotEmpty ? m.statusText : statusLabel));
    final seriesLine = m == null
        ? 'West Indies Tour of New Zealand, 2025'
        : (m.series.isNotEmpty ? m.series : '');
    final leftTeam = m == null
        ? AppData.newZealand
        : TeamInfo(
            code: m.teamAShort.isNotEmpty ? m.teamAShort : 'A',
            name: m.teamA.isNotEmpty ? m.teamA : 'Team A',
            shortName: m.teamAShort.isNotEmpty ? m.teamAShort : 'A',
            color: const Color(0xff22d3ee),
            asset: m.teamALogo,
          );
    final rightTeam = m == null
        ? AppData.westIndies
        : TeamInfo(
            code: m.teamBShort.isNotEmpty ? m.teamBShort : 'B',
            name: m.teamB.isNotEmpty ? m.teamB : 'Team B',
            shortName: m.teamBShort.isNotEmpty ? m.teamBShort : 'B',
            color: const Color(0xfff59e0b),
            asset: m.teamBLogo,
          );
    final showScore = m == null || isLive || isFinished;
    final leftScore = m?.teamAScoreText ?? '';
    final rightScore = m?.teamBScoreText ?? '';
    final hasAnyScore = leftScore.isNotEmpty || rightScore.isNotEmpty;
    final centerScore = m == null ? '158/3' : '';
    final centerOvers = m == null ? '(38.4 OV)' : '';
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
    final footLine = m == null
        ? 'NZ won the toss & chose to bat'
        : (isFinished
            ? (m.resultText.isNotEmpty ? m.resultText : m.statusText)
            : m.statusText);
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
                      if (showScore && centerScore.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(centerScore,
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: context.sp(narrow ? 34 : 44),
                                  height: .95)),
                        ),
                        if (centerOvers.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(centerOvers,
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: .88),
                                  fontWeight: FontWeight.w700,
                                  fontSize: context.sp(13))),
                        ],
                      ],
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

class MatchScorecardTab extends StatelessWidget {
  const MatchScorecardTab({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    const batting = [
      ('K Williamson', '64*', '78', '6', '1', '82.05', true),
      ('R Ravindra', '22*', '29', '3', '0', '75.86', true),
      ('D Conway', '28', '42', '4', '0', '66.67', false),
      ('T Latham (wk)', '16', '24', '1', '0', '66.67', false),
      ('G Phillips', '8', '10', '0', '1', '80.00', false),
    ];
    return PremiumCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title row wraps onto two lines on narrow widths instead of
          // bleeding past the right edge.
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('NZ 158/3  (38.4 OV)',
                  style: TextStyle(
                      color: c.text,
                      fontWeight: FontWeight.w900,
                      fontSize: context.sp(17))),
              StatusBadge(label: '1st Innings', color: c.primary, filled: true),
            ],
          ),
          const SizedBox(height: 14),
          // Horizontally scrollable table: every cell has a fixed width so
          // SR/4s/6s never collapse to letter-fragments on narrow phones.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  decoration: BoxDecoration(
                    color: c.card2,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: c.border),
                  ),
                  child: const Row(
                    children: [
                      SizedBox(width: 15),
                      _ScoreCell('Batting',
                          width: 160, header: true, align: TextAlign.left),
                      _ScoreCell('R', width: 44, header: true),
                      _ScoreCell('B', width: 44, header: true),
                      _ScoreCell('4s', width: 44, header: true),
                      _ScoreCell('6s', width: 44, header: true),
                      _ScoreCell('SR', width: 60, header: true),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                for (var i = 0; i < batting.length; i++) ...[
                  _BattingRow(
                    name: batting[i].$1,
                    runs: batting[i].$2,
                    balls: batting[i].$3,
                    fours: batting[i].$4,
                    sixes: batting[i].$5,
                    sr: batting[i].$6,
                    live: batting[i].$7,
                  ),
                  if (i != batting.length - 1)
                    Divider(color: c.border, height: 0),
                ],
              ],
            ),
          ),
          Divider(color: c.border),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Expanded(
                    flex: 5,
                    child: Text('Extras',
                        style: TextStyle(
                            color: c.text, fontWeight: FontWeight.w700))),
                Expanded(
                    flex: 5,
                    child: Text('(b 1, lb 2, w 3, nb 0)',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: c.muted))),
                Text('6',
                    style:
                        TextStyle(color: c.text, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          Divider(color: c.border),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  c.cyan.withValues(alpha: .14),
                  c.cyan.withValues(alpha: 0),
                ],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Expanded(
                    child: Text('Total',
                        style: TextStyle(
                            color: c.cyan,
                            fontWeight: FontWeight.w800,
                            fontSize: context.sp(17)))),
                Text('158/3 (38.4 OV)',
                    style: TextStyle(
                        color: c.cyan,
                        fontWeight: FontWeight.w900,
                        fontSize: context.sp(17))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BattingRow extends StatelessWidget {
  const _BattingRow({
    required this.name,
    required this.runs,
    required this.balls,
    required this.fours,
    required this.sixes,
    required this.sr,
    required this.live,
  });

  final String name;
  final String runs;
  final String balls;
  final String fours;
  final String sixes;
  final String sr;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: Row(
        children: [
          SizedBox(
            width: 15,
            child: live
                ? PulseDot(color: c.success, size: 7, intensity: .6)
                : null,
          ),
          SizedBox(
            width: 160,
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.text,
                fontWeight: live ? FontWeight.w800 : FontWeight.w700,
              ),
            ),
          ),
          _ScoreCell(runs, width: 44),
          _ScoreCell(balls, width: 44),
          _ScoreCell(fours, width: 44),
          _ScoreCell(sixes, width: 44),
          _ScoreCell(sr, width: 60),
        ],
      ),
    );
  }
}

class _ScoreCell extends StatelessWidget {
  const _ScoreCell(
    this.text, {
    required this.width,
    this.header = false,
    this.align = TextAlign.center,
  });

  final String text;
  final double width;
  final bool header;
  final TextAlign align;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return SizedBox(
      width: width,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: align,
        style: TextStyle(
          color: header ? c.muted : c.text,
          fontWeight: header ? FontWeight.w800 : FontWeight.w600,
        ),
      ),
    );
  }
}

enum CommentaryFilter { all, wickets, boundaries, key }

class MatchCommentaryTab extends StatefulWidget {
  const MatchCommentaryTab({super.key});

  @override
  State<MatchCommentaryTab> createState() => _MatchCommentaryTabState();
}

class _MatchCommentaryTabState extends State<MatchCommentaryTab> {
  CommentaryFilter _filter = CommentaryFilter.all;

  static const _items = <(String, String, String, String)>[
    (
      '38.4',
      'RUNS',
      '2 runs',
      'Mitchell clips Holder through midwicket to bring up another productive over.'
    ),
    (
      '37.5',
      'WICKET',
      'Williamson falls',
      'Williamson falls attempting the late cut. Holder gets the breakthrough.'
    ),
    (
      '36.2',
      'FOUR',
      'Boundary!',
      'Conway drives gloriously on the up through cover.'
    ),
    (
      '35.6',
      'SIX',
      'Maximum!',
      'Phillips launches the final ball over long-on.'
    ),
    (
      '34.3',
      'RUNS',
      '1 run',
      'Latham nudges to mid-on for a comfortable single.'
    ),
  ];

  bool _passes(String type) {
    switch (_filter) {
      case CommentaryFilter.all:
        return true;
      case CommentaryFilter.wickets:
        return type == 'WICKET';
      case CommentaryFilter.boundaries:
        return type == 'FOUR' || type == 'SIX';
      case CommentaryFilter.key:
        return type != 'RUNS';
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final filtered = _items.where((e) => _passes(e.$2)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const PremiumCard(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(child: _MiniCommentaryStat(title: 'Runs', value: 158)),
              Expanded(child: _MiniCommentaryStat(title: 'Wickets', value: 3)),
              Expanded(
                  child: _MiniCommentaryStat(
                      title: 'Run Rate', value: 4.12, fractionDigits: 2)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 42,
          child: ListView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            children: [
              _filterChip('All', CommentaryFilter.all),
              const SizedBox(width: 8),
              _filterChip('Wickets', CommentaryFilter.wickets),
              const SizedBox(width: 8),
              _filterChip('Boundaries', CommentaryFilter.boundaries),
              const SizedBox(width: 8),
              _filterChip('Key Events', CommentaryFilter.key),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < filtered.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: FadeUp(
              delay: Duration(milliseconds: 60 * i),
              child: _CommentaryRow(
                ball: filtered[i].$1,
                type: filtered[i].$2,
                headline: filtered[i].$3,
                description: filtered[i].$4,
                isLast: i == filtered.length - 1,
              ),
            ),
          ),
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'No events match this filter yet.',
              textAlign: TextAlign.center,
              style: TextStyle(color: c.muted, fontWeight: FontWeight.w600),
            ),
          ),
      ],
    );
  }

  Widget _filterChip(String label, CommentaryFilter f) {
    final c = context.cric;
    final selected = _filter == f;
    return TapScale(
      onTap: () => setState(() => _filter = f),
      borderRadius: 22,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () => setState(() => _filter = f),
          borderRadius: BorderRadius.circular(22),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              gradient: selected ? c.primaryGradient : null,
              color: selected ? null : Colors.white.withValues(alpha: .02),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: selected ? c.cyan.withValues(alpha: .7) : c.border,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : c.text,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                fontSize: context.sp(13),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CommentaryRow extends StatelessWidget {
  const _CommentaryRow({
    required this.ball,
    required this.type,
    required this.headline,
    required this.description,
    required this.isLast,
  });

  final String ball;
  final String type;
  final String headline;
  final String description;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final accent = switch (type) {
      'WICKET' => c.live,
      'FOUR' => c.cyan,
      'SIX' => const Color(0xff8b5cff),
      _ => c.muted,
    };
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .22),
                  border: Border.all(color: accent.withValues(alpha: .55)),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  ball,
                  style: TextStyle(
                      color: accent, fontWeight: FontWeight.w900, fontSize: 11),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: c.border,
                    margin: const EdgeInsets.symmetric(vertical: 2),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: PremiumCard(
              padding: const EdgeInsets.all(14),
              radius: 18,
              borderColor: accent.withValues(alpha: .3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      StatusBadge(label: type, color: accent, filled: true),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'NZ 158/3',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: c.muted,
                              fontWeight: FontWeight.w700,
                              fontSize: context.sp(12.5)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    headline,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.text,
                      fontWeight: FontWeight.w800,
                      fontSize: context.sp(14.5),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.muted,
                      height: 1.45,
                      fontSize: context.sp(13),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniCommentaryStat extends StatelessWidget {
  const _MiniCommentaryStat({
    required this.title,
    required this.value,
    this.fractionDigits = 0,
  });

  final String title;
  final dynamic value;
  final int fractionDigits;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final style = TextStyle(
      color: c.text,
      fontWeight: FontWeight.w900,
      fontSize: context.sp(20),
    );
    final num? n = value is num ? value as num : num.tryParse(value.toString());
    return Column(
      children: [
        Text(title,
            style: TextStyle(color: c.muted, fontSize: context.sp(12.5))),
        const SizedBox(height: 4),
        if (n != null)
          CountUpText(value: n, style: style, fractionDigits: fractionDigits)
        else
          Text(value.toString(), style: style),
      ],
    );
  }
}

class MatchOversTab extends StatelessWidget {
  const MatchOversTab({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final w = context.w;
    final narrow = w <= 400;
    final cardPad = narrow ? 12.0 : 16.0;
    final chartHeight = narrow ? 160.0 : (w <= 480 ? 190.0 : 220.0);
    final overs = [
      (
        '38',
        '8',
        'Alzarri Joseph',
        'Fast',
        ['1', '0', '4', '0', '1', '2'],
        'Daryl Mitchell 64 (83)',
        'Tom Latham 27 (38)'
      ),
      (
        '37',
        '9',
        'Jason Holder',
        'Medium Fast',
        ['0', '4', '1', 'W', '2', '2'],
        'Daryl Mitchell 60 (79)',
        'Tom Latham 26 (36)'
      ),
      (
        '36',
        '8',
        'Alzarri Joseph',
        'Fast',
        ['1', '1', '0', '4', '1', '1'],
        'Daryl Mitchell 55 (74)',
        'Tom Latham 25 (34)'
      ),
      (
        '35',
        '11',
        'Jason Holder',
        'Medium Fast',
        ['4', '0', '4', '1', '1', '1'],
        'Daryl Mitchell 54 (71)',
        'Tom Latham 24 (33)'
      ),
    ];
    return Column(
      children: [
        PremiumCard(
          padding: EdgeInsets.all(cardPad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                      child: Text('Run Progression',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: c.text,
                              fontWeight: FontWeight.w900,
                              fontSize: context.sp(17)))),
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                        color: c.card2,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: c.border)),
                    child: Icon(Icons.open_in_full_rounded,
                        color: c.muted, size: 16),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 6,
                children: [
                  _legendDot(context, c.cyan, 'New Zealand'),
                  _legendDot(context, c.live, 'West Indies'),
                ],
              ),
              const SizedBox(height: 14),
              LayoutBuilder(
                builder: (ctx, constraints) {
                  return SizedBox(
                    width: constraints.maxWidth,
                    height: chartHeight,
                    child: CustomPaint(
                      size: Size(constraints.maxWidth, chartHeight),
                      painter: _RunChartPainter(c, compact: narrow),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              Divider(color: c.border, height: 1),
              const SizedBox(height: 12),
              Text('Recent Overs',
                  style: TextStyle(color: c.text, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text.rich(TextSpan(
                  style: TextStyle(color: c.muted, fontSize: 12.5),
                  children: [
                    const TextSpan(text: 'Runs: '),
                    TextSpan(
                        text: '42',
                        style: TextStyle(
                            color: c.cyan, fontWeight: FontWeight.w900)),
                    const TextSpan(text: '   Wickets: '),
                    TextSpan(
                        text: '1',
                        style: TextStyle(
                            color: c.cyan, fontWeight: FontWeight.w900)),
                    const TextSpan(text: '   Avg: '),
                    TextSpan(
                        text: '7.00',
                        style: TextStyle(
                            color: c.cyan, fontWeight: FontWeight.w900)),
                  ])),
              const SizedBox(height: 12),
              SizedBox(
                height: 60,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final item in [
                      ('34', '6'),
                      ('35', '11'),
                      ('36', '8'),
                      ('37', '9'),
                      ('38', '8*')
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(item.$1,
                                style: TextStyle(
                                    color: c.muted,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            _BallChip(
                                label: item.$2,
                                highlight: item.$2 == '11' || item.$2 == '8*',
                                wicket: item.$2 == '9'),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        for (final over in overs)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _OverRow(
              overNumber: over.$1,
              overRuns: over.$2,
              bowler: over.$3,
              bowlerType: over.$4,
              balls: over.$5,
              batter1: over.$6,
              batter2: over.$7,
              narrow: narrow,
            ),
          )
      ],
    );
  }

  Widget _legendDot(BuildContext context, Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(radius: 4, backgroundColor: color),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(color: context.cric.muted, fontSize: 12)),
      ],
    );
  }
}

class _OverRow extends StatelessWidget {
  const _OverRow({
    required this.overNumber,
    required this.overRuns,
    required this.bowler,
    required this.bowlerType,
    required this.balls,
    required this.batter1,
    required this.batter2,
    required this.narrow,
  });

  final String overNumber;
  final String overRuns;
  final String bowler;
  final String bowlerType;
  final List<String> balls;
  final String batter1;
  final String batter2;
  final bool narrow;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    if (narrow) {
      return PremiumCard(
        padding: const EdgeInsets.all(12),
        radius: 18,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _overBlock(context, c),
                const SizedBox(width: 12),
                Expanded(child: _bowlerBlock(context, c)),
                Icon(Icons.chevron_right_rounded, color: c.muted),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final ball in balls)
                _BallChip(
                    label: ball,
                    highlight: ball == '4' || ball == '6',
                    wicket: ball == 'W'),
            ]),
            const SizedBox(height: 10),
            Container(height: 1, color: c.border),
            const SizedBox(height: 10),
            _batterRow(context, c, batter1),
            const SizedBox(height: 4),
            _batterRow(context, c, batter2),
          ],
        ),
      );
    }
    return PremiumCard(
      padding: const EdgeInsets.all(14),
      radius: 18,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _overBlock(context, c),
          VerticalDivider(color: c.border, width: 22),
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _bowlerBlock(context, c),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final ball in balls)
                      _BallChip(
                          label: ball,
                          highlight: ball == '4' || ball == '6',
                          wicket: ball == 'W'),
                  ],
                ),
              ],
            ),
          ),
          VerticalDivider(color: c.border, width: 22),
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _batterRow(context, c, batter1),
                const SizedBox(height: 6),
                _batterRow(context, c, batter2),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: c.muted),
        ],
      ),
    );
  }

  Widget _overBlock(BuildContext context, CricColors c) {
    return SizedBox(
      width: 54,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('OVER', style: TextStyle(color: c.muted, fontSize: 10)),
          Text(overNumber,
              style: TextStyle(
                  color: c.cyan, fontWeight: FontWeight.w900, fontSize: 28)),
          Text('$overRuns RUNS',
              style: TextStyle(
                  color: c.cyan, fontSize: 10, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _bowlerBlock(BuildContext context, CricColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(children: [
          Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: c.live, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Expanded(
              child: Text(bowler,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      TextStyle(color: c.text, fontWeight: FontWeight.w800))),
        ]),
        Padding(
            padding: const EdgeInsets.only(left: 14, top: 2),
            child: Text(bowlerType,
                style: TextStyle(color: c.muted, fontSize: 12))),
      ],
    );
  }

  Widget _batterRow(BuildContext context, CricColors c, String name) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.sports_cricket_rounded, color: c.cyan, size: 14),
        const SizedBox(width: 6),
        Expanded(
            child: Text(name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: c.text, fontSize: 12, fontWeight: FontWeight.w700))),
      ],
    );
  }
}

class _RunChartPainter extends CustomPainter {
  _RunChartPainter(this.c, {this.compact = false});

  final CricColors c;
  final bool compact;

  TextPainter _label(String t,
      {Color? color, double size = 10, FontWeight weight = FontWeight.w700}) {
    final tp = TextPainter(
      text: TextSpan(
          text: t,
          style: TextStyle(
              color: color ?? c.muted, fontSize: size, fontWeight: weight)),
      textDirection: TextDirection.ltr,
    )..layout();
    return tp;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final leftPad = compact ? 26.0 : 32.0;
    final rightPad = compact ? 30.0 : 44.0;
    const bottomPad = 20.0;
    final chartW = size.width - leftPad - rightPad;
    final chartH = size.height - bottomPad;
    if (chartW <= 0 || chartH <= 0) return;

    final grid = Paint()
      ..color = c.border.withValues(alpha: .55)
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = chartH * i / 4;
      canvas.drawLine(Offset(leftPad, y), Offset(leftPad + chartW, y), grid);
      final label = _label('${200 - i * 50}');
      label.paint(
          canvas, Offset(leftPad - label.width - 8, y - label.height / 2));
    }
    final xSteps = compact ? 3 : 5;
    final lastIndex = xSteps;
    for (var i = 0; i <= xSteps; i++) {
      final x = leftPad + chartW * i / xSteps;
      if (i == lastIndex) continue;
      final overNum = (i * 50 / xSteps).round();
      final label = _label('$overNum');
      label.paint(canvas, Offset(x - label.width / 2, chartH + 4));
    }
    final overs =
        _label('OVERS', weight: FontWeight.w900, size: compact ? 9 : 10);
    overs.paint(canvas, Offset(leftPad + chartW - overs.width + 2, chartH + 4));

    final nz = [
      0,
      12,
      25,
      38,
      44,
      56,
      68,
      80,
      94,
      105,
      118,
      127,
      139,
      145,
      158
    ];
    final wi = [0, 6, 11, 20, 25, 31, 38, 45, 52, 60, 66, 72, 78];

    final nzPaint = Paint()
      ..color = c.cyan
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    final wiPaint = Paint()
      ..color = c.live
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke;

    final pathNz = Path();
    final pathWi = Path();
    Offset lastPoint = Offset.zero;
    for (var i = 0; i < nz.length; i++) {
      final x = leftPad + chartW * (i / (nz.length - 1)) * (42 / 50);
      final y = chartH - (nz[i] / 200) * chartH;
      lastPoint = Offset(x, y);
      if (i == 0) {
        pathNz.moveTo(x, y);
      } else {
        pathNz.lineTo(x, y);
      }
    }
    for (var i = 0; i < wi.length; i++) {
      final x = leftPad + chartW * (i / (nz.length - 1)) * (42 / 50);
      final y = chartH - (wi[i] / 200) * chartH;
      if (i == 0) {
        pathWi.moveTo(x, y);
      } else {
        pathWi.lineTo(x, y);
      }
    }
    canvas.drawPath(pathNz, nzPaint);
    canvas.drawPath(pathWi, wiPaint);

    final glow = Paint()
      ..color = c.cyan.withValues(alpha: .35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);
    canvas.drawCircle(lastPoint, 8, glow);
    canvas.drawCircle(lastPoint, 5, Paint()..color = c.cyan);
    final label = _label('158/3',
        color: c.cyan, size: compact ? 12 : 14, weight: FontWeight.w900);
    final fitsRight = lastPoint.dx + 8 + label.width <= size.width;
    final labelDx =
        fitsRight ? lastPoint.dx + 8 : lastPoint.dx - 8 - label.width;
    label.paint(canvas, Offset(labelDx, lastPoint.dy - label.height / 2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _BallChip extends StatelessWidget {
  const _BallChip(
      {required this.label, this.highlight = false, this.wicket = false});

  final String label;
  final bool highlight;
  final bool wicket;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final bg = wicket
        ? c.live
        : highlight
            ? c.primary
            : c.card2;
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(label,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13)),
    );
  }
}

class MatchInfoTab extends StatelessWidget {
  const MatchInfoTab({super.key});

  @override
  Widget build(BuildContext context) {
    const items = <(IconData, String, String, String?)>[
      (Icons.stadium_outlined, 'Venue', 'Hagley Oval', 'Christchurch'),
      (Icons.sports_cricket_rounded, 'Toss', 'New Zealand', 'elected to bat'),
      (
        Icons.person_outline_rounded,
        'Umpires',
        'Richard Kettleborough',
        'Michael Gough'
      ),
      (Icons.wb_cloudy_outlined, 'Weather', 'Cloudy', '18°C • Humid'),
      (
        Icons.live_tv_rounded,
        'Streaming',
        'CricPro Live',
        'English & Hindi feed'
      ),
      (Icons.shield_outlined, 'Series', '3rd ODI', 'Of 3 matches'),
    ];
    return PremiumCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: LayoutBuilder(
        builder: (ctx, cs) {
          // On mobile use a single full-width list. On tablet/desktop the
          // info reads better as a 2-column grid of the same list rows.
          final cols = cs.maxWidth >= 720 ? 2 : 1;
          if (cols == 1) {
            return Column(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  FadeUp(
                    delay: Duration(milliseconds: 60 * i),
                    child: InfoListTile(
                      icon: items[i].$1,
                      label: items[i].$2,
                      value: items[i].$3,
                      subtitle: items[i].$4,
                    ),
                  ),
                  if (i != items.length - 1)
                    Divider(color: context.cric.border, height: 1),
                ],
              ],
            );
          }
          const spacing = 12.0;
          final tileW = computeGridChildWidth(
            maxWidth: cs.maxWidth,
            columns: cols,
            spacing: spacing,
          );
          return Wrap(
            spacing: spacing,
            runSpacing: 0,
            children: [
              for (var i = 0; i < items.length; i++)
                SizedBox(
                  width: tileW,
                  child: FadeUp(
                    delay: Duration(milliseconds: 60 * i),
                    child: InfoListTile(
                      icon: items[i].$1,
                      label: items[i].$2,
                      value: items[i].$3,
                      subtitle: items[i].$4,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class MatchSquadsTab extends StatelessWidget {
  const MatchSquadsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final players = [
      'Devon Conway',
      'Rachin Ravindra',
      'Kane Williamson',
      'Daryl Mitchell',
      'Tom Latham',
      'Glenn Phillips',
    ];
    return Column(
      children: [
        const PremiumCard(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(child: _MiniCommentaryStat(title: 'Toss', value: 'NZ')),
              Expanded(
                  child: _MiniCommentaryStat(title: 'Venue', value: 'Hagley')),
              Expanded(
                  child: _MiniCommentaryStat(title: 'Umpires', value: '2')),
              Expanded(
                  child:
                      _MiniCommentaryStat(title: 'Series', value: '3rd ODI')),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SegmentedTabs(
            items: const [('New Zealand', null), ('West Indies', null)],
            selected: 0,
            onChanged: (_) {},
            height: 56),
        const SizedBox(height: 16),
        PremiumCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text('PLAYING XI',
                    style: TextStyle(
                        color: c.cyan,
                        fontWeight: FontWeight.w800,
                        fontSize: 18)),
                const Spacer(),
                Text('CAPTAIN: Mitchell Santner',
                    style:
                        TextStyle(color: c.muted, fontWeight: FontWeight.w700))
              ]),
              const SizedBox(height: 12),
              for (var i = 0; i < players.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: PremiumCard(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    radius: 16,
                    child: Row(
                      children: [
                        Container(
                            width: 28,
                            height: 28,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                                color: c.card2, shape: BoxShape.circle),
                            child: Text('${i + 1}',
                                style: TextStyle(
                                    color: c.text,
                                    fontWeight: FontWeight.w800))),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Text(players[i],
                                style: TextStyle(
                                    color: c.text,
                                    fontWeight: FontWeight.w700))),
                        StatusBadge(
                            label: i == 4 ? 'WK' : 'BAT',
                            color: i == 4 ? const Color(0xff3b82f6) : c.cyan,
                            filled: true),
                        const SizedBox(width: 8),
                        StatusBadge(
                            label: 'Playing XI',
                            color: c.success,
                            filled: true),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Text('BENCH',
                  style: TextStyle(
                      color: c.cyan,
                      fontWeight: FontWeight.w800,
                      fontSize: 18)),
              const SizedBox(height: 10),
              const Wrap(spacing: 10, runSpacing: 10, children: [
                PillChip('Will Young'),
                PillChip('Lockie Ferguson'),
                PillChip('Michael Bracewell')
              ]),
            ],
          ),
        )
      ],
    );
  }
}
