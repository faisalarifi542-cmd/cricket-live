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

class VideoHighlight {
  const VideoHighlight({
    required this.title,
    required this.match,
    required this.duration,
    required this.views,
    required this.tag,
    this.asset,
    this.featured = false,
  });

  final String title;
  final String match;
  final String duration;
  final String views;
  final String tag;
  final String? asset;
  final bool featured;
}

class SeriesMatchRow {
  const SeriesMatchRow({
    required this.label,
    required this.left,
    required this.right,
    required this.date,
    required this.venue,
    required this.status,
    required this.trailing,
  });

  final String label;
  final TeamInfo left;
  final TeamInfo right;
  final String date;
  final String venue;
  final String status;
  final String trailing;
}

class StatLine {
  const StatLine(this.label, this.value,
      {this.subtitle, this.icon = Icons.star_rounded});

  final String label;
  final String value;
  final String? subtitle;
  final IconData icon;
}

// ⚠️ WARNING: This class contains MOCK/DEMO data for UI development only.
// DO NOT use AppData in production code paths.
// Production UI must use real API data from CricketRepository.
// This data is only for:
// - UI component previews/storybook
// - Debug/demo mode with kDebugMode guards
// - Unit tests
class AppData {
  static const india = TeamInfo(
    code: 'IND',
    name: 'India',
    shortName: 'India',
    color: Color(0xff1c77ff),
    emoji: '🇮🇳',
  );
  static const australia = TeamInfo(
    code: 'AUS',
    name: 'Australia',
    shortName: 'Australia',
    color: Color(0xfff4c840),
    emoji: '🇦🇺',
  );
  static const england = TeamInfo(
    code: 'ENG',
    name: 'England',
    shortName: 'England',
    color: Color(0xfff2f5fa),
    emoji: '🏴',
  );
  static const newZealand = TeamInfo(
    code: 'NZ',
    name: 'New Zealand',
    shortName: 'New Zealand',
    color: Color(0xff0e3a96),
    asset: 'assets/images/team_nz.png',
    emoji: '🇳🇿',
  );
  static const westIndies = TeamInfo(
    code: 'WI',
    name: 'West Indies',
    shortName: 'West Indies',
    color: Color(0xff7e173d),
    asset: 'assets/images/team_wi.png',
    emoji: '🇼🇸',
  );
  static const pakistan = TeamInfo(
    code: 'PAK',
    name: 'Pakistan',
    shortName: 'Pakistan',
    color: Color(0xff1b7c4f),
    emoji: '🇵🇰',
  );
  static const bangladesh = TeamInfo(
    code: 'BAN',
    name: 'Bangladesh',
    shortName: 'Bangladesh',
    color: Color(0xff0c7c4d),
    asset: 'assets/images/team_ban.png',
    emoji: '🇧🇩',
  );
  static const southAfrica = TeamInfo(
    code: 'SA',
    name: 'South Africa',
    shortName: 'South Africa',
    color: Color(0xff2d9f74),
    emoji: '🇿🇦',
  );
  static const sriLanka = TeamInfo(
    code: 'SL',
    name: 'Sri Lanka',
    shortName: 'Sri Lanka',
    color: Color(0xffd3a53f),
    emoji: '🇱🇰',
  );
  static const victoria = TeamInfo(
    code: 'VIC',
    name: 'Victoria',
    shortName: 'Victoria',
    color: Color(0xff1f5e49),
    asset: 'assets/images/team_vic.png',
  );
  static const westernAustralia = TeamInfo(
    code: 'WA',
    name: 'Western Australia',
    shortName: 'Western Australia',
    color: Color(0xfff2c21f),
    asset: 'assets/images/team_wa.png',
  );
  static const sunrisers = TeamInfo(
    code: 'SUN',
    name: 'Sunrisers',
    shortName: 'Sunrisers',
    color: Color(0xfffb7d34),
  );
  static const durban = TeamInfo(
    code: 'DSG',
    name: 'Durban Super Giants',
    shortName: 'Durban',
    color: Color(0xff3459f6),
  );
  static const qalandars = TeamInfo(
    code: 'LQ',
    name: 'Lahore Qalandars',
    shortName: 'Lahore',
    color: Color(0xff21a95b),
  );
  static const trinbago = TeamInfo(
    code: 'TKR',
    name: 'Trinbago Knight Riders',
    shortName: 'Trinbago',
    color: Color(0xff861734),
  );
  static const rcb = TeamInfo(
    code: 'RCB',
    name: 'Royal Challengers',
    shortName: 'RCB',
    color: Color(0xffc4252d),
  );
  static const mi = TeamInfo(
    code: 'MI',
    name: 'Mumbai Indians',
    shortName: 'MI',
    color: Color(0xff2c5de5),
  );

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

