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
    required this.title,
    required this.subtitle,
    required this.source,
    required this.date,
    required this.tag,
    this.asset,
    this.featured = false,
    this.breaking = false,
    this.timeAgo,
  });

  final String title;
  final String subtitle;
  final String source;
  final String date;
  final String tag;
  final String? asset;
  final bool featured;
  final bool breaking;
  final String? timeAgo;
}
