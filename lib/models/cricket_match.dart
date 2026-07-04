import 'package:flutter/material.dart';
import 'package:cricpro_flutter/api_models.dart';

import '../models.dart';

/// Coarse match lifecycle phase, used to pick the Match Details initial tab.
enum MatchPhase { live, finished, upcoming }

/// Sentinel for `TeamScoreView.currentInningsIndex` returned by
/// [CricketMatch.currentScoredIndexForTeam] when the call site KNOWS this team
/// is NOT the one currently batting (or the match isn't live). It must suppress
/// the current-innings `*` even in a live match — distinct from the widget's
/// default `-1` ("auto": a live multi-innings score may star its own latest
/// innings). Keeping these two negatives distinct is what stops the star from
/// ever landing on BOTH teams.
const int kNoCurrentInnings = -2;

/// A single batting innings for one team, kept STRUCTURED so the UI can render
/// each innings (runs/wickets + its own overs) professionally — Test/first-class
/// matches show every innings clearly (`362/10 & 391/10` with `87.1 ov • 96.2
/// ov`) instead of a flattened, truncated string. This is the source of truth
/// for the centralized score presentation; the legacy flat `teamAScoreText` /
/// `teamBScoreText` strings are derived from the same data and kept for change
/// detection and back-compat.
class InningsScore {
  const InningsScore({
    this.runs,
    this.wickets,
    this.overs = '',
    this.declared = false,
    this.inningsNumber,
  });

  final int? runs;
  final int? wickets;

  /// Already-normalized overs text, e.g. `87.1` (no unit). Empty when unknown.
  final String overs;
  final bool declared;

  /// The chronological innings ordinal as reported by the provider (the
  /// `inningsId` / `inningsNo` / sequence). May be a match-global number
  /// (1 = team1 1st, 2 = team2 1st, 3 = team1 2nd, …) or a per-team number —
  /// either way ascending order is chronological, so the parser sorts each
  /// team's innings by this ONCE so every screen sees the SAME order. Null when
  /// the feed omitted it (then natural array position is preserved instead).
  final int? inningsNumber;

  /// True once this innings has a runs figure (a real, batted innings).
  bool get hasRuns => runs != null;

  /// True when this innings is CLOSED (cannot receive more runs): all out
  /// (10 wickets) or declared. A team's earlier innings is always closed before
  /// its next innings starts, so this is the reliable chronological signal when
  /// the provider omits an explicit innings ordinal.
  bool get isClosed => declared || (wickets != null && wickets! >= 10);

  /// `362/10`, `45/3`, `218` (no wickets), with a trailing `d` when declared.
  String get scoreText {
    if (runs == null) return '';
    final base = wickets == null ? '$runs' : '$runs/$wickets';
    return declared ? '${base}d' : base;
  }

  /// Overs without the unit, e.g. `87.1`. Empty when the feed omitted overs.
  String get oversText => overs.trim();

  InningsScore copyWith({
    int? runs,
    int? wickets,
    String? overs,
    bool? declared,
    int? inningsNumber,
  }) =>
      InningsScore(
        runs: runs ?? this.runs,
        wickets: wickets ?? this.wickets,
        overs: overs ?? this.overs,
        declared: declared ?? this.declared,
        inningsNumber: inningsNumber ?? this.inningsNumber,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'runs': runs,
        'wickets': wickets,
        'overs': overs,
        'declared': declared,
        'inningsNumber': inningsNumber,
      };

  factory InningsScore.fromJson(Map<String, dynamic> j) => InningsScore(
        runs: _toInt(j['runs']),
        wickets: _toInt(j['wickets']),
        overs: (j['overs'] ?? '').toString(),
        declared: j['declared'] == true,
        inningsNumber: _toInt(j['inningsNumber']),
      );

  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString().trim());
  }
}

/// A normalized cricket match parsed from any of the supported API shapes.
///
/// The webcrichd API returns matches in different shapes depending on the
/// endpoint (`/matches/live`, `/matches/upcoming`, `/matches/recent`,
/// `/schedule/upcoming`, `/match/:id`, ...). This class smooths over those
/// differences so the UI layer can always rely on the same fields and never
/// renders a raw `Map` or `List` from the API.
class CricketMatch {
  const CricketMatch({
    required this.id,
    required this.title,
    required this.series,
    required this.matchDesc,
    required this.status,
    required this.statusText,
    this.phase = '',
    required this.resultText,
    required this.venue,
    required this.startTime,
    required this.startDateTime,
    required this.teamA,
    required this.teamB,
    required this.teamAShort,
    required this.teamBShort,
    required this.teamALogo,
    required this.teamBLogo,
      required this.teamAScoreText,
      required this.teamBScoreText,
      this.teamAInnings = const <InningsScore>[],
      this.teamBInnings = const <InningsScore>[],
      this.teamAId = '',
      this.teamBId = '',
      this.battingTeamId,
      this.currentInningsId = 0,
      required this.isLive,
      required this.isUpcoming,
      required this.isFinished,
      required this.hasLiveStream,
      required this.watchLiveEnabled,
      required this.streamCount,
      required this.isPremiumStreamAvailable,
      required this.streamBadgeText,
      required this.hasStreamInfo,
      required this.defaultStreamId,
      this.score,
    });

  final String id;
  final String title;
  final String series;
  final String matchDesc;
  final String status;
  final String statusText;

  /// Finer-grained live sub-phase from the backend (`stumps`/`lunch`/`tea`/
  /// `drinks`/`rain`/`innings_break`/`live`/`upcoming`/`completed`/`abandoned`/
  /// `no_result`). Empty when the provider/payload didn't send one (older
  /// caches); callers fall back to [statusText] heuristics via
  /// `MatchStatusDisplay.from`. This is ADDITIVE — [status] (coarse) and the
  /// [isLive]/[isFinished]/[isUpcoming] flags are unchanged, so polling and tab
  /// selection behave exactly as before.
  final String phase;
  final String resultText;
  final String venue;
  final String startTime;
  final DateTime? startDateTime;
  final String teamA;
  final String teamB;
  final String teamAShort;
  final String teamBShort;
  final String? teamALogo;
  final String? teamBLogo;
  final String teamAScoreText;
  final String teamBScoreText;

  /// Structured per-innings scores (source of truth for professional score
  /// rendering). Empty when the team has not batted / no score is available.
  final List<InningsScore> teamAInnings;
  final List<InningsScore> teamBInnings;

  /// Provider team ids (Cricbuzz `teamId`). Used together with [battingTeamId]
  /// to decide which side is currently batting, so ONLY the batting team's
  /// active innings is starred. Empty when the feed omitted them.
  final String teamAId;
  final String teamBId;

  /// Id of the team currently batting (`curr_bat_team_id` / `currBatTeamId` /
  /// `batTeamId`). The single most reliable "who is batting now" signal the
  /// feeds carry — present on /app/home and /matches/live. Null when absent.
  final String? battingTeamId;

  /// Global current-innings ordinal (`current_innings` / `currInnings` /
  /// `inningsId`): 1 = team1 1st, 2 = team2 1st, 3 = team1 2nd, 4 = team2 2nd.
  /// 0 when the feed omitted it. Used as a fallback batting-side signal.
  final int currentInningsId;
  final bool isLive;
  final bool isUpcoming;
  final bool isFinished;
  final bool hasLiveStream;
  final bool watchLiveEnabled;
  final int streamCount;
  final bool isPremiumStreamAvailable;
  final String? streamBadgeText;
  final bool hasStreamInfo;
  final String? defaultStreamId;
  final String? score;

