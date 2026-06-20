class ApiBattingEntry {
  final String playerId;
  final String name;
  final int runs;
  final int balls;
  final int fours;
  final int sixes;
  final double strikeRate;
  final String dismissal;
  final bool isBatting;
  final int position;

  ApiBattingEntry({
    required this.playerId,
    required this.name,
    required this.runs,
    required this.balls,
    required this.fours,
    required this.sixes,
    required this.strikeRate,
    required this.dismissal,
    required this.isBatting,
    required this.position,
  });

  factory ApiBattingEntry.fromJson(Map<String, dynamic> json) {
    return ApiBattingEntry(
      playerId: json['player_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      runs: json['runs'] ?? 0,
      balls: json['balls'] ?? 0,
      fours: json['fours'] ?? 0,
      sixes: json['sixes'] ?? 0,
      strikeRate: (json['strike_rate'] is num) ? (json['strike_rate'] as num).toDouble() : 0.0,
      dismissal: json['dismissal']?.toString() ?? '',
      isBatting: json['is_batting'] ?? false,
      position: json['position'] ?? 0,
    );
  }

  bool get isNotOut => dismissal == 'not out' || isBatting;
  bool get didBat => balls > 0 || dismissal != 'not out';
}

class ApiBowlingEntry {
  final String playerId;
  final String name;
  final int overs;
  final int maidens;
  final int runs;
  final int wickets;
  final double economy;
  final int dots;
  final int wides;
  final int noBalls;

  ApiBowlingEntry({
    required this.playerId,
    required this.name,
    required this.overs,
    required this.maidens,
    required this.runs,
    required this.wickets,
    required this.economy,
    required this.dots,
    required this.wides,
    required this.noBalls,
  });

  factory ApiBowlingEntry.fromJson(Map<String, dynamic> json) {
    return ApiBowlingEntry(
      playerId: json['player_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      overs: json['overs'] ?? 0,
      maidens: json['maidens'] ?? 0,
      runs: json['runs'] ?? 0,
      wickets: json['wickets'] ?? 0,
      economy: (json['economy'] is num) ? (json['economy'] as num).toDouble() : 0.0,
      dots: json['dots'] ?? 0,
      wides: json['wides'] ?? 0,
      noBalls: json['no_balls'] ?? 0,
    );
  }
}

class ApiFallOfWicket {
  final int wicketNumber;
  final int runs;
  final double overs;
  final String player;

  ApiFallOfWicket({
    required this.wicketNumber,
    required this.runs,
    required this.overs,
    required this.player,
  });

  factory ApiFallOfWicket.fromJson(Map<String, dynamic> json) {
    return ApiFallOfWicket(
      wicketNumber: json['wicket_number'] ?? 0,
      runs: json['runs'] ?? 0,
      overs: (json['overs'] is num) ? (json['overs'] as num).toDouble() : 0.0,
      player: json['player']?.toString() ?? '',
    );
  }
}

class ApiPartnershipDetail {
  final int runs;
  final int balls;
  final ApiPartnershipBatsman? bat1;
  final ApiPartnershipBatsman? bat2;

  ApiPartnershipDetail({
    required this.runs,
    required this.balls,
    this.bat1,
    this.bat2,
  });

  factory ApiPartnershipDetail.fromJson(Map<String, dynamic> json) {
    return ApiPartnershipDetail(
      runs: json['runs'] ?? 0,
      balls: json['balls'] ?? 0,
      bat1: json['bat1'] != null ? ApiPartnershipBatsman.fromJson(json['bat1']) : null,
      bat2: json['bat2'] != null ? ApiPartnershipBatsman.fromJson(json['bat2']) : null,
    );
  }
}

class ApiPartnershipBatsman {
  final String name;
  final int runs;

  ApiPartnershipBatsman({required this.name, required this.runs});

  factory ApiPartnershipBatsman.fromJson(Map<String, dynamic> json) {
    return ApiPartnershipBatsman(
      name: json['name']?.toString() ?? '',
      runs: json['runs'] ?? 0,
    );
  }
}

class ApiExtras {
  final int total;
  final int byes;
  final int legByes;
  final int wides;
  final int noBalls;
  final int penalty;

  ApiExtras({
    required this.total,
    required this.byes,
    required this.legByes,
    required this.wides,
    required this.noBalls,
    required this.penalty,
  });

  factory ApiExtras.fromJson(Map<String, dynamic> json) {
    return ApiExtras(
      total: json['total'] ?? 0,
      byes: json['byes'] ?? 0,
      legByes: json['leg_byes'] ?? 0,
      wides: json['wides'] ?? 0,
      noBalls: json['no_balls'] ?? 0,
      penalty: json['penalty'] ?? 0,
    );
  }

  String get breakdown {
    final parts = <String>[];
    if (byes > 0) parts.add('b $byes');
    if (legByes > 0) parts.add('lb $legByes');
    if (wides > 0) parts.add('w $wides');
    if (noBalls > 0) parts.add('nb $noBalls');
    if (penalty > 0) parts.add('p $penalty');
    return parts.isEmpty ? '$total' : '$total (${ parts.join(', ')})';
  }
}

class ApiScorecardTotal {
  final int runs;
  final int wickets;
  final int overs;

  ApiScorecardTotal({required this.runs, required this.wickets, required this.overs});

  factory ApiScorecardTotal.fromJson(Map<String, dynamic> json) {
    return ApiScorecardTotal(
      runs: json['runs'] ?? 0,
      wickets: json['wickets'] ?? 0,
      overs: json['overs'] ?? 0,
    );
  }

  String get text => '$runs/$wickets ($overs ov)';
}

class ApiScorecardInnings {
  final int inningsNumber;
  final String battingTeam;
  final String battingTeamId;
  final ApiScorecardTotal total;
  final double runRate;
  final ApiExtras extras;
  final List<ApiBattingEntry> batting;
  final List<ApiBowlingEntry> bowling;
  final List<ApiFallOfWicket> fallOfWickets;
  final List<ApiPartnershipDetail> partnerships;

  ApiScorecardInnings({
    required this.inningsNumber,
    required this.battingTeam,
    required this.battingTeamId,
    required this.total,
    required this.runRate,
    required this.extras,
    required this.batting,
    required this.bowling,
    required this.fallOfWickets,
    required this.partnerships,
  });

  factory ApiScorecardInnings.fromJson(Map<String, dynamic> json) {
    return ApiScorecardInnings(
      inningsNumber: json['innings_number'] ?? 0,
      battingTeam: json['batting_team']?.toString() ?? '',
      battingTeamId: json['batting_team_id']?.toString() ?? '',
      total: ApiScorecardTotal.fromJson(json['total'] ?? {}),
      runRate: (json['run_rate'] is num) ? (json['run_rate'] as num).toDouble() : 0.0,
      extras: ApiExtras.fromJson(json['extras'] ?? {}),
      batting: (json['batting'] as List?)?.map((e) => ApiBattingEntry.fromJson(e)).toList() ?? [],
      bowling: (json['bowling'] as List?)?.map((e) => ApiBowlingEntry.fromJson(e)).toList() ?? [],
      fallOfWickets: (json['fall_of_wickets'] as List?)?.map((e) => ApiFallOfWicket.fromJson(e)).toList() ?? [],
      partnerships: (json['partnerships'] as List?)?.map((e) => ApiPartnershipDetail.fromJson(e)).toList() ?? [],
    );
  }
}

class ApiScorecard {
  final List<ApiScorecardInnings> innings;
  final DateTime? lastUpdated;

  ApiScorecard({required this.innings, this.lastUpdated});

  factory ApiScorecard.fromJson(Map<String, dynamic> json) {
    return ApiScorecard(
      innings: (json['innings'] as List?)?.map((e) => ApiScorecardInnings.fromJson(e)).toList() ?? [],
      lastUpdated: json['last_updated'] != null ? DateTime.tryParse(json['last_updated'].toString()) : null,
    );
  }
}
