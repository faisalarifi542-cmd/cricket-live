import 'package:cricpro_flutter/models/api_response.dart';
import 'package:cricpro_flutter/api_models.dart';
import 'package:cricpro_flutter/models/cricket_match.dart';
import 'package:cricpro_flutter/services/cricket_api_service.dart';

class CricketRepository {
  CricketRepository({CricketApiService? service})
      : _service = service ?? CricketApiService();

  final CricketApiService _service;
  final Map<String, _CacheEntry<dynamic>> _cache = {};

  Future<ApiEnvelope<List<CricketMatch>>> matchesForTab(int tabIndex,
      {bool forceRefresh = false}) {
    if (tabIndex == 0) {
      return _cached(
          'matches:live', const Duration(seconds: 10), _service.liveMatches,
          forceRefresh: forceRefresh);
    }
    if (tabIndex == 2) {
      return _cached(
          'matches:recent', const Duration(minutes: 5), _service.recentMatches,
          forceRefresh: forceRefresh);
    }
    return _cached('matches:upcoming', const Duration(minutes: 5),
        _service.upcomingMatches,
        forceRefresh: forceRefresh);
  }

  Future<ApiEnvelope<Map<String, dynamic>>> home({bool forceRefresh = false}) =>
      _cached('app:home', const Duration(seconds: 30), _service.appHome,
          forceRefresh: forceRefresh);

  Future<ApiEnvelope<Map<String, dynamic>>> appConfig(
          {bool forceRefresh = false}) =>
      _cached('app:config', const Duration(minutes: 5), _service.appConfig,
          forceRefresh: forceRefresh);

  Future<ApiEnvelope<Map<String, dynamic>>> matchDetail(String matchId,
          {bool forceRefresh = false}) =>
      _cached('match:$matchId:detail', const Duration(seconds: 10),
          () => _service.matchDetail(matchId),
          forceRefresh: forceRefresh);

  Future<ApiEnvelope<Map<String, dynamic>>> matchLiveLine(String matchId,
          {bool forceRefresh = false}) =>
      _cached('match:$matchId:live-line', const Duration(seconds: 5),
          () => _service.matchLiveLine(matchId),
          forceRefresh: forceRefresh);

  Future<ApiEnvelope<Map<String, dynamic>>> matchScorecard(String matchId,
          {bool forceRefresh = false}) =>
      _cached('match:$matchId:scorecard', const Duration(seconds: 30),
          () => _service.matchScorecard(matchId),
          forceRefresh: forceRefresh);

  Future<ApiEnvelope<Map<String, dynamic>>> matchCommentary(String matchId,
          {bool forceRefresh = false}) =>
      _cached('match:$matchId:commentary', const Duration(seconds: 30),
          () => _service.matchCommentary(matchId),
          forceRefresh: forceRefresh);

  Future<ApiEnvelope<Map<String, dynamic>>> matchOvers(String matchId,
          {bool forceRefresh = false}) =>
      _cached('match:$matchId:overs', const Duration(seconds: 20),
          () => _service.matchOvers(matchId),
          forceRefresh: forceRefresh);

  Future<ApiEnvelope<Map<String, dynamic>>> matchSquads(String matchId,
          {bool forceRefresh = false}) =>
      _cached('match:$matchId:squads', const Duration(hours: 1),
          () => _service.matchSquads(matchId),
          forceRefresh: forceRefresh);

  Future<ApiEnvelope<Map<String, dynamic>>> matchStreams(String matchId,
          {bool forceRefresh = false}) =>
      _cached('match:$matchId:streams', const Duration(seconds: 30),
          () => _service.matchStreams(matchId),
          forceRefresh: forceRefresh);

