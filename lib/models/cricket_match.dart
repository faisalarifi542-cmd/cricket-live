import 'package:flutter/material.dart';

import '../models.dart';

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
    required this.isLive,
    required this.isUpcoming,
    required this.isFinished,
    this.score,
  });

  final String id;
  final String title;
  final String series;
  final String matchDesc;
  final String status;
  final String statusText;
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
  final bool isLive;
  final bool isUpcoming;
  final bool isFinished;
  final String? score;

  factory CricketMatch.fromJson(dynamic value) {
    final json = value is Map<String, dynamic> ? value : <String, dynamic>{};
    final t1 = _team(json, const ['team1', 'teamA', 'homeTeam', 'batTeam']);
    final t2 = _team(json, const ['team2', 'teamB', 'awayTeam', 'bowlTeam']);
    final venue = _venue(json);
    final status = _str(json, const ['status', 'matchStatus', 'state'], fallback: 'upcoming').toLowerCase();
    final statusText = _str(
      json,
      const ['status_text', 'statusText', 'short_status', 'shortStatus'],
      fallback: '',
    );
    final matchDesc = _str(
      json,
      const ['match_desc', 'matchDesc', 'match_number', 'matchNumber', 'matchDescription', 'title'],
      fallback: '',
    );
    final score = _scoreMap(json);
    final t1Score = _formatTeamScore(score?['team1'] ?? score?['teamA'] ?? t1.innings);
    final t2Score = _formatTeamScore(score?['team2'] ?? score?['teamB'] ?? t2.innings);
    final start = _str(
      json,
      const ['start_time', 'startTime', 'dateTimeGMT', 'date', 'time'],
      fallback: '',
    );
    final startDt = _parseStart(start);
    final isLive = status == 'live' || status == 'in_progress';
    final isFinished = status == 'completed' ||
        status == 'recent' ||
        status == 'finished' ||
        status == 'result' ||
        status == 'abandoned';
    final isUpcoming = !isLive && !isFinished;
    final title = _str(json, const ['title', 'matchTitle', 'name'], fallback: '').isNotEmpty
        ? _str(json, const ['title', 'matchTitle', 'name'])
        : (t1.short.isNotEmpty && t2.short.isNotEmpty
            ? '${t1.short} vs ${t2.short}'
            : '${t1.name} vs ${t2.name}');
    final result = _str(json, const ['result', 'resultText', 'short_status', 'shortStatus'], fallback: '');
    return CricketMatch(
      id: _str(json, const ['match_id', 'matchId', 'id'], fallback: ''),
      title: title,
      series: _str(json, const ['series_name', 'seriesName', 'series', 'tournament'], fallback: 'Cricket'),
      matchDesc: matchDesc,
      status: status,
      statusText: statusText,
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
      isLive: isLive,
      isUpcoming: isUpcoming,
      isFinished: isFinished,
      score: t1Score.isEmpty && t2Score.isEmpty ? null : '$t1Score vs $t2Score',
    );
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
      pieces.add('${teamAShort.isNotEmpty ? teamAShort : teamA} $teamAScoreText');
    }
    if (teamBScoreText.isNotEmpty) {
      pieces.add('${teamBShort.isNotEmpty ? teamBShort : teamB} $teamBScoreText');
    }
    return pieces.join('  •  ');
  }

  CompactFixture toCompactFixture({required bool finished}) {
    final dateLine = _dateLine();
    final venueLabel = finished
        ? (resultText.isNotEmpty ? resultText : (statusText.isNotEmpty ? statusText : venue))
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
      result: finished ? (resultText.isNotEmpty ? resultText : statusText) : null,
      playerOfMatch: null,
      playerStat: null,
    );
  }

  HeroFixture toHeroFixture({required bool live, required bool finished}) {
    final dateLine = _dateLine();
    final heroLeftScore = teamAScoreText.isNotEmpty ? teamAScoreText : (live ? 'Yet to bat' : '');
    final heroRightScore = teamBScoreText.isNotEmpty ? teamBScoreText : (live ? 'Yet to bat' : '');
    final timeLine = live
        ? (statusText.isNotEmpty ? statusText : 'Live')
        : finished
            ? (resultText.isNotEmpty
                ? resultText
                : (statusText.isNotEmpty ? statusText : 'Finished'))
            : (statusText.isNotEmpty ? statusText : (dateLine.isEmpty ? 'Upcoming' : dateLine));
    return HeroFixture(
      badge: live ? 'LIVE' : (finished ? 'RESULT' : 'UPCOMING'),
      series: series,
      date: dateLine.isNotEmpty ? dateLine : (finished ? (resultText.isNotEmpty ? resultText : 'Finished') : 'Upcoming'),
      time: timeLine,
      left: _teamInfo(teamA, teamAShort, teamALogo, const Color(0xff22d3ee)),
      right: _teamInfo(teamB, teamBShort, teamBLogo, const Color(0xfff59e0b)),
      centerTitle: 'VS',
      venue: venue,
      button: live ? 'Watch Live' : (finished ? 'Scorecard' : 'Remind Me'),
      result: finished ? (resultText.isNotEmpty ? resultText : statusText) : null,
      leftMeta: (live || finished) && heroLeftScore.isNotEmpty ? heroLeftScore : null,
      rightMeta: (live || finished) && heroRightScore.isNotEmpty ? heroRightScore : null,
    );
  }

  String _dateLine() {
    final dt = startDateTime;
    if (dt == null) return statusText.isNotEmpty ? statusText : '';
    final local = dt.toLocal();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    return '${months[local.month - 1]} ${local.day} • $hh:$mm';
  }

  static TeamInfo _teamInfo(String name, String short, String? logo, Color color) {
    final fullName = name.trim().isEmpty ? 'TBD' : name.trim();
    final shortName = short.trim().isEmpty
        ? _initials(fullName)
        : short.trim().toUpperCase();
    return TeamInfo(
      code: shortName,
      name: fullName,
      shortName: shortName,
      color: color,
      asset: logo,
    );
  }

  static String _initials(String value) {
    final cleaned = value.trim();
    if (cleaned.isEmpty) return 'TBD';
    final parts = cleaned.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length == 1) {
      final len = parts.first.length.clamp(1, 3);
      return parts.first.substring(0, len).toUpperCase();
    }
    return parts.take(2).map((p) => p[0]).join().toUpperCase();
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
        final name = _str(value, const ['name', 'teamName', 'fullName'], fallback: '');
        final short = _str(value, const ['short_name', 'shortName', 'code', 'abbr'], fallback: '');
        final logo = _str(value, const ['logo_url', 'logoUrl', 'logo', 'image', 'imageUrl'], fallback: '');
        final innings = value['innings'];
        return _TeamData(
          name: name.isNotEmpty ? name : (short.isNotEmpty ? short : 'TBD'),
          short: short.isNotEmpty ? short : (name.isNotEmpty ? _initials(name) : 'TBD'),
          logo: logo.isEmpty ? null : logo,
          innings: innings is List ? innings : const [],
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
    final flatName = _str(json, [for (final k in keys) '${k}_name', ...keys.map((k) => '${k}Name')]);
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
    final value = json['score'];
    if (value is Map<String, dynamic>) return value;
    return null;
  }

  static String _formatTeamScore(dynamic innings) {
    if (innings is! List || innings.isEmpty) return '';
    final parts = <String>[];
    for (final raw in innings) {
      if (raw is! Map<String, dynamic>) continue;
      final runs = raw['runs'];
      if (runs == null) continue;
      final wickets = raw['wickets'];
      final overs = raw['overs'];
      final declared = raw['declared'] == true;
      final score = wickets == null ? '$runs' : '$runs/$wickets';
      final oversText = overs == null ? '' : ' (${_formatOvers(overs)} OV)';
      final declaredText = declared ? 'd' : '';
      // For multi-innings (tests) show the latest with overs; previous as
      // just `runs/wkts`.
      parts.add(parts.isEmpty || raw == innings.last
          ? '$score$declaredText$oversText'
          : '$score$declaredText');
    }
    if (parts.isEmpty) return '';
    if (parts.length == 1) return parts.first;
    // Combine multiple innings (test matches): "490/8d & 232/10 (63.2 OV)"
    return parts.reversed.join(' & ');
  }

  static String _formatOvers(dynamic overs) {
    if (overs is num) {
      if (overs == overs.toInt()) return overs.toInt().toString();
      return overs.toString();
    }
    return overs.toString();
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
  });
  final String name;
  final String short;
  final String? logo;
  final List<dynamic> innings;
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
    return parts.first.trim().substring(0, parts.first.trim().length.clamp(0, 3));
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
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
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
      'JAN': 1, 'FEB': 2, 'MAR': 3, 'APR': 4, 'MAY': 5, 'JUN': 6,
      'JUL': 7, 'AUG': 8, 'SEP': 9, 'OCT': 10, 'NOV': 11, 'DEC': 12,
    };
    final parts = cleaned.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length < 2) return null;
    final month = months[parts[0].toUpperCase()];
    if (month == null) return null;
    final day = int.tryParse(parts[1]);
    if (day == null) return null;
    final year = parts.length >= 3 ? int.tryParse(parts[2]) ?? DateTime.now().year : DateTime.now().year;
    return DateTime(year, month, day);
  }
}
