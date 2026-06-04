import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'package:cricpro_flutter/app_theme.dart';
import 'package:cricpro_flutter/api_models.dart';
import 'package:cricpro_flutter/components.dart';

/// Premium compact "Live Center" tab for Match Details.
///
/// Renders different layouts depending on the match state:
///
/// * **Live / in progress** — current batters, current bowler, partnership,
///   last wicket, the recent over and a live commentary timeline.
/// * **Completed / result** — a result summary, player of the match, top
///   performers from the scorecard, the last wicket and the latest commentary.
/// * **Upcoming** — a premium "not started" state with teams, venue and start
///   time.
///
/// It intentionally has **no** timer of its own — it is a pure function of the
/// data passed in, so it updates silently whenever the parent refreshes.
class LiveMatchTab extends StatelessWidget {
  const LiveMatchTab({
    super.key,
    required this.summary,
    this.liveCenter,
    this.commentaryData,
    this.scorecardData,
  });

  /// Match detail payload (`matchDetail`) carrying the live miniscore:
  /// `current_batsmen`, `current_bowler`, `partnership`, `last_wicket`, the
  /// `result`/`status` text and `player_of_match`. Used as a fallback when the
  /// merged live-center is not yet available.
  final Map<String, dynamic>? summary;

  /// Merged Live Center payload (`/match/:id/live-center`). Preferred source —
  /// already contains current batters, bowler, partnership, last wicket,
  /// recent balls and latest commentary (with scorecard/commentary fallbacks
  /// merged server-side).
  final Map<String, dynamic>? liveCenter;

  /// Optional raw commentary payload (legacy fallback for the recent-over
  /// bubbles + timeline when the live-center has no commentary).
  final Map<String, dynamic>? commentaryData;

  /// Scorecard payload (`matchScorecard`) used for completed-match top
  /// performers and final innings scores. May be null until it loads.
  final Map<String, dynamic>? scorecardData;

  @override
  Widget build(BuildContext context) {
    // Prefer the merged live-center payload; fall back to the match summary.
    final lc = _liveMap(liveCenter?['data'] ??
        liveCenter?['liveCenter'] ??
        liveCenter?['live_center'] ??
        liveCenter);
    final summaryData = summary ?? const <String, dynamic>{};
    final embeddedLc = _liveMap(summaryData['live_center'] ??
        summaryData['liveCenter'] ??
        summaryData['live_center_data']);
    final effectiveLc = _mergeLiveCenterFallback(primary: lc, fallback: embeddedLc);

    // Determine state primarily from the live-center, then the summary.
    final lcState = _liveStr(_liveValue(effectiveLc, 'match_state', 'matchState'));
    final _MatchState state;
    if (lcState == 'finished') {
      state = _MatchState.finished;
    } else if (lcState == 'live') {
      state = _MatchState.live;
    } else if (lcState == 'upcoming') {
      state = _MatchState.upcoming;
    } else {
      state = _MatchStateHelper.of(summaryData);
    }

    // Commentary: prefer live-center commentary, then the raw commentary list.
    List<dynamic> comms = _liveList(_liveValue(
      effectiveLc,
      'commentary',
      'commentaryList',
      'comments',
    ));
    if (comms.isEmpty) {
      final raw = commentaryData ?? const <String, dynamic>{};
      comms = _liveList(raw['data'] ??
          raw['items'] ??
          raw['commentary'] ??
          raw['commentaryList']);
    }

    switch (state) {
      case _MatchState.finished:
        return _LiveMatchResultView(
          summary: summaryData,
          liveCenter: effectiveLc,
          comms: comms,
          scorecard: scorecardData ?? const <String, dynamic>{},
        );
      case _MatchState.upcoming:
        return _LiveMatchUpcomingView(summary: summaryData);
      case _MatchState.live:
        return _LiveMatchActiveView(
          summary: summaryData,
          liveCenter: effectiveLc,
          comms: comms,
        );
    }
  }
}

// ---------------------------------------------------------------------------
// Match state
// ---------------------------------------------------------------------------

enum _MatchState { live, finished, upcoming }

class _MatchStateHelper {
  static _MatchState of(Map<String, dynamic> data) {
    final status =
        _liveStr(data['status'] ?? data['state'] ?? data['match_status'])
            .toLowerCase();
    if (_isFinishedStatus(status)) return _MatchState.finished;
    if (_isLiveStatus(status)) return _MatchState.live;

    // Status was inconclusive — fall back to the data we actually have. A
    // populated result string with no live miniscore means the match is over.
    final hasLiveMiniscore = _liveList(data['current_batsmen']).isNotEmpty ||
        _liveMap(data['current_bowler']).isNotEmpty;
    final resultText =
        _liveStr(data['result'] ?? data['status_text'] ?? data['result_text']);
    if (!hasLiveMiniscore && _looksLikeResult(resultText)) {
      return _MatchState.finished;
    }
    if (hasLiveMiniscore) return _MatchState.live;
    return _MatchState.upcoming;
  }

  static bool _isFinishedStatus(String s) =>
      s.contains('complete') ||
      s.contains('result') ||
      s == 'finished' ||
      s == 'recent' ||
      s.contains('won') ||
      s.contains('draw') ||
      s.contains('abandon') ||
      s.contains('no result') ||
      s.contains('no_result') ||
      s.contains('tie');

  static bool _looksLikeResult(String text) {
    final t = text.toLowerCase();
    return t.contains('won') ||
        t.contains('win') ||
        t.contains('draw') ||
        t.contains('tie') ||
        t.contains('abandon') ||
        t.contains('no result');
  }
}

// ---------------------------------------------------------------------------
// Active (live) view
// ---------------------------------------------------------------------------

class _LiveMatchActiveView extends StatelessWidget {
  const _LiveMatchActiveView({
    required this.summary,
    required this.liveCenter,
    required this.comms,
  });