  static const topRunScorers = <PlayerInfo>[
    PlayerInfo(
        name: 'Yashasvi Jaiswal',
        role: 'BAT',
        team: india,
        asset: 'assets/images/player_yashasvi_jaiswal.png',
        stat: '391',
        secondaryStat: 'Runs'),
    PlayerInfo(
        name: 'Steve Smith',
        role: 'BAT',
        team: australia,
        asset: 'assets/images/player_steven_smith.png',
        stat: '317',
        secondaryStat: 'Runs'),
    PlayerInfo(
        name: 'Virat Kohli',
        role: 'BAT',
        team: india,
        asset: 'assets/images/player_rohit_sharma.png',
        stat: '280',
        secondaryStat: 'Runs'),
  ];

  static const topWickets = <PlayerInfo>[
    PlayerInfo(
        name: 'Jasprit Bumrah',
        role: 'BOWL',
        team: india,
        asset: 'assets/images/player_rohit_sharma.png',
        stat: '21',
        secondaryStat: 'Wickets'),
    PlayerInfo(
        name: 'Pat Cummins',
        role: 'BOWL',
        team: australia,
        asset: 'assets/images/player_steven_smith.png',
        stat: '17',
        secondaryStat: 'Wickets'),
    PlayerInfo(
        name: 'Mohammed Siraj',
        role: 'BOWL',
        team: india,
        asset: 'assets/images/player_daryl_mitchell.png',
        stat: '14',
        secondaryStat: 'Wickets'),
  ];

  static const upcomingHero = HeroFixture(
    badge: 'UPCOMING',
    series: "ICC MEN'S ODI SERIES",
    date: 'Sun, 8 Jun 2025',
    time: '3:30 PM IST',
    left: india,
    right: australia,
    centerTitle: 'VS',
    venue: 'Narendra Modi Stadium\nAhmedabad, India',
    button: 'Set Reminder',
  );

  static const finishedHero = HeroFixture(
    badge: 'FINISHED',
    series: "ICC MEN'S ODI SERIES",
    date: '8 Jun 2025 • Ahmedabad',
    time: 'India 321/4 • Australia 315/9',
    left: india,
    right: australia,
    centerTitle: 'VS',
    venue: '49.2 OV                     50.0 OV',
    button: 'View Scorecard',
    result: 'India won by 6 wickets',
    leftMeta: '321/4',
    rightMeta: '315/9',
  );

  static const upcomingSeries = <CompactFixture>[
    CompactFixture(
      series: 'India vs England',
      subtitle: '5 Matches • ODI',
      left: india,
      right: england,
      date: '12 Jun – 22 Jun 2025',
      venue: 'Upcoming Series',
      status: 'ODI',
      action: 'Open Series',
    ),
    CompactFixture(
      series: 'Pakistan vs Bangladesh',
      subtitle: '3 Matches • T20I',
      left: pakistan,
      right: bangladesh,
      date: '18 Jul – 24 Jul 2025',
      venue: 'Upcoming Series',
      status: 'T20I',
      action: 'Open Series',
    ),
  ];

  static const featuredFixtures = <CompactFixture>[
    CompactFixture(
      series: 'T20I • 1st Match',
      subtitle: 'SL vs SA',
      left: sriLanka,
      right: southAfrica,
      date: '15 Jun 2025 • 7:00 PM IST',
      venue: 'Quick reminder',
      status: 'T20I',
      action: 'Notify Me',
    ),
    CompactFixture(
      series: 'ODI • 2nd Match',
      subtitle: 'NZ vs WI',
      left: newZealand,
      right: westIndies,
      date: '16 Jun 2025 • 3:30 PM IST',
      venue: 'Quick reminder',
      status: 'ODI',
      action: 'Notify Me',
    ),
    CompactFixture(
      series: 'Test • 1st Test',
      subtitle: 'AUS vs IND',
      left: australia,
      right: india,
      date: '20 Jun 2025 • 9:30 AM IST',
      venue: 'Quick reminder',
      status: 'Test',
      action: 'Notify Me',
    ),
  ];