  /// Overlays ONLY the live-mutable fields from a fresh score-feed match
  /// (`/app/live-scores`) onto this richer object, preserving everything the
  /// lightweight feed doesn't carry — stream badges, logos, title, series,
  /// venue, start time. Used by the Home poll so a fast score update never
  /// wipes the card's stream/featured metadata. `fresh` must be the same match
  /// (same id); score/status/result + the derived live/finished flags are
  /// taken from it.
  CricketMatch mergeLiveScore(CricketMatch fresh) {
    return CricketMatch(
      id: id,
      title: title,
      series: series,
      matchDesc: matchDesc,
      status: fresh.status,
      statusText: fresh.statusText,
      phase: fresh.phase,
      resultText: fresh.resultText,
      venue: venue,
      startTime: startTime,
      startDateTime: startDateTime,
      teamA: teamA,
      teamB: teamB,
      teamAShort: teamAShort,
      teamBShort: teamBShort,
      teamALogo: teamALogo,
      teamBLogo: teamBLogo,
      teamAScoreText: fresh.teamAScoreText,
      teamBScoreText: fresh.teamBScoreText,
      teamAInnings: _stickyDeclared(teamAInnings, fresh.teamAInnings),
      teamBInnings: _stickyDeclared(teamBInnings, fresh.teamBInnings),
      // Team ids are stable identity → keep ours if the fresh feed omitted them.
      teamAId: fresh.teamAId.isNotEmpty ? fresh.teamAId : teamAId,
      teamBId: fresh.teamBId.isNotEmpty ? fresh.teamBId : teamBId,
      // Batting side / current innings are live-mutable → take from fresh.
      battingTeamId: fresh.battingTeamId ?? battingTeamId,
      currentInningsId:
          fresh.currentInningsId != 0 ? fresh.currentInningsId : currentInningsId,
      isLive: fresh.isLive,
      isUpcoming: fresh.isUpcoming,
      isFinished: fresh.isFinished,
      hasLiveStream: hasLiveStream,
      watchLiveEnabled: watchLiveEnabled,
      streamCount: streamCount,
      isPremiumStreamAvailable: isPremiumStreamAvailable,
      streamBadgeText: streamBadgeText,
      hasStreamInfo: hasStreamInfo,
      defaultStreamId: defaultStreamId,
      score: fresh.score ?? score,
    );
  }

  /// Last-known coarse phase for a match id, captured whenever the match was
  /// parsed for any list/feed. Lets Match Details resolve its initial tab
  /// synchronously (before the detail summary network call returns), so a live
  /// match opens straight on Live and a finished match on Scorecard with no
  /// first-frame flash on Info. Null when the match has never been seen
  /// (e.g. a cold deep link / notification open).
  static final Map<String, MatchPhase> _phaseRegistry = {};

  static MatchPhase? knownPhase(String matchId) =>
      matchId.isEmpty ? null : _phaseRegistry[matchId];

  /// Last-known *good* summary for a match id, captured whenever the match was
  /// parsed for a list/feed (Home, Matches, Schedule, Series) that carried real
  /// team data. Match Details reads this as an immediate fallback so an upcoming
  /// match opened from a card never flashes "TBD vs TBD" / "No Details" while
  /// the `/match/:id` detail loads — and, if the detail payload is thin (no
  /// teams), the good summary is kept instead of being replaced by placeholders.
  ///
  /// Only matches with at least one real (non-`TBD`, non-empty) team name are
  /// stored, so a placeholder never overwrites a good prior summary.
  static final Map<String, CricketMatch> _summaryRegistry = {};

  static CricketMatch? knownSummary(String matchId) =>
      matchId.isEmpty ? null : _summaryRegistry[matchId];

  /// Cap the instant-open registries so they can't grow unbounded across a
  /// long session (one entry per match id ever parsed, never evicted before).
  /// 200 covers a full day's schedule with headroom; oldest entries (by
  /// insertion order) are dropped first.
  static const int _registryCap = 200;

  static void _rememberPhase(String id, MatchPhase phase) {
    if (id.isEmpty) return;
    _phaseRegistry[id] = phase;
    if (_phaseRegistry.length > _registryCap) {
      _phaseRegistry.remove(_phaseRegistry.keys.first);
    }
  }

  static void _rememberSummary(String id, CricketMatch match) {
    if (id.isEmpty || !match._hasRealTeams) return;
    _summaryRegistry[id] = match;
    if (_summaryRegistry.length > _registryCap) {
      _summaryRegistry.remove(_summaryRegistry.keys.first);
    }
  }

  bool get _hasRealTeams =>
      (teamA.isNotEmpty && teamA != 'TBD') ||
      (teamB.isNotEmpty && teamB != 'TBD');

  /// Returns a copy of `this` where any empty / placeholder (`TBD`) field is
  /// backfilled from [other]. Used to merge a thin detail payload with a richer
  /// known summary without ever overwriting good detail data. Live-mutable
  /// fields (scores, status, result, phase flags) always come from `this` (the
  /// fresher detail), so a refresh updates the score but never wipes teams.
  CricketMatch fillFrom(CricketMatch? other) {
    if (other == null) return this;
    String pick(String mine, String theirs) =>
        (mine.isEmpty || mine == 'TBD') ? theirs : mine;
    String? pickN(String? mine, String? theirs) =>
        (mine == null || mine.isEmpty) ? theirs : mine;
    return CricketMatch(
      id: id.isEmpty ? other.id : id,
      title: pick(title, other.title),
      series: pick(series, other.series),
      matchDesc: pick(matchDesc, other.matchDesc),
      status: status,
      statusText: statusText,
      phase: phase,
      resultText: resultText,
      venue: pick(venue, other.venue),
      startTime: pick(startTime, other.startTime),
      startDateTime: startDateTime ?? other.startDateTime,
      teamA: pick(teamA, other.teamA),
      teamB: pick(teamB, other.teamB),
      teamAShort: pick(teamAShort, other.teamAShort),
      teamBShort: pick(teamBShort, other.teamBShort),
      teamALogo: pickN(teamALogo, other.teamALogo),
      teamBLogo: pickN(teamBLogo, other.teamBLogo),
      teamAScoreText: teamAScoreText,
      teamBScoreText: teamBScoreText,
      teamAInnings: teamAInnings,
      teamBInnings: teamBInnings,
      teamAId: teamAId.isNotEmpty ? teamAId : other.teamAId,
      teamBId: teamBId.isNotEmpty ? teamBId : other.teamBId,
      battingTeamId: battingTeamId ?? other.battingTeamId,
      currentInningsId:
          currentInningsId != 0 ? currentInningsId : other.currentInningsId,
      isLive: isLive,
      isUpcoming: isUpcoming,
      isFinished: isFinished,
      hasLiveStream: hasLiveStream || other.hasLiveStream,
      watchLiveEnabled: watchLiveEnabled || other.watchLiveEnabled,
      streamCount: streamCount > 0 ? streamCount : other.streamCount,
      isPremiumStreamAvailable:
          isPremiumStreamAvailable || other.isPremiumStreamAvailable,
      streamBadgeText: pickN(streamBadgeText, other.streamBadgeText),
      hasStreamInfo: hasStreamInfo || other.hasStreamInfo,
      defaultStreamId: pickN(defaultStreamId, other.defaultStreamId),
      score: score ?? other.score,
    );
  }