  final Map<String, dynamic> summary;
  final Map<String, dynamic> liveCenter;
  final List<dynamic> comms;

  @override
  Widget build(BuildContext context) {
    final data = summary;
    final lc = liveCenter;

    // Prefer live-center sections; fall back to the summary miniscore.
    final batters = _validBatters(
      _liveValue(lc, 'current_batters', 'currentBatters') != null
          ? _liveList(_liveValue(lc, 'current_batters', 'currentBatters'))
          : _liveList(_liveValue(data, 'current_batsmen', 'currentBatsmen')),
    );
    final bowler = _validBowler(
      _liveValue(lc, 'current_bowler', 'currentBowler') != null
          ? _liveMap(_liveValue(lc, 'current_bowler', 'currentBowler'))
          : _liveMap(_liveValue(data, 'current_bowler', 'currentBowler')),
    );
    final partnership = _liveValue(lc, 'partnership') != null
        ? _liveMap(_liveValue(lc, 'partnership'))
        : _liveMap(_liveValue(data, 'partnership'));
    final lastWicket = _liveStr(
      _liveValue(lc, 'last_wicket', 'lastWicket'),
      fallback: _liveStr(_liveValue(data, 'last_wicket', 'lastWicket')),
    );

    // Recent balls: prefer the structured live-center list, then commentary
    // deliveries (rows with an over number).
    final lcBalls = _liveList(_liveValue(lc, 'recent_balls', 'recentBalls'));
    final List<Map<String, dynamic>> recentBalls;
    if (lcBalls.isNotEmpty) {
      recentBalls = lcBalls.map(_liveMap).toList(growable: false);
    } else {
      final balls = comms
          .map(_liveMap)
          .where((row) => _liveStr(row['over']).isNotEmpty)
          .toList(growable: false);
      recentBalls = balls.take(6).toList(growable: false);
    }

    final hasAnyLive = batters.isNotEmpty ||
        bowler.isNotEmpty ||
        partnership.isNotEmpty ||
        lastWicket.isNotEmpty ||
        recentBalls.isNotEmpty ||
        comms.isNotEmpty;

    if (!hasAnyLive) {
      return const _LiveEmptyState();
    }

    if (kDebugMode) {
      debugPrint('[LiveTab] liveCenter keys: ${liveCenter.keys.toList()}');
      debugPrint('[LiveTab] currentBatters=${batters.length}');
      debugPrint('[LiveTab] currentBowler=${bowler.isNotEmpty}');
      debugPrint('[LiveTab] partnership=${partnership.isNotEmpty}');
      debugPrint('[LiveTab] recentBalls=${recentBalls.length}');
      debugPrint('[LiveTab] commentary=${comms.length}');
    }

    final recentOverLabel = recentBalls.isNotEmpty
        ? _liveStr(recentBalls.first['over'])
        : '';
    final lcRecentFromBalls = lcBalls.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (batters.isNotEmpty) ...[
          const _LiveSectionTitle('Current Batters', color: null),
          const SizedBox(height: 10),
          _CurrentBattersCard(batters: batters),
          const SizedBox(height: 18),
        ],
        if (bowler.isNotEmpty) ...[
          const _LiveSectionTitle('Current Bowler', color: null),
          const SizedBox(height: 10),
          _CurrentBowlerCard(bowler: bowler),
          const SizedBox(height: 18),
        ],
        if (partnership.isNotEmpty || lastWicket.isNotEmpty) ...[
          _PartnershipLastWicketRow(
            partnership: partnership,
            lastWicket: lastWicket,
          ),
          const SizedBox(height: 18),
        ],
        if (recentBalls.isNotEmpty) ...[
          _RecentOverHeader(over: recentOverLabel),
          const SizedBox(height: 10),
          _RecentOverBubbles(balls: recentBalls, fromLiveCenter: lcRecentFromBalls),
          const SizedBox(height: 18),
        ],
        if (comms.isNotEmpty) ...[
          const _LiveSectionTitle('Live Commentary', color: null),
          const SizedBox(height: 10),
          _LiveCommentaryTimeline(items: comms.take(8).toList()),
          const SizedBox(height: 14),
        ],
        const _LiveFooter(isLive: true),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Result (completed) view
// ---------------------------------------------------------------------------

class _LiveMatchResultView extends StatelessWidget {
  const _LiveMatchResultView({
    required this.summary,
    required this.liveCenter,
    required this.comms,
    required this.scorecard,
  });

  final Map<String, dynamic> summary;
  final Map<String, dynamic> liveCenter;
  final List<dynamic> comms;
  final Map<String, dynamic> scorecard;

  @override
  Widget build(BuildContext context) {
    // Player of match: prefer live-center, then summary.
    final lcPom = _liveMap(liveCenter['player_of_match']);
    final Map<String, dynamic>? pom =
        lcPom.isNotEmpty ? lcPom : _resolvePlayerOfMatch(summary);
    final performers = _topPerformers(scorecard);
    final lastWicket = _liveStr(
      liveCenter['last_wicket'],
      fallback: _resolveLastWicket(summary, scorecard),
    );
    final lcBalls = _liveList(liveCenter['recent_balls']);
    final List<Map<String, dynamic>> finalOver;
    bool lcRecentFromBalls = false;
    if (lcBalls.isNotEmpty) {
      finalOver = lcBalls.map(_liveMap).toList(growable: false);
      lcRecentFromBalls = true;
    } else {
      finalOver = comms
          .map(_liveMap)
          .where((row) => _liveStr(row['over']).isNotEmpty)
          .take(6)
          .toList(growable: false);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ResultSummaryCard(summary: summary, liveCenter: liveCenter),
        const SizedBox(height: 18),
        const _LiveSectionTitle('Player of the Match'),
        const SizedBox(height: 10),
        _PlayerOfMatchCard(player: (pom == null || pom.isEmpty) ? null : pom),
        if (performers.isNotEmpty) ...[
          const SizedBox(height: 18),
          const _LiveSectionTitle('Top Performers'),
          const SizedBox(height: 10),
          _TopPerformersCard(performers: performers),
        ],
        if (lastWicket.isNotEmpty) ...[
          const SizedBox(height: 18),
          const _LiveSectionTitle('Last Wicket'),
          const SizedBox(height: 10),
          _LastWicketCard(text: lastWicket),
        ],
        if (finalOver.isNotEmpty) ...[
          const SizedBox(height: 18),
          _RecentOverHeader(over: _liveStr(finalOver.first['over'])),
          const SizedBox(height: 10),
          _RecentOverBubbles(balls: finalOver, fromLiveCenter: lcRecentFromBalls),
        ],
        if (comms.isNotEmpty) ...[
          const SizedBox(height: 18),
          const _LiveSectionTitle('Match Commentary'),
          const SizedBox(height: 10),
          _LiveCommentaryTimeline(items: comms.take(8).toList()),
        ],
        const SizedBox(height: 14),
        const _LiveFooter(isLive: false, finished: true),
      ],
    );
  }
}

class _ResultSummaryCard extends StatelessWidget {
  const _ResultSummaryCard({required this.summary, this.liveCenter});

