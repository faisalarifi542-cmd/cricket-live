import 'package:flutter/material.dart';
import '../models.dart';

class MockMatches {
  static const liveHero = HeroFixture(
    badge: 'LIVE',
    series: '1st Test • Day 1',
    date: 'West Indies tour of New Zealand, 2025',
    time: '158/3 (38.4 OV)',
    left: MockTeams.newZealand,
    right: MockTeams.westIndies,
    centerTitle: 'VS',
    venue: 'NZ won the toss & chose to bat',
    button: 'Watch Live',
  );

  static const upcomingHero = HeroFixture(
    badge: 'UPCOMING',
    series: "ICC MEN'S ODI SERIES",
    date: 'Sun, 8 Jun 2025',
    time: '3:30 PM IST',
    left: MockTeams.india,
    right: MockTeams.australia,
    centerTitle: 'VS',
    venue: 'Narendra Modi Stadium\nAhmedabad, India',
    button: 'Set Reminder',
  );

  static const finishedHero = HeroFixture(
    badge: 'FINISHED',
    series: "ICC MEN'S ODI SERIES",
    date: '8 Jun 2025 • Ahmedabad',
    time: 'India 321/4 • Australia 315/9',
    left: MockTeams.india,
    right: MockTeams.australia,
    centerTitle: 'VS',
    venue: '49.2 OV                     50.0 OV',
    button: 'View Scorecard',
    result: 'India won by 6 wickets',
    leftMeta: '321/4',
    rightMeta: '315/9',
  );

  static const matchesUpcoming = <CompactFixture>[
    CompactFixture(
      series: "ICC MEN'S ODI SERIES",
      subtitle: 'ODI • 3rd Match',
      left: MockTeams.india,
      right: MockTeams.australia,
      date: 'Sun, 22 Jun 2025 • 3:30 PM IST',
      venue: 'Narendra Modi Stadium\nAhmedabad, India',
      status: 'NOT STARTED',
      action: 'Set Reminder',
    ),
    CompactFixture(
      series: 'ENGLAND TOUR OF WEST INDIES 2025',
      subtitle: 'T20I • 2nd Match',
      left: MockTeams.england,
      right: MockTeams.westIndies,
      date: 'Tue, 24 Jun 2025 • 7:00 PM GMT',
      venue: 'Kensington Oval\nBridgetown, Barbados',
      status: 'NOT STARTED',
      action: 'Set Reminder',
    ),
    CompactFixture(
      series: 'PAKISTAN TOUR OF BANGLADESH 2025',
      subtitle: 'T20I • 1st Match',
      left: MockTeams.pakistan,
      right: MockTeams.bangladesh,
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
      left: MockTeams.newZealand,
      right: MockTeams.westIndies,
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
      left: MockTeams.victoria,
      right: MockTeams.westernAustralia,
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
      left: MockTeams.sunrisers,
      right: MockTeams.durban,
      date: '189/6 (20.0 OV) • 160/9 (20.0 OV)',
      venue: 'Sunrisers won by 29 runs',
      status: 'RESULT',
      action: 'Highlights',
      playerOfMatch: 'Aiden Markram (SR)',
      playerStat: '57 (32) & 1/24 (4)',
    ),
  ];

  static const upcomingSeries = <CompactFixture>[
    CompactFixture(
      series: 'India vs England',
      subtitle: '5 Matches • ODI',
      left: MockTeams.india,
      right: MockTeams.england,
      date: '12 Jun – 22 Jun 2025',
      venue: 'Upcoming Series',
      status: 'ODI',
      action: 'Open Series',
    ),
    CompactFixture(
      series: 'Pakistan vs Bangladesh',
      subtitle: '3 Matches • T20I',
      left: MockTeams.pakistan,
      right: MockTeams.bangladesh,
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
      left: MockTeams.sriLanka,
      right: MockTeams.southAfrica,
      date: '15 Jun 2025 • 7:00 PM IST',
      venue: 'Quick reminder',
      status: 'T20I',
      action: 'Notify Me',
    ),
    CompactFixture(
      series: 'ODI • 2nd Match',
      subtitle: 'NZ vs WI',
      left: MockTeams.newZealand,
      right: MockTeams.westIndies,
      date: '16 Jun 2025 • 3:30 PM IST',
      venue: 'Quick reminder',
      status: 'ODI',
      action: 'Notify Me',
    ),
    CompactFixture(
      series: 'Test • 1st Test',
      subtitle: 'AUS vs IND',
      left: MockTeams.australia,
      right: MockTeams.india,
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
      left: MockTeams.pakistan,
      right: MockTeams.bangladesh,
      date: '176/7 (20.0 OV) • 172/9 (20.0 OV)',
      venue: 'Pakistan won by 4 runs',
      status: 'FINISHED',
      action: 'Scorecard',
    ),
    CompactFixture(
      series: 'ODI • 3rd Match',
      subtitle: 'England vs South Africa',
      left: MockTeams.england,
      right: MockTeams.southAfrica,
      date: '298/8 (50.0 OV) • 294/7 (50.0 OV)',
      venue: 'England won by 4 runs',
      status: 'FINISHED',
      action: 'Scorecard',
    ),
  ];
}

class MockTeams {
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
}
