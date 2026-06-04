import 'dart:convert';

String apiString(dynamic value, [String fallback = '']) {
  if (value == null) return fallback;
  final text = value.toString().trim();
  return text.isEmpty ? fallback : text;
}

String cleanText(dynamic value, [String fallback = '']) {
  final text = apiString(value, fallback);
  if (text.isEmpty) return fallback;
  return text.replaceAll('\\', '').trim();
}

String formatMatchDateTime(dynamic value) {
  if (value == null) return '';
  DateTime? date;
  if (value is DateTime) {
    date = value;
  } else {
    final text = value.toString().trim();
    if (text.isEmpty) return '';
    date = DateTime.tryParse(text);
    if (date == null) {
      final epoch = int.tryParse(text);
      if (epoch != null && epoch > 1000000000000) {
        date = DateTime.fromMillisecondsSinceEpoch(epoch, isUtc: true);
      }
    }
  }
  if (date == null) return value.toString();
  final local = date.toLocal();
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];
  final now = DateTime.now();
  final sameDay = now.year == local.year &&
      now.month == local.month &&
      now.day == local.day;
  final tomorrow = now.add(const Duration(days: 1));
  final isTomorrow = tomorrow.year == local.year &&
      tomorrow.month == local.month &&
      tomorrow.day == local.day;
  final day = sameDay
      ? 'Today'
      : isTomorrow
          ? 'Tomorrow'
          : '${local.day} ${months[local.month - 1]} ${local.year}';
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$day • $hour:$minute';
}

int? apiInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

bool apiBool(dynamic value, [bool fallback = false]) {
  if (value == null) return fallback;
  if (value is bool) return value;
  if (value is num) return value != 0;
  final text = value.toString().trim().toLowerCase();
  if (text == 'true' || text == '1' || text == 'yes' || text == 'on') {
    return true;
  }
  if (text == 'false' || text == '0' || text == 'no' || text == 'off') {
    return false;
  }
  return fallback;
}

double? apiDouble(dynamic value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

DateTime? apiDate(dynamic value) => DateTime.tryParse(value?.toString() ?? '');

Map<String, dynamic> apiMap(dynamic value) =>
    value is Map<String, dynamic>
        ? value
        : value is String
            ? () {
                try {
                  final decoded = jsonDecode(value);
                  return decoded is Map<String, dynamic>
                      ? decoded
                      : <String, dynamic>{};
                } catch (_) {
                  return <String, dynamic>{};
                }
              }()
            : <String, dynamic>{};

List<dynamic> apiList(dynamic value) {
  if (value is List) return value;
  if (value is String) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is List) return decoded;
      if (decoded is Map<String, dynamic>) {
        for (final key in const [
          'items',
          'stories',
          'paginatedData',
          'matches',
          'teams',
          'news',
          'data',
          'results',
          'commentary',
          'commentaryList',
          'rows',
        ]) {
          final nested = decoded[key];
          if (nested is List) return nested;
        }
      }
    } catch (_) {
      // fall through to empty list
    }
  }
  if (value is Map<String, dynamic>) {
    for (final key in const [
      'items',
      'stories',
      'paginatedData',
      'matches',
      'teams',
      'news',
      'data',
      'results',
      'commentary',
      'commentaryList',
      'rows',
    ]) {
      final nested = value[key];
      if (nested is List) return nested;
    }
  }
  return const [];
}

String? resolveCricbuzzImageUrl(dynamic value) {
  if (value is String && value.trim().isNotEmpty) {
    final text = value.trim();
    if (text.startsWith('http://') || text.startsWith('https://')) return text;
    if (RegExp(r'^\d+$').hasMatch(text) || text.startsWith('c')) {
      return resolveCricbuzzImageUrlFromFields(imageId: text);
    }
  }
  final json = apiMap(value);
  final imageDetails = apiMap(json['imageDetails'] ?? json['image_details']);
  final resolved = resolveCricbuzzImageUrlFromFields(
    logoUrl: json['logo_url'] ??
        json['logoUrl'] ??
        json['logoURL'] ??
        json['logo'] ??
        json['image_url'] ??
        json['imageUrl'] ??
        json['imageURL'] ??
        imageDetails['url'] ??
        imageDetails['imageUrl'],
    imageId: json['image_id'] ??
        json['imageId'] ??
        json['faceImageId'] ??
        json['face_image_id'] ??
        json['teamImageId'] ??
        json['team_image_id'] ??
        json['playerImageId'] ??
        json['player_image_id'] ??
        imageDetails['imageId'] ??
        imageDetails['image_id'],
  );
  if (resolved != null) return resolved;

  return resolveKnownTeamLogoUrl(
    id: json['id'] ?? json['team_id'] ?? json['teamId'],
    name: json['name'] ?? json['teamName'] ?? json['fullName'],
    shortName: json['short_name'] ??
        json['shortName'] ??
        json['teamShort'] ??
        json['team_short'] ??
        json['abbr'] ??
        json['code'],
  );
}

