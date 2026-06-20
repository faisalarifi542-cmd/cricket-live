import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';
import '../../core/network/api_exception.dart';
import '../../models/api/api_match_model.dart';
import '../../models/api/api_match_detail_model.dart';
import '../../models/api/api_scorecard_model.dart';
import '../../models/api/api_commentary_model.dart';
import '../../models/api/api_series_model.dart';
import '../../models/api/api_player_model.dart';
import '../../models/api/api_team_model.dart';
import '../../models/api/api_series_stats_model.dart';
import '../../models/api/api_highlights_model.dart';
import '../../models/api/api_balls_map_model.dart';
import '../../models/api/api_over_by_over_model.dart';
import '../../models/api/api_schedule_model.dart';
import '../../models/news_model.dart';

class CricketApiService {
  final ApiClient _client = ApiClient.instance;

  // System
  Future<bool> checkHealth() => _client.checkHealth();

  // Matches
  Future<List<ApiMatch>> getLiveMatches() async {
    final data = await _client.get(ApiEndpoints.matchesLive);
    return _parseMatchList(data);
  }

  Future<List<ApiMatch>> getUpcomingMatches() async {
    final data = await _client.get(ApiEndpoints.matchesUpcoming);
    return _parseMatchList(data);
  }

  Future<List<ApiMatch>> getRecentMatches() async {
    final data = await _client.get(ApiEndpoints.matchesRecent);
    return _parseMatchList(data);
  }

  Future<ApiMatchDetail> getMatchDetail(String matchId) async {
    final data = await _client.get(ApiEndpoints.matchDetail(matchId));
    if (data is Map<String, dynamic>) {
      return ApiMatchDetail.fromJson(data);
    }
    throw ApiException.unknown('Invalid match detail response');
  }

  Future<ApiScorecard> getMatchScorecard(String matchId) async {
    final data = await _client.get(ApiEndpoints.matchScorecard(matchId));
    if (data is Map<String, dynamic>) {
      return ApiScorecard.fromJson(data);
    }
    throw ApiException.unknown('Invalid scorecard response');
  }

  Future<List<ApiCommentaryEntry>> getMatchCommentary(String matchId) async {
    final data = await _client.get(ApiEndpoints.matchCommentary(matchId));
    if (data is List) {
      return data.map((e) => ApiCommentaryEntry.fromJson(e)).toList();
    }
    throw ApiException.unknown('Invalid commentary response');
  }

  Future<List<ApiInningsDetail>> getMatchInnings(String matchId) async {
    final data = await _client.get(ApiEndpoints.matchInnings(matchId));
    if (data is List) {
      return data.map((e) => ApiInningsDetail.fromJson(e)).toList();
    }
    throw ApiException.unknown('Invalid innings response');
  }

  Future<Map<String, dynamic>> getMatchOvers(String matchId) async {
    final data = await _client.get(ApiEndpoints.matchOvers(matchId));
    if (data is Map<String, dynamic>) {
      return data;
    }
    return {};
  }

  Future<Map<String, dynamic>> getMatchStats(String matchId) async {
    final data = await _client.get(ApiEndpoints.matchStats(matchId));
    if (data is Map<String, dynamic>) {
      return data;
    }
    return {};
  }

  // Series
  Future<List<ApiSeries>> getSeries() async {
    final data = await _client.get(ApiEndpoints.series);
    if (data is List) {
      return data.map((e) => ApiSeries.fromJson(e)).toList();
    }
    return [];
  }

  Future<List<ApiMatch>> getSeriesMatches(String seriesId) async {
    final data = await _client.get(ApiEndpoints.seriesMatches(seriesId));
    if (data is Map<String, dynamic> && data['data'] != null) {
      return _parseMatchList(data['data']);
    }
    return _parseMatchList(data);
  }

  Future<List<dynamic>> getPointsTable(String seriesId) async {
    final data = await _client.get(ApiEndpoints.pointsTable(seriesId));
    if (data is List) return data;
    return [];
  }

  // Players & Teams
  Future<ApiPlayer> getPlayer(String playerId) async {
    final data = await _client.get(ApiEndpoints.player(playerId));
    if (data is Map<String, dynamic>) {
      return ApiPlayer.fromJson(data);
    }
    throw ApiException.unknown('Invalid player response');
  }

  Future<ApiTeamDetail> getTeam(String teamId) async {
    final data = await _client.get(ApiEndpoints.team(teamId));
    if (data is Map<String, dynamic>) {
      return ApiTeamDetail.fromJson(data);
    }
    throw ApiException.unknown('Invalid team response');
  }