  static const recentResults = <CompactFixture>[
    CompactFixture(
      series: 'T20I • 2nd Match',
      subtitle: 'Pakistan vs Bangladesh',
      left: pakistan,
      right: bangladesh,
      date: '176/7 (20.0 OV) • 172/9 (20.0 OV)',
      venue: 'Pakistan won by 4 runs',
      status: 'FINISHED',
      action: 'Scorecard',
    ),
    CompactFixture(
      series: 'ODI • 3rd Match',
      subtitle: 'England vs South Africa',
      left: england,
      right: southAfrica,
      date: '298/8 (50.0 OV) • 294/7 (50.0 OV)',
      venue: 'England won by 4 runs',
      status: 'FINISHED',
      action: 'Scorecard',
    ),
  ];

  static const matchesUpcoming = <CompactFixture>[
    CompactFixture(
      series: "ICC MEN'S ODI SERIES",
      subtitle: 'ODI • 3rd Match',
      left: india,
      right: australia,
      date: 'Sun, 22 Jun 2025 • 3:30 PM IST',
      venue: 'Narendra Modi Stadium\nAhmedabad, India',
      status: 'NOT STARTED',
      action: 'Set Reminder',
    ),
    CompactFixture(
      series: 'ENGLAND TOUR OF WEST INDIES 2025',
      subtitle: 'T20I • 2nd Match',
      left: england,
      right: westIndies,
      date: 'Tue, 24 Jun 2025 • 7:00 PM GMT',
      venue: 'Kensington Oval\nBridgetown, Barbados',
      status: 'NOT STARTED',
      action: 'Set Reminder',
    ),
    CompactFixture(
      series: 'PAKISTAN TOUR OF BANGLADESH 2025',
      subtitle: 'T20I • 1st Match',
      left: pakistan,
      right: bangladesh,
      date: 'Wed, 18 Jul 2025 • 6:00 PM BST',
      venue: 'Sher-e-Bangla National Stadium\nDhaka, Bangladesh',
      status: 'NOT STARTED',
      action: 'Set Reminder',
    ),
  ];

  static const matchesFinished = <CompactFixture>[
    CompactFixture(
      series: "ICC MEN'S ODI SERIES",
      subtitle: 'RESULT',
      left: newZealand,
      right: westIndies,
      date: '158/3 (38.4 OV) • 137 (50.0 OV)',
      venue: 'New Zealand won by 21 runs',
      status: 'RESULT',
      action: 'Highlights',
      playerOfMatch: 'Matt Henry (NZ)',
      playerStat: '4/26 (8.4 OV)',
    ),
    CompactFixture(
      series: 'AUSTRALIA DOMESTIC ONE-DAY CUP 2025-26',
      subtitle: 'RESULT',
      left: victoria,
      right: westernAustralia,
      date: '232/8 (50.0 OV) • 233/5 (48.2 OV)',
      venue: 'Western Australia won by 5 wickets',
      status: 'RESULT',
      action: 'Scorecard',
      playerOfMatch: 'Cameron Green (WA)',
      playerStat: '84* (72) & 2/35 (10)',
    ),
    CompactFixture(
      series: 'SOUTH AFRICA T20 LEAGUE',
      subtitle: 'RESULT',
      left: sunrisers,
      right: durban,
      date: '189/6 (20.0 OV) • 160/9 (20.0 OV)',
      venue: 'Sunrisers won by 29 runs',
      status: 'RESULT',
      action: 'Highlights',
      playerOfMatch: 'Aiden Markram (SR)',
      playerStat: '57 (32) & 1/24 (4)',
    ),
  ];

