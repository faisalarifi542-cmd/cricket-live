class ApiScheduleTeam {
  final String id;
  final String name;
  final String shortName;
  final String? imageId;
  final String? logoUrl;

  ApiScheduleTeam({required this.id, required this.name, required this.shortName, this.imageId, this.logoUrl});

  factory ApiScheduleTeam.fromJson(Map<String, dynamic> json) => ApiScheduleTeam(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? '',
    shortName: json['shortName']?.toString() ?? '',
    imageId: json['imageId']?.toString(),
    logoUrl: json['logoUrl']?.toString(),
  );
}

class ApiScheduleVenue {
  final String name;
  final String city;
  final String country;
  final String timezone;

  ApiScheduleVenue({required this.name, required this.city, required this.country, required this.timezone});

  factory ApiScheduleVenue.fromJson(Map<String, dynamic> json) => ApiScheduleVenue(
    name: json['name']?.toString() ?? '',
    city: json['city']?.toString() ?? '',
    country: json['country']?.toString() ?? '',
    timezone: json['timezone']?.toString() ?? '',
  );
}

class ApiScheduleMatch {
  final String matchId;
  final String seriesId;
  final String matchDesc;
  final String matchFormat;
  final String startTime;
  final String endTime;
  final ApiScheduleVenue? venue;
  final ApiScheduleTeam? team1;
  final ApiScheduleTeam? team2;

  ApiScheduleMatch({required this.matchId, required this.seriesId, required this.matchDesc, required this.matchFormat, required this.startTime, required this.endTime, this.venue, this.team1, this.team2});

  factory ApiScheduleMatch.fromJson(Map<String, dynamic> json) => ApiScheduleMatch(
    matchId: json['matchId']?.toString() ?? '',
    seriesId: json['seriesId']?.toString() ?? '',
    matchDesc: json['matchDesc']?.toString() ?? '',
    matchFormat: json['matchFormat']?.toString() ?? '',
    startTime: json['startTime']?.toString() ?? '',
    endTime: json['endTime']?.toString() ?? '',
    venue: json['venue'] is Map<String, dynamic> ? ApiScheduleVenue.fromJson(json['venue']) : null,
    team1: json['team1'] is Map<String, dynamic> ? ApiScheduleTeam.fromJson(json['team1']) : null,
    team2: json['team2'] is Map<String, dynamic> ? ApiScheduleTeam.fromJson(json['team2']) : null,
  );

  DateTime? get startDateTime {
    final ms = int.tryParse(startTime);
    return ms != null ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
  }
}

class ApiScheduleSeries {
  final String seriesId;
  final String seriesName;
  final String category;
  final List<ApiScheduleMatch> matches;

  ApiScheduleSeries({required this.seriesId, required this.seriesName, required this.category, required this.matches});

  factory ApiScheduleSeries.fromJson(Map<String, dynamic> json) => ApiScheduleSeries(
    seriesId: json['seriesId']?.toString() ?? '',
    seriesName: json['seriesName']?.toString() ?? '',
    category: json['category']?.toString() ?? '',
    matches: (json['matches'] as List<dynamic>? ?? []).map((e) => ApiScheduleMatch.fromJson(e as Map<String, dynamic>)).toList(),
  );
}

class ApiScheduleDay {
  final String date;
  final List<ApiScheduleSeries> series;

  ApiScheduleDay({required this.date, required this.series});

  factory ApiScheduleDay.fromJson(Map<String, dynamic> json) => ApiScheduleDay(
    date: json['date']?.toString() ?? '',
    series: (json['series'] as List<dynamic>? ?? []).map((e) => ApiScheduleSeries.fromJson(e as Map<String, dynamic>)).toList(),
  );

  int get totalMatches => series.fold(0, (sum, s) => sum + s.matches.length);
}

class ApiSchedule {
  final List<ApiScheduleDay> days;

  ApiSchedule({required this.days});

  factory ApiSchedule.fromJson(Map<String, dynamic> json) {
    final data = json['data'] ?? json;
    return ApiSchedule(
      days: (data['days'] as List<dynamic>? ?? []).map((e) => ApiScheduleDay.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}