  /// Serializes this match to a plain JSON map for the persistent disk cache
  /// (Phase F1). This is a FAITHFUL, field-by-field round-trip — it is NOT the
  /// provider's wire shape. It exists only so a parsed match list can be saved
  /// and restored losslessly across cold starts. [fromCacheJson] is its exact
  /// inverse. The network parse path ([fromJson]) is unaffected.
  Map<String, dynamic> toCacheJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'series': series,
        'matchDesc': matchDesc,
        'status': status,
        'statusText': statusText,
        'phase': phase,
        'resultText': resultText,
        'venue': venue,
        'startTime': startTime,
        'startDateTime': startDateTime?.toIso8601String(),
        'teamA': teamA,
        'teamB': teamB,
        'teamAShort': teamAShort,
        'teamBShort': teamBShort,
        'teamALogo': teamALogo,
        'teamBLogo': teamBLogo,
        'teamAScoreText': teamAScoreText,
        'teamBScoreText': teamBScoreText,
        'teamAInnings': teamAInnings.map((e) => e.toJson()).toList(),
        'teamBInnings': teamBInnings.map((e) => e.toJson()).toList(),
        'teamAId': teamAId,
        'teamBId': teamBId,
        'battingTeamId': battingTeamId,
        'currentInningsId': currentInningsId,
        'isLive': isLive,
        'isUpcoming': isUpcoming,
        'isFinished': isFinished,
        'hasLiveStream': hasLiveStream,
        'watchLiveEnabled': watchLiveEnabled,
        'streamCount': streamCount,
        'isPremiumStreamAvailable': isPremiumStreamAvailable,
        'streamBadgeText': streamBadgeText,
        'hasStreamInfo': hasStreamInfo,
        'defaultStreamId': defaultStreamId,
        'score': score,
      };

  /// Reconstructs a match previously saved by [toCacheJson]. Reads the explicit
  /// camelCase keys this serializer wrote (no provider heuristics), so the
  /// restored object is identical to the one that was cached. Also re-populates
  /// the phase/summary registries so Match Details keeps its instant-open
  /// behaviour after a cold start.
  factory CricketMatch.fromCacheJson(Map<String, dynamic> json) {
    final id = (json['id'] ?? '').toString();
    final isLive = json['isLive'] == true;
    final isFinished = json['isFinished'] == true;
    final isUpcoming = json['isUpcoming'] == true || (!isLive && !isFinished);
    final match = CricketMatch(
      id: id,
      title: (json['title'] ?? '').toString(),
      series: (json['series'] ?? '').toString(),
      matchDesc: (json['matchDesc'] ?? '').toString(),
      status: (json['status'] ?? 'upcoming').toString(),
      statusText: (json['statusText'] ?? '').toString(),
      phase: (json['phase'] ?? '').toString(),
      resultText: (json['resultText'] ?? '').toString(),
      venue: (json['venue'] ?? '').toString(),
      startTime: (json['startTime'] ?? '').toString(),
      startDateTime: DateTime.tryParse((json['startDateTime'] ?? '').toString()),
      teamA: (json['teamA'] ?? '').toString(),
      teamB: (json['teamB'] ?? '').toString(),
      teamAShort: (json['teamAShort'] ?? '').toString(),
      teamBShort: (json['teamBShort'] ?? '').toString(),
      teamALogo: json['teamALogo']?.toString(),
      teamBLogo: json['teamBLogo']?.toString(),
      teamAScoreText: (json['teamAScoreText'] ?? '').toString(),
      teamBScoreText: (json['teamBScoreText'] ?? '').toString(),
      teamAInnings: _inningsFromCache(json['teamAInnings']),
      teamBInnings: _inningsFromCache(json['teamBInnings']),
      teamAId: (json['teamAId'] ?? '').toString(),
      teamBId: (json['teamBId'] ?? '').toString(),
      battingTeamId: json['battingTeamId']?.toString(),
      currentInningsId: (json['currentInningsId'] is num)
          ? (json['currentInningsId'] as num).toInt()
          : int.tryParse('${json['currentInningsId'] ?? ''}') ?? 0,
      isLive: isLive,
      isUpcoming: isUpcoming,
      isFinished: isFinished,
      hasLiveStream: json['hasLiveStream'] == true,
      watchLiveEnabled: json['watchLiveEnabled'] == true,
      streamCount: (json['streamCount'] is num)
          ? (json['streamCount'] as num).toInt()
          : int.tryParse('${json['streamCount'] ?? ''}') ?? 0,
      isPremiumStreamAvailable: json['isPremiumStreamAvailable'] == true,
      streamBadgeText: json['streamBadgeText']?.toString(),
      hasStreamInfo: json['hasStreamInfo'] == true,
      defaultStreamId: json['defaultStreamId']?.toString(),
      score: json['score']?.toString(),
    );
    // Keep the instant-open registries warm across cold starts.
    if (id.isNotEmpty) {
      _rememberPhase(
          id,
          isLive
              ? MatchPhase.live
              : isFinished
                  ? MatchPhase.finished
                  : MatchPhase.upcoming);
      _rememberSummary(id, match);
    }
    return match;
  }

  factory CricketMatch.fromJson(dynamic value) {
    final json = value is Map<String, dynamic> ? value : <String, dynamic>{};
    final t1 = _team(json, const ['team1', 'teamA', 'homeTeam', 'batTeam']);
    final t2 = _team(json, const ['team2', 'teamB', 'awayTeam', 'bowlTeam']);
    final venue = _venue(json);
    final status = _str(json, const ['status', 'matchStatus', 'state'],
            fallback: 'upcoming')
        .toLowerCase();
    final statusText = _str(
      json,
      const ['status_text', 'statusText', 'short_status', 'shortStatus'],
      fallback: '',
    );
    // Finer-grained live sub-phase from the backend (stumps/lunch/tea/drinks/
    // rain/innings_break/...). Empty when absent; the UI falls back to
    // statusText heuristics. Lower-cased to match the resolver's expectations.
    final phase = _str(
      json,
      const ['phase', 'matchPhase', 'match_phase'],
      fallback: '',
    ).toLowerCase();
    final matchDesc = _str(
      json,
      const [
        'match_desc',
        'matchDesc',
        'match_number',
        'matchNumber',
        'matchDescription',
        'title'
      ],
      fallback: '',
    );
    final score = _scoreMap(json);
    final t1Raw = score?['team1'] ?? score?['teamA'] ?? t1.innings;
    final t2Raw = score?['team2'] ?? score?['teamB'] ?? t2.innings;
    // Parse the STRUCTURED innings first (chronologically ordered), then derive
    // the legacy flat strings FROM them — so the flat text and the structured
    // innings can never disagree on order, and the unit is always lowercase.
    final t1Innings = _parseInnings(t1Raw);
    final t2Innings = _parseInnings(t2Raw);
    // Cricbuzz's list/home feeds (`/matches/live`, `/matches/recent`,
    // `/app/home`) DROP the per-innings `declared` flag that the detail /
    // `/app/live-scores` feed carries — so a declared innings like `288/9`
    // rendered as `288/9` on the Matches screen and FLICKERED on Home as the
    // declared (live-scores) and non-declared (matches/live) feeds alternated
    // during polling. Derive `d` deterministically from signals EVERY feed
    // carries (corrected innings order + the batting-team id) so the marker is
    // identical on every screen and stable across polls.
    final battingIdForDeclared = _str(
      json,
      const [
        'curr_bat_team_id',
        'currBatTeamId',
        'battingTeamId',
        'batTeamId',
        'bat_team_id',
      ],
      fallback: '',
    );
    final finishedForDeclared = status == 'completed' ||
        status == 'recent' ||
        status == 'finished' ||
        status == 'result' ||
        status == 'abandoned';
    final derivedDeclared = _deriveDeclared(
      t1Innings,
      t2Innings,
      t1Id: t1.id,
      t2Id: t2.id,
      battingTeamId: battingIdForDeclared,
      finished: finishedForDeclared,
    );
    final t1InningsD = derivedDeclared.$1;
    final t2InningsD = derivedDeclared.$2;
    final t1Score = _flatScoreFrom(t1InningsD);
    final t2Score = _flatScoreFrom(t2InningsD);
    final start = _str(
      json,
      const ['start_time', 'startTime', 'dateTimeGMT', 'date', 'time'],
      fallback: '',
    );
    final startDt = _parseStart(start);
    // A match is "live" for polling/UI purposes not only during active play but
    // also during innings breaks and stoppages (rain/tea/drinks/stumps) that the
    // backend surfaces. Excluding these froze the score until pull-to-refresh.
    final isLive = status == 'live' ||
        status == 'in_progress' ||
        status == 'inprogress' ||
        status == 'progress' ||
        status == 'innings_break' ||
        status == 'inningsbreak' ||
        status == 'break' ||
        status == 'rain_delay' ||
        status == 'delay' ||
        status == 'tea' ||
        status == 'lunch' ||
        status == 'drinks' ||
        status == 'stumps';
    final isFinished = status == 'completed' ||
        status == 'recent' ||
        status == 'finished' ||
        status == 'result' ||
        status == 'abandoned';
    final isUpcoming = !isLive && !isFinished;
    final hasStreamInfo = json.containsKey('hasLiveStream') ||
        json.containsKey('watchLiveEnabled') ||
        json.containsKey('hasStream') ||
        json.containsKey('hasStreams') ||
        json.containsKey('streamCount') ||
        json.containsKey('isPremiumStreamAvailable') ||
        json.containsKey('streamBadgeText') ||
        json.containsKey('defaultStreamId');
    final streamCount = apiInt(json['streamCount']) ?? apiInt(json['stream_count']) ?? 0;
    final hasLiveStream =
        apiBool(json['hasLiveStream']) ||
        apiBool(json['hasStream']) ||
        apiBool(json['hasStreams']) ||
        streamCount > 0;
    final watchLiveEnabled =
        apiBool(json['watchLiveEnabled'], hasLiveStream);
    final premiumStreamAvailable =
        apiBool(json['isPremiumStreamAvailable']) ||
        apiBool(json['premiumStreamAvailable']);
    final streamBadgeText = apiString(json['streamBadgeText'], '').isEmpty
        ? null
        : apiString(json['streamBadgeText']);
    final defaultStreamId =
        apiString(json['defaultStreamId'], '').isEmpty
            ? null
            : apiString(json['defaultStreamId']);

    // Build title from actual team names, never use hardcoded title if it doesn't match teams
    final rawTitle =
        _str(json, const ['title', 'matchTitle', 'name'], fallback: '');
    String title;
    if (rawTitle.isNotEmpty) {
      // Check if title matches the actual teams
      final titleLower = rawTitle.toLowerCase();
      final t1Lower = t1.name.toLowerCase();
      final t2Lower = t2.name.toLowerCase();
      final t1ShortLower = t1.short.toLowerCase();
      final t2ShortLower = t2.short.toLowerCase();

      // Only use the title if it contains both team names or short names
      if ((titleLower.contains(t1Lower) || titleLower.contains(t1ShortLower)) &&
          (titleLower.contains(t2Lower) || titleLower.contains(t2ShortLower))) {
        title = rawTitle;
      } else {
        // Title doesn't match teams, build from team names
        title = formatMatchTitle(t1.name, t2.name,
            shortName1: t1.short, shortName2: t2.short);
      }
    } else {
      // No title, build from team names
      title = formatMatchTitle(t1.name, t2.name,
          shortName1: t1.short, shortName2: t2.short);
    }

    final result = _str(
        json, const ['result', 'resultText', 'short_status', 'shortStatus'],
        fallback: '');
    // Which team is batting now + the global current-innings ordinal. These are
    // the reliable "who is batting" signals the feeds carry (home + live both
    // emit `curr_bat_team_id`; live also emits `current_innings`). They drive
    // the current-innings `*` so ONLY the batting team's active innings is
    // starred — never both teams, never a finished innings.
    final battingTeamId = _str(
      json,
      const [
        'curr_bat_team_id',
        'currBatTeamId',
        'battingTeamId',
        'batTeamId',
        'bat_team_id',
      ],
      fallback: '',
    );
    final currentInningsId = _toInt(json['current_innings']) ??
        _toInt(json['currInnings']) ??
        _toInt(json['currentInnings']) ??
        _toInt(json['inningsId']) ??
        0;
    final id = _str(json, const ['match_id', 'matchId', 'id'], fallback: '');
    // Remember the coarse phase so Match Details can pick the right initial tab
    // before its detail summary loads (no Info-tab flash on live/finished opens).
    if (id.isNotEmpty) {
      _rememberPhase(
          id,
          isLive
              ? MatchPhase.live
              : isFinished
                  ? MatchPhase.finished
                  : MatchPhase.upcoming);
    }
    final match = CricketMatch(
      id: id,
      title: title,
      series: _str(json,
                  const ['series_name', 'seriesName', 'series', 'tournament'],
                  fallback: '')
              .isEmpty
          ? (matchDesc.isNotEmpty ? matchDesc : 'Cricket Match')
          : _str(json,
              const ['series_name', 'seriesName', 'series', 'tournament']),
      matchDesc: matchDesc,
      status: status,
      statusText: statusText,
      phase: phase,
      resultText: result,
      venue: venue,
      startTime: start,
      startDateTime: startDt,
      teamA: t1.name,
      teamB: t2.name,
      teamAShort: t1.short,
      teamBShort: t2.short,
      teamALogo: t1.logo,
      teamBLogo: t2.logo,
      teamAScoreText: t1Score,
      teamBScoreText: t2Score,
      teamAInnings: t1InningsD,
      teamBInnings: t2InningsD,
      teamAId: t1.id,
      teamBId: t2.id,
      battingTeamId: battingTeamId.isEmpty ? null : battingTeamId,
      currentInningsId: currentInningsId,
      isLive: isLive,
      isUpcoming: isUpcoming,
      isFinished: isFinished,
      hasLiveStream: hasLiveStream,
      watchLiveEnabled: watchLiveEnabled,
      streamCount: streamCount,
      isPremiumStreamAvailable: premiumStreamAvailable,
      streamBadgeText: streamBadgeText,
      hasStreamInfo: hasStreamInfo,
      defaultStreamId: defaultStreamId,
      score: t1Score.isEmpty && t2Score.isEmpty ? null : '$t1Score vs $t2Score',
    );
    // Cache the last-known good summary so Match Details can render real teams
    // immediately and never regress to "TBD vs TBD" on a thin detail payload.
    // Only store when teams are real, so a placeholder can't clobber good data.
    _rememberSummary(id, match);
    return match;
  }

  /// Human friendly status label, e.g. `LIVE`, `Upcoming`, `Finished`.
  String get statusLabel {
    if (isLive) return 'LIVE';
    if (isFinished) return 'Finished';
    if (status == 'not_started') return 'Not Started';
    return 'Upcoming';
  }

  /// Title formatted like `PAK vs AUS`, falling back to full names if codes
  /// are unavailable.
  String get versusTitle {
    if (teamAShort.isNotEmpty && teamBShort.isNotEmpty) {
      return '$teamAShort vs $teamBShort';
    }
    return '$teamA vs $teamB';
  }

  /// Score line such as `RR 214/6 — GT 191/2 (15.6 OV)` for live matches, or
  /// `IND 321/4 (49.2) AUS 315/9 (50.0)` for finished matches. Returns an
  /// empty string when no score is available.
  String get scoreLine {
    final pieces = <String>[];
    if (teamAScoreText.isNotEmpty) {
      pieces
          .add('${teamAShort.isNotEmpty ? teamAShort : teamA} $teamAScoreText');
    }
    if (teamBScoreText.isNotEmpty) {
      pieces
          .add('${teamBShort.isNotEmpty ? teamBShort : teamB} $teamBScoreText');
    }
    return pieces.join('  •  ');
  }

  /// Index, within a team's SCORED innings (oldest-first), of the innings that
  /// is currently being batted — i.e. the one that should carry the `*`. Returns
  /// `-1` when the match is not live, the team has not batted, OR this team is
  /// not the side currently batting. This is the SINGLE source of truth for the
  /// current-innings highlight: every score block passes the result straight to
  /// [TeamScoreView], so the star can never land on both teams or on a finished
  /// innings.
  ///
  /// Pass [isTeamA] true for the [teamAInnings] side, false for [teamBInnings].
  int currentScoredIndexForTeam({required bool isTeamA}) {
    if (!isLive) return kNoCurrentInnings;
    final inns = isTeamA ? teamAInnings : teamBInnings;
    final scoredCount = inns.where((i) => i.hasRuns).length;
    if (scoredCount == 0) return kNoCurrentInnings;
    // Explicitly suppress the star on the side that is NOT batting, so a live
    // match never stars both teams (the non-batting team returns the sentinel
    // rather than -1, which the widget would otherwise treat as "auto").
    if (!_isTeamBatting(isTeamA: isTeamA)) return kNoCurrentInnings;
    // The active innings is always a team's LAST (most recent) scored innings.
    return scoredCount - 1;
  }

  /// Whether [isTeamA]'s side is the one batting right now. Resolved from the
  /// most reliable available signal, in order:
  ///   1. Explicit `battingTeamId` matched against the team ids (feeds carry
  ///      this on /app/home and /matches/live).
  ///   2. The global current-innings ordinal ([currentInningsId]) matched
  ///      against each team's innings ordinals (needs the provider innings id).
  ///   3. Heuristic: the side whose latest innings is still OPEN (wickets < 10
  ///      and not declared) while the other side's latest innings is closed.
  ///   4. Otherwise nobody is starred (safer than starring the wrong/both).
  bool _isTeamBatting({required bool isTeamA}) {
    final myId = isTeamA ? teamAId : teamBId;
    final otherId = isTeamA ? teamBId : teamAId;

    // 1) Explicit batting-team id (most reliable).
    final bt = battingTeamId;
    if (bt != null && bt.isNotEmpty) {
      if (myId.isNotEmpty && myId == bt) return true;
      if (otherId.isNotEmpty && otherId == bt) return false;
      // bt present but matches neither id → fall through to weaker signals.
    }

    final myInns = (isTeamA ? teamAInnings : teamBInnings)
        .where((i) => i.hasRuns)
        .toList(growable: false);
    final otherInns = (isTeamA ? teamBInnings : teamAInnings)
        .where((i) => i.hasRuns)
        .toList(growable: false);
    if (myInns.isEmpty) return false;

    // 2) Global current-innings ordinal: the side that owns the highest innings
    //    ordinal across both teams is batting.
    if (currentInningsId > 0) {
      final mineHas = myInns.any((i) => i.inningsNumber == currentInningsId);
      final otherHas = otherInns.any((i) => i.inningsNumber == currentInningsId);
      if (mineHas && !otherHas) return true;
      if (otherHas && !mineHas) return false;
    }
    final allOrdinals = <int>[
      for (final i in myInns) if (i.inningsNumber != null) i.inningsNumber!,
      for (final i in otherInns) if (i.inningsNumber != null) i.inningsNumber!,
    ];
    if (allOrdinals.length == (myInns.length + otherInns.length) &&
        allOrdinals.isNotEmpty) {
      final maxOrdinal = allOrdinals.reduce((a, b) => a > b ? a : b);
      final mineOwnsMax = myInns.any((i) => i.inningsNumber == maxOrdinal);
      final otherOwnsMax = otherInns.any((i) => i.inningsNumber == maxOrdinal);
      if (mineOwnsMax && !otherOwnsMax) return true;
      if (otherOwnsMax && !mineOwnsMax) return false;
    }

    // 3) Open-innings heuristic: a team's latest innings is "open" when it is
    //    not all out and not declared. Only star when exactly one side is open.
    bool open(List<InningsScore> inns) {
      if (inns.isEmpty) return false;
      final last = inns.last;
      final w = last.wickets;
      return !last.declared && (w == null || w < 10);
    }

    final mineOpen = open(myInns);
    final otherOpen = open(otherInns);
    if (mineOpen && !otherOpen) return true;
    if (otherOpen && !mineOpen) return false;

    // 4) Ambiguous → do not star (never star both teams).
    return false;
  }

  CompactFixture toCompactFixture({required bool finished}) {
    final dateLine = _dateLine();
    final venueLabel = finished
        ? (resultText.isNotEmpty
            ? resultText
            : (statusText.isNotEmpty ? statusText : venue))
        : venue;
    return CompactFixture(
      series: series,
      subtitle: matchDesc.isNotEmpty ? matchDesc : '',
      left: _teamInfo(teamA, teamAShort, teamALogo, const Color(0xff22d3ee)),
      right: _teamInfo(teamB, teamBShort, teamBLogo, const Color(0xfff59e0b)),
      date: dateLine,
      venue: venueLabel,
      status: statusLabel,
      action: finished ? 'Scorecard' : (isLive ? 'View Match' : 'Remind Me'),
      leftScore: teamAScoreText.isEmpty ? null : teamAScoreText,
      rightScore: teamBScoreText.isEmpty ? null : teamBScoreText,
      result:
          finished ? (resultText.isNotEmpty ? resultText : statusText) : null,
      playerOfMatch: null,
      playerStat: null,
    );
  }

  HeroFixture toHeroFixture({required bool live, required bool finished}) {
    final dateLine = _dateLine();
    final heroLeftScore =
        teamAScoreText.isNotEmpty ? teamAScoreText : (live ? 'Yet to bat' : '');
    final heroRightScore =
        teamBScoreText.isNotEmpty ? teamBScoreText : (live ? 'Yet to bat' : '');
    final timeLine = live
        ? (statusText.isNotEmpty ? statusText : 'Live')
        : finished
            ? (resultText.isNotEmpty
                ? resultText
                : (statusText.isNotEmpty ? statusText : 'Finished'))
            : (statusText.isNotEmpty
                ? statusText
                : (dateLine.isEmpty ? 'Upcoming' : dateLine));
    return HeroFixture(
      badge: live ? 'LIVE' : (finished ? 'RESULT' : 'UPCOMING'),
      series: series,
      date: dateLine.isNotEmpty
          ? dateLine
          : (finished
              ? (resultText.isNotEmpty ? resultText : 'Finished')
              : 'Upcoming'),
      time: timeLine,
      left: _teamInfo(teamA, teamAShort, teamALogo, const Color(0xff22d3ee)),
      right: _teamInfo(teamB, teamBShort, teamBLogo, const Color(0xfff59e0b)),
      centerTitle: 'VS',
      venue: venue,
      button: live ? 'Watch Live' : (finished ? 'Scorecard' : 'Remind Me'),
      result:
          finished ? (resultText.isNotEmpty ? resultText : statusText) : null,
      leftMeta:
          (live || finished) && heroLeftScore.isNotEmpty ? heroLeftScore : null,
      rightMeta: (live || finished) && heroRightScore.isNotEmpty
          ? heroRightScore
          : null,
    );
  }

  String _dateLine() {
    final formatted = formatMatchDateTime(startDateTime ?? startTime);
    if (formatted.isNotEmpty) return formatted;
    return statusText.isNotEmpty ? statusText : '';
  }

  static TeamInfo _teamInfo(
      String name, String short, String? logo, Color color) {
    final fullName = name.trim().isEmpty ? 'TBD' : name.trim();
    final shortName =
        short.trim().isEmpty ? _initials(fullName) : short.trim().toUpperCase();
    return TeamInfo(
      code: shortName,
      name: fullName,
      shortName: shortName,
      color: color,
      asset: logo,
    );
  }

  static String _initials(String value) {
    return safeTeamInitials(value);
  }

  static String _str(
    Map<String, dynamic> json,
    List<String> keys, {
    String fallback = '',
  }) {
    for (final key in keys) {
      final value = json[key];
      if (value == null) continue;
      if (value is String) {
        if (value.trim().isNotEmpty) return value.trim();
        continue;
      }
      if (value is num || value is bool) {
        final text = value.toString();
        if (text.isNotEmpty) return text;
      }
      // Refuse to stringify Maps/Lists — that's where the "raw object" bug
      // came from.
    }
    return fallback;
  }

  static _TeamData _team(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value is Map<String, dynamic>) {
        final name =
            _str(value, const ['name', 'teamName', 'fullName'], fallback: '');
        final teamId = _str(value,
            const ['id', 'teamId', 'team_id', 'tid'],
            fallback: '');
        final short = _str(
            value,
            const [
              'short_name',
              'shortName',
              'teamShort',
              'team_short',
              'teamShortName',
              'code',
              'abbr'
            ],
            fallback: '');

        final logoUrl = resolveTeamLogoUrl(value);

        // Per-team innings can live under several keys depending on endpoint:
        // `innings` (list), or a nested `score`/`scr`/`scores` object/list.
        dynamic innings = value['innings'];
        if (innings is! List || innings.isEmpty) {
          for (final sk in const ['score', 'scr', 'scores', 'innings']) {
            final sv = value[sk];
            if (sv is List && sv.isNotEmpty) {
              innings = sv;
              break;
            }
            if (sv is Map<String, dynamic> && sv.isNotEmpty) {
              innings = _innsFromScoreMap(sv);
              break;
            }
          }
        }
        return _TeamData(
          name: name.isNotEmpty ? name : (short.isNotEmpty ? short : 'TBD'),
          short: short.isNotEmpty
              ? short
              : (name.isNotEmpty ? _initials(name) : 'TBD'),
          logo: logoUrl,
          innings: innings is List ? innings : const [],
          id: teamId,
        );
      }
      if (value is String && value.trim().isNotEmpty) {
        final name = value.trim();
        return _TeamData(
          name: name,
          short: _initials(name),
          logo: null,
          innings: const [],
        );
      }
    }
    // Fall through — try snake_case sibling keys (some endpoints flatten the
    // team data instead of nesting it).
    final flatName = _str(json,
        [for (final k in keys) '${k}_name', ...keys.map((k) => '${k}Name')]);
    if (flatName.isNotEmpty) {
      return _TeamData(
        name: flatName,
        short: _initials(flatName),
        logo: null,
        innings: const [],
      );
    }
    return const _TeamData(name: 'TBD', short: 'TBD', logo: null, innings: []);
  }

  static String _venue(Map<String, dynamic> json) {
    final value = json['venue'] ?? json['ground'] ?? json['location'];
    if (value is Map<String, dynamic>) {
      final parts = <String>[];
      final name = _str(value, const ['name', 'venue', 'stadium']);
      if (name.isNotEmpty) parts.add(name);
      final city = _str(value, const ['city', 'town']);
      if (city.isNotEmpty && !parts.contains(city)) parts.add(city);
      return parts.isEmpty ? 'Venue TBD' : parts.join(', ');
    }
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return 'Venue TBD';
  }

  static Map<String, dynamic>? _scoreMap(Map<String, dynamic> json) {
    // Direct `score` object (most endpoints, incl. /app/home).
    final value = json['score'];
    if (value is Map<String, dynamic> && value.isNotEmpty) return value;
    // Some live shapes wrap the per-team innings under a different top-level
    // container. Probe the common ones so /matches/live scores aren't dropped.
    for (final k in const ['matchScore', 'scorecard', 'scores', 'liveScore']) {
      final v = json[k];
      if (v is Map<String, dynamic> && v.isNotEmpty) return v;
    }

    final team1 = _scoreEntries(
      json,
      const [
        'team1Score',
        'team1_score',
        'teamAScore',
        'team_a_score',
        'team1score',
        'batTeamScore',
        'homeScore',
      ],
    );
    final team2 = _scoreEntries(
      json,
      const [
        'team2Score',
        'team2_score',
        'teamBScore',
        'team_b_score',
        'team2score',
        'bowlTeamScore',
        'awayScore',
      ],
    );
    if (team1.isEmpty && team2.isEmpty) return null;
    return {
      if (team1.isNotEmpty) 'team1': team1,
      if (team2.isNotEmpty) 'team2': team2,
    };
  }

  static List<Map<String, dynamic>> _scoreEntries(
      Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value is Map<String, dynamic>) {
        return _innsFromScoreMap(value);
      }
      if (value is List) {
        final list = <Map<String, dynamic>>[];
        for (final item in value) {
          if (item is Map<String, dynamic>) {
            list.add({
              'runs': item['runs'] ?? item['score'] ?? item['r'],
              'wickets': item['wickets'] ?? item['w'],
              'overs': item['overs'] ?? item['o'],
              'declared': item['isDeclared'] ?? item['declared'] == true,
              'inningsNumber': _inningsNumberOf(item),
            });
          }
        }
        if (list.isNotEmpty) return list;
      }
      if (value != null && value.toString().trim().isNotEmpty) {
        final text = value.toString().trim();
        final runs = RegExp(r'^(\d+)').firstMatch(text)?.group(1);
        if (runs != null) {
          return [
            {
              'runs': int.tryParse(runs) ?? runs,
              'wickets': null,
              'overs': null,
            }
          ];
        }
      }
    }
    return const [];
  }

  static List<Map<String, dynamic>> _innsFromScoreMap(
      Map<String, dynamic> map) {
    final innings = map['inngs'] ?? map['innings'] ?? map['scorecard'];
    if (innings is List) {
      return innings
          .whereType<Map<String, dynamic>>()
          .map((i) => {
                'runs': i['runs'] ?? i['score'] ?? i['r'],
                'wickets': i['wickets'] ?? i['w'],
                'overs': i['overs'] ?? i['o'],
                'declared': i['isDeclared'] ?? i['declared'] == true,
                'inningsNumber': _inningsNumberOf(i),
              })
          .toList();
    }
    // Some shapes nest innings as keyed objects (`inngs1`, `inngs2`, …) instead
    // of a list. Build the list from those, deriving the ordinal from the key
    // so chronological order survives.
    final keyed = <Map<String, dynamic>>[];
    for (final entry in map.entries) {
      final m = RegExp(r'^inn(?:g|ing)s?(\d+)$', caseSensitive: false)
          .firstMatch(entry.key);
      final v = entry.value;
      if (m != null && v is Map<String, dynamic> && v['runs'] != null) {
        keyed.add({
          'runs': v['runs'] ?? v['score'] ?? v['r'],
          'wickets': v['wickets'] ?? v['w'],
          'overs': v['overs'] ?? v['o'],
          'declared': v['isDeclared'] ?? v['declared'] == true,
          'inningsNumber': _inningsNumberOf(v) ?? int.tryParse(m.group(1)!),
        });
      }
    }
    if (keyed.isNotEmpty) return keyed;
    if (map['runs'] != null) {
      return [
        {
          'runs': map['runs'] ?? map['score'] ?? map['r'],
          'wickets': map['wickets'] ?? map['w'],
          'overs': map['overs'] ?? map['o'],
          'declared': map['isDeclared'] ?? map['declared'] == true,
          'inningsNumber': _inningsNumberOf(map),
        }
      ];
    }
    return const [];
  }

  /// The chronological innings ordinal from any of the field names the various
  /// provider shapes use. Returns null when none is present (caller then falls
  /// back to natural array position, never reordering).
  static int? _inningsNumberOf(Map<String, dynamic> raw) {
    const keys = [
      'inningsId',
      'innings_id',
      'inningsNo',
      'inningsNumber',
      'innings_number',
      'innNo',
      'inningsNbr',
      'inningOrder',
      'inningsOrder',
      'inning',
      'inningId',
      'order',
      'sequence',
      'seq',
      'num',
    ];
    for (final k in keys) {
      final n = _toInt(raw[k]);
      if (n != null && n > 0) return n;
    }
    return null;
  }

  /// Sorts a parsed innings list into chronological order using the provider
  /// ordinal when present (stable; equal/absent ordinals keep their original
  /// relative position so we never reorder a feed that gave no ordinal).
  static List<InningsScore> _orderInnings(List<InningsScore> inns) {
    final indexed = <MapEntry<int, InningsScore>>[
      for (var i = 0; i < inns.length; i++) MapEntry(i, inns[i]),
    ];
    indexed.sort((a, b) {
      // PRIMARY — physically invariant: for ONE team a CLOSED innings (all out
      // / declared) always precedes its in-progress one (you cannot begin the
      // next innings until the current closes). This dominates the provider
      // ordinal, so a feed that lists the live innings first AND numbers it by
      // raw array index (`/app/live-scores`: 224/8#1 before 438/10#2) can never
      // reverse the rendered order — the Home-hero `222/7 & 438/10*` poll bug.
      final ac = a.value.isClosed;
      final bc = b.value.isClosed;
      if (ac != bc) return ac ? -1 : 1; // closed first
      // SECONDARY — chronological provider ordinal, used to order MULTIPLE
      // closed innings (or multiple open, which shouldn't happen) correctly.
      final an = a.value.inningsNumber;
      final bn = b.value.inningsNumber;
      if (an != null && bn != null && an != bn) return an.compareTo(bn);
      // Stable fallback: preserve original relative order.
      return a.key.compareTo(b.key);
    });
    return indexed.map((e) => e.value).toList(growable: false);
  }

  static int? _toInt(dynamic v) => InningsScore._toInt(v);

  /// Parses provider innings maps into the STRUCTURED [InningsScore] list
  /// (preserving each innings' own overs) and normalizes them into chronological
  /// order ONCE (see [_orderInnings]) so a Test reads `362/10 & 391/10` with
  /// `87.1 ov • 96.2 ov`. Overs are normalized here too. The legacy flat string
  /// is then derived from this list via [_flatScoreFrom].
  static List<InningsScore> _parseInnings(dynamic innings) {
    if (innings is! List || innings.isEmpty) return const <InningsScore>[];
    final out = <InningsScore>[];
    for (final raw in innings) {
      if (raw is! Map<String, dynamic>) continue;
      final runs = raw['runs'];
      if (runs == null) continue;
      out.add(InningsScore(
        runs: InningsScore._toInt(runs),
        wickets: InningsScore._toInt(raw['wickets']),
        overs: raw['overs'] == null ? '' : normalizeOversText(raw['overs']),
        declared: raw['declared'] == true,
        inningsNumber: _inningsNumberOf(raw),
      ));
    }
    // Normalize chronological order ONCE here so every screen (Home hero, cards,
    // Match Details, minimized bar) sees the SAME order regardless of the raw
    // per-endpoint array order. Oldest innings first; the current/live innings
    // is never moved ahead of an earlier one.
    return _orderInnings(out);
  }

  /// Derives the per-innings DECLARED marker from signals every feed carries —
  /// the CORRECTED innings order plus the batting-team id — so it is never
  /// fooled by a lying positional ordinal.
  ///
  /// In a MULTI-INNINGS (Test / first-class) match an innings that is CLOSED yet
  /// NOT all out (1..9 wickets) can only have ended by a DECLARATION:
  ///   • A NON-LAST innings of a team is physically closed (the team began a
  ///     later innings), so a non-all-out close is a declaration.
  ///   • A team's LAST innings is closed when the OTHER team is now batting
  ///     (`battingTeamId` ≠ this team) — so its `d` shows while live without
  ///     mis-declaring the in-progress innings or a successful run-chase.
  /// Limited-overs matches (each side a single innings) are never touched, so a
  /// T20 `154/8` never gains a spurious `d`. An explicit feed flag always wins.
  static (List<InningsScore>, List<InningsScore>) _deriveDeclared(
    List<InningsScore> t1,
    List<InningsScore> t2, {
    required String t1Id,
    required String t2Id,
    required String battingTeamId,
    required bool finished,
  }) {
    final isMultiInnings = t1.where((i) => i.hasRuns).length > 1 ||
        t2.where((i) => i.hasRuns).length > 1;
    if (!isMultiInnings) return (t1, t2);

    List<InningsScore> mark(List<InningsScore> list, String teamId) {
      final scoredIdx = <int>[
        for (var i = 0; i < list.length; i++)
          if (list[i].hasRuns) i,
      ];
      if (scoredIdx.isEmpty) return list;
      final lastScored = scoredIdx.last;
      final otherTeamBatting = battingTeamId.isNotEmpty &&
          teamId.isNotEmpty &&
          battingTeamId != teamId &&
          !finished;
      return [
        for (var i = 0; i < list.length; i++)
          if (!list[i].hasRuns ||
              list[i].declared ||
              list[i].wickets == null ||
              list[i].wickets! >= 10) // all out / already declared / no wkts
            list[i]
          else if (i != lastScored)
            list[i].copyWith(declared: true) // earlier innings: physically closed
          else if (otherTeamBatting)
            list[i].copyWith(declared: true) // last innings, other side batting
          else
            list[i],
      ];
    }

    return (mark(t1, t1Id), mark(t2, t2Id));
  }

  /// Keeps a DECLARED marker stable across a poll. The lightweight live-score
  /// feed can momentarily omit `isDeclared`; a declared innings is CLOSED so its
  /// runs/wickets are final — if a fresh innings matches a previously-declared
  /// one on runs+wickets (and innings ordinal when both carry it) it is still
  /// declared. Prevents the `d` from blinking out for one poll tick.
  static List<InningsScore> _stickyDeclared(
      List<InningsScore> prev, List<InningsScore> fresh) {
    if (prev.isEmpty) return fresh;
    return [
      for (final f in fresh)
        if (f.declared)
          f
        else
          () {
            for (final p in prev) {
              if (!p.declared) continue;
              final sameScore = p.runs == f.runs && p.wickets == f.wickets;
              final ordinalsKnown =
                  p.inningsNumber != null && f.inningsNumber != null;
              final sameOrdinal = p.inningsNumber == f.inningsNumber;
              if (sameScore && (!ordinalsKnown || sameOrdinal)) {
                return f.copyWith(declared: true);
              }
            }
            return f;
          }(),
    ];
  }

  /// Restores a structured innings list previously written by [toCacheJson].
  /// Re-applies [_orderInnings] so a list cached in a reversed/legacy order
  /// (before deterministic ordering existed) is corrected on restore — a stale
  /// cache can never resurrect the `215/7 & 438/10*` reversal.
  static List<InningsScore> _inningsFromCache(dynamic value) {
    if (value is! List || value.isEmpty) return const <InningsScore>[];
    final list = value
        .whereType<Map<String, dynamic>>()
        .map(InningsScore.fromJson)
        .toList();
    return _orderInnings(list);
  }

  /// Builds the legacy flat score string from the already-ordered structured
  /// innings (oldest innings first), e.g. `362/10 & 391/10 (96.2 ov)`. Only the
  /// current (last) innings carries overs to keep the line short. Unit is always
  /// lowercase `ov`. Used for change-detection and the legacy `scoreLine`.
  static String _flatScoreFrom(List<InningsScore> innings) {
    final scored = innings.where((i) => i.hasRuns).toList(growable: false);
    if (scored.isEmpty) return '';
    final scores = scored.map((i) => i.scoreText).join(' & ');
    final lastOvers = scored.last.oversText;
    return lastOvers.isEmpty ? scores : '$scores ($lastOvers ov)';
  }

  static DateTime? _parseStart(String value) {
    if (value.isEmpty) return null;
    // ISO-8601 (recent/live/upcoming).
    final iso = DateTime.tryParse(value);
    if (iso != null) return iso;
    // Epoch millis as a string (schedule endpoint).
    final ms = int.tryParse(value);
    if (ms != null && ms > 1000000000000) {
      return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    }
    return null;
  }
}