  Future<bool> hasPlayableStreams(String matchId,
      {bool forceRefresh = false}) async {
    if (matchId.isEmpty) return false;
    final config = await appConfig();
    if (!AppConfig.fromJson(config.data).liveStreamingEnabled) return false;
    final response = await matchStreams(matchId, forceRefresh: forceRefresh);
    final data = apiMap(response.data);
    final streams = apiList(data['streams'])
        .map(StreamSource.fromJson)
        .where((stream) => stream.url.isNotEmpty)
        .toList();
    return apiBool(data['hasStream']) ||
        apiBool(data['hasStreams']) ||
        streams.isNotEmpty;
  }

  bool shouldShowWatchLive(CricketMatch match, AppConfig appConfig) {
    return appConfig.liveStreamingEnabled &&
        match.watchLiveEnabled &&
        match.hasLiveStream;
  }

  Future<bool> shouldShowWatchLiveForMatch(CricketMatch match,
      {bool forceRefresh = false}) async {
    if (match.id.isEmpty) return false;
    if (!match.hasStreamInfo) {
      return hasPlayableStreams(match.id, forceRefresh: forceRefresh);
    }
    final config = await appConfig(forceRefresh: forceRefresh);
    return shouldShowWatchLive(match, AppConfig.fromJson(config.data));
  }

  Future<ApiEnvelope<List<dynamic>>> schedule(
          {String type = 'upcoming', bool forceRefresh = false}) =>
      _cached('schedule:$type', const Duration(minutes: 5),
          () => _service.schedule(type: type),
          forceRefresh: forceRefresh);

  Future<ApiEnvelope<List<CricketMatch>>> scheduleMatches(
      {String type = 'upcoming', bool forceRefresh = false}) async {
    final response = await schedule(type: type, forceRefresh: forceRefresh);
    return ApiEnvelope(
        data: response.data.map(CricketMatch.fromJson).toList(),
        meta: response.meta);
  }

  /// Returns the schedule grouped by day so the Schedule screen can show
  /// real, navigable date chips. Each [ScheduleDay] carries its label (as
  /// returned by the API), a parsed [DateTime] when possible, and the list
  /// of matches that start on that day.
  Future<ApiEnvelope<List<ScheduleDay>>> scheduleByDay(
      {String type = 'upcoming', bool forceRefresh = false}) async {
    final response = await _cached<ApiEnvelope<List<Map<String, dynamic>>>>(
      'schedule:days:$type',
      const Duration(minutes: 5),
      () => _service.scheduleDays(type: type),
      forceRefresh: forceRefresh,
    );
    return ApiEnvelope(
      data: response.data.map(ScheduleDay.fromJson).toList(),
      meta: response.meta,
    );
  }

  Future<ApiEnvelope<List<dynamic>>> news(
          {int limit = 20, bool forceRefresh = false}) =>
      _cached('news:$limit', const Duration(minutes: 5),
          () => _service.news(limit: limit),
          forceRefresh: forceRefresh);

  Future<ApiEnvelope<List<NewsStory>>> newsStories(
      {int limit = 20, bool forceRefresh = false}) async {
    final response = await news(limit: limit, forceRefresh: forceRefresh);
    return ApiEnvelope(
        data: response.data.map(NewsStory.fromJson).toList(),
        meta: response.meta);
  }

  Future<ApiEnvelope<Map<String, dynamic>>> newsDetail(String newsId,
          {bool forceRefresh = false}) =>
      _cached('news:detail:$newsId', const Duration(minutes: 10),
          () => _service.newsDetail(newsId),
          forceRefresh: forceRefresh);

  Future<ApiEnvelope<List<RankingEntry>>> rankings({
    String gender = 'men',
    String category = 'batting',
    String format = 'test',
    bool forceRefresh = false,
  }) async {
    final key = 'rankings:$gender:$category:$format';
    final response = await _cached(
      key,
      const Duration(hours: 1),
      () => _service.rankings(
        gender: gender,
        category: category,
        format: format,
      ),
      forceRefresh: forceRefresh,
    );
    return ApiEnvelope(
      data: response.data.map(RankingEntry.fromJson).toList(),
      meta: response.meta,
    );
  }

  Future<ApiEnvelope<List<dynamic>>> series({bool forceRefresh = false}) =>
      _cached('series:list', const Duration(hours: 1), _service.series,
          forceRefresh: forceRefresh);