  static const newsAll = <NewsArticle>[
    NewsArticle(
      title:
          'Kohli & Rohit masterclass power India to 78-run win in Adelaide ODI',
      subtitle:
          'Centuries from Kohli and Rohit guide India to a dominant victory and a 1-0 lead in the three-match series.',
      source: 'ESPNcricinfo',
      date: '8 Jun 2025',
      tag: 'ODI',
      asset: 'assets/images/player_rohit_sharma.png',
      featured: true,
    ),
    NewsArticle(
      title: 'Australia announce squad for West Indies tour of New Zealand',
      subtitle:
          'Pat Cummins to lead 15-member squad for the three-match Test series starting 16 July.',
      source: 'Cricket Australia',
      date: '7 Jun 2025',
      tag: 'TEST',
      asset: 'assets/images/player_steven_smith.png',
    ),
    NewsArticle(
      title: 'KKR edge past MI in thriller to enter IPL 2025 playoffs',
      subtitle:
          'Rinku Singh’s fiery 48* takes Kolkata to a 5-wicket win in a last-over finish.',
      source: 'Star Sports',
      date: '7 Jun 2025',
      tag: 'T20',
      asset: 'assets/images/player_daryl_mitchell.png',
    ),
    NewsArticle(
      title: 'I bowl to enjoy pressure, not escape it: Jasprit Bumrah',
      subtitle:
          'Exclusive interview where Bumrah opens up on fitness, captaincy and Team India’s mindset.',
      source: 'Cricbuzz',
      date: '6 Jun 2025',
      tag: 'INTERVIEW',
      asset: 'assets/images/player_rohit_sharma.png',
    ),
    NewsArticle(
      title:
          'India vs England 2nd Test at Edgbaston – Full Schedule & Match Details',
      subtitle:
          'Check match timings, squad news, pitch report and where to watch live.',
      source: 'Cricinfo',
      date: '6 Jun 2025',
      tag: 'SCHEDULE',
      asset: 'assets/images/stadium_live.png',
    ),
  ];

  static const newsInternational = <NewsArticle>[
    NewsArticle(
      title: 'India power to commanding win in high-scoring ODI thriller',
      subtitle:
          'Rohit Sharma’s century and Kohli’s late flourish help India seal a 38-run victory over England in Ahmedabad.',
      source: 'ESPNcricinfo',
      date: '8 Jun 2025',
      tag: 'ODI',
      asset: 'assets/images/player_rohit_sharma.png',
      featured: true,
    ),
    NewsArticle(
      title: 'New Zealand level series with clinical run chase in Napier',
      subtitle:
          'Daryl Mitchell’s unbeaten 74 guides NZ to a five-wicket win in the 2nd ODI.',
      source: 'ICC',
      date: '8 Jun 2025',
      tag: 'ODI',
      asset: 'assets/images/player_daryl_mitchell.png',
    ),
    NewsArticle(
      title: 'Australia announce squad for West Indies tour of New Zealand',
      subtitle:
          'Pat Cummins to lead 15-member squad for the three-match Test series starting 16 July.',
      source: 'Cricket Australia',
      date: '7 Jun 2025',
      tag: 'Test',
      asset: 'assets/images/player_steven_smith.png',
    ),
    NewsArticle(
      title: 'West Indies stun Sri Lanka in final-over thriller in Pallekele',
      subtitle:
          'Alzarri Joseph’s deadly yorkers in the final over seal a memorable 5-run win.',
      source: 'Windies Cricket',
      date: '7 Jun 2025',
      tag: 'ODI',
      asset: 'assets/images/team_wi.png',
    ),
    NewsArticle(
      title: 'England make history with biggest T20I win over South Africa',
      subtitle:
          'England register record 146-run victory in the 1st T20I at The Oval.',
      source: 'BBC Sport',
      date: '6 Jun 2025',
      tag: 'T20I',
      asset: 'assets/images/team_placeholder.png',
    ),
  ];

