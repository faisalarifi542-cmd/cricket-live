class ApiBatsmanInfo {
  final String id;
  final String name;
  final int runs;
  final int balls;
  final int fours;
  final int sixes;
  final double strikeRate;

  ApiBatsmanInfo({required this.id, required this.name, required this.runs, required this.balls, required this.fours, required this.sixes, required this.strikeRate});

  factory ApiBatsmanInfo.fromJson(Map<String, dynamic> json) => ApiBatsmanInfo(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    runs: json['runs'] ?? 0,
    balls: json['balls'] ?? 0,
    fours: json['fours'] ?? 0,
    sixes: json['sixes'] ?? 0,
    strikeRate: (json['strikeRate'] ?? 0).toDouble(),
  );
}

class ApiBowlerInfo {
  final String id;
  final String name;
  final double overs;
  final int runs;
  final int wickets;
  final double economy;

  ApiBowlerInfo({required this.id, required this.name, required this.overs, required this.runs, required this.wickets, required this.economy});

  factory ApiBowlerInfo.fromJson(Map<String, dynamic> json) => ApiBowlerInfo(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    overs: (json['overs'] ?? 0).toDouble(),
    runs: json['runs'] ?? 0,
    wickets: json['wickets'] ?? 0,
    economy: (json['economy'] ?? 0).toDouble(),
  );
}

class ApiCommentaryEntry {
  final int inningsId;
  final double overNumber;
  final int ballNumber;
  final String event;
  final String text;
  final int timestamp;
  final String batTeamName;
  final ApiBatsmanInfo? batsman;
  final ApiBowlerInfo? bowler;
  final int legalRuns;
  final int totalRuns;
  final int scoreRuns;
  final int scoreWickets;
  final bool isWicket;
  final bool isFour;
  final bool isSix;
  final bool isOverBreak;
  final String? overSummary;

  ApiCommentaryEntry({
    required this.inningsId,
    required this.overNumber,
    required this.ballNumber,
    required this.event,
    required this.text,
    required this.timestamp,
    required this.batTeamName,
    this.batsman,
    this.bowler,
    required this.legalRuns,
    required this.totalRuns,
    required this.scoreRuns,
    required this.scoreWickets,
    required this.isWicket,
    required this.isFour,
    required this.isSix,
    required this.isOverBreak,
    this.overSummary,
  });

  factory ApiCommentaryEntry.fromJson(Map<String, dynamic> json) {
    return ApiCommentaryEntry(
      inningsId: json['inningsId'] ?? json['innings_number'] ?? 0,
      overNumber: (json['overNumber'] ?? json['over'] ?? 0).toDouble(),
      ballNumber: json['ballNumber'] ?? json['ball'] ?? 0,
      event: json['event']?.toString() ?? 'NONE',
      text: json['text']?.toString() ?? '',
      timestamp: json['timestamp'] ?? 0,
      batTeamName: json['batTeamName']?.toString() ?? '',
      batsman: json['batsman'] is Map<String, dynamic> ? ApiBatsmanInfo.fromJson(json['batsman']) : null,
      bowler: json['bowler'] is Map<String, dynamic> ? ApiBowlerInfo.fromJson(json['bowler']) : null,
      legalRuns: json['runs'] is Map ? (json['runs']['legal'] ?? 0) : (json['runs'] ?? 0),
      totalRuns: json['runs'] is Map ? (json['runs']['total'] ?? 0) : (json['runs'] ?? 0),
      scoreRuns: json['score'] is Map ? (json['score']['runs'] ?? 0) : 0,
      scoreWickets: json['score'] is Map ? (json['score']['wickets'] ?? 0) : 0,
      isWicket: json['isWicket'] ?? json['is_wicket'] ?? false,
      isFour: json['isFour'] ?? json['is_four'] ?? false,
      isSix: json['isSix'] ?? json['is_six'] ?? false,
      isOverBreak: json['isOverBreak'] ?? false,
      overSummary: json['overSummary'],
    );
  }

  // Backward-compat getters
  String get id => '$inningsId-$ballNumber';
  int get inningsNumber => inningsId;
  int? get over => overNumber > 0 ? overNumber.floor() : null;
  int? get ball => ballNumber > 0 ? ballNumber : null;
  bool get isBoundary => isFour || isSix;
  bool get isBallByBall => overNumber > 0 && ballNumber > 0;

  String get overText {
    if (overNumber <= 0) return '';
    final over = overNumber.floor();
    final ball = ballNumber > 0 ? ballNumber : ((overNumber * 10).round() % 10);
    return '$over.$ball';
  }

  String get outcomeText {
    if (isWicket) return 'W';
    if (isSix) return '6';
    if (isFour) return '4';
    return '$totalRuns';
  }

  String get batsmanName => batsman?.name ?? '';
  String get bowlerName => bowler?.name ?? '';
}

class ApiCommentary {
  final String? matchId;
  final int inningsId;
  final List<ApiCommentaryEntry> entries;

  ApiCommentary({this.matchId, required this.inningsId, required this.entries});

  factory ApiCommentary.fromJson(Map<String, dynamic> json) {
    final data = json['data'] ?? json;
    List<ApiCommentaryEntry> entries = [];

    if (data is Map<String, dynamic>) {
      final commList = data['commentary'];
      if (commList is List) {
        entries = commList.map((e) => ApiCommentaryEntry.fromJson(e as Map<String, dynamic>)).toList();
      }
    } else if (data is List) {
      entries = data.map((e) => ApiCommentaryEntry.fromJson(e as Map<String, dynamic>)).toList();
    }

    return ApiCommentary(
      matchId: json['matchId']?.toString() ?? data?['matchId']?.toString(),
      inningsId: json['inningsId'] ?? data?['inningsId'] ?? 0,
      entries: entries,
    );
  }

  // Backward compat
  int get totalPages => 1;
  int get currentPage => 1;
}
