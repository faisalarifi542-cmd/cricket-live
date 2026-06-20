class ApiHighlightEntry {
  final double overNumber;
  final int ballNumber;
  final String event;
  final String type;
  final String text;
  final int timestamp;
  final String batTeamName;
  final String batsman;
  final String? batsmanId;
  final String bowler;
  final String? bowlerId;
  final bool isWicket;
  final bool isFour;
  final bool isSix;
  final int? scoreRuns;
  final int? scoreWickets;
  final int? inningsId;

  ApiHighlightEntry({
    required this.overNumber,
    required this.ballNumber,
    required this.event,
    required this.type,
    required this.text,
    required this.timestamp,
    required this.batTeamName,
    required this.batsman,
    this.batsmanId,
    required this.bowler,
    this.bowlerId,
    required this.isWicket,
    required this.isFour,
    required this.isSix,
    this.scoreRuns,
    this.scoreWickets,
    this.inningsId,
  });

  factory ApiHighlightEntry.fromJson(Map<String, dynamic> json) {
    return ApiHighlightEntry(
      overNumber: (json['overNumber'] ?? 0).toDouble(),
      ballNumber: json['ballNumber'] ?? 0,
      event: json['event']?.toString() ?? 'NONE',
      type: json['type']?.toString() ?? 'other',
      text: json['text']?.toString() ?? '',
      timestamp: json['timestamp'] ?? 0,
      batTeamName: json['batTeamName']?.toString() ?? '',
      batsman: json['batsman']?.toString() ?? '',
      batsmanId: json['batsmanId']?.toString(),
      bowler: json['bowler']?.toString() ?? '',
      bowlerId: json['bowlerId']?.toString(),
      isWicket: json['isWicket'] ?? false,
      isFour: json['isFour'] ?? false,
      isSix: json['isSix'] ?? false,
      scoreRuns: json['score'] is Map ? json['score']['runs'] : null,
      scoreWickets: json['score'] is Map ? json['score']['wickets'] : null,
      inningsId: json['inningsId'],
    );
  }
}

class ApiHighlights {
  final List<ApiHighlightEntry> highlights;

  ApiHighlights({required this.highlights});

  factory ApiHighlights.fromJson(Map<String, dynamic> json) {
    final data = json['data'] ?? json;
    final list = data['highlights'] as List<dynamic>? ?? [];
    return ApiHighlights(
      highlights: list.map((e) => ApiHighlightEntry.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  List<ApiHighlightEntry> get wickets => highlights.where((h) => h.isWicket).toList();
  List<ApiHighlightEntry> get fours => highlights.where((h) => h.isFour).toList();
  List<ApiHighlightEntry> get sixes => highlights.where((h) => h.isSix).toList();
}
