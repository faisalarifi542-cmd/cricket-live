import '../../core/utils/cricket_helpers.dart';

class ApiTeam {
  final String id;
  final String name;
  final String shortName;
  final String? imageId;
  final String? logoUrl;
  final List<ApiInningsScore>? innings;

  ApiTeam({
    required this.id,
    required this.name,
    required this.shortName,
    this.imageId,
    this.logoUrl,
    this.innings,
  });

  factory ApiTeam.fromJson(Map<String, dynamic> json) {
    List<ApiInningsScore>? innings;
    if (json['innings'] is List) {
      innings = (json['innings'] as List)
          .map((e) => ApiInningsScore.fromJson(e))
          .toList();
    }
    return ApiTeam(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      shortName: json['short_name']?.toString() ?? '',
      imageId: json['image_id']?.toString(),
      logoUrl: json['logo_url']?.toString(),
      innings: innings,
    );
  }
}

class ApiInningsScore {
  final int runs;
  final int wickets;
  final double overs;
  final bool declared;
  final bool followOn;

  ApiInningsScore({
    required this.runs,
    required this.wickets,
    required this.overs,
    this.declared = false,
    this.followOn = false,
  });

  factory ApiInningsScore.fromJson(Map<String, dynamic> json) {
    return ApiInningsScore(
      runs: json['runs'] ?? 0,
      wickets: json['wickets'] ?? 0,
      overs: (json['overs'] is num) ? (json['overs'] as num).toDouble() : 0.0,
      declared: json['declared'] ?? false,
      followOn: json['follow_on'] ?? false,
    );
  }

  String get scoreText => '$runs/$wickets';
  String get oversText => '(${formatCricketOvers(overs)} ov)';
  String get fullText => '$runs/$wickets (${formatCricketOvers(overs)} ov)';
}

class ApiVenue {
  final String name;
  final String city;
  final String country;

  ApiVenue({required this.name, required this.city, required this.country});

  factory ApiVenue.fromJson(Map<String, dynamic> json) {
    return ApiVenue(
      name: json['name']?.toString() ?? '',
      city: json['city']?.toString() ?? '',
      country: json['country']?.toString() ?? '',
    );
  }

  String get displayName {
    final parts = [name, city, country].where((s) => s.isNotEmpty);
    return parts.isNotEmpty ? parts.join(', ') : '';
  }
}

class ApiMatchScore {
  final List<ApiInningsScore> team1;
  final List<ApiInningsScore> team2;

  ApiMatchScore({required this.team1, required this.team2});

  factory ApiMatchScore.fromJson(Map<String, dynamic> json) {
    return ApiMatchScore(
      team1: (json['team1'] as List?)
              ?.map((e) => ApiInningsScore.fromJson(e))
              .toList() ??
          [],
      team2: (json['team2'] as List?)
              ?.map((e) => ApiInningsScore.fromJson(e))
              .toList() ??
          [],
    );
  }
}

class ApiMatch {
  final String matchId;
  final String seriesId;
  final String seriesName;
  final String matchFormat;
  final String matchType;
  final String matchDesc;
  final String status;
  final String statusText;
  final String shortStatus;
  final ApiTeam team1;
  final ApiTeam team2;
  final ApiVenue venue;
  final DateTime? startTime;
  final DateTime? endTime;
  final int currentInnings;
  final String? currBatTeamId;
  final String? matchImageUrl;
  final ApiMatchScore? score;
  final DateTime? lastUpdated;

  ApiMatch({
    required this.matchId,
    required this.seriesId,
    required this.seriesName,
    required this.matchFormat,
    required this.matchType,
    this.matchDesc = '',
    required this.status,
    required this.statusText,
    this.shortStatus = '',
    required this.team1,
    required this.team2,
    required this.venue,
    this.startTime,
    this.endTime,
    required this.currentInnings,
    this.currBatTeamId,
    this.matchImageUrl,
    this.score,
    this.lastUpdated,
  });

  factory ApiMatch.fromJson(Map<String, dynamic> json) {
    return ApiMatch(
      matchId: json['match_id']?.toString() ?? '',
      seriesId: json['series_id']?.toString() ?? '',
      seriesName: json['series_name']?.toString() ?? '',
      matchFormat: json['match_format']?.toString() ?? '',
      matchType: json['match_type']?.toString() ?? '',
      matchDesc: json['match_desc']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      statusText: json['status_text']?.toString() ?? '',
      shortStatus: json['short_status']?.toString() ?? '',
      team1: ApiTeam.fromJson(json['team1'] ?? {}),
      team2: ApiTeam.fromJson(json['team2'] ?? {}),
      venue: ApiVenue.fromJson(json['venue'] ?? {}),
      startTime: json['start_time'] != null
          ? DateTime.tryParse(json['start_time'].toString())
          : null,
      endTime: json['end_time'] != null
          ? DateTime.tryParse(json['end_time'].toString())
          : null,
      currentInnings: json['current_innings'] ?? 0,
      currBatTeamId: json['curr_bat_team_id']?.toString(),
      matchImageUrl: json['match_image_url']?.toString(),
      score: json['score'] != null
          ? ApiMatchScore.fromJson(json['score'])
          : null,
      lastUpdated: json['last_updated'] != null
          ? DateTime.tryParse(json['last_updated'].toString())
          : null,
    );
  }

  bool get isLive => status == 'live' || status == 'in_progress';
  bool get isCompleted => status == 'completed';
  bool get isUpcoming => status == 'upcoming';

  String get formatLabel => matchFormat.toUpperCase();

  String get title => '${team1.name} vs ${team2.name}';

  String get team1Score {
    if (score == null || score!.team1.isEmpty) return '';
    return score!.team1.map((i) => i.fullText).join(' & ');
  }

  String get team2Score {
    if (score == null || score!.team2.isEmpty) return '';
    return score!.team2.map((i) => i.fullText).join(' & ');
  }
}