  final Map<String, dynamic> summary;
  final Map<String, dynamic>? liveCenter;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final lc = liveCenter ?? const <String, dynamic>{};
    final resultText = _liveStr(
      lc['result'],
      fallback: _liveStr(
        summary['result'] ?? summary['status_text'] ?? summary['result_text'],
        fallback: 'Match completed',
      ),
    );
    final scoreLines = _resultScoreLines(summary);
    final venue = _venueLine(summary);
    final toss = _tossLine(summary);
    final date = formatMatchDateTime(
      summary['end_time'] ?? summary['start_time'] ?? summary['startTime'],
    );

    return PremiumCard(
      padding: const EdgeInsets.all(16),
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.emoji_events_rounded, color: c.cyan, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  resultText,
                  style: TextStyle(
                    color: c.text,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
          if (scoreLines.isNotEmpty) ...[
            const SizedBox(height: 14),
            for (final line in scoreLines) ...[
              _ScoreLineRow(team: line.$1, score: line.$2),
              const SizedBox(height: 6),
            ],
          ],
          if (toss.isNotEmpty || venue.isNotEmpty || date.isNotEmpty) ...[
            const SizedBox(height: 8),
            Divider(color: c.border.withValues(alpha: 0.6), height: 1),
            const SizedBox(height: 10),
            if (toss.isNotEmpty)
              _MetaLine(icon: Icons.casino_rounded, text: toss),
            if (venue.isNotEmpty)
              _MetaLine(icon: Icons.location_on_rounded, text: venue),
            if (date.isNotEmpty)
              _MetaLine(icon: Icons.calendar_today_rounded, text: date),
          ],
        ],
      ),
    );
  }
}

class _ScoreLineRow extends StatelessWidget {
  const _ScoreLineRow({required this.team, required this.score});

