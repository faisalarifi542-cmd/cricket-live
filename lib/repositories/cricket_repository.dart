import '../models/api_response.dart';
import '../models/cricket_match.dart';
import '../services/cricket_api_service.dart';

class CricketRepository {
  CricketRepository({CricketApiService? service}) : _service = service ?? CricketApiService();

  final CricketApiService _service;

  Future<ApiEnvelope<List<CricketMatch>>> matchesForTab(int tabIndex) {
    if (tabIndex == 0) return _service.liveMatches();
    if (tabIndex == 2) return _service.recentMatches();
    return _service.upcomingMatches();
  }

  Future<ApiEnvelope<Map<String, dynamic>>> home() => _service.appHome();

  Future<ApiEnvelope<Map<String, dynamic>>> appConfig() => _service.appConfig();

  Future<ApiEnvelope<Map<String, dynamic>>> matchDetail(String matchId) => _service.matchDetail(matchId);

  Future<ApiEnvelope<Map<String, dynamic>>> matchStreams(String matchId) => _service.matchStreams(matchId);
}