class _TeamData {
  const _TeamData({
    required this.name,
    required this.short,
    required this.logo,
    required this.innings,
    this.id = '',
  });
  final String name;
  final String short;
  final String? logo;
  final List<dynamic> innings;

  /// Provider team id (e.g. Cricbuzz `teamId`). Used to resolve which side is
  /// currently batting from the match-level `curr_bat_team_id` signal. Empty
  /// when the feed omitted it.
  final String id;
}

/// A bucket of fixtures for a single calendar day in the schedule.
class ScheduleDay {
  const ScheduleDay({
    required this.label,
    required this.date,
    required this.matches,
  });

  /// Human-readable day label as returned by the API, e.g. `SAT, MAY 30 2026`.
  final String label;

  /// Parsed [DateTime] when [label] is recognisable.
  final DateTime? date;

  /// All matches starting on this day.
  final List<CricketMatch> matches;

  /// Short label like `Mon` for the date chip.
  String get dayShort {
    if (date != null) {
      const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return names[date!.weekday - 1];
    }
    final parts = label.split(',');
    if (parts.isEmpty) return label;
    return parts.first
        .trim()
        .substring(0, parts.first.trim().length.clamp(0, 3));
  }

  /// Numeric day-of-month for the date chip.
  String get dayNumber {
    if (date != null) return date!.day.toString();
    // Fall back to the second token, e.g. "MAY 30 2026" → "30".
    final after = label.contains(',') ? label.split(',').last.trim() : label;
    final match = RegExp(r'(\d{1,2})').firstMatch(after);
    return match?.group(1) ?? '';
  }

