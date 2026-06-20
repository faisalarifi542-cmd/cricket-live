import 'package:flutter/material.dart';


class TeamInfo {
  const TeamInfo({
    required this.code,
    required this.name,
    required this.shortName,
    required this.color,
    this.asset,
    this.emoji,
  });

  final String code;
  final String name;
  final String shortName;
  final Color color;
  final String? asset;
  final String? emoji;
}

class PlayerInfo {
  const PlayerInfo({
    required this.name,
    required this.role,
    required this.team,
    this.subtitle,
    this.asset,
    this.badge,
    this.order,
    this.stat,
    this.secondaryStat,
  });

  final String name;
  final String role;
  final TeamInfo team;
  final String? subtitle;
  final String? asset;
  final String? badge;
  final int? order;
  final String? stat;
  final String? secondaryStat;
}

class RankingPlayer {
  const RankingPlayer(
      this.rank, this.name, this.country, this.asset, this.rating,
      {this.move = 0, this.flag = ''});
  final int rank;
  final String name;
  final String country;
  final String asset;
  final int rating;
  final int move;
  final String flag;
}

class VideoHighlight {
  const VideoHighlight({
    required this.title,
    required this.match,
    required this.views,
    required this.duration,
    required this.tag,
    this.asset,
    this.featured = false,
  });

  final String title;
  final String match;
  final String views;
  final String duration;
  final String tag;
  final String? asset;
  final bool featured;
}

class SeriesMatchRow {
  const SeriesMatchRow({
    required this.label,
    required this.status,
    required this.left,
    required this.right,
    required this.date,
    required this.venue,
    required this.trailing,
  });

  final String label;
  final String status;
  final TeamInfo left;
  final TeamInfo right;
  final String date;
  final String venue;
  final String trailing;
}

class SeriesOverviewStat {
  const SeriesOverviewStat({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;
}

class AppData {
  static const TeamInfo india = TeamInfo(
    code: 'IND',
    name: 'India',
    shortName: 'IND',
    color: Color(0xff22d3ee),
  );
  static const TeamInfo australia = TeamInfo(
    code: 'AUS',
    name: 'Australia',
    shortName: 'AUS',
    color: Color(0xfff59e0b),
  );
  static const TeamInfo england = TeamInfo(
    code: 'ENG',
    name: 'England',
    shortName: 'ENG',
    color: Color(0xff60a5fa),
  );
  static const TeamInfo westIndies = TeamInfo(
    code: 'WI',
    name: 'West Indies',
    shortName: 'WI',
    color: Color(0xfff97316),
  );
  static const TeamInfo pakistan = TeamInfo(
    code: 'PAK',
    name: 'Pakistan',
    shortName: 'PAK',
    color: Color(0xff34d399),
  );
  static const TeamInfo bangladesh = TeamInfo(
    code: 'BAN',
    name: 'Bangladesh',
    shortName: 'BAN',
    color: Color(0xfff43f5e),
  );
  static const TeamInfo newZealand = TeamInfo(
    code: 'NZ',
    name: 'New Zealand',
    shortName: 'NZ',
    color: Color(0xff38bdf8),
  );

  static const List<String> searchTopics = <String>[];
  static const List<String> trendingPlayers = <String>[];
  static const List<VideoHighlight> topMoments = <VideoHighlight>[];
  static const List<SeriesMatchRow> seriesUpcomingRows = <SeriesMatchRow>[];
  static const List<SeriesMatchRow> seriesCompletedRows = <SeriesMatchRow>[];
  static const List<PlayerInfo> indiaSquadTop = <PlayerInfo>[];
  static const List<PlayerInfo> indiaSquadMiddle = <PlayerInfo>[];
  static const List<PlayerInfo> indiaAllRounders = <PlayerInfo>[];
  static const List<PlayerInfo> indiaBowlers = <PlayerInfo>[];
  static const List<PlayerInfo> indiaReserves = <PlayerInfo>[];
  static const List<PlayerInfo> topRunScorers = <PlayerInfo>[];
  static const List<PlayerInfo> topWickets = <PlayerInfo>[];
  static const List<SeriesOverviewStat> seriesOverviewStats =
      <SeriesOverviewStat>[];
}

class HeroFixture {
  const HeroFixture({
    required this.badge,
    required this.series,
    required this.date,
    required this.time,
    required this.left,
    required this.right,
    required this.centerTitle,
    required this.venue,
    required this.button,
    this.result,
    this.rightMeta,
    this.leftMeta,
  });

  final String badge;
  final String series;
  final String date;
  final String time;
  final TeamInfo left;
  final TeamInfo right;
  final String centerTitle;
  final String venue;
  final String button;
  final String? result;
  final String? rightMeta;
  final String? leftMeta;
}

class CompactFixture {
  const CompactFixture({
    required this.series,
    required this.subtitle,
    required this.left,
    required this.right,
    required this.date,
    required this.venue,
    required this.status,
    required this.action,
    this.leftScore,
    this.rightScore,
    this.result,
    this.playerOfMatch,
    this.playerStat,
  });

  final String series;
  final String subtitle;
  final TeamInfo left;
  final TeamInfo right;
  final String date;
  final String venue;
  final String status;
  final String action;

  /// Formatted score line for the left team, e.g. `158/3 (38.4 OV)`. Empty
  /// for upcoming matches.
  final String? leftScore;

  /// Formatted score line for the right team.
  final String? rightScore;

  final String? result;
  final String? playerOfMatch;
  final String? playerStat;
}

class NewsArticle {
  const NewsArticle({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.source,
    required this.date,
    required this.tag,
    this.body,
    this.asset,
    this.featured = false,
    this.breaking = false,
    this.timeAgo,
    this.context,
    this.storyType,
  });

  final String id;
  final String title;
  final String subtitle;
  final String source;
  final String date;
  final String tag;
  final String? body;
  final String? asset;
  final bool featured;
  final bool breaking;
  final String? timeAgo;
  final String? context;
  final String? storyType;
}
