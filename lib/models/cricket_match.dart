import 'package:flutter/material.dart';

import '../models.dart';

class CricketMatch {
  const CricketMatch({
    required this.id,
    required this.title,
    required this.series,
    required this.status,
    required this.venue,
    required this.startTime,
    required this.teamA,
    required this.teamB,
    this.score,
  });

  final String id;
  final String title;
  final String series;
  final String status;
  final String venue;
  final String startTime;
  final String teamA;
  final String teamB;
  final String? score;

  factory CricketMatch.fromJson(dynamic value) {
    final json = value is Map<String, dynamic> ? value : <String, dynamic>{};
    final teams = _extractTeams(json);
    return CricketMatch(
      id: _firstString(json, const ['matchId', 'id', 'match_id']),
      title: _firstString(json, const ['title', 'matchTitle', 'name'], fallback: '${teams.$1} vs ${teams.$2}'),
      series: _firstString(json, const ['series', 'seriesName', 'series_name'], fallback: 'Cricket'),
      status: _firstString(json, const ['status', 'matchStatus', 'state'], fallback: 'Upcoming'),
      venue: _firstString(json, const ['venue', 'ground', 'location'], fallback: 'Unknown'),
      startTime: _firstString(json, const ['startTime', 'dateTimeGMT', 'date', 'time'], fallback: ''),
      teamA: teams.$1,
      teamB: teams.$2,
      score: _firstString(json, const ['score', 'liveScore'], fallback: ''),
    );
  }

  CompactFixture toCompactFixture({required bool finished}) {
    return CompactFixture(
      series: series,
      subtitle: title,
      left: _team(teamA, const Color(0xff22d3ee)),
      right: _team(teamB, const Color(0xfff59e0b)),
      date: startTime.isEmpty ? status : startTime,
      venue: venue,
      status: status,
      action: finished ? 'Scorecard' : 'View Match',
      result: score?.isNotEmpty == true ? score : null,
    );
  }

  HeroFixture toHeroFixture({required bool live, required bool finished}) {
    return HeroFixture(
      badge: live ? 'LIVE' : finished ? 'RESULT' : 'UPCOMING',
      series: series,
      date: startTime.isEmpty ? status : startTime,
      time: score?.isNotEmpty == true ? score! : status,
      left: _team(teamA, const Color(0xff22d3ee)),
      right: _team(teamB, const Color(0xfff59e0b)),
      centerTitle: 'VS',
      venue: venue,
      button: live ? 'Watch Live' : finished ? 'Scorecard' : 'Remind Me',
      result: finished ? status : null,
    );
  }

  static TeamInfo _team(String name, Color color) {
    final clean = name.trim().isEmpty ? 'TBD' : name.trim();
    final words = clean.split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();
    final shortLength = words.first.length.clamp(1, 3).toInt();
    final short = words.length == 1
        ? words.first.substring(0, shortLength).toUpperCase()
        : words.take(2).map((word) => word[0]).join().toUpperCase();
    return TeamInfo(
      code: short,
      name: clean,
      shortName: short,
      color: color,
    );
  }

  static (String, String) _extractTeams(Map<String, dynamic> json) {
    final teamA = _firstString(json, const ['teamA', 'team1', 'homeTeam', 'batTeam', 'team1Name'], fallback: 'TBD');
    final teamB = _firstString(json, const ['teamB', 'team2', 'awayTeam', 'bowlTeam', 'team2Name'], fallback: 'TBD');
    return (_teamName(teamA), _teamName(teamB));
  }

  static String _teamName(String value) {
    if (!value.trim().startsWith('{')) return value;
    return value;
  }

  static String _firstString(
    Map<String, dynamic> json,
    List<String> keys, {
    String fallback = '',
  }) {
    for (final key in keys) {
      final value = json[key];
      if (value == null) continue;
      if (value is Map && value['name'] != null) return value['name'].toString();
      if (value is Map && value['shortName'] != null) return value['shortName'].toString();
      if (value is List && value.isNotEmpty) return value.first.toString();
      final text = value.toString();
      if (text.trim().isNotEmpty) return text;
    }
    return fallback;
  }
}
