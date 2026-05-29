String apiString(dynamic value, [String fallback = '']) {
  if (value == null) return fallback;
  final text = value.toString().trim();
  return text.isEmpty ? fallback : text;
}

int? apiInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

double? apiDouble(dynamic value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

DateTime? apiDate(dynamic value) => DateTime.tryParse(value?.toString() ?? '');

Map<String, dynamic> apiMap(dynamic value) =>
    value is Map<String, dynamic> ? value : <String, dynamic>{};

List<dynamic> apiList(dynamic value) {
  if (value is List) return value;
  if (value is Map<String, dynamic>) {
    for (final key in const ['items', 'matches', 'news', 'data', 'results']) {
      final nested = value[key];
      if (nested is List) return nested;
    }
  }
  return const [];
}

class ApiTeam {
  const ApiTeam({required this.id, required this.name, required this.shortName, this.logo});
  final String id;
  final String name;
  final String shortName;
  final String? logo;
  factory ApiTeam.fromJson(dynamic value) {
    final json = apiMap(value);
    final name = apiString(json['name'] ?? json['teamName'] ?? value, 'TBD');
    return ApiTeam(
      id: apiString(json['id'] ?? json['teamId'], name),
      name: name,
      shortName: apiString(json['shortName'] ?? json['code'], name.length > 3 ? name.substring(0, 3).toUpperCase() : name.toUpperCase()),
      logo: json['logo']?.toString(),
    );
  }
}

class ApiVenue {
  const ApiVenue({required this.name, this.city, this.country});
  final String name;
  final String? city;
  final String? country;
  factory ApiVenue.fromJson(dynamic value) {
    final json = apiMap(value);
    return ApiVenue(
      name: apiString(json['name'] ?? json['venue'] ?? value, 'Unknown'),
      city: json['city']?.toString(),
      country: json['country']?.toString(),
    );
  }
}

class ApiScore {
  const ApiScore({this.runs, this.wickets, this.overs, this.display});
  final int? runs;
  final int? wickets;
  final String? overs;
  final String? display;
  factory ApiScore.fromJson(dynamic value) {
    final json = apiMap(value);
    return ApiScore(
      runs: apiInt(json['runs']),
      wickets: apiInt(json['wickets']),
      overs: json['overs']?.toString(),
      display: value is String ? value : json['display']?.toString(),
    );
  }
}

class ApiMatchDetail {
  const ApiMatchDetail({required this.id, required this.title, required this.status, required this.venue});
  final String id;
  final String title;
  final String status;
  final String venue;
  factory ApiMatchDetail.fromJson(dynamic value) {
    final json = apiMap(value);
    return ApiMatchDetail(
      id: apiString(json['matchId'] ?? json['id']),
      title: apiString(json['title'] ?? json['name'], 'Match'),
      status: apiString(json['status'], 'Upcoming'),
      venue: apiString(json['venue'], 'Unknown'),
    );
  }
}

class LiveLine {
  const LiveLine({required this.status, this.score, this.lastUpdated});
  final String status;
  final String? score;
  final DateTime? lastUpdated;
  factory LiveLine.fromJson(dynamic value) {
    final json = apiMap(value);
    return LiveLine(
      status: apiString(json['status'] ?? json['matchStatus'], 'Live'),
      score: json['score']?.toString() ?? json['liveScore']?.toString(),
      lastUpdated: apiDate(json['lastUpdated']),
    );
  }
}

class Scorecard {
  const Scorecard({required this.available, required this.innings});
  final bool available;
  final List<dynamic> innings;
  factory Scorecard.fromJson(dynamic value) {
    final json = apiMap(value);
    final innings = apiList(json['innings'] ?? value);
    return Scorecard(available: innings.isNotEmpty, innings: innings);
  }
}

class CommentaryEntry {
  const CommentaryEntry({required this.text, this.over, this.time});
  final String text;
  final String? over;
  final DateTime? time;
  factory CommentaryEntry.fromJson(dynamic value) {
    final json = apiMap(value);
    return CommentaryEntry(
      text: apiString(json['text'] ?? json['commentary'] ?? value),
      over: json['over']?.toString(),
      time: apiDate(json['time']),
    );
  }
}

class OversData {
  const OversData({required this.overs});
  final List<dynamic> overs;
  factory OversData.fromJson(dynamic value) => OversData(overs: apiList(value));
}

class MatchSquads {
  const MatchSquads({required this.teams});
  final List<dynamic> teams;
  factory MatchSquads.fromJson(dynamic value) => MatchSquads(teams: apiList(value));
}

class StreamSource {
  const StreamSource({required this.id, required this.name, required this.url, this.quality});
  final String id;
  final String name;
  final String url;
  final String? quality;
  factory StreamSource.fromJson(dynamic value) {
    final json = apiMap(value);
    return StreamSource(
      id: apiString(json['id'] ?? json['streamId']),
      name: apiString(json['name'] ?? json['serverName'], 'Stream'),
      url: apiString(json['url'] ?? json['streamUrl']),
      quality: json['quality']?.toString(),
    );
  }
}

class ApiSeries {
  const ApiSeries({
    required this.id,
    required this.name,
    required this.status,
    this.startDate,
    this.endDate,
    this.format,
    this.country,
    this.matchCount,
  });
  final String id;
  final String name;
  final String status;
  final String? startDate;
  final String? endDate;
  final String? format;
  final String? country;
  final int? matchCount;
  factory ApiSeries.fromJson(dynamic value) {
    final json = apiMap(value);
    return ApiSeries(
      id: apiString(json['seriesId'] ?? json['id']),
      name: apiString(json['name'] ?? json['seriesName'], 'Series'),
      status: apiString(json['status'], 'Upcoming'),
      startDate: apiString(json['startDate'] ?? json['start_date'], '').isEmpty ? null : apiString(json['startDate'] ?? json['start_date']),
      endDate: apiString(json['endDate'] ?? json['end_date'], '').isEmpty ? null : apiString(json['endDate'] ?? json['end_date']),
      format: apiString(json['format'] ?? json['seriesType'] ?? json['series_type'], '').isEmpty ? null : apiString(json['format'] ?? json['seriesType'] ?? json['series_type']),
      country: apiString(json['country'] ?? json['host'], '').isEmpty ? null : apiString(json['country'] ?? json['host']),
      matchCount: apiInt(json['matchCount'] ?? json['totalMatches'] ?? json['matchesCount']),
    );
  }
}

class PointsTable {
  const PointsTable({required this.rows});
  final List<dynamic> rows;
  factory PointsTable.fromJson(dynamic value) => PointsTable(rows: apiList(value));
}

class SeriesStats {
  const SeriesStats({required this.sections});
  final Map<String, dynamic> sections;
  factory SeriesStats.fromJson(dynamic value) => SeriesStats(sections: apiMap(value));
}

class ApiSchedule {
  const ApiSchedule({required this.matches});
  final List<dynamic> matches;
  factory ApiSchedule.fromJson(dynamic value) => ApiSchedule(matches: apiList(value));
}

class NewsStory {
  const NewsStory({required this.id, required this.title, this.summary, this.image, this.publishedAt});
  final String id;
  final String title;
  final String? summary;
  final String? image;
  final DateTime? publishedAt;
  factory NewsStory.fromJson(dynamic value) {
    final json = apiMap(value);
    return NewsStory(
      id: apiString(json['id'] ?? json['newsId'] ?? json['slug'], apiString(json['title'])),
      title: apiString(json['title'] ?? json['headline'], 'Cricket news'),
      summary: json['summary']?.toString() ?? json['description']?.toString(),
      image: json['image']?.toString() ?? json['imageUrl']?.toString(),
      publishedAt: apiDate(json['publishedAt'] ?? json['date']),
    );
  }
}

class ApiPlayer {
  const ApiPlayer({
    required this.id,
    required this.name,
    this.role,
    this.country,
    this.image,
    this.battingStyle,
    this.bowlingStyle,
    this.dateOfBirth,
    this.stats = const {},
    this.recent = const [],
  });
  final String id;
  final String name;
  final String? role;
  final String? country;
  final String? image;
  final String? battingStyle;
  final String? bowlingStyle;
  final String? dateOfBirth;
  final Map<String, dynamic> stats;
  final List<dynamic> recent;
  factory ApiPlayer.fromJson(dynamic value) {
    final json = apiMap(value);
    return ApiPlayer(
      id: apiString(json['playerId'] ?? json['id']),
      name: apiString(json['name'], 'Player'),
      role: json['role']?.toString(),
      country: apiString(json['country'] ?? json['nationality'], '').isEmpty ? null : apiString(json['country'] ?? json['nationality']),
      image: apiString(json['image'] ?? json['imageUrl'] ?? json['profileImage'], '').isEmpty ? null : apiString(json['image'] ?? json['imageUrl'] ?? json['profileImage']),
      battingStyle: apiString(json['battingStyle'] ?? json['batting_style'], '').isEmpty ? null : apiString(json['battingStyle'] ?? json['batting_style']),
      bowlingStyle: apiString(json['bowlingStyle'] ?? json['bowling_style'], '').isEmpty ? null : apiString(json['bowlingStyle'] ?? json['bowling_style']),
      dateOfBirth: apiString(json['dateOfBirth'] ?? json['dob'], '').isEmpty ? null : apiString(json['dateOfBirth'] ?? json['dob']),
      stats: apiMap(json['stats'] ?? json['careerStats']),
      recent: apiList(json['recent'] ?? json['recentPerformance']),
    );
  }
}

class ApiTeamProfile {
  const ApiTeamProfile({
    required this.id,
    required this.name,
    this.shortName,
    this.country,
    this.logo,
    this.squad = const [],
    this.recentMatches = const [],
    this.series = const [],
  });
  final String id;
  final String name;
  final String? shortName;
  final String? country;
  final String? logo;
  final List<dynamic> squad;
  final List<dynamic> recentMatches;
  final List<dynamic> series;
  factory ApiTeamProfile.fromJson(dynamic value) {
    final json = apiMap(value);
    return ApiTeamProfile(
      id: apiString(json['teamId'] ?? json['id']),
      name: apiString(json['name'] ?? json['teamName'], 'Team'),
      shortName: apiString(json['shortName'] ?? json['teamShort'], '').isEmpty ? null : apiString(json['shortName'] ?? json['teamShort']),
      country: apiString(json['country'], '').isEmpty ? null : apiString(json['country']),
      logo: apiString(json['logo'] ?? json['logoUrl'], '').isEmpty ? null : apiString(json['logo'] ?? json['logoUrl']),
      squad: apiList(json['squad'] ?? json['players']),
      recentMatches: apiList(json['recentMatches'] ?? json['matches']),
      series: apiList(json['series'] ?? json['tournaments']),
    );
  }
}

class AppConfig {
  const AppConfig({required this.values});
  final Map<String, dynamic> values;
  factory AppConfig.fromJson(dynamic value) => AppConfig(values: apiMap(value));
}

class HomeConfig {
  const HomeConfig({required this.values});
  final Map<String, dynamic> values;
  factory HomeConfig.fromJson(dynamic value) => HomeConfig(values: apiMap(value));
}