  // News
  Future<NewsListResponse> getNews({String? cursor, int limit = 10, String? context, String? storyType}) async {
    final params = <String, dynamic>{'limit': limit};
    if (cursor != null) params['cursor'] = cursor;
    if (context != null) params['context'] = context;
    if (storyType != null) params['storyType'] = storyType;
    final data = await _client.get(ApiEndpoints.news, queryParameters: params);
    if (data is Map<String, dynamic>) {
      return NewsListResponse.fromJson(data);
    }
    return NewsListResponse(stories: []);
  }

  Future<NewsModel?> getNewsDetail(String id) async {
    final data = await _client.get(ApiEndpoints.newsDetail(id));
    if (data is Map<String, dynamic>) {
      return NewsModel.fromJson(data);
    }
    return null;
  }

  // Series Stats
  Future<ApiSeriesStatsTypes> getSeriesStatsTypes(String seriesId) async {
    final data = await _client.get(ApiEndpoints.seriesStatsTypes(seriesId));
    if (data is Map<String, dynamic>) {
      return ApiSeriesStatsTypes.fromJson(data);
    }
    return ApiSeriesStatsTypes(types: []);
  }

  Future<ApiSeriesStatsTable> getSeriesStatsTable(String seriesId, String statType) async {
    final data = await _client.get(ApiEndpoints.seriesStatsTable(seriesId, statType));
    if (data is Map<String, dynamic>) {
      return ApiSeriesStatsTable.fromJson(data);
    }
    return ApiSeriesStatsTable(header: statType, category: '', headers: [], players: []);
  }

  // Series News
  Future<NewsListResponse> getSeriesNews(String seriesId, {String? cursor, int limit = 10}) async {
    final params = <String, dynamic>{'limit': limit};
    if (cursor != null) params['cursor'] = cursor;
    final data = await _client.get(ApiEndpoints.seriesNews(seriesId), queryParameters: params);
    if (data is Map<String, dynamic>) {
      return NewsListResponse.fromJson(data);
    }
    return NewsListResponse(stories: []);
  }

  // Match News
  Future<NewsListResponse> getMatchNews(String matchId, {String? cursor}) async {
    final params = <String, dynamic>{};
    if (cursor != null) params['cursor'] = cursor;
    final data = await _client.get(ApiEndpoints.matchNews(matchId), queryParameters: params);
    if (data is Map<String, dynamic>) {
      return NewsListResponse.fromJson(data);
    }
    return NewsListResponse(stories: []);
  }

  // Full Commentary
  Future<ApiCommentary> getFullCommentary(String matchId, int inningsId) async {
    final data = await _client.get(ApiEndpoints.fullCommentary(matchId, inningsId));
    if (data is Map<String, dynamic>) {
      return ApiCommentary.fromJson(data);
    }
    return ApiCommentary(inningsId: inningsId, entries: []);
  }

  // Highlights
  Future<ApiHighlights> getMatchHighlights(String matchId, int inningsId) async {
    final data = await _client.get(ApiEndpoints.matchHighlights(matchId, inningsId));
    if (data is Map<String, dynamic>) {
      return ApiHighlights.fromJson(data);
    }
    return ApiHighlights(highlights: []);
  }

  Future<ApiHighlights> getMatchHighlightsAll(String matchId) async {
    final data = await _client.get(ApiEndpoints.matchHighlightsAll(matchId));
    if (data is Map<String, dynamic>) {
      return ApiHighlights.fromJson(data);
    }
    return ApiHighlights(highlights: []);
  }

  // Balls Map
  Future<ApiBallsMap> getBallsMap(String matchId, int inningsId) async {
    final data = await _client.get(ApiEndpoints.ballsMap(matchId, inningsId));
    if (data is Map<String, dynamic>) {
      return ApiBallsMap.fromJson(data);
    }
    return ApiBallsMap(balls: [], batters: [], bowlers: [], summary: ApiBallsSummary(dots: 0, ones: 0, twos: 0, threes: 0, fours: 0, sixes: 0, wickets: 0));
  }

  // Over-by-over
  Future<ApiOverByOver> getOverByOver(String matchId, int inningsId) async {
    final data = await _client.get(ApiEndpoints.overByOver(matchId, inningsId));
    if (data is Map<String, dynamic>) {
      return ApiOverByOver.fromJson(data);
    }
    return ApiOverByOver(overs: []);
  }

  // Schedule
  Future<ApiSchedule> getUpcomingSchedule({String type = 'all', String? timestamp}) async {
    final params = <String, dynamic>{};
    if (timestamp != null) params['timestamp'] = timestamp;
    final data = await _client.get(ApiEndpoints.scheduleByType(type), queryParameters: params);
    if (data is Map<String, dynamic>) {
      return ApiSchedule.fromJson(data);
    }
    return ApiSchedule(days: []);
  }

  // Helpers
  List<ApiMatch> _parseMatchList(dynamic data) {
    if (data is List) {
      return data.map((e) => ApiMatch.fromJson(e)).toList();
    }
    return [];
  }
}
