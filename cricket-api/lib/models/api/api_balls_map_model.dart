class ApiBallEntry {
  final int timestamp;
  final int ballNumber;
  final double overNumber;
  final int inningsId;
  final String event;
  final int totalRuns;
  final String? batsmanId;
  final String? bowlerId;
  final String ballLabel;

  ApiBallEntry({required this.timestamp, required this.ballNumber, required this.overNumber, required this.inningsId, required this.event, required this.totalRuns, this.batsmanId, this.bowlerId, required this.ballLabel});

  factory ApiBallEntry.fromJson(Map<String, dynamic> json) => ApiBallEntry(
    timestamp: json['timestamp'] ?? 0,
    ballNumber: json['ballNumber'] ?? 0,
    overNumber: (json['overNumber'] ?? 0).toDouble(),
    inningsId: json['inningsId'] ?? 0,
    event: json['event']?.toString() ?? 'NONE',
    totalRuns: json['totalRuns'] ?? 0,
    batsmanId: json['batsmanId']?.toString(),
    bowlerId: json['bowlerId']?.toString(),
    ballLabel: json['ballLabel']?.toString() ?? '',
  );

  bool get isWicket => event == 'WICKET';
  bool get isFour => event == 'FOUR';
  bool get isSix => event == 'SIX';
  bool get isDot => totalRuns == 0 && !isWicket;
}

class ApiBatterSummary {
  final String id;
  final String name;
  final int runs;
  final int balls;
  final int dots;
  final int fours;
  final int sixes;
  final double strikeRate;

  ApiBatterSummary({required this.id, required this.name, required this.runs, required this.balls, required this.dots, required this.fours, required this.sixes, required this.strikeRate});

  factory ApiBatterSummary.fromJson(Map<String, dynamic> json) => ApiBatterSummary(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    runs: json['runs'] ?? 0,
    balls: json['balls'] ?? 0,
    dots: json['dots'] ?? 0,
    fours: json['fours'] ?? 0,
    sixes: json['sixes'] ?? 0,
    strikeRate: (json['strikeRate'] ?? 0).toDouble(),
  );
}

class ApiBowlerSummary {
  final String id;
  final String name;
  final double overs;
  final int maidens;
  final int runs;
  final int wickets;
  final double economy;

  ApiBowlerSummary({required this.id, required this.name, required this.overs, required this.maidens, required this.runs, required this.wickets, required this.economy});

  factory ApiBowlerSummary.fromJson(Map<String, dynamic> json) => ApiBowlerSummary(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    overs: (json['overs'] ?? 0).toDouble(),
    maidens: json['maidens'] ?? 0,
    runs: json['runs'] ?? 0,
    wickets: json['wickets'] ?? 0,
    economy: (json['economy'] ?? 0).toDouble(),
  );
}

class ApiBallsSummary {
  final int dots;
  final int ones;
  final int twos;
  final int threes;
  final int fours;
  final int sixes;
  final int wickets;

  ApiBallsSummary({required this.dots, required this.ones, required this.twos, required this.threes, required this.fours, required this.sixes, required this.wickets});

  factory ApiBallsSummary.fromJson(Map<String, dynamic> json) => ApiBallsSummary(
    dots: json['dots'] ?? 0,
    ones: json['ones'] ?? 0,
    twos: json['twos'] ?? 0,
    threes: json['threes'] ?? 0,
    fours: json['fours'] ?? 0,
    sixes: json['sixes'] ?? 0,
    wickets: json['wickets'] ?? 0,
  );
}

class ApiBallsMap {
  final List<ApiBallEntry> balls;
  final List<ApiBatterSummary> batters;
  final List<ApiBowlerSummary> bowlers;
  final ApiBallsSummary summary;

  ApiBallsMap({required this.balls, required this.batters, required this.bowlers, required this.summary});

  factory ApiBallsMap.fromJson(Map<String, dynamic> json) {
    final data = json['data'] ?? json;
    return ApiBallsMap(
      balls: (data['balls'] as List<dynamic>? ?? []).map((e) => ApiBallEntry.fromJson(e as Map<String, dynamic>)).toList(),
      batters: (data['batters'] as List<dynamic>? ?? []).map((e) => ApiBatterSummary.fromJson(e as Map<String, dynamic>)).toList(),
      bowlers: (data['bowlers'] as List<dynamic>? ?? []).map((e) => ApiBowlerSummary.fromJson(e as Map<String, dynamic>)).toList(),
      summary: data['summary'] is Map<String, dynamic> ? ApiBallsSummary.fromJson(data['summary']) : ApiBallsSummary(dots: 0, ones: 0, twos: 0, threes: 0, fours: 0, sixes: 0, wickets: 0),
    );
  }
}