  static const newsLeagues = <NewsArticle>[
    NewsArticle(
      title: 'IPL 2025: Playoffs picture takes shape as MI storm into top four',
      subtitle:
          'Mumbai Indians beat Lucknow Super Giants by 54 runs to strengthen their playoff chances with a clinical all-round show.',
      source: 'ESPNcricinfo',
      date: '8 Jun 2025',
      tag: 'IPL 2025',
      asset: 'assets/images/stadium_live.png',
      featured: true,
    ),
    NewsArticle(
      title: 'RCB finally break the jinx, lift maiden IPL trophy in epic final',
      subtitle:
          'Royal Challengers Bengaluru end 17-year wait with a thrilling 6-run win over Punjab Kings in IPL 2025 final.',
      source: 'Cricbuzz',
      date: '7 Jun 2025',
      tag: 'IPL 2025',
      asset: 'assets/images/player_steven_smith.png',
    ),
    NewsArticle(
      title:
          'Sydney Thunder edge past Scorchers in BBL|14 final to lift trophy',
      subtitle:
          'Thunder hold their nerve in a low-scoring thriller to claim their second Big Bash League title.',
      source: 'BBL Official',
      date: '6 Jun 2025',
      tag: 'BBL|14',
      asset: 'assets/images/player_yashasvi_jaiswal.png',
    ),
    NewsArticle(
      title:
          'Lahore Qalandars defend title with comprehensive win in PSL 2025 final',
      subtitle:
          'Sikandar Raza’s all-round brilliance guides Qalandars to a dominant 63-run victory over Multan Sultans.',
      source: 'PSL Official',
      date: '5 Jun 2025',
      tag: 'PSL 2025',
      asset: 'assets/images/player_placeholder.png',
    ),
    NewsArticle(
      title: 'Trinbago Knight Riders clinch record fifth CPL title',
      subtitle:
          'TKR outclass Guyana Amazon Warriors by 7 wickets in a one-sided CPL 2025 final.',
      source: 'CPL Official',
      date: '4 Jun 2025',
      tag: 'CPL 2025',
      asset: 'assets/images/team_wi.png',
    ),
  ];

  static const newsLatest = <NewsArticle>[
    NewsArticle(
      title: 'Rohit Sharma smashes 264 in India’s record 387-run chase',
      subtitle:
          'India chased down the highest total in ODI history, scripting a stunning victory over Sri Lanka in Colombo.',
      source: 'ESPNcricinfo',
      date: '8 Jun 2025',
      tag: 'ODI',
      asset: 'assets/images/player_rohit_sharma.png',
      featured: true,
      breaking: true,
      timeAgo: '5m ago',
    ),
    NewsArticle(
      title: 'New Zealand level series with clinical run chase in Napier',
      subtitle:
          'Daryl Mitchell’s unbeaten 74 guides NZ to a five-wicket win in the 2nd ODI.',
      source: 'ICC',
      date: '18m ago',
      tag: 'ODI',
      asset: 'assets/images/player_daryl_mitchell.png',
      timeAgo: '18m ago',
    ),
    NewsArticle(
      title: 'Australia announce squad for West Indies tour of New Zealand',
      subtitle:
          'Pat Cummins to lead 15-member squad for the three-match Test series starting 16 July.',
      source: 'Cricket Australia',
      date: '1h ago',
      tag: 'Test',
      asset: 'assets/images/player_steven_smith.png',
      timeAgo: '1h ago',
    ),
    NewsArticle(
      title: 'West Indies stun Sri Lanka in final-over thriller in Pallekele',
      subtitle:
          'Alzarri Joseph’s deadly yorkers in the final over seal a memorable 5-run win.',
      source: 'Windies Cricket',
      date: '3h ago',
      tag: 'ODI',
      asset: 'assets/images/team_wi.png',
      timeAgo: '3h ago',
    ),
    NewsArticle(
      title: 'England make history with biggest T20I win over South Africa',
      subtitle:
          'England register record 146-run victory in the 1st T20I at The Oval.',
      source: 'BBC Sport',
      date: '5h ago',
      tag: 'T20I',
      asset: 'assets/images/team_placeholder.png',
      timeAgo: '5h ago',
    ),
  ];

  static const topMoments = <VideoHighlight>[
    VideoHighlight(
      title: 'Rohit Sharma’s blazing 121* powers India to series-clinching win',
      match: 'India vs Australia • ODI',
      duration: '05:42',
      views: '1.2M views',
      tag: 'Featured',
      asset: 'assets/images/player_rohit_sharma.png',
      featured: true,
    ),
    VideoHighlight(
      title: 'Bumrah rips through Australia with dream spell',
      match: 'India vs Australia • ODI',
      duration: '02:14',
      views: '740K views',
      tag: 'Bowling',
      asset: 'assets/images/player_rohit_sharma.png',
    ),
    VideoHighlight(
      title: 'Mitchell Santner’s impossible one-handed catch',
      match: 'NZ vs WI • Test',
      duration: '01:08',
      views: '510K views',
      tag: 'Fielding',
      asset: 'assets/images/player_daryl_mitchell.png',
    ),
    VideoHighlight(
      title: 'Virat Kohli ends the chase with trademark cover drive',
      match: 'India vs England • ODI',
      duration: '00:48',
      views: '1.8M views',
      tag: 'Batting',
      asset: 'assets/images/player_rohit_sharma.png',
    ),
  ];