  Future<ApiEnvelope<List<ApiSeries>>> seriesList(
      {bool forceRefresh = false}) async {
    final response = await series(forceRefresh: forceRefresh);
    return ApiEnvelope(
        data: response.data.map(ApiSeries.fromJson).toList(),
        meta: response.meta);
  }

  Future<ApiEnvelope<Map<String, dynamic>>> seriesDetail(String seriesId,
          {bool forceRefresh = false}) =>
      _cached('series:$seriesId:detail', const Duration(hours: 1),
          () => _service.seriesDetail(seriesId),
          forceRefresh: forceRefresh);

  Future<ApiEnvelope<List<CricketMatch>>> seriesMatchList(String seriesId,
      {String? status, bool forceRefresh = false}) async {
    final key = 'series:$seriesId:matches:${status ?? 'all'}';
    final response = await _cached(key, const Duration(minutes: 10),
        () => _service.seriesMatches(seriesId, status: status),
        forceRefresh: forceRefresh);
    return ApiEnvelope(
        data: response.data.map(CricketMatch.fromJson).toList(),
        meta: response.meta);
  }

  Future<ApiEnvelope<Map<String, dynamic>>> pointsTable(String seriesId,
          {bool forceRefresh = false}) =>
      _cached('series:$seriesId:points', const Duration(minutes: 5),
          () => _service.pointsTable(seriesId),
          forceRefresh: forceRefresh);

  Future<ApiEnvelope<Map<String, dynamic>>> seriesStats(String seriesId,
          {bool forceRefresh = false}) =>
      _cached('series:$seriesId:stats', const Duration(minutes: 5),
          () => _service.seriesStats(seriesId),
          forceRefresh: forceRefresh);

  Future<ApiEnvelope<List<dynamic>>> seriesTeams(String seriesId,
          {bool forceRefresh = false}) =>
      _cached('series:$seriesId:teams', const Duration(hours: 1),
          () => _service.seriesTeams(seriesId),
          forceRefresh: forceRefresh);

  Future<ApiEnvelope<List<CricketMatch>>> seriesSchedule(String seriesId,
      {bool forceRefresh = false}) async {
    final response = await _cached('series:$seriesId:schedule',
        const Duration(minutes: 10), () => _service.seriesSchedule(seriesId),
        forceRefresh: forceRefresh);
    return ApiEnvelope(
        data: response.data.map(CricketMatch.fromJson).toList(),
        meta: response.meta);
  }

  Future<ApiEnvelope<ApiPlayer>> player(String playerId,
      {bool forceRefresh = false}) async {
    final response = await _cached('player:$playerId', const Duration(days: 1),
        () => _service.player(playerId),
        forceRefresh: forceRefresh);
    return ApiEnvelope(
        data: ApiPlayer.fromJson(response.data), meta: response.meta);
  }

  Future<ApiEnvelope<ApiTeamProfile>> team(String teamId,
      {bool forceRefresh = false}) async {
    final response = await _cached(
        'team:$teamId', const Duration(days: 1), () => _service.team(teamId),
        forceRefresh: forceRefresh);
    return ApiEnvelope(
        data: ApiTeamProfile.fromJson(response.data), meta: response.meta);
  }

  Future<T> _cached<T>(
    String key,
    Duration ttl,
    Future<T> Function() fetch, {
    bool forceRefresh = false,
  }) async {
    final now = DateTime.now();
    final cached = _cache[key];
    if (!forceRefresh && cached != null && cached.expiresAt.isAfter(now)) {
      return cached.value as T;
    }
    try {
      final value = await fetch();
      _cache[key] = _CacheEntry(value, now.add(ttl));
      return value;
    } catch (_) {
      if (cached != null) return cached.value as T;
      rethrow;
    }
  }
}

class _CacheEntry<T> {
  const _CacheEntry(this.value, this.expiresAt);

  final T value;
  final DateTime expiresAt;
}