String? resolveCricbuzzImageUrlFromFields({
  dynamic logoUrl,
  dynamic imageUrl,
  dynamic imageId,
}) {
  final direct = apiString(logoUrl ?? imageUrl ?? '', '');
  if (direct.isNotEmpty) return direct;

  final imageKey = apiString(imageId);
  if (imageKey.isEmpty) return null;
  final normalized =
      imageKey.startsWith('c') ? imageKey.substring(1) : imageKey;
  return 'https://static.cricbuzz.com/a/img/v1/i1/c$normalized/i.jpg';
}

String? resolveKnownTeamLogoUrl({
  dynamic id,
  dynamic name,
  dynamic shortName,
}) {
  final candidates = [
    apiString(id),
    apiString(shortName),
    apiString(name),
  ].map(_normalizeTeamKey).where((value) => value.isNotEmpty);

  for (final key in candidates) {
    final imageId = _knownTeamImageIds[key];
    if (imageId != null) {
      return resolveCricbuzzImageUrlFromFields(imageId: imageId);
    }
  }
  return null;
}

String _normalizeTeamKey(String value) {
  return value
      .trim()
      .toUpperCase()
      .replaceAll(RegExp(r'[^A-Z0-9]+'), ' ');
}

const Map<String, String> _knownTeamImageIds = {
  '5': '776254',
  'SL': '776254',
  'SRI LANKA': '776254',
  '10': '776191',
  'WI': '776191',
  'WEST INDIES': '776191',
  '2': '776182',
  'IND': '776182',
  'INDIA': '776182',
  '96': '778316',
  'AFG': '778316',
  'AFGHANISTAN': '778316',
  '3': '776308',
  'PAK': '776308',
  'PAKISTAN': '776308',
  '4': '776202',
  'AUS': '776202',
  'AUSTRALIA': '776202',
  '9': '776241',
  'ENG': '776241',
  'ENGLAND': '776241',
  '13': '776263',
  'NZ': '776263',
  'NEW ZEALAND': '776263',
  '11': '776313',
  'SA': '776313',
  'SOUTH AFRICA': '776313',
  '6': '776210',
  'BAN': '776210',
  'BANGLADESH': '776210',
};

/// Normalizes cricket overs format.
/// Converts invalid formats like 19.6 to 20.0 (6 balls = 1 over).
/// Examples:
/// - 19.6 â†’ 20.0
/// - 18.6 â†’ 19.0
/// - 4.6 â†’ 5.0
/// - 18.4 â†’ 18.4 (valid, unchanged)
String normalizeOversText(dynamic value) {
  if (value == null) return '';

  final str = value.toString().trim();
  if (str.isEmpty) return '';

  // Try to parse as number
  final num? parsed = num.tryParse(str);
  if (parsed == null) return str;

  // Split into overs and balls
  final overs = parsed.floor();
  final balls = ((parsed - overs) * 10).round();

  // If balls >= 6, carry over to next over
  if (balls >= 6) {
    final extraOvers = balls ~/ 6;
    final remainingBalls = balls % 6;
    final normalizedOvers = overs + extraOvers;

    if (remainingBalls == 0) {
      return '$normalizedOvers.0';
    }
    return '$normalizedOvers.$remainingBalls';
  }

  // Valid format, return as is
  if (balls == 0) {
    return '$overs.0';
  }
  return '$overs.$balls';
}

