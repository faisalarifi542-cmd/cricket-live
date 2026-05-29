import '../core/api/api_client.dart';
import '../models/api_response.dart';
import '../models/cricket_match.dart';

class CricketApiService {
  CricketApiService({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  Future<ApiEnvelope<List<CricketMatch>>> liveMatches() => _matchList('/matches/live');

  Future<ApiEnvelope<List<CricketMatch>>> upcomingMatches() => _matchList('/matches/upcoming');

  Future<ApiEnvelope<List<CricketMatch>>> recentMatches() => _matchList('/matches/recent');

  Future<ApiEnvelope<Map<String, dynamic>>> appConfig() => _map('/app-config');

  Future<ApiEnvelope<Map<String, dynamic>>> homeConfig() => _map('/home-config');

  Future<ApiEnvelope<Map<String, dynamic>>> appHome() => _map('/app/home');

  Future<ApiEnvelope<Map<String, dynamic>>> matchDetail(String matchId) => _map('/match/$matchId');

  Future<ApiEnvelope<Map<String, dynamic>>> matchLiveLine(String matchId) => _map('/match/$matchId/live-line');

  Future<ApiEnvelope<Map<String, dynamic>>> matchScorecard(String matchId) => _map('/match/$matchId/scorecard');

  Future<ApiEnvelope<Map<String, dynamic>>> matchCommentary(String matchId, {int page = 1, int limit = 50}) =>
      _map('/match/$matchId/commentary', query: {'page': page, 'limit': limit});

  Future<ApiEnvelope<Map<String, dynamic>>> matchOvers(String matchId) => _map('/match/$matchId/overs');

  Future<ApiEnvelope<Map<String, dynamic>>> matchSquads(String matchId) => _map('/match/$matchId/squads');

  Future<ApiEnvelope<Map<String, dynamic>>> matchStreams(String matchId) => _map('/match/$matchId/streams');

  Future<ApiEnvelope<List<dynamic>>> series() => _list('/series');

  Future<ApiEnvelope<Map<String, dynamic>>> seriesDetail(String seriesId) => _map('/series/$seriesId');

  Future<ApiEnvelope<List<dynamic>>> seriesMatches(String seriesId, {String? status}) =>
      _list('/series/$seriesId/matches', query: {'status': status});

  Future<ApiEnvelope<Map<String, dynamic>>> pointsTable(String seriesId) => _map('/points-table/$seriesId');

  Future<ApiEnvelope<Map<String, dynamic>>> seriesStats(String seriesId) => _map('/series/$seriesId/stats');

  Future<ApiEnvelope<List<dynamic>>> seriesSchedule(String seriesId) => _list('/series/$seriesId/schedule');

  Future<ApiEnvelope<List<dynamic>>> seriesTeams(String seriesId) => _list('/series/$seriesId/teams');

  Future<ApiEnvelope<List<dynamic>>> schedule({String type = 'upcoming'}) => _list('/schedule/upcoming${type == 'upcoming' ? '' : '/$type'}');

  /// Returns schedule grouped by day. Each day exposes its label and the list
  /// of matches that begin on that day. The webcrichd schedule endpoint
  /// returns `{ data: { days: [{ date, series: [{ matches: [...] }] }] } }`,
  /// so the helper flattens that structure for the UI layer.
  Future<ApiEnvelope<List<Map<String, dynamic>>>> scheduleDays({String type = 'upcoming'}) async {
    final path = '/schedule/upcoming${type == 'upcoming' ? '' : '/$type'}';
    final json = await _client.get(path);
    return ApiEnvelope.fromJson(json, (value) {
      final root = value is Map<String, dynamic> ? value : <String, dynamic>{};
      final days = root['days'];
      if (days is! List) return const <Map<String, dynamic>>[];
      return [
        for (final raw in days)
          if (raw is Map<String, dynamic>)
            <String, dynamic>{
              'date': raw['date']?.toString() ?? '',
              'matches': _flattenSeriesMatches(raw),
            },
      ];
    });
  }

  Future<ApiEnvelope<List<dynamic>>> news({int limit = 20}) => _list('/news', query: {'limit': limit});

  Future<ApiEnvelope<Map<String, dynamic>>> newsDetail(String newsId) => _map('/news/$newsId');

  Future<ApiEnvelope<Map<String, dynamic>>> player(String playerId) => _map('/player/$playerId');

  Future<ApiEnvelope<Map<String, dynamic>>> team(String teamId) => _map('/team/$teamId');

  Future<ApiEnvelope<List<CricketMatch>>> _matchList(String path) async {
    final json = await _client.get(path);
    return ApiEnvelope.fromJson(json, (value) => _asList(value).map(CricketMatch.fromJson).toList());
  }

  Future<ApiEnvelope<List<dynamic>>> _list(String path, {Map<String, dynamic>? query}) async {
    final json = await _client.get(path, query: query);
    return ApiEnvelope.fromJson(json, _asList);
  }

  Future<ApiEnvelope<Map<String, dynamic>>> _map(String path, {Map<String, dynamic>? query}) async {
    final json = await _client.get(path, query: query);
    return ApiEnvelope.fromJson(json, (value) => value is Map<String, dynamic> ? value : <String, dynamic>{});
  }

  /// Recursively unwrap the response payload into a flat `List<dynamic>` of
  /// match-shaped maps. The API returns several different shapes:
  /// - `{ data: [...] }` — `/matches/live`, `/matches/recent`, ...
  /// - `{ data: { matches: [...] } }` — alternate shape.
  /// - `{ data: { days: [{ series: [{ matches: [...] }] }] } }` — schedule.
  List<dynamic> _asList(dynamic value) {
    if (value is List) return value;
    if (value is Map<String, dynamic>) {
      // Schedule shape — `days` is the outermost grouping.
      if (value['days'] is List) {
        final List<dynamic> flat = [];
        for (final day in (value['days'] as List)) {
          if (day is Map<String, dynamic>) {
            flat.addAll(_flattenSeriesMatches(day));
          }
        }
        return flat;
      }
      for (final key in const ['matches', 'items', 'news', 'data', 'results']) {
        final nested = value[key];
        if (nested is List) return nested;
      }
    }
    return const [];
  }

  static List<Map<String, dynamic>> _flattenSeriesMatches(Map<String, dynamic> day) {
    final out = <Map<String, dynamic>>[];
    final series = day['series'];
    if (series is! List) return out;
    for (final entry in series) {
      if (entry is! Map<String, dynamic>) continue;
      final matches = entry['matches'];
      if (matches is! List) continue;
      for (final raw in matches) {
        if (raw is! Map<String, dynamic>) continue;
        // Merge series-level metadata onto each match so the parser has
        // everything it needs.
        out.add(<String, dynamic>{
          ...raw,
          'series_name': raw['series_name'] ?? raw['seriesName'] ?? entry['seriesName'] ?? entry['series_name'],
          'series_id': raw['series_id'] ?? raw['seriesId'] ?? entry['seriesId'] ?? entry['series_id'],
          'match_type': raw['match_type'] ?? raw['matchType'] ?? entry['category'],
          // Schedule entries don't carry an explicit status — every match
          // returned by `/schedule/upcoming` is upcoming.
          'status': raw['status'] ?? 'upcoming',
          'day_date': day['date'],
        });
      }
    }
    return out;
  }
}
