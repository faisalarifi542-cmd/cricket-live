import '../../core/network/api_exception.dart';
import '../../core/network/network_result.dart';
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
import '../services/cricket_api_service.dart';

class CricketRepository {
  static CricketRepository? _instance;
  final CricketApiService _service = CricketApiService();

  CricketRepository._();

  static CricketRepository get instance {
    _instance ??= CricketRepository._();
    return _instance!;
  }

  // Health
  Future<bool> checkHealth() => _service.checkHealth();

  // Matches
  Future<NetworkResult<List<ApiMatch>>> getLiveMatches() async {
    return _safeCall(() => _service.getLiveMatches());
  }

  Future<NetworkResult<List<ApiMatch>>> getUpcomingMatches() async {
    return _safeCall(() => _service.getUpcomingMatches());
  }

  Future<NetworkResult<List<ApiMatch>>> getRecentMatches() async {
    return _safeCall(() => _service.getRecentMatches());
  }

  Future<NetworkResult<ApiMatchDetail>> getMatchDetail(String matchId) async {
    return _safeCall(() => _service.getMatchDetail(matchId));
  }

  Future<NetworkResult<ApiScorecard>> getMatchScorecard(String matchId) async {
    return _safeCall(() => _service.getMatchScorecard(matchId));
  }

  Future<NetworkResult<List<ApiCommentaryEntry>>> getMatchCommentary(String matchId) async {
    return _safeCall(() => _service.getMatchCommentary(matchId));
  }

  Future<NetworkResult<List<ApiInningsDetail>>> getMatchInnings(String matchId) async {
    return _safeCall(() => _service.getMatchInnings(matchId));
  }

  Future<NetworkResult<Map<String, dynamic>>> getMatchOvers(String matchId) async {
    return _safeCall(() => _service.getMatchOvers(matchId));
  }

  Future<NetworkResult<Map<String, dynamic>>> getMatchStats(String matchId) async {
    return _safeCall(() => _service.getMatchStats(matchId));
  }

  // Series
  Future<NetworkResult<List<ApiSeries>>> getSeries() async {
    return _safeCall(() => _service.getSeries());
  }

  Future<NetworkResult<List<ApiMatch>>> getSeriesMatches(String seriesId) async {
    return _safeCall(() => _service.getSeriesMatches(seriesId));
  }

  Future<NetworkResult<List<dynamic>>> getPointsTable(String seriesId) async {
    return _safeCall(() => _service.getPointsTable(seriesId));
  }

  // Players & Teams
  Future<NetworkResult<ApiPlayer>> getPlayer(String playerId) async {
    return _safeCall(() => _service.getPlayer(playerId));
  }

  Future<NetworkResult<ApiTeamDetail>> getTeam(String teamId) async {
    return _safeCall(() => _service.getTeam(teamId));
  }

  // News
  Future<NetworkResult<NewsListResponse>> getNews({String? cursor, int limit = 10, String? context, String? storyType}) async {
    return _safeCall(() => _service.getNews(cursor: cursor, limit: limit, context: context, storyType: storyType));
  }

  Future<NetworkResult<NewsModel?>> getNewsDetail(String id) async {
    return _safeCall(() => _service.getNewsDetail(id));
  }

  // Series Stats
  Future<NetworkResult<ApiSeriesStatsTypes>> getSeriesStatsTypes(String seriesId) async {
    return _safeCall(() => _service.getSeriesStatsTypes(seriesId));
  }

  Future<NetworkResult<ApiSeriesStatsTable>> getSeriesStatsTable(String seriesId, String statType) async {
    return _safeCall(() => _service.getSeriesStatsTable(seriesId, statType));
  }

  // Series News
  Future<NetworkResult<NewsListResponse>> getSeriesNews(String seriesId, {String? cursor, int limit = 10}) async {
    return _safeCall(() => _service.getSeriesNews(seriesId, cursor: cursor, limit: limit));
  }

  // Match News
  Future<NetworkResult<NewsListResponse>> getMatchNews(String matchId, {String? cursor}) async {
    return _safeCall(() => _service.getMatchNews(matchId, cursor: cursor));
  }

  // Full Commentary
  Future<NetworkResult<ApiCommentary>> getFullCommentary(String matchId, int inningsId) async {
    return _safeCall(() => _service.getFullCommentary(matchId, inningsId));
  }

  // Highlights
  Future<NetworkResult<ApiHighlights>> getMatchHighlights(String matchId, int inningsId) async {
    return _safeCall(() => _service.getMatchHighlights(matchId, inningsId));
  }

  Future<NetworkResult<ApiHighlights>> getMatchHighlightsAll(String matchId) async {
    return _safeCall(() => _service.getMatchHighlightsAll(matchId));
  }

  // Balls Map
  Future<NetworkResult<ApiBallsMap>> getBallsMap(String matchId, int inningsId) async {
    return _safeCall(() => _service.getBallsMap(matchId, inningsId));
  }

  // Over-by-over
  Future<NetworkResult<ApiOverByOver>> getOverByOver(String matchId, int inningsId) async {
    return _safeCall(() => _service.getOverByOver(matchId, inningsId));
  }

  // Schedule
  Future<NetworkResult<ApiSchedule>> getUpcomingSchedule({String type = 'all', String? timestamp}) async {
    return _safeCall(() => _service.getUpcomingSchedule(type: type, timestamp: timestamp));
  }

  // Safe wrapper
  Future<NetworkResult<T>> _safeCall<T>(Future<T> Function() call) async {
    try {
      final result = await call();
      return NetworkSuccess(result);
    } on ApiException catch (e) {
      return NetworkError(e);
    } catch (e) {
      return NetworkError(ApiException.unknown(e.toString()));
    }
  }
}