/// Formats team initials safely, ensuring they fit in UI circles.
/// Returns 2-3 character uppercase initials.
String safeTeamInitials(String name) {
  final cleaned = name.trim();
  if (cleaned.isEmpty) return 'TBD';

  // If already short (3 chars or less), use as is
  if (cleaned.length <= 3) {
    return cleaned.toUpperCase();
  }

  // Split by spaces and take first letters
  final parts =
      cleaned.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.length >= 2) {
    // Take first letter of first two words
    return parts.take(2).map((p) => p[0]).join().toUpperCase();
  }

  // Single word, take first 3 characters
  return cleaned.substring(0, 3).toUpperCase();
}

/// Formats match title from team names, avoiding hardcoded titles.
String formatMatchTitle(String team1, String team2,
    {String? shortName1, String? shortName2}) {
  final t1 = team1.trim().isEmpty ? 'TBD' : team1.trim();
  final t2 = team2.trim().isEmpty ? 'TBD' : team2.trim();

  // Use short names if available and not empty
  if (shortName1 != null &&
      shortName1.trim().isNotEmpty &&
      shortName2 != null &&
      shortName2.trim().isNotEmpty) {
    return '${shortName1.trim()} vs ${shortName2.trim()}';
  }

  return '$t1 vs $t2';
}

/// Formats team score with normalized overs.
String formatTeamScore(int? runs, int? wickets, dynamic overs) {
  if (runs == null) return '';

  final scoreText = wickets == null ? '$runs' : '$runs/$wickets';

  if (overs == null) return scoreText;

  final normalizedOvers = normalizeOversText(overs);
  if (normalizedOvers.isEmpty) return scoreText;

  return '$scoreText ($normalizedOvers OV)';
}

/// Formats result text, normalizing common abbreviations.
String formatResultText(String? result) {
  if (result == null || result.trim().isEmpty) return '';

  final text = result.trim();

  // Normalize common abbreviations
  final normalized = text
      .replaceAll(RegExp(r'\bwkts\b', caseSensitive: false), 'wickets')
      .replaceAll(RegExp(r'\bruns?\b', caseSensitive: false), 'runs');

  return normalized;
}

/// Formats status chip text.
String formatStatusChip(String status) {
  final lower = status.toLowerCase().trim();

  if (lower == 'live' || lower == 'in_progress' || lower == 'inprogress') {
    return 'LIVE';
  }
  if (lower == 'completed' || lower == 'finished' || lower == 'result') {
    return 'RESULT';
  }
  if (lower == 'upcoming' || lower == 'scheduled' || lower == 'not_started') {
    return 'UPCOMING';
  }

  return status.toUpperCase();
}

