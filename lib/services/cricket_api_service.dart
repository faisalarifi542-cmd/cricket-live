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

  List<dynamic> _asList(dynamic value) {
    if (value is List) return value;
    if (value is Map<String, dynamic>) {
      for (final key in const ['matches', 'items', 'news', 'data', 'results']) {
        final nested = value[key];
        if (nested is List) return nested;
      }
    }
    return const [];
  }
}