  static const shorts = <VideoHighlight>[
    VideoHighlight(
        title: 'Rohit upper-cut for six',
        match: 'IND vs AUS',
        duration: '0:21',
        views: '230K',
        tag: 'Short',
        asset: 'assets/images/player_rohit_sharma.png'),
    VideoHighlight(
        title: 'Bumrah yorker angle',
        match: 'IND vs AUS',
        duration: '0:18',
        views: '180K',
        tag: 'Short',
        asset: 'assets/images/player_daryl_mitchell.png'),
    VideoHighlight(
        title: 'Gill lofted drive',
        match: 'IND vs ENG',
        duration: '0:15',
        views: '260K',
        tag: 'Short',
        asset: 'assets/images/player_yashasvi_jaiswal.png'),
    VideoHighlight(
        title: 'Pant reverse sweep',
        match: 'IND vs AUS',
        duration: '0:19',
        views: '210K',
        tag: 'Short',
        asset: 'assets/images/player_placeholder.png'),
    VideoHighlight(
        title: 'Rahul diving take',
        match: 'IND vs AUS',
        duration: '0:17',
        views: '196K',
        tag: 'Short',
        asset: 'assets/images/player_steven_smith.png'),
    VideoHighlight(
        title: 'Starc inswinger',
        match: 'AUS vs IND',
        duration: '0:16',
        views: '242K',
        tag: 'Short',
        asset: 'assets/images/player_steven_smith.png'),
  ];

  static const seriesOverviewStats = <StatLine>[
    StatLine('Format', '3 Test • 3 ODI • 5 T20I',
        icon: Icons.sports_cricket_rounded),
    StatLine('Host', 'Australia', icon: Icons.shield_outlined),
    StatLine('Start Date', '22 Nov 2024', icon: Icons.calendar_month_rounded),
    StatLine('End Date', '7 Jan 2025', icon: Icons.event_available_rounded),
    StatLine('Total Matches', '11 Matches', icon: Icons.gesture_rounded),
    StatLine('Series Status', 'In Progress', icon: Icons.show_chart_rounded),
  ];

  static const seriesUpcomingRows = <SeriesMatchRow>[
    SeriesMatchRow(
        label: '1st Test',
        left: india,
        right: australia,
        date: '22 – 26 Nov 2024',
        venue: 'Optus Stadium\nPerth',
        status: 'UPCOMING',
        trailing: 'Starts in\n2 Days'),
    SeriesMatchRow(
        label: '2nd Test',
        left: india,
        right: australia,
        date: '6 – 10 Dec 2024',
        venue: 'Adelaide Oval\nAdelaide',
        status: 'UPCOMING',
        trailing: 'Starts in\n16 Days'),
    SeriesMatchRow(
        label: '3rd Test',
        left: india,
        right: australia,
        date: '14 – 18 Dec 2024',
        venue: 'The Gabba\nBrisbane',
        status: 'UPCOMING',
        trailing: 'Starts in\n24 Days'),
  ];

  static const seriesCompletedRows = <SeriesMatchRow>[
    SeriesMatchRow(
        label: '1st ODI',
        left: india,
        right: australia,
        date: '22 Nov 2024',
        venue: 'Perth Stadium\nPerth',
        status: 'IND WON',
        trailing: 'IND won by\n8 Wickets'),
    SeriesMatchRow(
        label: '2nd ODI',
        left: india,
        right: australia,
        date: '24 Nov 2024',
        venue: 'Adelaide Oval\nAdelaide',
        status: 'IND WON',
        trailing: 'IND won by\n99 Runs'),
    SeriesMatchRow(
        label: '3rd ODI',
        left: india,
        right: australia,
        date: '27 Nov 2024',
        venue: 'MCG\nMelbourne',
        status: 'AUS WON',
        trailing: 'AUS won by\n2 Wickets'),
  ];

