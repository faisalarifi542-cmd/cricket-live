import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';

import 'package:cricpro_flutter/app_theme.dart';
import 'package:cricpro_flutter/api_models.dart';
import 'package:cricpro_flutter/components.dart';
import 'package:cricpro_flutter/models/cricket_match.dart';
import 'package:cricpro_flutter/screens/match_details/widgets/match_details_ui.dart';
import 'package:cricpro_flutter/utils/score_presentation.dart';
import 'package:cricpro_flutter/widgets/team_score_view.dart';

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
    this.fullCommentary,
    this.onViewMoreCommentary,
  });

  /// Tap on the Live tab's "View More Commentary" CTA → switch Match Details to
  /// the full Commentary tab. Null disables the CTA (still rendered).
  final VoidCallback? onViewMoreCommentary;

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

  /// Fresher full-commentary payload (`/match/:id/full-commentary`, accumulated
  /// through CommentaryCache). When it carries items they are PREFERRED for the
  /// Live-tab preview because the merged live-center commentary lags 1–2 balls.
  final Map<String, dynamic>? fullCommentary;

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
    final effectiveLc =
        _mergeLiveCenterFallback(primary: lc, fallback: embeddedLc);

    // Determine state primarily from the live-center, then the summary.
    final lcState =
        _liveStr(_liveValue(effectiveLc, 'match_state', 'matchState'));
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

    // Commentary: PREFER the fresher accumulated full-commentary feed (only its
    // ball deliveries), then live-center commentary, then the raw list. The
    // full feed updates 1–2 balls ahead of the merged live-center.
    List<dynamic> comms = _liveList(_liveValue(
      effectiveLc,
      'commentary',
      'commentaryList',
      'comments',
    ));
    final fullItems = _liveList(fullCommentary?['items'] ??
        fullCommentary?['data'] ??
        fullCommentary?['commentary']);
    final fullBalls = fullItems
        .map(_liveMap)
        .where((row) =>
            _truthyLive(row['isBall']) ||
            _truthyLive(row['is_ball']) ||
            _liveStr(row['over']).isNotEmpty)
        .map(_normalizeFullComm)
        .toList(growable: false);
    if (fullBalls.isNotEmpty) {
      comms = fullBalls;
    }
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
          onViewMoreCommentary: onViewMoreCommentary,
        );
      case _MatchState.upcoming:
        return _LiveMatchUpcomingView(summary: summaryData);
      case _MatchState.live:
        return _LiveMatchActiveView(
          summary: summaryData,
          liveCenter: effectiveLc,
          comms: comms,
          onViewMoreCommentary: onViewMoreCommentary,
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
    this.onViewMoreCommentary,
  });

  final Map<String, dynamic> summary;
  final Map<String, dynamic> liveCenter;
  final List<dynamic> comms;
  final VoidCallback? onViewMoreCommentary;

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

    final recentOverLabel =
        recentBalls.isNotEmpty ? _liveStr(recentBalls.first['over']) : '';
    final lcRecentFromBalls = lcBalls.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (batters.isNotEmpty) ...[
          _CurrentBattersCard(
            batters: batters,
            inningsLine: _battingInningsLine(summary, lc),
          ),
          const SizedBox(height: 10),
        ],
        if (bowler.isNotEmpty || partnership.isNotEmpty) ...[
          _LiveTwoCol(
            left: bowler.isNotEmpty ? _CurrentBowlerCard(bowler: bowler) : null,
            right: partnership.isNotEmpty
                ? _PartnershipCard(partnership: partnership, batters: batters)
                : null,
          ),
          const SizedBox(height: 10),
        ],
        if (lastWicket.isNotEmpty || recentBalls.isNotEmpty) ...[
          _LiveTwoCol(
            left: lastWicket.isNotEmpty
                ? _LastWicketCard(text: lastWicket)
                : null,
            right: recentBalls.isNotEmpty
                ? _RecentOverCard(
                    balls: recentBalls,
                    over: recentOverLabel,
                    runs: _recentOverRuns(recentBalls, lcRecentFromBalls),
                    fromLiveCenter: lcRecentFromBalls,
                  )
                : null,
          ),
          const SizedBox(height: 10),
        ],
        if (comms.isNotEmpty)
          _LiveCommentaryTimeline(
            items: comms.take(6).toList(),
            onViewMore: onViewMoreCommentary,
          ),
      ],
    );
  }
}