class ApiTeam {
  const ApiTeam(
      {required this.id,
      required this.name,
      required this.shortName,
      this.logo});
  final String id;
  final String name;
  final String shortName;
  final String? logo;
  factory ApiTeam.fromJson(dynamic value) {
    final json = apiMap(value);
    final name = apiString(
        json['name'] ?? json['teamName'] ?? json['team_name'] ?? value, 'TBD');

    final logoUrl = resolveCricbuzzImageUrl(json);

    return ApiTeam(
      id: apiString(json['id'] ?? json['teamId'] ?? json['team_id'], name),
      name: name,
      shortName: apiString(
          json['shortName'] ??
              json['short_name'] ??
              json['teamShort'] ??
              json['team_short'] ??
              json['teamShortName'] ??
              json['code'],
          name.length > 3
              ? name.substring(0, 3).toUpperCase()
              : name.toUpperCase()),
      logo: logoUrl,
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
  const ApiMatchDetail(
      {required this.id,
      required this.title,
      required this.status,
      required this.venue});
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
  factory MatchSquads.fromJson(dynamic value) =>
      MatchSquads(teams: apiList(value));
}

class StreamSource {
  const StreamSource({
    required this.id,
    required this.name,
    required this.url,
    this.quality,
    this.label,
    this.language,
    this.streamType,
    this.isPremium = false,
    this.requiresRewardAd = false,
    this.requiresLogin = false,
    this.priority,
    this.status,
    this.backupUrl,
    this.headers = const {},
    this.drm = const {},
  });
  final String id;
  final String name;
  final String url;
  final String? quality;
  final String? label;
  final String? language;
  final String? streamType;
  final bool isPremium;
  final bool requiresRewardAd;
  final bool requiresLogin;
  final int? priority;
  final String? status;
  final String? backupUrl;
  final Map<String, dynamic> headers;
  final Map<String, dynamic> drm;

  String get qualityLabel => apiString(label ?? quality, 'AUTO');
  String get qualityCode => apiString(quality ?? label, 'AUTO').toUpperCase();
  String get type => apiString(streamType, 'hls').toLowerCase();
  bool get isHls => type == 'hls' || url.toLowerCase().contains('.m3u8');
  bool get isDash =>
      type == 'dash' || type == 'mpd' || url.toLowerCase().contains('.mpd');
  bool get isExternal => type == 'external' || type == 'iframe';
  bool get isPlayable => url.isNotEmpty && !isExternal && !isDash;
  bool get isWorking =>
      status == null ||
      status!.isEmpty ||
      status!.toLowerCase() == 'unknown' ||
      status!.toLowerCase() == 'working' ||
      status!.toLowerCase() == 'active';
  int get qualityRank => switch (qualityCode) {
        'AUTO' => 0,
        'FHD' => 1,
        'HD' => 2,
        'SD' => 3,
        _ => 4,
      };

  factory StreamSource.fromJson(dynamic value) {
    final json = apiMap(value);
    return StreamSource(
      id: apiString(json['id'] ?? json['streamId']),
      name: apiString(
          json['serverName'] ?? json['server_name'] ?? json['name'], 'Server'),
      url: apiString(json['url'] ?? json['streamUrl'] ?? json['stream_url']),
      quality: json['quality']?.toString(),
      label: json['label']?.toString(),
      language: json['language']?.toString(),
      streamType:
          json['streamType']?.toString() ?? json['stream_type']?.toString(),
      isPremium: json['isPremium'] == true ||
          json['isPremium'] == 1 ||
          json['is_premium'] == 1,
      requiresRewardAd: json['requiresRewardAd'] == true ||
          json['requiresRewardAd'] == 1 ||
          json['requires_reward_ad'] == 1,
      requiresLogin: json['requiresLogin'] == true ||
          json['requiresLogin'] == 1 ||
          json['requires_login'] == 1,
      priority: apiInt(json['priority']),
      status: json['status']?.toString(),
      backupUrl: apiString(
              json['backupUrl'] ?? json['backup_url'] ?? json['backup_stream_url'])
          .isEmpty
          ? null
          : apiString(
              json['backupUrl'] ?? json['backup_url'] ?? json['backup_stream_url']),
      headers: apiMap(json['headers'] ?? json['headers_json']),
      drm: apiMap(json['drm']),
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
    final id = cleanText(json['seriesId'] ??
        json['series_id'] ??
        json['id'] ??
        json['seasonSeriesId'] ??
        json['source_series_id'] ??
        json['sourceSeriesId']);
    final name = cleanText(
        json['name'] ??
            json['seriesName'] ??
            json['series_name'] ??
            json['source_series_name'] ??
            json['sourceSeriesName'] ??
            json['title'],
        'Series');
    return ApiSeries(
      id: id,
      name: name,
      status: apiString(json['status'], 'Upcoming'),
      startDate: apiString(
                  json['startDate'] ??
                      json['start_date'] ??
                      json['startTime'] ??
                      json['start_time'],
                  '')
              .isEmpty
          ? null
          : apiString(json['startDate'] ??
              json['start_date'] ??
              json['startTime'] ??
              json['start_time']),
      endDate: apiString(
                  json['endDate'] ??
                      json['end_date'] ??
                      json['endTime'] ??
                      json['end_time'],
                  '')
              .isEmpty
          ? null
          : apiString(json['endDate'] ??
              json['end_date'] ??
              json['endTime'] ??
              json['end_time']),
      format: apiString(
                  json['format'] ?? json['seriesType'] ?? json['series_type'],
                  '')
              .isEmpty
          ? null
          : apiString(
              json['format'] ?? json['seriesType'] ?? json['series_type']),
      country: apiString(json['country'] ?? json['host'], '').isEmpty
          ? null
          : apiString(json['country'] ?? json['host']),
      matchCount: apiInt(
          json['matchCount'] ?? json['totalMatches'] ?? json['matchesCount']),
    );
  }
}

class PointsTable {
  const PointsTable({required this.rows});
  final List<dynamic> rows;
  factory PointsTable.fromJson(dynamic value) =>
      PointsTable(rows: apiList(value));
}

class SeriesStats {
  const SeriesStats({required this.sections});
  final Map<String, dynamic> sections;
  factory SeriesStats.fromJson(dynamic value) =>
      SeriesStats(sections: apiMap(value));
}

class ApiSchedule {
  const ApiSchedule({required this.matches});
  final List<dynamic> matches;
  factory ApiSchedule.fromJson(dynamic value) =>
      ApiSchedule(matches: apiList(value));
}

class NewsStory {
  const NewsStory(
      {required this.id,
      required this.title,
      this.summary,
      this.body,
      this.image,
      this.imageId,
      this.imageUrl,
      this.publishedAt,
      this.publishedLabel,
      this.context,
      this.storyType});
  final String id;
  final String title;
  final String? summary;
  final String? body;
  final String? image;
  final String? imageId;
  final String? imageUrl;
  final DateTime? publishedAt;
  final String? publishedLabel;
  final String? context;
  final String? storyType;
  factory NewsStory.fromJson(dynamic value) {
    final json = apiMap(value);
    final imageUrl = resolveCricbuzzImageUrl(json);
    final imageDetails = apiMap(json['imageDetails'] ?? json['image_details']);
    final imageId = apiString(
      json['imageId'] ?? json['image_id'] ?? imageDetails['imageId'],
      '',
    );
    final publishedRaw = json['publishedTime'] ??
        json['published_time'] ??
        json['publishedAt'] ??
        json['date'];
    return NewsStory(
      id: apiString(json['id'] ?? json['newsId'] ?? json['slug'],
          apiString(json['title'] ?? json['headline'])),
      title: apiString(json['title'] ?? json['headline'], 'Cricket news'),
      summary: json['summary']?.toString() ??
          json['description']?.toString() ??
          json['intro']?.toString(),
      body: json['content']?.toString() ??
          json['body']?.toString() ??
          json['articleBody']?.toString(),
      image: imageUrl,
      imageId: imageId.isEmpty ? null : imageId,
      imageUrl: imageUrl,
      publishedAt: apiDate(publishedRaw),
      publishedLabel: apiString(publishedRaw, 'Latest'),
      context: apiString(json['context'] ?? json['category'], ''),
      storyType: apiString(json['storyType'] ?? json['story_type'], ''),
    );
  }
}

class RankingEntry {
  const RankingEntry({
    required this.rank,
    required this.name,
    required this.country,
    required this.rating,
    this.playerId,
    this.teamId,
    this.points,
    this.matches,
    this.movement = 0,
    this.imageUrl,
    this.isTeam = false,
  });

  final int rank;
  final String name;
  final String country;
  final int rating;
  final String? playerId;
  final String? teamId;
  final int? points;
  final int? matches;
  final int movement;
  final String? imageUrl;
  final bool isTeam;

  factory RankingEntry.fromJson(dynamic value) {
    final json = apiMap(value);
    final isTeam = apiString(json['category']).toLowerCase() == 'teams' ||
        json.containsKey('teamName') ||
        json.containsKey('team_name');
    return RankingEntry(
      rank: apiInt(json['rank'] ?? json['position']) ?? 0,
      name: apiString(
          json['playerName'] ??
              json['player_name'] ??
              json['teamName'] ??
              json['team_name'] ??
              json['name'],
          isTeam ? 'Team' : 'Player'),
      country: apiString(json['country'] ?? json['countryCode'] ?? '', ''),
      rating: apiInt(json['rating']) ?? 0,
      playerId:
          apiString(json['playerId'] ?? json['player_id'] ?? json['id'], '')
                  .isEmpty
              ? null
              : apiString(json['playerId'] ?? json['player_id'] ?? json['id']),
      teamId: apiString(json['teamId'] ?? json['team_id'], '').isEmpty
          ? null
          : apiString(json['teamId'] ?? json['team_id']),
      points: apiInt(json['points']),
      matches: apiInt(json['matches'] ?? json['matchCount']),
      movement: apiInt(json['movement'] ?? json['trend']) ?? 0,
      imageUrl: resolveCricbuzzImageUrl(json),
      isTeam: isTeam,
    );
  }
}

class ApiPlayer {
  const ApiPlayer({
    required this.id,
    required this.name,
    this.fullName,
    this.role,
    this.country,
    this.countryCode,
    this.image,
    this.imageId,
    this.battingStyle,
    this.bowlingStyle,
    this.dateOfBirth,
    this.birthPlace,
    this.nationality,
    this.debut,
    this.jerseyNumber,
    this.rankings,
    this.careerSummary = const [],
    this.battingStats = const [],
    this.bowlingStats = const [],
    this.recentForm = const [],
    this.achievements = const [],
    this.teams = const [],
    this.bio,
    this.stats = const {},
    this.recent = const [],
  });
  final String id;
  final String name;
  final String? fullName;
  final String? role;
  final String? country;
  final String? countryCode;
  final String? image;
  final String? imageId;
  final String? battingStyle;
  final String? bowlingStyle;
  final String? dateOfBirth;
  final String? birthPlace;
  final String? nationality;
  final String? debut;
  final String? jerseyNumber;
  final Map<String, dynamic>? rankings;
  final List<dynamic> careerSummary;
  final List<dynamic> battingStats;
  final List<dynamic> bowlingStats;
  final List<dynamic> recentForm;
  final List<dynamic> achievements;
  final List<dynamic> teams;
  final String? bio;
  final Map<String, dynamic> stats;
  final List<dynamic> recent;
  factory ApiPlayer.fromJson(dynamic value) {
    final json = apiMap(value);
    final imageId = apiString(json['imageId'] ?? json['image_id'], '').isEmpty
        ? null
        : apiString(json['imageId'] ?? json['image_id']);
    final imageUrl = resolveCricbuzzImageUrl(json) ??
        (imageId == null
            ? ''
            : 'https://static.cricbuzz.com/a/img/v1/i1/c${imageId.startsWith('c') ? imageId.substring(1) : imageId}/i.jpg');
    return ApiPlayer(
      id: apiString(json['playerId'] ?? json['player_id'] ?? json['id']),
      name: apiString(json['name'], 'Player'),
      fullName:
          apiString(json['fullName'] ?? json['full_name'] ?? json['name'], ''),
      role: json['role']?.toString(),
      country: apiString(json['country'] ?? json['nationality'], '').isEmpty
          ? null
          : apiString(json['country'] ?? json['nationality']),
      countryCode:
          apiString(json['countryCode'] ?? json['country_code'], '').isEmpty
              ? null
              : apiString(json['countryCode'] ?? json['country_code']),
      image: imageUrl.isNotEmpty
          ? imageUrl
          : (apiString(json['image'] ?? json['profileImage'], '').isEmpty
              ? null
              : apiString(json['image'] ?? json['profileImage'])),
      imageId: imageId,
      battingStyle:
          apiString(json['battingStyle'] ?? json['batting_style'], '').isEmpty
              ? null
              : apiString(json['battingStyle'] ?? json['batting_style']),
      bowlingStyle:
          apiString(json['bowlingStyle'] ?? json['bowling_style'], '').isEmpty
              ? null
              : apiString(json['bowlingStyle'] ?? json['bowling_style']),
      dateOfBirth: apiString(json['dateOfBirth'] ?? json['dob'], '').isEmpty
          ? null
          : apiString(json['dateOfBirth'] ?? json['dob']),
      birthPlace:
          apiString(json['birthPlace'] ?? json['birth_place'], '').isEmpty
              ? null
              : apiString(json['birthPlace'] ?? json['birth_place']),
      nationality: apiString(json['nationality'] ?? json['country'], '').isEmpty
          ? null
          : apiString(json['nationality'] ?? json['country']),
      debut: apiString(json['debut'], '').isEmpty
          ? null
          : apiString(json['debut']),
      jerseyNumber:
          apiString(json['jerseyNumber'] ?? json['jersey_number'], '').isEmpty
              ? null
              : apiString(json['jerseyNumber'] ?? json['jersey_number']),
      rankings: apiMap(json['rankings']),
      careerSummary: apiList(json['careerSummary'] ?? json['career_summary']),
      battingStats: apiList(json['battingStats'] ?? json['batting_stats']),
      bowlingStats: apiList(json['bowlingStats'] ?? json['bowling_stats']),
      recentForm: apiList(json['recentForm'] ?? json['recent_form']),
      achievements: apiList(json['achievements']),
      teams: apiList(json['teams']),
      bio: apiString(json['bio'], '').isEmpty ? null : apiString(json['bio']),
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

    final logoUrl = resolveCricbuzzImageUrl(json);

    return ApiTeamProfile(
      id: apiString(json['teamId'] ?? json['id']),
      name: cleanText(
          json['name'] ?? json['teamName'] ?? json['team_name'], 'Team'),
      shortName: cleanText(
                  json['shortName'] ??
                      json['short_name'] ??
                      json['teamShort'] ??
                      json['team_short'] ??
                      json['teamShortName'],
                  '')
              .isEmpty
          ? null
          : cleanText(json['shortName'] ??
              json['short_name'] ??
              json['teamShort'] ??
              json['team_short'] ??
              json['teamShortName']),
      country: apiString(json['country'], '').isEmpty
          ? null
          : apiString(json['country']),
      logo: logoUrl,
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

  Map<String, dynamic> get app => apiMap(values['app']);
  Map<String, dynamic> get features => apiMap(values['features']);
  Map<String, dynamic> get player => apiMap(values['player']);
  Map<String, dynamic> get ads => apiMap(values['ads']);
  Map<String, dynamic> get notifications => apiMap(values['notifications']);

  bool get maintenanceMode =>
      _boolPath(['maintenanceMode']) || _boolPath(['app', 'maintenanceMode']);
  bool get forceUpdateEnabled =>
      _boolPath(['forceUpdateEnabled']) || _boolPath(['app', 'forceUpdateEnabled']);
  bool get liveStreamingEnabled =>
      _boolPath(['enableLiveStreaming'], fallback: true) &&
      _boolPath(['features', 'liveStreamsEnabled'], fallback: true) &&
      _boolPath(['features', 'liveStreaming'], fallback: true);
  bool get adsEnabled =>
      _boolPath(['enableAds']) ||
      _boolPath(['features', 'adsEnabled']) ||
      _boolPath(['features', 'ads']) ||
      _boolPath(['ads', 'enabled']);
  String get defaultHomeTab =>
      _stringPath(['defaultHomeTab']) ?? _stringPath(['app', 'defaultHomeTab']) ?? 'live';
  String get streamUnavailableMessage =>
      _stringPath(['streamUnavailableMessage']) ??
      _stringPath(['player', 'streamUnavailableMessage']) ??
      'Live stream will be available closer to match time.';
  String get defaultStreamQuality =>
      _stringPath(['defaultStreamQuality']) ??
      _stringPath(['player', 'defaultStreamQuality']) ??
      'AUTO';
  int get liveLineRefreshSeconds =>
      _intPath(['liveLineRefreshSeconds']) ?? _intPath(['player', 'liveLineRefreshSeconds']) ?? 5;
  int get liveScoreRefreshSeconds =>
      _intPath(['liveScoreRefreshSeconds']) ?? _intPath(['player', 'liveScoreRefreshSeconds']) ?? 5;
  int get scorecardRefreshSeconds =>
      _intPath(['scorecardRefreshSeconds']) ?? _intPath(['player', 'scorecardRefreshSeconds']) ?? 30;
  int get commentaryRefreshSeconds =>
      _intPath(['commentaryRefreshSeconds']) ?? _intPath(['player', 'commentaryRefreshSeconds']) ?? 30;
  int get oversRefreshSeconds =>
      _intPath(['oversRefreshSeconds']) ?? _intPath(['player', 'oversRefreshSeconds']) ?? 20;
  String? get oneSignalAppId =>
      _stringPath(['notifications', 'oneSignalAppId']) ?? _stringPath(['oneSignalAppId']);

  bool _boolPath(List<String> path, {bool fallback = false}) {
    dynamic current = values;
    for (final key in path) {
      if (current is Map<String, dynamic>) {
        current = current[key];
      } else {
        return fallback;
      }
    }
    return apiBool(current, fallback);
  }

  String? _stringPath(List<String> path) {
    dynamic current = values;
    for (final key in path) {
      if (current is Map<String, dynamic>) {
        current = current[key];
      } else {
        return null;
      }
    }
    final text = current?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  int? _intPath(List<String> path) {
    final text = _stringPath(path);
    if (text == null) return null;
    return int.tryParse(text);
  }
}

class HomeConfig {
  const HomeConfig({required this.values});
  final Map<String, dynamic> values;
  factory HomeConfig.fromJson(dynamic value) =>
      HomeConfig(values: apiMap(value));
}