  final String team;
  final String score;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(
          child: Text(
            team,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: c.muted,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          score,
          style: TextStyle(
            color: c.text,
            fontWeight: FontWeight.w900,
            fontSize: 14,
          ),
        ),
      ],
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: c.muted, size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: c.muted,
                fontWeight: FontWeight.w700,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayerOfMatchCard extends StatelessWidget {
  const _PlayerOfMatchCard({required this.player});

  /// `null` when the API has not provided a player of the match yet.
  final Map<String, dynamic>? player;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    if (player == null) {
      return PremiumCard(
        padding: const EdgeInsets.all(16),
        radius: 18,
        child: Row(
          children: [
            Icon(Icons.workspace_premium_rounded, color: c.muted, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Player of the Match will be updated soon',
                style: TextStyle(
                  color: c.muted,
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final name = _liveStr(player!['name'] ?? player!['fullName'],
        fallback: 'Player of the Match');
    final detail = _liveStr(player!['team'] ?? player!['role']);
    return PremiumCard(
      padding: const EdgeInsets.all(14),
      radius: 18,
      child: Row(
        children: [
          _PlayerAvatar(row: player!, name: name),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.text,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail.isEmpty ? 'Player of the Match' : detail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.cyan,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.workspace_premium_rounded, color: c.cyan, size: 22),
        ],
      ),
    );
  }
}

class _TopPerformersCard extends StatelessWidget {
  const _TopPerformersCard({required this.performers});

  final List<_Performer> performers;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      radius: 18,
      child: Column(
        children: [
          for (var i = 0; i < performers.length; i++) ...[
            if (i != 0)
              Divider(color: c.border.withValues(alpha: 0.5), height: 1),
            _PerformerRow(performer: performers[i]),
          ],
        ],
      ),
    );
  }
}

class _PerformerRow extends StatelessWidget {
  const _PerformerRow({required this.performer});

  final _Performer performer;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: (performer.isBowler ? c.live : c.success)
                  .withValues(alpha: 0.16),
            ),
            child: Icon(
              performer.isBowler
                  ? Icons.sports_baseball_rounded
                  : Icons.sports_cricket_rounded,
              color: performer.isBowler ? c.live : c.success,
              size: 16,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              performer.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.text,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            performer.line,
            style: TextStyle(
              color: c.text,
              fontWeight: FontWeight.w900,
              fontSize: 13.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Upcoming view
// ---------------------------------------------------------------------------

class _LiveMatchUpcomingView extends StatelessWidget {
  const _LiveMatchUpcomingView({required this.summary});

  final Map<String, dynamic> summary;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final t1 = _teamName(summary['team1'] ?? summary['teamA']);
    final t2 = _teamName(summary['team2'] ?? summary['teamB']);
    final start = formatMatchDateTime(
      summary['start_time'] ?? summary['startTime'] ?? summary['date'],
    );
    final venue = _venueLine(summary);
    final statusText = _liveStr(summary['status_text'] ?? summary['statusText']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _LiveEmptyState(),
        if (t1.isNotEmpty && t2.isNotEmpty ||
            start.isNotEmpty ||
            venue.isNotEmpty ||
            statusText.isNotEmpty) ...[
          const SizedBox(height: 14),
          PremiumCard(
            padding: const EdgeInsets.all(16),
            radius: 18,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (t1.isNotEmpty && t2.isNotEmpty) ...[
                  Row(
                    children: [
                      Icon(Icons.sports_cricket_rounded, color: c.cyan, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '$t1 vs $t2',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: c.text,
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
                if (statusText.isNotEmpty)
                  _MetaLine(icon: Icons.info_outline_rounded, text: statusText),
                if (start.isNotEmpty)
                  _MetaLine(icon: Icons.schedule_rounded, text: start),
                if (venue.isNotEmpty)
                  _MetaLine(icon: Icons.location_on_rounded, text: venue),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Sections
// ---------------------------------------------------------------------------

class _LiveSectionTitle extends StatelessWidget {
  const _LiveSectionTitle(this.text, {this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        color: color ?? c.cyan,
        fontWeight: FontWeight.w900,
        fontSize: 13,
        letterSpacing: 0.6,
      ),
    );
  }
}

class _CurrentBattersCard extends StatelessWidget {
  const _CurrentBattersCard({required this.batters});

  final List<dynamic> batters;

  @override
  Widget build(BuildContext context) {
    return PremiumCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      radius: 18,
      child: _LiveStatTable(
        leadingHeader: 'Batter',
        headers: const ['R', 'B', '4s', '6s', 'SR'],
        rows: [
          for (final raw in batters)
            _battingRow(context, _liveMap(raw)),
        ],
      ),
    );
  }

  _LiveRow _battingRow(BuildContext context, Map<String, dynamic> row) {
    final striker = _truthyLive(row['is_striker']) ||
        _truthyLive(row['isStriker']);
    final runs = _liveStr(row['runs'], fallback: '0');
    return _LiveRow(
      leading: _PlayerCell(
        row: row,
        striker: striker,
      ),
      values: [
        striker ? '$runs*' : runs,
        _liveStr(row['balls'], fallback: '0'),
        _liveStr(row['fours'], fallback: '0'),
        _liveStr(row['sixes'], fallback: '0'),
        _liveStr(row['strike_rate'] ?? row['strikeRate'], fallback: '—'),
      ],
      boldFirstValue: true,
    );
  }
}

class _CurrentBowlerCard extends StatelessWidget {
  const _CurrentBowlerCard({required this.bowler});

  final Map<String, dynamic> bowler;

  @override
  Widget build(BuildContext context) {
    return PremiumCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      radius: 18,
      child: _LiveStatTable(
        leadingHeader: 'Bowler',
        headers: const ['O', 'M', 'R', 'W', 'Econ'],
        dividerBeforeValues: true,
        rows: [
          _LiveRow(
            leading: _PlayerCell(row: bowler, striker: false),
            values: [
              _liveStr(bowler['overs'], fallback: '0'),
              _liveStr(bowler['maidens'], fallback: '0'),
              _liveStr(bowler['runs'] ?? bowler['runs_conceded'],
                  fallback: '0'),
              _liveStr(bowler['wickets'], fallback: '0'),
              _liveStr(bowler['economy'], fallback: '—'),
            ],
          ),
        ],
      ),
    );
  }
}

class _PartnershipLastWicketRow extends StatelessWidget {
  const _PartnershipLastWicketRow({
    required this.partnership,
    required this.lastWicket,
  });

  final Map<String, dynamic> partnership;
  final String lastWicket;

  @override
  Widget build(BuildContext context) {
    final showPartnership = partnership.isNotEmpty;
    final showLastWicket = lastWicket.trim().isNotEmpty;
    if (!showPartnership && !showLastWicket) {
      return const SizedBox.shrink();
    }

    final cards = <Widget>[
      if (showPartnership) _PartnershipCard(partnership: partnership),
      if (showLastWicket) _LastWicketCard(text: lastWicket),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 380 || cards.length == 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                cards[i],
                if (i != cards.length - 1) const SizedBox(height: 12),
              ],
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: cards[0]),
            const SizedBox(width: 12),
            Expanded(child: cards[1]),
          ],
        );
      },
    );
  }
}

class _PartnershipCard extends StatelessWidget {
  const _PartnershipCard({required this.partnership});

  final Map<String, dynamic> partnership;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final runs = _liveStr(partnership['runs'], fallback: '—');
    final balls = _liveStr(partnership['balls']);
    final overs = _oversFromBalls(balls);
    return PremiumCard(
      padding: const EdgeInsets.all(14),
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.people_alt_rounded, color: c.cyan, size: 16),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'PARTNERSHIP',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.cyan,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _StatBlock(
                  value: runs,
                  hint: balls.isEmpty ? null : '($balls)',
                  label: 'Runs',
                ),
              ),
              Expanded(
                child: _StatBlock(
                  value: overs.isEmpty ? '—' : overs,
                  label: 'Overs',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatBlock extends StatelessWidget {
  const _StatBlock({required this.value, required this.label, this.hint});

  final String value;
  final String? hint;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: c.text,
                  fontWeight: FontWeight.w900,
                  fontSize: 22,
                  height: 1.0,
                ),
              ),
            ),
            if (hint != null && hint!.isNotEmpty) ...[
              const SizedBox(width: 4),
              Text(
                hint!,
                style: TextStyle(
                  color: c.muted,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: c.muted,
            fontWeight: FontWeight.w700,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

class _LastWicketCard extends StatelessWidget {
  const _LastWicketCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final parsed = _parseLastWicket(text);
    return PremiumCard(
      padding: const EdgeInsets.all(14),
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.cancel_rounded, color: c.live, size: 16),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'LAST WICKET',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.live,
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            parsed.title.isEmpty ? '—' : parsed.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: c.text,
              fontWeight: FontWeight.w900,
              fontSize: 14,
              height: 1.25,
            ),
          ),
          if (parsed.subtitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              parsed.subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.muted,
                fontWeight: FontWeight.w700,
                fontSize: 12,
                height: 1.25,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _RecentOverHeader extends StatelessWidget {
  const _RecentOverHeader({required this.over});

  final String over;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final label = _overOrdinal(over);
    return Row(
      children: [
        const Expanded(child: _LiveSectionTitle('Recent Over')),
        if (label.isNotEmpty)
          Text(
            label,
            style: TextStyle(
              color: c.muted,
              fontWeight: FontWeight.w800,
              fontSize: 11,
              letterSpacing: 0.4,
            ),
          ),
      ],
    );
  }
}

class _RecentOverBubbles extends StatelessWidget {
  const _RecentOverBubbles({required this.balls, this.fromLiveCenter = false});

  final List<Map<String, dynamic>> balls;
  final bool fromLiveCenter;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final ball in balls)
          _BallPill(row: ball, fromLiveCenter: fromLiveCenter),
      ],
    );
  }
}

class _BallPill extends StatelessWidget {
  const _BallPill({required this.row, this.fromLiveCenter = false});

  final Map<String, dynamic> row;
  final bool fromLiveCenter;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final over = _liveStr(row['over']);
    final ball = _liveStr(row['ball']);
    final label = over.isEmpty
        ? '—'
        : (ball.isEmpty ? over : '$over.$ball');
    final outcome =
        fromLiveCenter ? _ballOutcomeFromLiveCenter(row) : _ballOutcome(row);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 5, 5, 5),
      decoration: BoxDecoration(
        color: c.card2.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (label != '—') ...[
            Text(
              label,
              style: TextStyle(
                color: c.muted,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 8),
          ],
          _BallBubble(outcome: outcome),
        ],
      ),
    );
  }
}

