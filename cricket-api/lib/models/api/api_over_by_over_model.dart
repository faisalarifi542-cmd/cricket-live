class ApiOverEntry {
  final int inningsId;
  final int overNumber;
  final String summary;
  final int runs;
  final int wickets;
  final String score;
  final int totalScore;
  final int totalWickets;
  final String batTeamName;
  final int timestamp;
  final String bowlerName;
  final String? bowlerId;
  final double bowlerOvers;
  final int bowlerRuns;
  final int bowlerWickets;
  final int bowlerMaidens;
  final List<String> batsmanNames;
  final String event;

  ApiOverEntry({
    required this.inningsId,
    required this.overNumber,
    required this.summary,
    required this.runs,
    required this.wickets,
    required this.score,
    required this.totalScore,
    required this.totalWickets,
    required this.batTeamName,
    required this.timestamp,
    required this.bowlerName,
    this.bowlerId,
    required this.bowlerOvers,
    required this.bowlerRuns,
    required this.bowlerWickets,
    required this.bowlerMaidens,
    required this.batsmanNames,
    required this.event,
  });

  factory ApiOverEntry.fromJson(Map<String, dynamic> json) => ApiOverEntry(
    inningsId: json['inningsId'] ?? 0,
    overNumber: json['overNumber'] ?? 0,
    summary: json['summary']?.toString() ?? '',
    runs: json['runs'] ?? 0,
    wickets: json['wickets'] ?? 0,
    score: json['score']?.toString() ?? '',
    totalScore: json['totalScore'] ?? 0,
    totalWickets: json['totalWickets'] ?? 0,
    batTeamName: json['batTeamName']?.toString() ?? '',
    timestamp: json['timestamp'] ?? 0,
    bowlerName: json['bowlerName']?.toString() ?? '',
    bowlerId: json['bowlerId']?.toString(),
    bowlerOvers: (json['bowlerOvers'] ?? 0).toDouble(),
    bowlerRuns: json['bowlerRuns'] ?? 0,
    bowlerWickets: json['bowlerWickets'] ?? 0,
    bowlerMaidens: json['bowlerMaidens'] ?? 0,
    batsmanNames: (json['batsmanNames'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
    event: json['event']?.toString() ?? '',
  );

  bool get hasWicket => summary.contains('W');
}

class ApiOverByOver {
  final List<ApiOverEntry> overs;
  final String? nextTimestamp;

  ApiOverByOver({required this.overs, this.nextTimestamp});

  factory ApiOverByOver.fromJson(Map<String, dynamic> json) {
    final data = json['data'] ?? json;
    return ApiOverByOver(
      overs: (data['overs'] as List<dynamic>? ?? []).map((e) => ApiOverEntry.fromJson(e as Map<String, dynamic>)).toList(),
      nextTimestamp: data['nextTimestamp']?.toString(),
    );
  }
}
