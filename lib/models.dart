import 'package:flutter/material.dart';

class Team {
  const Team(this.short, this.name, this.asset, this.color);
  final String short;
  final String name;
  final String asset;
  final Color color;
}

class CricketMatch {
  const CricketMatch({
    required this.series,
    required this.matchNo,
    required this.left,
    required this.right,
    required this.leftScore,
    this.leftOvers = '',
    this.rightScore = 'Yet to bat',
    required this.status,
    this.isLive = true,
  });
  final String series;
  final String matchNo;
  final Team left;
  final Team right;
  final String leftScore;
  final String leftOvers;
  final String rightScore;
  final String status;
  final bool isLive;
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

class AppData {
  static const nz =
      Team('NZ', 'New Zealand', 'assets/images/team_nz.png', Color(0xff083890));
  static const wi =
      Team('WI', 'West Indies', 'assets/images/team_wi.png', Color(0xff8a1238));
  static const ban = Team(
      'BAN', 'Bangladesh', 'assets/images/team_ban.png', Color(0xff08784f));
  static const ire =
      Team('IRE', 'Ireland', 'assets/images/team_ire.png', Color(0xff13753c));
  static const vic =
      Team('VIC', 'Victoria', 'assets/images/team_vic.png', Color(0xff00663e));
  static const wa = Team('WA', 'Western Australia', 'assets/images/team_wa.png',
      Color(0xffffc83d));
  static const qld = Team(
      'QLD', 'Queensland', 'assets/images/team_qld.png', Color(0xff8c1538));
  static const sa = Team(
      'SA', 'South Australia', 'assets/images/team_sa.png', Color(0xffd23c27));
  static const dcp = Team(
      'DCP', 'Dubai Capitals', 'assets/images/team_dcp.png', Color(0xff5523a9));
  static const dv = Team(
      'DV', 'Desert Vipers', 'assets/images/team_dv.png', Color(0xff084bbe));
  static const brt = Team('BRT', 'Biratnagar Kings',
      'assets/images/team_brt.png', Color(0xffc94575));
  static const cgr = Team(
      'CGR', 'Chitwan Rhinos', 'assets/images/team_cgr.png', Color(0xff8cc827));

  static final liveMatches = <CricketMatch>[
    const CricketMatch(
        series: 'WEST INDIES TOUR OF NEW ZEALAND, 2025',
        matchNo: '1st Test • Day 1',
        left: nz,
        right: wi,
        leftScore: '158/3',
        leftOvers: '(38.4 OV)',
        rightScore: 'Yet to bat',
        status: 'Day 1: Play stopped due to rain'),
    const CricketMatch(
        series: 'AUSTRALIA DOMESTIC ONE-DAY CUP 2025-26',
        matchNo: '15th Match',
        left: vic,
        right: wa,
        leftScore: '32/1',
        leftOvers: '(5.3 OV)',
        rightScore: 'Yet to bat',
        status: 'Western Australia opt to bowl'),
    const CricketMatch(
        series: 'AUSTRALIA DOMESTIC ONE-DAY CUP 2025-26',
        matchNo: '13th Match',
        left: qld,
        right: sa,
        leftScore: '210/6',
        leftOvers: '(36.0 OV)',
        rightScore: 'Yet to bat',
        status: 'South Australia won the toss & chose to field'),
  ];

  static final upcomingMatches = <CricketMatch>[
    const CricketMatch(
        series: 'IRELAND TOUR OF BANGLADESH, 2025',
        matchNo: '3rd T20I',
        left: ban,
        right: ire,
        leftScore: '',
        rightScore: '',
        status: 'Starts at Dec 02, 08:00 GMT',
        isLive: false),
    const CricketMatch(
        series: 'INTERNATIONAL LEAGUE T20, 2025-26',
        matchNo: '1st Match',
        left: dcp,
        right: dv,
        leftScore: '',
        rightScore: '',
        status: 'Starts at Dec 02, 14:30 GMT',
        isLive: false),
    const CricketMatch(
        series: 'NEPAL PREMIER LEAGUE 2025',
        matchNo: 'Match 2',
        left: brt,
        right: cgr,
        leftScore: '',
        rightScore: '',
        status: 'Starts at Dec 02, 09:15 GMT',
        isLive: false),
  ];

  static const rankings = <RankingPlayer>[
    RankingPlayer(
        1, 'Joe Root', 'England', 'assets/images/player_joe_root.png', 908,
        flag: '🏴'),
    RankingPlayer(2, 'Harry Brook', 'England',
        'assets/images/player_harry_brook.png', 868,
        move: 1, flag: '🏴'),
    RankingPlayer(3, 'Kane Williamson', 'New Zealand',
        'assets/images/player_kane_williamson.png', 850,
        move: -1, flag: '🇳🇿'),
    RankingPlayer(4, 'Steven Smith', 'Australia',
        'assets/images/player_steven_smith.png', 816,
        flag: '🇦🇺'),
    RankingPlayer(5, 'Yashasvi Jaiswal', 'India',
        'assets/images/player_yashasvi_jaiswal.png', 791,
        move: 2, flag: '🇮🇳'),
    RankingPlayer(6, 'Kamindu Mendis', 'Sri Lanka',
        'assets/images/player_kamindu_mendis.png', 781,
        move: 1, flag: '🇱🇰'),
  ];

  static const homeRankings = <RankingPlayer>[
    RankingPlayer(1, 'Rohit Sharma', 'India',
        'assets/images/player_rohit_sharma.png', 781,
        flag: '🇮🇳'),
    RankingPlayer(2, 'Ibrahim Zadran', 'Afghanistan',
        'assets/images/player_ibrahim_zadran.png', 774,
        flag: '🇦🇫'),
    RankingPlayer(3, 'Daryl Mitchell', 'New Zealand',
        'assets/images/player_daryl_mitchell.png', 746,
        flag: '🇳🇿'),
  ];
}
