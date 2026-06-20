class ApiSeriesStatType {
  final String value;
  final String header;
  final String category;

  ApiSeriesStatType({required this.value, required this.header, required this.category});

  factory ApiSeriesStatType.fromJson(Map<String, dynamic> json) {
    return ApiSeriesStatType(
      value: json['value'] ?? '',
      header: json['header'] ?? '',
      category: json['category'] ?? '',
    );
  }
}

class ApiSeriesStatsTypes {
  final List<ApiSeriesStatType> types;

  ApiSeriesStatsTypes({required this.types});

  factory ApiSeriesStatsTypes.fromJson(Map<String, dynamic> json) {
    return ApiSeriesStatsTypes(
      types: (json['types'] as List?)
              ?.map((e) => ApiSeriesStatType.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class ApiSeriesStatsPlayer {
  final String playerId;
  final String playerName;
  final String? imageUrl;
  final Map<String, String?> stats;

  ApiSeriesStatsPlayer({
    required this.playerId,
    required this.playerName,
    this.imageUrl,
    required this.stats,
  });

  factory ApiSeriesStatsPlayer.fromJson(Map<String, dynamic> json) {
    final stats = <String, String?>{};
    json.forEach((key, value) {
      if (key != 'playerId' && key != 'playerName' && key != 'imageUrl') {
        stats[key] = value?.toString();
      }
    });
    return ApiSeriesStatsPlayer(
      playerId: json['playerId']?.toString() ?? '',
      playerName: json['playerName'] ?? '',
      imageUrl: json['imageUrl']?.toString(),
      stats: stats,
    );
  }
}

class ApiSeriesStatsTable {
  final String header;
  final String category;
  final List<String> headers;
  final List<ApiSeriesStatsPlayer> players;

  ApiSeriesStatsTable({
    required this.header,
    required this.category,
    required this.headers,
    required this.players,
  });

  factory ApiSeriesStatsTable.fromJson(Map<String, dynamic> json) {
    return ApiSeriesStatsTable(
      header: json['header'] ?? '',
      category: json['category'] ?? '',
      headers: (json['headers'] as List?)?.map((e) => e.toString()).toList() ?? [],
      players: (json['players'] as List?)
              ?.map((e) => ApiSeriesStatsPlayer.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}