  /// `May 30` style label for the section heading.
  String get dayDescriptive {
    if (date != null) {
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
      return '${months[date!.month - 1]} ${date!.day}';
    }
    return label;
  }

  factory ScheduleDay.fromJson(Map<String, dynamic> json) {
    final label = json['date']?.toString() ?? '';
    final matches = (json['matches'] is List)
        ? (json['matches'] as List)
            .whereType<Map<String, dynamic>>()
            .map(CricketMatch.fromJson)
            .toList()
        : <CricketMatch>[];
    return ScheduleDay(
      label: label,
      date: _parseDayLabel(label),
      matches: matches,
    );
  }

  static DateTime? _parseDayLabel(String label) {
    // The schedule API returns labels like `SAT, MAY 30 2026`.
    final cleaned = label.replaceFirst(RegExp(r'^[A-Z]{3},\s*'), '');
    const months = {
      'JAN': 1,
      'FEB': 2,
      'MAR': 3,
      'APR': 4,
      'MAY': 5,
      'JUN': 6,
      'JUL': 7,
      'AUG': 8,
      'SEP': 9,
      'OCT': 10,
      'NOV': 11,
      'DEC': 12,
    };
    final parts =
        cleaned.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length < 2) return null;
    final month = months[parts[0].toUpperCase()];
    if (month == null) return null;
    final day = int.tryParse(parts[1]);
    if (day == null) return null;
    final year = parts.length >= 3
        ? int.tryParse(parts[2]) ?? DateTime.now().year
        : DateTime.now().year;
    return DateTime(year, month, day);
  }
}