  static const indiaSquadTop = <PlayerInfo>[
    PlayerInfo(
        name: 'Rohit Sharma',
        role: 'BAT',
        team: india,
        asset: 'assets/images/player_rohit_sharma.png',
        subtitle: '(C) Captain',
        order: 1),
    PlayerInfo(
        name: 'Shubman Gill',
        role: 'BAT',
        team: india,
        asset: 'assets/images/player_yashasvi_jaiswal.png',
        order: 2),
    PlayerInfo(
        name: 'Virat Kohli',
        role: 'BAT',
        team: india,
        asset: 'assets/images/player_rohit_sharma.png',
        order: 3),
    PlayerInfo(
        name: 'Shreyas Iyer',
        role: 'BAT',
        team: india,
        asset: 'assets/images/player_daryl_mitchell.png',
        order: 4),
    PlayerInfo(
        name: 'KL Rahul',
        role: 'WK',
        team: india,
        asset: 'assets/images/player_placeholder.png',
        order: 5),
  ];

  static const indiaSquadMiddle = <PlayerInfo>[
    PlayerInfo(
        name: 'Rishabh Pant',
        role: 'WK',
        team: india,
        asset: 'assets/images/player_placeholder.png',
        order: 6),
    PlayerInfo(
        name: 'Suryakumar Yadav',
        role: 'BAT',
        team: india,
        asset: 'assets/images/player_daryl_mitchell.png',
        order: 7),
    PlayerInfo(
        name: 'Rinku Singh',
        role: 'BAT',
        team: india,
        asset: 'assets/images/player_placeholder.png',
        order: 8),
    PlayerInfo(
        name: 'Tilak Varma',
        role: 'BAT',
        team: india,
        asset: 'assets/images/player_placeholder.png',
        order: 9),
  ];

  static const indiaAllRounders = <PlayerInfo>[
    PlayerInfo(
        name: 'Ravindra Jadeja',
        role: 'AR',
        team: india,
        asset: 'assets/images/player_placeholder.png',
        order: 1),
    PlayerInfo(
        name: 'Hardik Pandya',
        role: 'AR',
        team: india,
        asset: 'assets/images/player_placeholder.png',
        subtitle: '(VC) Vice Captain',
        order: 2),
    PlayerInfo(
        name: 'Axar Patel',
        role: 'AR',
        team: india,
        asset: 'assets/images/player_placeholder.png',
        order: 3),
  ];

  static const indiaBowlers = <PlayerInfo>[
    PlayerInfo(
        name: 'Jasprit Bumrah',
        role: 'BOWL',
        team: india,
        asset: 'assets/images/player_placeholder.png'),
    PlayerInfo(
        name: 'Mohammed Siraj',
        role: 'BOWL',
        team: india,
        asset: 'assets/images/player_placeholder.png'),
    PlayerInfo(
        name: 'Kuldeep Yadav',
        role: 'BOWL',
        team: india,
        asset: 'assets/images/player_placeholder.png'),
    PlayerInfo(
        name: 'Arshdeep Singh',
        role: 'BOWL',
        team: india,
        asset: 'assets/images/player_placeholder.png'),
  ];

  static const indiaReserves = <PlayerInfo>[
    PlayerInfo(
        name: 'Yashasvi Jaiswal',
        role: 'BAT',
        team: india,
        asset: 'assets/images/player_yashasvi_jaiswal.png'),
    PlayerInfo(
        name: 'Ishan Kishan',
        role: 'WK',
        team: india,
        asset: 'assets/images/player_placeholder.png'),
    PlayerInfo(
        name: 'Washington Sundar',
        role: 'AR',
        team: india,
        asset: 'assets/images/player_placeholder.png'),
    PlayerInfo(
        name: 'Mukesh Kumar',
        role: 'BOWL',
        team: india,
        asset: 'assets/images/player_placeholder.png'),
    PlayerInfo(
        name: 'Avesh Khan',
        role: 'BOWL',
        team: india,
        asset: 'assets/images/player_placeholder.png'),
  ];

  static const searchTopics = <String>[
    'India vs Australia',
    'Virat Kohli',
    'IPL 2025',
    'World Test Championship',
    'Highlights',
  ];

  static const trendingPlayers = <String>[
    'Rohit Sharma',
    'Virat Kohli',
    'Jasprit Bumrah',
    'Pat Cummins',
    'Daryl Mitchell',
  ];
}