class _BallBubble extends StatelessWidget {
  const _BallBubble({required this.outcome});

  final _BallOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final Color fill;
    switch (outcome.kind) {
      case _BallKind.wicket:
        fill = c.live;
        break;
      case _BallKind.boundary:
        fill = c.success;
        break;
      case _BallKind.runs:
        fill = c.cyan;
        break;
      case _BallKind.dot:
        fill = c.border;
        break;
    }
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, color: fill),
      child: outcome.kind == _BallKind.dot
          ? Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
            )
          : Text(
              outcome.label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
    );
  }
}

class _LiveCommentaryTimeline extends StatelessWidget {
  const _LiveCommentaryTimeline({required this.items});

  final List<dynamic> items;

  @override
  Widget build(BuildContext context) {
    return PremiumCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      radius: 18,
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++)
            _CommentaryRow(
              row: _liveMap(items[i]),
              isFirst: i == 0,
              isLast: i == items.length - 1,
            ),
        ],
      ),
    );
  }
}

class _CommentaryRow extends StatelessWidget {
  const _CommentaryRow({
    required this.row,
    required this.isFirst,
    required this.isLast,
  });

  final Map<String, dynamic> row;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final over = _liveStr(row['over']);
    final ball = _liveStr(row['ball']);
    final label =
        over.isEmpty ? '' : (ball.isEmpty ? over : '$over.$ball');
    final text = _liveStr(row['text'] ?? row['commentary']);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline rail (dot + connector line).
          SizedBox(
            width: 18,
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.card,
                    border: Border.all(color: c.cyan, width: 2),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: c.border,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 40,
            child: Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(
                label,
                style: TextStyle(
                  color: c.cyan,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 1, bottom: isLast ? 10 : 14),
              child: _CommentaryText(row: row, text: text),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentaryText extends StatelessWidget {
  const _CommentaryText({required this.row, required this.text});

  final Map<String, dynamic> row;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final event = _liveStr(row['event']).toLowerCase();
    final isWicket = _truthyLive(row['is_wicket']) || event == 'wicket';
    final isFour = _truthyLive(row['is_four']) || event == 'four';
    final isSix = _truthyLive(row['is_six']) || event == 'six';

    final base = TextStyle(
      color: c.text.withValues(alpha: 0.92),
      fontWeight: FontWeight.w600,
      fontSize: 13.5,
      height: 1.35,
    );

    // Highlight a leading keyword (FOUR!/SIX!/OUT!) in colour when present.
    String? keyword;
    Color? keywordColor;
    if (isWicket) {
      keyword = 'OUT!';
      keywordColor = c.live;
    } else if (isSix) {
      keyword = 'SIX!';
      keywordColor = c.success;
    } else if (isFour) {
      keyword = 'FOUR!';
      keywordColor = c.success;
    }

    if (keyword != null) {
      var rest = text;
      // Strip a duplicate leading keyword from the commentary text so we do
      // not show it twice.
      final lowered = rest.toLowerCase();
      final kw = keyword.toLowerCase();
      if (lowered.startsWith(kw)) {
        rest = rest.substring(keyword.length).trimLeft();
      } else if (lowered.startsWith(kw.replaceAll('!', ''))) {
        rest = rest.substring(keyword.length - 1).trimLeft();
      }
      return RichText(
        text: TextSpan(
          style: base,
          children: [
            TextSpan(
              text: '$keyword ',
              style: base.copyWith(
                color: keywordColor,
                fontWeight: FontWeight.w900,
              ),
            ),
            TextSpan(text: rest),
          ],
        ),
      );
    }

    return Text(text.isEmpty ? '—' : text, style: base);
  }
}

class _LiveFooter extends StatelessWidget {
  const _LiveFooter({required this.isLive, this.finished = false});

  final bool isLive;
  final bool finished;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Row(
      children: [
        Icon(
          finished ? Icons.check_circle_rounded : Icons.schedule_rounded,
          color: finished ? c.success : c.muted,
          size: 14,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            finished ? 'Match completed' : 'Updated just now',
            style: TextStyle(
              color: c.muted,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
        if (isLive && !finished) ...[
          Icon(Icons.sensors_rounded, color: c.cyan, size: 16),
          const SizedBox(width: 6),
          Text(
            'Live',
            style: TextStyle(
              color: c.cyan,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.success,
            ),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared building blocks
// ---------------------------------------------------------------------------

class _LiveRow {
  const _LiveRow({
    required this.leading,
    required this.values,
    this.boldFirstValue = false,
  });

  final Widget leading;
  final List<String> values;
  final bool boldFirstValue;
}

class _LiveStatTable extends StatelessWidget {
  const _LiveStatTable({
    required this.leadingHeader,
    required this.headers,
    required this.rows,
    this.dividerBeforeValues = false,
  });

  final String leadingHeader;
  final List<String> headers;
  final List<_LiveRow> rows;
  final bool dividerBeforeValues;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Drop the trailing column (SR/Econ) on very tight widths so values
        // never clip horizontally.
        final dropLast = constraints.maxWidth < 320 && headers.length > 4;
        final visibleHeaders =
            dropLast ? headers.take(headers.length - 1).toList() : headers;
        final colWidth = constraints.maxWidth < 360 ? 38.0 : 44.0;

        Widget numericHeader(String h) => SizedBox(
              width: colWidth,
              child: Text(
                h,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: c.muted,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            );

        Widget numericValue(String v, bool bold) => SizedBox(
              width: colWidth,
              child: Text(
                v,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: c.text,
                  fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            );

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      leadingHeader,
                      style: TextStyle(
                        color: c.muted,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  if (dividerBeforeValues) const SizedBox(width: 13),
                  for (final h in visibleHeaders) numericHeader(h),
                ],
              ),
            ),
            Divider(color: c.border.withValues(alpha: 0.6), height: 1),
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Row(
                  children: [
                    Expanded(child: row.leading),
                    if (dividerBeforeValues)
                      Container(
                        width: 1,
                        height: 26,
                        margin: const EdgeInsets.only(right: 12),
                        color: c.border.withValues(alpha: 0.6),
                      ),
                    for (var i = 0; i < visibleHeaders.length; i++)
                      numericValue(
                        i < row.values.length ? row.values[i] : '—',
                        row.boldFirstValue && i == 0,
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _PlayerCell extends StatelessWidget {
  const _PlayerCell({required this.row, required this.striker});

  final Map<String, dynamic> row;
  final bool striker;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final name = _liveStr(
      row['name'] ?? row['player_name'] ?? row['fullName'],
      fallback: 'Player',
    );
    return Row(
      children: [
        SizedBox(
          width: 14,
          child: striker
              ? Icon(Icons.play_arrow_rounded, color: c.cyan, size: 14)
              : null,
        ),
        _PlayerAvatar(row: row, name: name),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: c.text,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }
}

class _PlayerAvatar extends StatelessWidget {
  const _PlayerAvatar({required this.row, required this.name});

  final Map<String, dynamic> row;
  final String name;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final image = resolvePlayerImageUrl(row);
    if (image == null) {
      return Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [c.cyan.withValues(alpha: 0.30), c.card2],
          ),
          border: Border.all(color: c.border),
        ),
        child: Text(
          _initials(name),
          style: TextStyle(
            color: c.text,
            fontWeight: FontWeight.w900,
            fontSize: 12,
          ),
        ),
      );
    }
    return CircleAvatar(
      radius: 17,
      backgroundColor: c.card2,
      backgroundImage: NetworkImage(
        image,
        webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
      ),
    );
  }
}

class _LiveEmptyState extends StatelessWidget {
  const _LiveEmptyState();

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      padding: const EdgeInsets.all(22),
      child: Row(
        children: [
          Icon(Icons.sensors_rounded, color: c.cyan),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Live data will appear once the match starts.',
              style: TextStyle(
                color: c.muted,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Outcome model + helpers
// ---------------------------------------------------------------------------

enum _BallKind { wicket, boundary, runs, dot }

class _BallOutcome {
  const _BallOutcome(this.kind, this.label);

  final _BallKind kind;
  final String label;
}

_BallOutcome _ballOutcome(Map<String, dynamic> row) {
  if (_truthyLive(row['is_wicket'])) return const _BallOutcome(_BallKind.wicket, 'W');
  if (_truthyLive(row['is_six'])) return const _BallOutcome(_BallKind.boundary, '6');
  if (_truthyLive(row['is_four'])) return const _BallOutcome(_BallKind.boundary, '4');
  final runs = _liveStr(row['runs'], fallback: '0');
  if (runs.isEmpty || runs == '0') {
    return const _BallOutcome(_BallKind.dot, '');
  }
  return _BallOutcome(_BallKind.runs, runs);
}

/// Builds a ball outcome from the merged live-center ball shape
/// (`{ over, value, type }`).
_BallOutcome _ballOutcomeFromLiveCenter(Map<String, dynamic> row) {
  final type = _liveStr(row['type']).toLowerCase();
  final value = _liveStr(row['value']);
  switch (type) {
    case 'wicket':
      return const _BallOutcome(_BallKind.wicket, 'W');
    case 'six':
      return const _BallOutcome(_BallKind.boundary, '6');
    case 'four':
      return const _BallOutcome(_BallKind.boundary, '4');
    case 'dot':
      return const _BallOutcome(_BallKind.dot, '');
    default:
      if (value.isEmpty || value == '0') {
        return const _BallOutcome(_BallKind.dot, '');
      }
      return _BallOutcome(_BallKind.runs, value);
  }
}

({String title, String subtitle}) _parseLastWicket(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return (title: '', subtitle: '');
  final dismissal = RegExp(
    r'(\bc & b\b|\bc\b|\bb\b|\blbw\b|\brun out\b|\bst\b|\bretired\b)',
    caseSensitive: false,
  ).firstMatch(s);
  if (dismissal == null) return (title: s, subtitle: '');
  var name = s.substring(0, dismissal.start).trim();
  var rest = s.substring(dismissal.start).trim();
  final runsBalls = RegExp(r'(\d+)\s*\(\s*\d+\s*\)').firstMatch(s);
  var runsToken = '';
  if (runsBalls != null) {
    runsToken = runsBalls.group(0)!.replaceAll(' ', '');
    rest = rest.replaceAll(RegExp(r'\d+\s*\(\s*\d+\s*\)'), '').trim();
  }
  final title = runsToken.isEmpty ? name : '$name $runsToken';
  return (
    title: title.isEmpty ? s : title,
    subtitle: rest,
  );
}

String _oversFromBalls(String balls) {
  final n = int.tryParse(balls);
  if (n == null || n <= 0) return '';
  return '${n ~/ 6}.${n % 6}';
}

String _overOrdinal(String over) {
  final n = int.tryParse(over);
  if (n == null) return '';
  final suffix = (n % 100 >= 11 && n % 100 <= 13)
      ? 'th'
      : switch (n % 10) {
          1 => 'st',
          2 => 'nd',
          3 => 'rd',
          _ => 'th',
        };
  return '$n$suffix OVER';
}

String _initials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) {
    return parts.first.substring(0, 1).toUpperCase();
  }
  return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
      .toUpperCase();
}

// ---------------------------------------------------------------------------
// Row validation — never render fake / empty / all-zero rows.
// ---------------------------------------------------------------------------

/// Keep only batters that have a real name. This guards against the
/// "Player 0 0 0 0 0" placeholder row (whose name is the literal fallback
/// "Player") while still showing a genuine new batter who is yet to score.
List<dynamic> _validBatters(List<dynamic> batters) {
  return batters.where((raw) => _hasRealName(_liveMap(raw))).toList(
        growable: false,
      );
}

/// Returns the bowler map only when it is a valid, real-named bowler,
/// otherwise an empty map so the section is hidden.
Map<String, dynamic> _validBowler(Map<String, dynamic> bowler) {
  if (bowler.isEmpty) return const <String, dynamic>{};
  if (!_hasRealName(bowler)) return const <String, dynamic>{};
  return bowler;
}

bool _hasRealName(Map<String, dynamic> row) {
  final name = _liveStr(row['name'] ?? row['player_name'] ?? row['fullName']);
  if (name.isEmpty) return false;
  return name.toLowerCase() != 'player';
}

double _numLive(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString().trim() ?? '') ?? 0;
}

// ---------------------------------------------------------------------------
// Completed-match data mapping helpers.
// ---------------------------------------------------------------------------

/// Resolves the player of the match from the various shapes the backend may
/// send. Returns `null` (not a fake row) when nothing is available.
Map<String, dynamic>? _resolvePlayerOfMatch(Map<String, dynamic> summary) {
  final pom = summary['player_of_match'] ?? summary['playerOfMatch'];
  if (pom is Map<String, dynamic>) {
    final name = _liveStr(pom['name'] ?? pom['fullName']);
    if (name.isNotEmpty) return pom;
  }
  if (pom is List && pom.isNotEmpty) {
    final first = _liveMap(pom.first);
    if (_liveStr(first['name'] ?? first['fullName']).isNotEmpty) return first;
  }
  final name = _liveStr(summary['man_of_match'] ?? summary['manOfMatch']);
  if (name.isNotEmpty) return <String, dynamic>{'name': name};
  return null;
}

/// Builds team score lines such as `SL 303/7 (50.0 ov)` from the match detail
/// team innings.
List<(String, String)> _resultScoreLines(Map<String, dynamic> summary) {
  final lines = <(String, String)>[];
  for (final key in const ['team1', 'team2']) {
    final team = _liveMap(summary[key]);
    if (team.isEmpty) continue;
    final name = _liveStr(
      team['short_name'] ?? team['shortName'] ?? team['name'],
    );
    final innings = _liveList(team['innings']);
    if (innings.isEmpty) continue;
    final parts = <String>[];
    for (final raw in innings) {
      final inn = _liveMap(raw);
      final runs = _liveStr(inn['runs'], fallback: '0');
      final wickets = _liveStr(inn['wickets'], fallback: '0');
      final oversRaw = _liveStr(inn['overs']);
      final overs = oversRaw.isEmpty ? '' : normalizeOversText(oversRaw);
      final declared = _truthyLive(inn['declared']) ? 'd' : '';
      final scoreText = '$runs/$wickets$declared';
      parts.add(overs.isEmpty ? scoreText : '$scoreText ($overs ov)');
    }
    if (parts.isEmpty) continue;
    lines.add((name.isEmpty ? 'Team' : name, parts.join(' & ')));
  }
  return lines;
}

/// Pulls top performers (top batters + top bowlers) from the full scorecard,
/// filtering out zero-only rows.
List<_Performer> _topPerformers(Map<String, dynamic> scorecard) {
  final innings = _liveList(scorecard['innings']);
  final batters = <_Performer>[];
  final bowlers = <_Performer>[];

  for (final raw in innings) {
    final inn = _liveMap(raw);
    for (final b in _liveList(inn['batting'] ?? inn['batters'] ?? inn['batsmen'])) {
      final row = _liveMap(b);
      if (!_hasRealName(row)) continue;
      final runs = _numLive(row['runs']);
      final balls = _numLive(row['balls']);
      if (runs <= 0 && balls <= 0) continue;
      final name = _liveStr(row['name'] ?? row['player_name']);
      final ballsText = balls > 0 ? ' (${balls.toStringAsFixed(0)})' : '';
      batters.add(_Performer(
        name: name,
        line: '${runs.toStringAsFixed(0)}$ballsText',
        sortValue: runs,
        isBowler: false,
      ));
    }
    for (final b in _liveList(inn['bowling'] ?? inn['bowlers'])) {
      final row = _liveMap(b);
      if (!_hasRealName(row)) continue;
      final wickets = _numLive(row['wickets']);
      final overs = _numLive(row['overs']);
      if (wickets <= 0 && overs <= 0) continue;
      final name = _liveStr(row['name'] ?? row['player_name'] ?? row['bowler']);
      final oversText = _liveStr(row['overs'], fallback: '0');
      final maidens = _liveStr(row['maidens'], fallback: '0');
      final runsText =
          _liveStr(row['runs'] ?? row['runs_conceded'], fallback: '0');
      final wktText = wickets.toStringAsFixed(0);
      bowlers.add(_Performer(
        name: name,
        line: '$oversText-$maidens-$runsText-$wktText',
        sortValue: wickets * 100 + 1,
        isBowler: true,
      ));
    }
  }

  batters.sort((a, b) => b.sortValue.compareTo(a.sortValue));
  bowlers.sort((a, b) => b.sortValue.compareTo(a.sortValue));

  return [
    ...batters.take(3),
    ...bowlers.take(2),
  ];
}

/// Resolves the last/most-recent wicket text from the miniscore, falling back
/// to the final innings fall-of-wickets in the scorecard.
String _resolveLastWicket(
  Map<String, dynamic> summary,
  Map<String, dynamic> scorecard,
) {
  final fromSummary = _liveStr(summary['last_wicket']);
  if (fromSummary.isNotEmpty) return fromSummary;

  final innings = _liveList(scorecard['innings']);
  for (final raw in innings.reversed) {
    final inn = _liveMap(raw);
    final fows = _liveList(inn['fall_of_wickets'] ?? inn['fow']);
    if (fows.isEmpty) continue;
    final last = _liveMap(fows.last);
    final player = _liveStr(last['player'] ?? last['batName']);
    final runs = _liveStr(last['runs']);
    final overs = _liveStr(last['overs']);
    if (player.isEmpty) continue;
    final scorePart = runs.isEmpty ? '' : ' $runs';
    final oversPart = overs.isEmpty ? '' : ' ($overs ov)';
    return '$player$scorePart$oversPart';
  }
  return '';
}

String _teamName(dynamic team) {
  final map = _liveMap(team);
  if (map.isNotEmpty) {
    return _liveStr(map['name'] ?? map['short_name'] ?? map['shortName']);
  }
  return _liveStr(team);
}

String _venueLine(Map<String, dynamic> summary) {
  final venue = summary['venue'] ?? summary['ground'] ?? summary['location'];
  if (venue is Map<String, dynamic>) {
    final parts = <String>[];
    final name = _liveStr(venue['name'] ?? venue['stadium']);
    if (name.isNotEmpty) parts.add(name);
    final city = _liveStr(venue['city']);
    if (city.isNotEmpty && !parts.contains(city)) parts.add(city);
    return parts.join(', ');
  }
  return _liveStr(venue);
}

String _tossLine(Map<String, dynamic> summary) {
  final toss = _liveMap(summary['toss']);
  if (toss.isEmpty) return '';
  final winner = _liveStr(toss['winner'] ?? toss['tossWinnerName']);
  if (winner.isEmpty) return '';
  final decision = _liveStr(toss['decision']);
  if (decision.isEmpty) return '$winner won the toss';
  return '$winner won the toss and chose to ${decision.toLowerCase()}';
}

class _Performer {
  const _Performer({
    required this.name,
    required this.line,
    required this.sortValue,
    required this.isBowler,
  });

  final String name;
  final String line;
  final double sortValue;
  final bool isBowler;
}

bool _isLiveStatus(String status) {
  final s = status.toLowerCase();
  return s == 'live' ||
      s == 'inprogress' ||
      s == 'in_progress' ||
      s == 'progress';
}

// ---------------------------------------------------------------------------
// Local parsing helpers (kept private so the tab is self-contained).
// ---------------------------------------------------------------------------

List<dynamic> _liveList(dynamic value) => apiList(value);

Map<String, dynamic> _liveMap(dynamic value) =>
    value is Map<String, dynamic>
        ? value
        : value is Map
            ? Map<String, dynamic>.from(value)
            : const <String, dynamic>{};

dynamic _liveValue(Map<String, dynamic> map, String key,
    [String? altKey, String? thirdKey]) {
  if (map.containsKey(key)) return map[key];
  if (altKey != null && map.containsKey(altKey)) return map[altKey];
  if (thirdKey != null && map.containsKey(thirdKey)) return map[thirdKey];
  return null;
}

Map<String, dynamic> _mergeLiveCenterFallback({
  required Map<String, dynamic> primary,
  required Map<String, dynamic> fallback,
}) {
  if (fallback.isEmpty) return primary;
  if (primary.isEmpty) return fallback;
  final merged = Map<String, dynamic>.from(primary);
  for (final entry in fallback.entries) {
    final current = merged[entry.key];
    final shouldFill = current == null ||
        (current is String && current.trim().isEmpty) ||
        (current is List && current.isEmpty) ||
        (current is Map && current.isEmpty);
    if (shouldFill) merged[entry.key] = entry.value;
  }
  return merged;
}

String _liveStr(dynamic value, {String fallback = ''}) {
  if (value == null) return fallback;
  final text = value.toString().trim();
  return text.isEmpty || text == 'null' ? fallback : text;
}

bool _truthyLive(dynamic value) =>
    value == true ||
    value == 1 ||
    value == '1' ||
    value.toString().toLowerCase() == 'true';