/// Responsive two-column row: side-by-side on wide widths, stacked on narrow.
class _LiveTwoCol extends StatelessWidget {
  const _LiveTwoCol({this.left, this.right});

  final Widget? left;
  final Widget? right;

  @override
  Widget build(BuildContext context) {
    final cards = <Widget>[if (left != null) left!, if (right != null) right!];
    if (cards.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        // Two-column grid whenever there's room for it. A 360px device has
        // ~328px of content width (16px padding each side), so the breakpoint
        // must sit comfortably below that or the cards wrongly stack.
        if (constraints.maxWidth < 300 || cards.length == 1) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                cards[i],
                if (i != cards.length - 1) const SizedBox(height: 10),
              ],
            ],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: cards[0]),
              const SizedBox(width: 10),
              Expanded(child: cards[1]),
            ],
          ),
        );
      },
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
    this.onViewMoreCommentary,
  });

  final Map<String, dynamic> summary;
  final Map<String, dynamic> liveCenter;
  final List<dynamic> comms;
  final Map<String, dynamic> scorecard;
  final VoidCallback? onViewMoreCommentary;

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
          _RecentOverBubbles(
              balls: finalOver, fromLiveCenter: lcRecentFromBalls),
        ],
        if (comms.isNotEmpty) ...[
          const SizedBox(height: 18),
          const _LiveSectionTitle('Match Commentary'),
          const SizedBox(height: 10),
          _LiveCommentaryTimeline(
            items: comms.take(8).toList(),
            onViewMore: onViewMoreCommentary,
          ),
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
            for (final team in scoreLines) ...[
              _ResultScoreRow(team: team),
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

/// One team's result score, rendered through the shared [TeamScoreView] so the
/// Live result view and the Score tab share a single score formatter (no more
/// hand-built `runs/wickets (overs ov)` strings that could drift on declared
/// innings, the `ov` unit, or the multi-innings `&` join).
class _ResultScoreRow extends StatelessWidget {
  const _ResultScoreRow({required this.team});

  final _ResultTeamScore team;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final pres = TeamScorePresentation(team.innings);
    final multi = pres.isMultiInnings;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 52,
          child: Text(
            team.name,
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
        Expanded(
          child: TeamScoreView(
            innings: team.innings,
            mainSize: multi ? 17 : 22,
            oversSize: 13,
            mode: multi
                ? ScoreDisplayMode.matchDetailsMultiInnings
                : ScoreDisplayMode.matchDetailsLimitedOvers,
            align: CrossAxisAlignment.start,
            // A finished match never stars an innings.
            currentInningsIndex: kNoCurrentInnings,
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
    final statusText =
        _liveStr(summary['status_text'] ?? summary['statusText']);

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
                      Icon(Icons.sports_cricket_rounded,
                          color: c.cyan, size: 18),
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
  const _LiveSectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        color: c.cyan,
        fontWeight: FontWeight.w900,
        fontSize: 13,
        letterSpacing: 0.6,
      ),
    );
  }
}

/// In-card header row (cyan icon + title) used by the live dashboard panels.
class _LiveHeader extends StatelessWidget {
  const _LiveHeader(this.icon, this.title, {this.color, this.trailing, this.asset});

  final IconData icon;
  final String title;
  final Color? color;
  final Widget? trailing;
  final String? asset;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final col = color ?? c.cyan;
    return Row(
      children: [
        asset != null
            ? MDIcon(asset!, fallback: icon, size: 16, tint: color)
            : Icon(icon, color: col, size: 15),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: col,
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _CurrentBattersCard extends StatelessWidget {
  const _CurrentBattersCard({required this.batters, this.inningsLine});

  final List<dynamic> batters;
  final String? inningsLine;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return MDGlassPanel(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _LiveStatTable(
            leadingHeader: 'Batter',
            headerIcon: Icons.sports_cricket_rounded,
            headerTitle: 'Current Batters',
            headerAsset: MDAsset.icCurrentBatters,
            headers: const ['R', 'B', '4s', '6s', 'SR'],
            rows: [
              for (final raw in batters) _battingRow(context, _liveMap(raw)),
            ],
          ),
          if (inningsLine != null && inningsLine!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Divider(color: c.cyan.withValues(alpha: .14), height: 1),
            const SizedBox(height: 7),
            Text(
              inningsLine!,
              style: TextStyle(
                color: c.cyan,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  _LiveRow _battingRow(BuildContext context, Map<String, dynamic> row) {
    final striker =
        _truthyLive(row['is_striker']) || _truthyLive(row['isStriker']);
    final runs = _liveStr(row['runs'], fallback: '0');
    return _LiveRow(
      leading: _PlayerCell(row: row, striker: striker),
      values: [
        striker ? '$runs*' : runs,
        _liveStr(row['balls'], fallback: '0'),
        _liveStr(row['fours'], fallback: '0'),
        _liveStr(row['sixes'], fallback: '0'),
        formatStatNumber(
            _liveStr(row['strike_rate'] ?? row['strikeRate'], fallback: '—')),
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
    final c = context.cric;
    final name = _liveStr(
        bowler['name'] ?? bowler['player_name'] ?? bowler['fullName'],
        fallback: 'Bowler');
    final style = _liveStr(bowler['bowling_style'] ??
        bowler['bowlingStyle'] ??
        bowler['style'] ??
        bowler['role']);
    final o = _liveStr(bowler['overs'], fallback: '0');
    final m = _liveStr(bowler['maidens'], fallback: '0');
    final r =
        _liveStr(bowler['runs'] ?? bowler['runs_conceded'], fallback: '0');
    final w = _liveStr(bowler['wickets'], fallback: '0');
    var econ = _liveStr(bowler['economy']);
    if (econ.isEmpty) {
      final oversNum = double.tryParse(o) ?? 0;
      final runsNum = double.tryParse(r) ?? 0;
      final whole = oversNum.floor();
      final balls = ((oversNum - whole) * 10).round();
      final trueOvers = whole + balls / 6.0;
      if (trueOvers > 0) econ = (runsNum / trueOvers).toStringAsFixed(2);
    }
    return MDGlassPanel(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _LiveHeader(Icons.sports_baseball_outlined, 'Current Bowler',
              asset: MDAsset.icCurrentBowler),
          const SizedBox(height: 10),
          Row(
            children: [
              _PlayerAvatar(row: bowler, name: name),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(formatCompactPlayerName(name),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: c.text,
                            fontWeight: FontWeight.w800,
                            fontSize: 13)),
                    if (style.isNotEmpty)
                      Text(style,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: c.muted,
                              fontWeight: FontWeight.w600,
                              fontSize: 10.5)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Divider(color: c.cyan.withValues(alpha: .12), height: 1),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _bowlStat(context, 'O', o),
              _bowlStat(context, 'M', m),
              _bowlStat(context, 'R', r),
              _bowlStat(context, 'W', w, accent: true),
              _bowlStat(context, 'ECO', econ.isEmpty ? '—' : formatStatNumber(econ)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bowlStat(BuildContext context, String label, String value,
      {bool accent = false}) {
    final c = context.cric;
    return Expanded(
      child: Column(
        children: [
          Text(label,
              style: TextStyle(
                  color: c.muted, fontWeight: FontWeight.w700, fontSize: 9.5)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value,
                style: TextStyle(
                    color: accent ? c.cyan : c.text,
                    fontWeight: FontWeight.w900,
                    fontSize: 15)),
          ),
        ],
      ),
    );
  }
}

class _PartnershipCard extends StatelessWidget {
  const _PartnershipCard({required this.partnership, required this.batters});

  final Map<String, dynamic> partnership;
  final List<dynamic> batters;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final runs = _liveStr(partnership['runs'], fallback: '—');
    final balls = _liveStr(partnership['balls']);
    final ballsNum = int.tryParse(balls) ?? 0;
    final runsNum = int.tryParse(runs) ?? 0;
    final rr = ballsNum > 0 ? (runsNum * 6 / ballsNum).toStringAsFixed(2) : '';
    final contributors = batters.map(_liveMap).take(2).toList();
    return MDGlassPanel(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _LiveHeader(Icons.people_alt_rounded, 'Partnership',
              asset: MDAsset.icPartnership),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(runs,
                  style: TextStyle(
                      color: c.text,
                      fontWeight: FontWeight.w900,
                      fontSize: 22,
                      height: 1)),
              if (balls.isNotEmpty) ...[
                const SizedBox(width: 5),
                Text('($balls)',
                    style: TextStyle(
                        color: c.muted,
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5)),
              ],
            ],
          ),
          const SizedBox(height: 8),
          for (final b in contributors)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: _contribRow(context, b),
            ),
          if (rr.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text('Run Rate: $rr',
                style: TextStyle(
                    color: c.cyan,
                    fontWeight: FontWeight.w800,
                    fontSize: 11.5)),
          ],
        ],
      ),
    );
  }

  Widget _contribRow(BuildContext context, Map<String, dynamic> b) {
    final c = context.cric;
    final name =
        _liveStr(b['name'] ?? b['player_name'] ?? b['fullName'], fallback: '');
    if (name.isEmpty) return const SizedBox.shrink();
    final runs = _liveStr(b['runs'], fallback: '0');
    final balls = _liveStr(b['balls']);
    return Row(
      children: [
        Expanded(
          child: Text(formatCompactPlayerName(name, maxLen: 13),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: c.text.withValues(alpha: .9),
                  fontWeight: FontWeight.w700,
                  fontSize: 11.5)),
        ),
        const SizedBox(width: 6),
        Text(balls.isEmpty ? runs : '$runs ($balls)',
            style: TextStyle(
                color: c.text, fontWeight: FontWeight.w900, fontSize: 11.5)),
      ],
    );
  }
}

/// Compact Recent Over panel: header + over label, ball bubbles, runs footer.
class _RecentOverCard extends StatelessWidget {
  const _RecentOverCard({
    required this.balls,
    required this.over,
    required this.runs,
    this.fromLiveCenter = false,
  });

  final List<Map<String, dynamic>> balls;
  final String over;
  final int runs;
  final bool fromLiveCenter;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return MDGlassPanel(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LiveHeader(
            Icons.timelapse_rounded,
            'Recent Over',
            asset: MDAsset.icRecentOver,
            trailing: over.isEmpty
                ? null
                : Text('$over ov',
                    style: TextStyle(
                        color: c.muted,
                        fontWeight: FontWeight.w800,
                        fontSize: 10.5)),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 4,
            runSpacing: 5,
            children: [
              for (final b in balls)
                _BallBubble(
                  size: 20,
                  outcome: fromLiveCenter
                      ? _ballOutcomeFromLiveCenter(b)
                      : _ballOutcome(b),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text('$runs ${runs == 1 ? 'run' : 'runs'} in this over',
              style: TextStyle(
                  color: c.muted, fontWeight: FontWeight.w700, fontSize: 11)),
        ],
      ),
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
    return MDGlassPanel(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LiveHeader(Icons.dangerous_outlined, 'Last Wicket',
              color: c.live, asset: MDAsset.icLastWicket),
          const SizedBox(height: 9),
          Text(
            parsed.title.isEmpty ? '—' : parsed.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: c.text,
              fontWeight: FontWeight.w900,
              fontSize: 13,
              height: 1.2,
            ),
          ),
          if (parsed.subtitle.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              parsed.subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.muted,
                fontWeight: FontWeight.w700,
                fontSize: 11,
                height: 1.2,
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
    final cleaned = formatOverLabel(over, ball);
    final label = cleaned.isEmpty ? '—' : cleaned;
    final outcome =
        fromLiveCenter ? _ballOutcomeFromLiveCenter(row) : _ballOutcome(row);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 5, 5, 5),
      decoration: BoxDecoration(
        color: c.isDark ? c.card2.withValues(alpha: 0.6) : c.card2,
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
  const _BallBubble({required this.outcome, this.size = 28});

  final _BallOutcome outcome;
  final double size;

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
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(shape: BoxShape.circle, color: fill),
      child: outcome.kind == _BallKind.dot
          ? Container(
              width: size * 0.21,
              height: size * 0.21,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white,
              ),
            )
          : Text(
              outcome.label,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: size * 0.43,
              ),
            ),
    );
  }
}

class _LiveCommentaryTimeline extends StatelessWidget {
  const _LiveCommentaryTimeline({required this.items, this.onViewMore});

  final List<dynamic> items;

  /// Tap the CTA → switch Match Details to the full Commentary tab.
  final VoidCallback? onViewMore;

  @override
  Widget build(BuildContext context) {
    return MDGlassPanel(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _LiveHeader(
              Icons.chat_bubble_outline_rounded, 'Live Commentary',
              asset: MDAsset.tabCommentary),
          const SizedBox(height: 12),
          for (var i = 0; i < items.length; i++)
            _CommentaryRow(
              row: _liveMap(items[i]),
              isLast: i == items.length - 1,
            ),
          _ViewMoreCommentaryCta(onTap: onViewMore),
        ],
      ),
    );
  }
}

/// Real call-to-action button (not a flat text link) that opens the full
/// Commentary tab. Cyan glass in dark mode, soft tint in light mode.
class _ViewMoreCommentaryCta extends StatelessWidget {
  const _ViewMoreCommentaryCta({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 6),
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: c.isDark
              ? LinearGradient(
                  colors: [
                    c.cyan.withValues(alpha: .20),
                    c.cyan.withValues(alpha: .07),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: c.isDark ? null : c.cyan.withValues(alpha: .08),
          border: Border.all(color: c.cyan.withValues(alpha: .5)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'View More Commentary',
              style: TextStyle(
                color: c.cyan,
                fontWeight: FontWeight.w800,
                fontSize: 13.5,
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.arrow_forward_rounded, color: c.cyan, size: 18),
          ],
        ),
      ),
    );
  }
}

class _CommentaryRow extends StatelessWidget {
  const _CommentaryRow({
    required this.row,
    required this.isLast,
  });

  final Map<String, dynamic> row;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final over = _liveStr(row['over']);
    final ball = _liveStr(row['ball']);
    final label = formatOverLabel(over, ball);
    final text = _liveStr(row['text'] ?? row['commentary']);
    final ev = _liveEvent(row, c);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline rail (event-coloured dot + connector line).
          SizedBox(
            width: 14,
            child: Column(
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: ev.color.withValues(alpha: .18),
                    border: Border.all(color: ev.color, width: 2),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: c.cyan.withValues(alpha: .18),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 38,
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                label.isEmpty ? '–' : label,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.visible,
                style: TextStyle(
                  color: c.cyan,
                  fontWeight: FontWeight.w900,
                  fontSize: 12.5,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 1, bottom: isLast ? 2 : 13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _EventPill(label: ev.label, color: ev.color),
                  if (text.isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.text.withValues(alpha: 0.9),
                        fontWeight: FontWeight.w600,
                        fontSize: 12.5,
                        height: 1.3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small premium glass pill: WICKET (red/pink), SIX (green), FOUR / runs / DOT
/// (cyan/blue), matching the full Commentary tab styling.
class _EventPill extends StatelessWidget {
  const _EventPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 10,
          letterSpacing: .4,
        ),
      ),
    );
  }
}

/// Resolves the event pill label + colour for a live commentary row.
class _LiveEvent {
  const _LiveEvent(this.label, this.color);
  final String label;
  final Color color;
}

/// Trusts the server-normalized `type`/`event` field first (mirroring the
/// Commentary tab's rule), then falls back to the `is_wicket`/`is_four`/
/// `is_six` flags, and finally the runs value. Handles extras (wide/no-ball/
/// bye/leg-bye) so a wide with `runs:1` is no longer mislabelled "1 RUN".
_LiveEvent _liveEvent(Map<String, dynamic> row, dynamic c) {
  final type = _liveStr(row['type'] ?? row['event']).toLowerCase();
  final event = type;
  final isWicket = _truthyLive(row['is_wicket']) || event == 'wicket';
  final isFour = _truthyLive(row['is_four']) || event == 'four';
  final isSix = _truthyLive(row['is_six']) || event == 'six';

  // Server-normalized extra types take precedence so extras are never re-guessed
  // from the runs count (a wide with 1 run must read WIDE, not "1 RUN").
  if (type == 'wide' || type == 'no_ball' || type == 'noball' || type == 'no-ball') {
    return _LiveEvent(type == 'wide' ? 'WIDE' : 'NO BALL', (c.warning as Color));
  }
  if (type == 'bye' || type == 'leg_bye' || type == 'legbye' || type == 'leg-bye') {
    return _LiveEvent(type == 'bye' ? 'BYE' : 'LEG BYE', (c.warning as Color));
  }
  if (type == 'extra') {
    return _LiveEvent('EXTRA', (c.warning as Color));
  }

  if (isWicket) return _LiveEvent('WICKET', c.live as Color);
  if (isSix) return _LiveEvent('SIX', c.success as Color);
  if (isFour) return _LiveEvent('FOUR', c.cyan as Color);
  if (type == 'dot') return const _LiveEvent('DOT BALL', Color(0xff60a5fa));

  final runs = _liveRuns(row);
  if (runs == null) {
    // A non-ball commentary update (drinks/stumps/lunch/milestone) — not a
    // delivery. Prefer the server's own event label (e.g. "Stumps", "Lunch
    // Break", "Drinks") so the Live tab reads the same label as the full
    // Commentary tab, instead of a generic "UPDATE".
    final label = _liveStr(row['label'] ?? row['event'] ?? row['type']);
    if (label.isNotEmpty) {
      return _LiveEvent(label.toUpperCase(), c.muted as Color);
    }
    return _LiveEvent('UPDATE', c.muted as Color);
  }
  if (runs == 0) return const _LiveEvent('DOT BALL', Color(0xff60a5fa));
  return _LiveEvent(runs == 1 ? '1 RUN' : '$runs RUNS', c.cyan as Color);
}

int? _liveRuns(Map<String, dynamic> row) {
  final v = row['runs'] ??
      row['runs_scored'] ??
      row['score_runs'] ??
      row['legal_runs'] ??
      row['total_runs'];
  if (v == null) return null;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString().trim());
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
    this.headerIcon,
    this.headerTitle,
    this.headerAsset,
  });

  final String leadingHeader;
  final List<String> headers;
  final List<_LiveRow> rows;
  final IconData? headerIcon;
  final String? headerTitle;
  final String? headerAsset;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Drop the trailing column (SR/Econ) on very tight widths so values
        // never clip horizontally.
        final dropLast = constraints.maxWidth < 270 && headers.length > 4;
        final visibleHeaders =
            dropLast ? headers.take(headers.length - 1).toList() : headers;
        final narrow = constraints.maxWidth < 360;

        // Fixed per-column widths. The last column (SR / Econ) is widest so
        // values like "133.33" or "60.61" are shown in full — never "33....".
        double widthFor(int index) {
          final isLast = index == visibleHeaders.length - 1;
          if (isLast) return narrow ? 44.0 : 50.0;
          return narrow ? 28.0 : 32.0;
        }

        Widget numericHeader(int i, String h) => SizedBox(
              width: widthFor(i),
              child: Text(
                h,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: c.muted,
                  fontWeight: FontWeight.w800,
                  fontSize: 11.5,
                ),
              ),
            );

        Widget numericValue(int i, String v, bool bold) => SizedBox(
              width: widthFor(i),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.center,
                child: Text(
                  v,
                  maxLines: 1,
                  style: TextStyle(
                    color: c.text,
                    fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            );

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: headerTitle != null
                        ? Row(
                            children: [
                              MDIcon(
                                headerAsset ?? MDAsset.icCurrentBatters,
                                fallback: headerIcon ??
                                    Icons.sports_cricket_rounded,
                                size: 16,
                              ),
                              const SizedBox(width: 7),
                              Flexible(
                                child: Text(
                                  headerTitle!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: c.cyan,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          )
                        : Text(
                            leadingHeader,
                            style: TextStyle(
                              color: c.muted,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                  ),
                  for (var i = 0; i < visibleHeaders.length; i++)
                    numericHeader(i, visibleHeaders[i]),
                ],
              ),
            ),
            Divider(color: c.border.withValues(alpha: 0.6), height: 1),
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(child: row.leading),
                    for (var i = 0; i < visibleHeaders.length; i++)
                      numericValue(
                        i,
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
          width: 9,
          child: striker
              ? Container(
                  width: 6,
                  height: 6,
                  decoration:
                      BoxDecoration(shape: BoxShape.circle, color: c.cyan),
                )
              : null,
        ),
        _PlayerAvatar(row: row, name: name),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            formatCompactPlayerName(name),
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
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [c.cyan.withValues(alpha: 0.30), c.card2],
          ),
          border: Border.all(color: c.cyan.withValues(alpha: .4)),
        ),
        child: Text(
          _initials(name),
          style: TextStyle(
            color: c.text,
            fontWeight: FontWeight.w900,
            fontSize: 11,
          ),
        ),
      );
    }
    return CircleAvatar(
      radius: 15,
      backgroundColor: c.card2,
      backgroundImage: CachedNetworkImageProvider(
        image,
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
  if (_truthyLive(row['is_wicket'])) {
    return const _BallOutcome(_BallKind.wicket, 'W');
  }
  if (_truthyLive(row['is_six'])) {
    return const _BallOutcome(_BallKind.boundary, '6');
  }
  if (_truthyLive(row['is_four'])) {
    return const _BallOutcome(_BallKind.boundary, '4');
  }
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

/// Shortens long player names for compact tables/cards while keeping them
/// readable. Mirrors the brief's rules:
///   * fits within [maxLen] -> full name unchanged
///   * otherwise -> first initial + last word (e.g. "S. Mukkamalla")
///   * 3+ words -> first initial + last word (e.g. "M. Safi")
/// Numeric stats are never passed through this.
String formatCompactPlayerName(String name, {int maxLen = 14}) {
  final n = name.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (n.isEmpty || n.length <= maxLen) return n;
  final parts = n.split(' ');
  if (parts.length < 2) return n;
  final initial = parts.first.isNotEmpty ? parts.first[0].toUpperCase() : '';
  final last = parts.last;
  final candidate = '$initial. $last';
  return candidate;
}

/// Formats a numeric stat (strike rate / economy) so it never overflows: at
/// most [decimals] decimals, trailing ".0" dropped. Non-numeric values (e.g.
/// the "—" fallback) pass straight through.
String formatStatNumber(String raw, {int decimals = 2}) {
  final s = raw.trim();
  if (s.isEmpty) return s;
  final d = double.tryParse(s);
  if (d == null) return s;
  if (d == d.roundToDouble()) return d.toInt().toString();
  return d.toStringAsFixed(decimals);
}

/// Produces a clean over.ball label for the commentary timeline, stripping any
/// trailing ball-id / sequence digits the provider may append (which caused
/// labels like "17.6.108" to wrap onto two lines). Always one short token.
String formatOverLabel(String over, [String ball = '']) {
  final o = over.trim();
  if (o.isNotEmpty) {
    final m = RegExp(r'^(\d+)\.(\d+)').firstMatch(o);
    if (m != null) return '${m.group(1)}.${m.group(2)}';
    final intMatch = RegExp(r'^\d+').firstMatch(o);
    final base = intMatch?.group(0) ?? o;
    final b = ball.trim();
    if (b.isNotEmpty) {
      final bm = RegExp(r'^\d+').firstMatch(b);
      if (bm != null) return '$base.${bm.group(0)}';
    }
    return base;
  }
  return '';
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

/// Builds the batting innings line for the Current Batters footer, e.g.
/// "IND 181/3 in 39.5 overs". Returns '' when it can't be derived.
String _battingInningsLine(
    Map<String, dynamic> summary, Map<String, dynamic> lc) {
  final direct = _liveStr(lc['innings_summary'] ??
      lc['current_innings'] ??
      lc['batting_team_score'] ??
      summary['current_score']);
  if (direct.isNotEmpty) return direct;

  final battingId = _liveStr(lc['batting_team_id'] ??
      summary['curr_bat_team_id'] ??
      summary['currentBatTeamId']);
  for (final key in const ['team1', 'team2']) {
    final t = _liveMap(summary[key]);
    if (t.isEmpty) continue;
    final id = _liveStr(t['id'] ?? t['team_id']);
    if (battingId.isNotEmpty && id.isNotEmpty && id != battingId) continue;
    final innings = _liveList(t['innings']);
    if (innings.isEmpty) continue;
    final inn = _liveMap(innings.last);
    final runs = _liveStr(inn['runs']);
    if (runs.isEmpty) continue;
    final wkts = _liveStr(inn['wickets'], fallback: '0');
    final short =
        _liveStr(t['short_name'] ?? t['shortName'] ?? t['name'], fallback: '');
    final oversRaw = _liveStr(inn['overs']);
    final ov = oversRaw.isEmpty ? '' : normalizeOversText(oversRaw);
    final scorePart = '$short $runs/$wkts'.trim();
    return ov.isEmpty ? scorePart : '$scorePart in $ov overs';
  }
  return '';
}

/// Total runs scored across the supplied recent-over deliveries.
int _recentOverRuns(List<Map<String, dynamic>> balls, bool fromLiveCenter) {
  var total = 0;
  for (final b in balls) {
    if (fromLiveCenter) {
      final type = _liveStr(b['type']).toLowerCase();
      if (type == 'four') {
        total += 4;
      } else if (type == 'six') {
        total += 6;
      } else if (type == 'dot') {
        continue;
      } else {
        total += int.tryParse(_liveStr(b['value'])) ?? 0;
      }
    } else {
      if (_truthyLive(b['is_six'])) {
        total += 6;
      } else if (_truthyLive(b['is_four'])) {
        total += 4;
      } else {
        total += int.tryParse(_liveStr(b['runs'])) ?? 0;
      }
    }
  }
  return total;
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
  final parts =
      name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
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

/// A team's score for the Live result view: the team's short name plus its
/// structured [InningsScore] list, rendered through the shared [TeamScoreView]
/// so the result view and the Score tab can never disagree on formatting
/// (declared `d`, the `ov` unit, the multi-innings `&` join, current-innings
/// starring).
class _ResultTeamScore {
  const _ResultTeamScore({required this.name, required this.innings});
  final String name;
  final List<InningsScore> innings;
}

/// Builds structured team scores from the match-detail team innings, so the
/// Live result view renders through the shared [TeamScoreView] (the single
/// score formatter) instead of hand-building `runs/wickets (overs ov)` strings.
List<_ResultTeamScore> _resultScoreLines(Map<String, dynamic> summary) {
  final lines = <_ResultTeamScore>[];
  for (final key in const ['team1', 'team2']) {
    final team = _liveMap(summary[key]);
    if (team.isEmpty) continue;
    final name = _liveStr(
      team['short_name'] ?? team['shortName'] ?? team['name'],
    );
    final rawInnings = _liveList(team['innings']);
    if (rawInnings.isEmpty) continue;
    final innings = <InningsScore>[];
    for (final raw in rawInnings) {
      final inn = _liveMap(raw);
      final runs = apiInt(inn['runs']);
      // A batted innings needs a runs figure; skip empty placeholders so a
      // "Yet to bat" innings never reads as 0/0.
      if (runs == null) continue;
      final oversRaw = _liveStr(inn['overs']);
      innings.add(InningsScore(
        runs: runs,
        wickets: apiInt(inn['wickets']),
        overs: oversRaw.isEmpty ? '' : normalizeOversText(oversRaw),
        declared: _truthyLive(inn['declared']),
      ));
    }
    if (innings.isEmpty) continue;
    lines.add(_ResultTeamScore(name: name.isEmpty ? 'Team' : name, innings: innings));
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
    for (final b
        in _liveList(inn['batting'] ?? inn['batters'] ?? inn['batsmen'])) {
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
    final overs = normalizeOversText(_liveStr(last['overs']));
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

/// Maps a full-commentary item (server-normalized: `over`, `type`, `isWicket`,
/// `isFour`, `isSix`, `runs`, `text`) onto the key shape the Live preview row
/// expects (`over`, `ball`, `event`, `is_wicket`/`is_four`/`is_six`, `runs`,
/// `text`). Splits an "18.3"-style over into over + ball.
Map<String, dynamic> _normalizeFullComm(Map<String, dynamic> m) {
  final overRaw = _liveStr(m['over'] ?? m['overNumber'] ?? m['over_number']);
  var over = overRaw;
  var ball = _liveStr(m['ball'] ?? m['ballNumber'] ?? m['ball_number']);
  final dot = overRaw.indexOf('.');
  if (dot > 0) {
    over = overRaw.substring(0, dot);
    if (ball.isEmpty) ball = overRaw.substring(dot + 1);
  }
  final type = _liveStr(m['type'] ?? m['event']).toLowerCase();
  return <String, dynamic>{
    'over': over,
    'ball': ball,
    'event': type,
    'is_wicket': _truthyLive(m['isWicket']) || type == 'wicket',
    'is_four': _truthyLive(m['isFour']) || type == 'four',
    'is_six': _truthyLive(m['isSix']) || type == 'six',
    'runs': m['runs'] ?? m['legalRuns'] ?? m['totalRuns'],
    'text': _liveStr(m['text'] ?? m['commentary']),
  };
}

Map<String, dynamic> _liveMap(dynamic value) => value is Map<String, dynamic>
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
