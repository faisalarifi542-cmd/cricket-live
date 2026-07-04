import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:cricpro_flutter/models/api_response.dart';
import 'package:cricpro_flutter/api_models.dart';
import 'package:cricpro_flutter/models/cricket_match.dart';
import 'package:cricpro_flutter/services/cricket_api_service.dart';
import 'package:cricpro_flutter/services/commentary_cache.dart';
import 'package:cricpro_flutter/services/persistent_cache.dart';
import 'package:cricpro_flutter/upcoming_sort.dart';
import 'package:cricpro_flutter/utils/match_classification.dart';

class CricketRepository {
  CricketRepository({CricketApiService? service})
      : _service = service ?? CricketApiService();

  final CricketApiService _service;
  final Map<String, _CacheEntry<dynamic>> _cache = {};
  // Tracks fetches currently in flight so concurrent callers for the same key
  // share one network request instead of firing duplicates.
  final Map<String, Future<dynamic>> _inflight = {};

  Future<ApiEnvelope<List<CricketMatch>>> matchesForTab(int tabIndex,
      {bool forceRefresh = false}) {
    if (tabIndex == 0) {
      return _cached(
          'matches:live', const Duration(seconds: 10), _service.liveMatches,
          forceRefresh: forceRefresh, persist: _matchListEnvelopeCodec);
    }
    if (tabIndex == 2) {
      return _cached(
          'matches:recent', const Duration(minutes: 5), _service.recentMatches,
          forceRefresh: forceRefresh, persist: _matchListEnvelopeCodec);
    }
    return _cached('matches:upcoming', const Duration(minutes: 5),
        _service.upcomingMatches,
        forceRefresh: forceRefresh, persist: _matchListEnvelopeCodec);
  }

  /// Lightweight live-score poll for the Home screen. Always hits the network
  /// (no client-side cache) because the backend already serves this from a tiny
  /// ~4s single-flight cache — a Flutter cache on top would re-add staleness.
  Future<ApiEnvelope<List<CricketMatch>>> liveScores(List<String> ids) =>
      _service.liveScores(ids);

  Future<ApiEnvelope<Map<String, dynamic>>> home({bool forceRefresh = false}) =>
      _cached('app:home', const Duration(seconds: 30), _service.appHome,
          forceRefresh: forceRefresh, persist: _mapEnvelopeCodec);

  Future<ApiEnvelope<Map<String, dynamic>>> appConfig(
          {bool forceRefresh = false}) =>
      _cached('app:config', const Duration(minutes: 5), _service.appConfig,
          forceRefresh: forceRefresh, persist: _mapEnvelopeCodec);

  Future<ApiEnvelope<Map<String, dynamic>>> appAssets(
          {bool forceRefresh = false}) =>
      _cached('app:assets', const Duration(minutes: 10), _service.appAssets,
          forceRefresh: forceRefresh);

  Future<ApiEnvelope<Map<String, dynamic>>> matchDetail(String matchId,
          {bool forceRefresh = false}) =>
      _cached('match:$matchId:detail', const Duration(seconds: 5),
          () => _service.matchDetail(matchId),
          forceRefresh: forceRefresh, persist: _mapEnvelopeCodec);

  Future<ApiEnvelope<Map<String, dynamic>>> matchLiveLine(String matchId,
          {bool forceRefresh = false}) =>
      _cached('match:$matchId:live-line', const Duration(seconds: 5),
          () => _service.matchLiveLine(matchId),
          forceRefresh: forceRefresh);

  Future<ApiEnvelope<Map<String, dynamic>>> matchScorecard(String matchId,
          {bool forceRefresh = false}) =>
      _cached('match:$matchId:scorecard', const Duration(seconds: 5),
          () => _service.matchScorecard(matchId),
          forceRefresh: forceRefresh, persist: _mapEnvelopeCodec);

  Future<ApiEnvelope<Map<String, dynamic>>> matchLiveCenter(String matchId,
          {bool forceRefresh = false}) =>
      _cached('match:$matchId:live-center', const Duration(seconds: 4),
          () => _service.matchLiveCenter(matchId),
          forceRefresh: forceRefresh);

  Future<ApiEnvelope<Map<String, dynamic>>> matchCommentary(String matchId,
          {bool forceRefresh = false}) =>
      _cached('match:$matchId:commentary', const Duration(seconds: 5),
          () => _service.matchCommentary(matchId),
          forceRefresh: forceRefresh, persist: _mapEnvelopeCodec);

  Future<ApiEnvelope<Map<String, dynamic>>> matchFullCommentary(String matchId,
      {bool forceRefresh = false}) async {
    final response = await _cached(
        'match:$matchId:full-commentary', const Duration(seconds: 8),
        () => _service.matchFullCommentary(matchId),
        forceRefresh: forceRefresh);
    return _accumulateCommentary(matchId, response);
  }

  /// FAST live commentary path. Pulls the freshest provider commentary from
  /// `/app/live-commentary` (short TTL + single-flight on the backend) and
  /// merges it through the SAME accumulator/cache as [matchFullCommentary], so
  /// the Live tab and Commentary tab share one correctly-sorted, no-removal
  /// list. Short client TTL (3s) since the server is already the single source
  /// of truth for freshness. Falls back to the full-commentary feed when the
  /// fast source returns nothing (older backend, or provider hiccup) so the UI
  /// is never blanked.
  Future<ApiEnvelope<Map<String, dynamic>>> matchLiveCommentary(String matchId,
      {bool forceRefresh = false}) async {
    final response = await _cached(
        'match:$matchId:live-commentary', const Duration(seconds: 3),
        () => _service.liveCommentary(matchId),
        forceRefresh: forceRefresh);
    final items = apiList(response.data['items']);
    if (items.isEmpty) {
      // Fast source empty — fall back to the heavier full-commentary feed
      // (also merged through the same cache) rather than showing nothing.
      return matchFullCommentary(matchId, forceRefresh: forceRefresh);
    }
    return _accumulateCommentary(matchId, response);
  }

  /// Merges a freshly fetched full-commentary envelope through
  /// [CommentaryCache] so previously seen items are never dropped when the
  /// provider returns a shorter list on a later poll. Replaces the envelope's
  /// `items` with the merged, newest-first list. A terminal match is hard-reset
  /// once so the final feed is exactly what the provider sent (clean & complete).
  ApiEnvelope<Map<String, dynamic>> _accumulateCommentary(
      String matchId, ApiEnvelope<Map<String, dynamic>> response) {
    final data = Map<String, dynamic>.from(response.data);
    final rawItems = apiList(data['items'] ??
        data['data'] ??
        data['commentary'] ??
        data['commentaryList']);
    if (rawItems.isEmpty) {
      // Empty/failed payload — serve whatever the cache already holds rather
      // than blanking the list.
      final kept = CommentaryCache.instance
          .merge(matchId, CommentaryCache.bucketFull, const []);
      if (kept.isNotEmpty) data['items'] = kept;
      return ApiEnvelope(data: data, meta: response.meta);
    }
    final items = rawItems
        .map((e) => e is Map<String, dynamic> ? e : <String, dynamic>{})
        .toList();
    final status = apiString(data['status'] ?? data['state']).toLowerCase();
    final terminal = status == 'completed' ||
        status == 'complete' ||
        status == 'finished' ||
        status == 'result' ||
        status == 'abandoned';
    final merged = CommentaryCache.instance.merge(
      matchId,
      CommentaryCache.bucketFull,
      items,
      hardReset: terminal,
    );
    data['items'] = merged;
    return ApiEnvelope(data: data, meta: response.meta);
  }

  Future<ApiEnvelope<Map<String, dynamic>>> matchOvers(String matchId,
          {bool forceRefresh = false}) =>
      _cached('match:$matchId:overs', const Duration(seconds: 5),
          () => _service.matchOvers(matchId),
          forceRefresh: forceRefresh, persist: _mapEnvelopeCodec);

  Future<ApiEnvelope<Map<String, dynamic>>> matchSquads(String matchId,
          {bool forceRefresh = false}) =>
      _cached('match:$matchId:squads', const Duration(hours: 1),
          () => _service.matchSquads(matchId),
          forceRefresh: forceRefresh, persist: _mapEnvelopeCodec);

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
    // Global kill-switch first: if live streaming is disabled in the admin
    // panel, never show Watch Live regardless of per-match flags.
    final config = await appConfig(forceRefresh: forceRefresh);
    if (!AppConfig.fromJson(config.data).liveStreamingEnabled) return false;

    // Trust the embedded flags only when they're positive. When the match
    // carries no stream info, or the flags say "not enabled", confirm against
    // the authoritative /match/:id/streams endpoint so a valid stream is never
    // hidden by stale/missing list-level flags.
    if (match.hasStreamInfo && match.watchLiveEnabled && match.hasLiveStream) {
      return true;
    }
    return hasPlayableStreams(match.id, forceRefresh: forceRefresh);
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

  /// Upcoming fixtures merged from BOTH the `/matches/upcoming` feed and the
  /// `/schedule/upcoming` feed, deduped by match id. The two endpoints often
  /// return different subsets (the matches feed is capped/curated while the
  /// schedule is broader), so merging them is why Home/Matches can show the
  /// full ~5 upcoming fixtures instead of only the 2 the matches feed carries.
  ///
  /// Best-effort: if one source fails the other is still returned; only when
  /// both fail (and there is nothing cached) does the error propagate so the
  /// UI can show an offline state.
  Future<ApiEnvelope<List<CricketMatch>>> upcomingMatchesMerged(
      {bool forceRefresh = false}) async {
    final seen = <String>{};
    final merged = <CricketMatch>[];
    Object? lastError;
    var anySucceeded = false;
    var matchesCount = 0;
    var scheduleCount = 0;

    // Live/recent take PRIORITY over upcoming. A multi-day Test that is live
    // (or just finished) is listed by the schedule feed as future "Day N"
    // entries under the SAME match id, with a future start time and status
    // "upcoming" + no score — so neither the model flags nor `classifyMatch`
    // can tell it apart from a genuine fixture. Collect the live + recent ids
    // first and exclude them, so a started/finished match can never reappear
    // in Upcoming (the ZIM vs BAN "Day 2" bug).
    final excludedIds = <String>{};
    Future<void> collectExcluded(int tab) async {
      try {
        final res = await matchesForTab(tab, forceRefresh: forceRefresh);
        for (final m in res.data) {
          if (m.id.isNotEmpty) excludedIds.add(m.id);
        }
        anySucceeded = true;
      } catch (_) {/* a feed failing must not block the upcoming merge */}
    }

    await Future.wait([collectExcluded(0), collectExcluded(2)]); // live, recent

    void addAll(List<CricketMatch> list) {
      for (final m in list) {
        if (m.id.isEmpty || m.isLive || m.isFinished) continue;
        if (excludedIds.contains(m.id)) continue; // live/recent copy wins
        // A schedule "Day N" (N>=2) entry is a later day of an already-started
        // multi-day match (no live/recent copy may exist to exclude it by id),
        // so it must never read as a fresh upcoming fixture.
        if (isMultiDayContinuationEntry(m)) continue;
        if (seen.add(m.id)) merged.add(m);
      }
    }

    try {
      final res = await matchesForTab(1, forceRefresh: forceRefresh);
      anySucceeded = true;
      matchesCount = res.data.length;
      addAll(res.data);
    } catch (e) {
      lastError = e;
    }
    try {
      final sched =
          await scheduleMatches(type: 'upcoming', forceRefresh: forceRefresh);
      anySucceeded = true;
      scheduleCount = sched.data.length;
      addAll(sched.data);
    } catch (e) {
      lastError = e;
    }

    if (!anySucceeded && lastError != null) throw lastError;
    if (kDebugMode) {
      debugPrint('CricProHomePoll: upcomingMerged matchesUpcoming=$matchesCount '
          'scheduleUpcoming=$scheduleCount excludedLiveRecent=${excludedIds.length} '
          'afterDedupe=${merged.length}');
    }
    return ApiEnvelope(data: merged, meta: ApiMeta.fromJson(null));
  }

  /// Returns the schedule grouped by day so the Schedule screen can show
  /// real, navigable date chips.
  ///
  /// The Cricbuzz `/schedule/upcoming` feed only carries FUTURE "upcoming
  /// series" days — it does NOT include matches that are live or that finished
  /// today, so a live international fixture (e.g. IRE vs IND on its match day)
  /// never appeared on the calendar while a late-night league game showed up
  /// alone. To make Schedule a real calendar, we MERGE the schedule feed with
  /// today's live / recent / upcoming match feeds, deduped by source match id
  /// (the live/recent/upcoming version wins because it carries score + status).
  ///
  /// For a category tab (international/league/domestic/women) the schedule feed
  /// is already filtered server-side; the merged-in live/recent/upcoming
  /// matches are filtered client-side to the same category so the tab stays
  /// correct. The Schedule screen regroups everything by the user's LOCAL date.
  Future<ApiEnvelope<List<ScheduleDay>>> scheduleByDay(
      {String type = 'upcoming', bool forceRefresh = false}) async {
    // 1) Cricbuzz schedule-pages feed (server-side filtered by [type]). Cache
    //    key is versioned (v2) so any stale single-match payload is bypassed.
    final response = await _cached<ApiEnvelope<List<Map<String, dynamic>>>>(
      'schedule:days:v2:$type',
      const Duration(minutes: 5),
      () => _service.scheduleDays(type: type),
      forceRefresh: forceRefresh,
    );
    final scheduleDays =
        response.data.map(ScheduleDay.fromJson).toList(growable: false);

    // 2) Today's live / recent / upcoming matches (NOT in the schedule feed).
    //    Best-effort: a failing feed must never blank the calendar.
    final extras = <CricketMatch>[];
    Future<void> addTab(int tab) async {
      try {
        final res = await matchesForTab(tab, forceRefresh: forceRefresh);
        for (final m in res.data) {
          if (m.id.isEmpty) continue;
          if (_scheduleCategoryMatches(type, m)) extras.add(m);
        }
      } catch (_) {/* ignore — other sources still populate the calendar */}
    }

    // live (0), recent (2), upcoming (1).
    await Future.wait([addTab(0), addTab(2), addTab(1)]);

    // 3) Merge: live/recent/upcoming first (they carry score + status), then
    //    the schedule-feed fixtures. Dedupe by match id (first seen wins).
    final seen = <String>{};
    final merged = <CricketMatch>[];
    for (final m in extras) {
      if (seen.add(m.id)) merged.add(m);
    }
    for (final day in scheduleDays) {
      for (final m in day.matches) {
        if (m.id.isEmpty) {
          merged.add(m); // keep id-less fixtures (can't dedupe them)
        } else if (seen.add(m.id)) {
          merged.add(m);
        }
      }
    }

    // Return one bucket; the Schedule screen regroups by the user's LOCAL date
    // (so a late-night UTC match lands under the correct local day). When the
    // merge is empty, return no days so the screen shows its empty state rather
    // than a blank date chip.
    if (merged.isEmpty) {
      return ApiEnvelope(data: const <ScheduleDay>[], meta: response.meta);
    }
    return ApiEnvelope(
      data: [ScheduleDay(label: '', date: null, matches: merged)],
      meta: response.meta,
    );
  }

  /// Whether [m] belongs in the schedule [type] tab. `all`/`upcoming` accept
  /// everything; the category tabs reuse the shared [UpcomingSort] classifier
  /// (and a simple women check) so the merged-in live/recent/upcoming matches
  /// are filtered exactly like the server-filtered schedule feed.
  bool _scheduleCategoryMatches(String type, CricketMatch m) {
    switch (type) {
      case 'international':
        return UpcomingSort.isInternationalMatch(m);
      case 'league':
        return UpcomingSort.isMajorLeague(m);
      case 'domestic':
        return UpcomingSort.isDomesticOrOther(m);
      case 'women':
        final s = '${m.series} ${m.matchDesc} ${m.title}'.toLowerCase();
        return s.contains('women');
      default: // 'all', 'upcoming'
        return true;
    }
  }

  Future<ApiEnvelope<List<dynamic>>> news(
          {int limit = 20, bool forceRefresh = false}) =>
      _cached('news:$limit', const Duration(minutes: 5),
          () => _service.news(limit: limit),
          forceRefresh: forceRefresh, persist: _rawListEnvelopeCodec);

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
          forceRefresh: forceRefresh, persist: _rawListEnvelopeCodec);

  /// Admin-managed Series hero banner config. Cached briefly so an operator's
  /// change in the Admin Panel surfaces quickly. Returns an envelope whose
  /// `data` is null when no hero is configured.
  Future<ApiEnvelope<Map<String, dynamic>>> seriesHero(
          {bool forceRefresh = false}) =>
      _cached('series:hero', const Duration(minutes: 2), _service.seriesHero,
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

  /// Series squads (players with face images). Cached for an hour because
  /// squad data changes rarely once announced.
  Future<ApiEnvelope<Map<String, dynamic>>> seriesSquads(String seriesId,
          {bool forceRefresh = false}) =>
      _cached('series:$seriesId:squads:v2', const Duration(hours: 1),
          () => _service.seriesSquads(seriesId),
          forceRefresh: forceRefresh);

  /// Match squads — used as a fallback source for series squads on backends
  /// that do not yet expose `/series/:id/squads`.
  Future<ApiEnvelope<Map<String, dynamic>>> matchSquadsFor(String matchId,
          {bool forceRefresh = false}) =>
      matchSquads(matchId, forceRefresh: forceRefresh);

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

  /// Drops cached stream-availability data (app config + per-match streams) so
  /// the next lookup re-fetches from the server. Called by pull-to-refresh so a
  /// stream an admin just added shows up (Watch Live) without an app restart.
  void invalidateStreamAvailability() {
    _cache.removeWhere((key, _) =>
        key == 'app:config' ||
        (key.startsWith('match:') && key.endsWith(':streams')));
  }

  Future<T> _cached<T>(
    String key,
    Duration ttl,
    Future<T> Function() fetch, {
    bool forceRefresh = false,
    _CacheCodec<T>? persist,
  }) async {
    final now = DateTime.now();
    final cached = _cache[key];
    if (!forceRefresh && cached != null && cached.expiresAt.isAfter(now)) {
      return cached.value as T;
    }
    // Share an in-flight request: a non-forced caller for the same key joins the
    // request already running instead of starting a duplicate network call.
    if (!forceRefresh) {
      final pending = _inflight[key];
      if (pending != null) return await pending as T;
    }
    // F1 persistent cache — cold-start seed. Only when there is NO usable
    // in-memory entry at all (a true cold start / first read this session) and
    // the caller opted into persistence. Serve the last saved disk value
    // instantly, then refresh from the network in the background so both caches
    // converge. This is the SAME unified flow (not a parallel path): the value
    // still flows through the in-memory cache and the normal fetch below.
    if (!forceRefresh && cached == null && persist != null) {
      final disk = await _readPersistent<T>(key, persist);
      if (disk != null) {
        _cache[key] = _CacheEntry(disk, now.add(ttl));
        _refreshInBackground<T>(key, ttl, fetch, persist);
        return disk;
      }
    }
    // Forced refresh (pull-to-refresh / retry) must never serve stale data:
    // drop the cached entry up front, and on fetch failure surface the error
    // so the retry UI shows and the next attempt hits the network again.
    if (forceRefresh) _cache.remove(key);
    final future = fetch();
    _inflight[key] = future;
    try {
      final value = await future;
      _cache[key] = _CacheEntry(value, now.add(ttl));
      // Persist successful responses so a cold start can serve them instantly.
      _writePersistent<T>(key, value, persist);
      return value;
    } catch (_) {
      if (!forceRefresh && cached != null) return cached.value as T;
      rethrow;
    } finally {
      _inflight.remove(key);
    }
  }

  /// Silently refreshes [key] from the network after a disk-seeded cold-start
  /// hit, then updates both the in-memory and persistent caches. Guarded by the
  /// shared in-flight map so it never stacks duplicate fetches, and never throws
  /// (a failure simply keeps the disk-seeded value until the next poll/retry).
  void _refreshInBackground<T>(
    String key,
    Duration ttl,
    Future<T> Function() fetch,
    _CacheCodec<T> persist,
  ) {
    if (_inflight.containsKey(key)) return;
    final now = DateTime.now();
    final future = fetch();
    _inflight[key] = future;
    future.then((value) {
      _cache[key] = _CacheEntry(value, now.add(ttl));
      _writePersistent<T>(key, value, persist);
    }).catchError((_) {
      // Keep the disk-seeded value; the screen's own poll/refresh retries.
    }).whenComplete(() {
      // Only clear the slot if it's still this future (a forced refresh may
      // have replaced it).
      if (identical(_inflight[key], future)) _inflight.remove(key);
    });
  }

  Future<T?> _readPersistent<T>(String key, _CacheCodec<T> persist) async {
    try {
      return await PersistentCache.instance.read<T>(key, persist.decode);
    } catch (_) {
      return null;
    }
  }

  void _writePersistent<T>(String key, T value, _CacheCodec<T>? persist) {
    if (persist == null) return;
    try {
      final payload = persist.encode(value);
      unawaited(PersistentCache.instance.write(key, payload));
    } catch (_) {
      // Encoding failed — skip persistence, never break the network result.
    }
  }

  // --- F1 persistence codecs -------------------------------------------------
  // Each codec serializes a cached [ApiEnvelope] to a JSON-safe payload and
  // back, preserving the raw API data shape. Built lazily and reused.

  static Map<String, dynamic> _encodeMeta(ApiMeta meta) => <String, dynamic>{
        'provider': meta.provider,
        'cache': meta.cache,
        'isStale': meta.isStale,
        'lastUpdated': meta.lastUpdated?.toIso8601String(),
        'ttl': meta.ttl,
      };

  static ApiMeta _decodeMeta(dynamic raw) =>
      ApiMeta.fromJson(raw is Map ? Map<String, dynamic>.from(raw) : null);

  /// Envelope whose `data` is a plain JSON map (already serializable as-is):
  /// `/app/home`, `/app-config`, match detail/scorecard/overs/squads/commentary.
  static final _CacheCodec<ApiEnvelope<Map<String, dynamic>>>
      _mapEnvelopeCodec = _CacheCodec(
    (env) => <String, dynamic>{'data': env.data, 'meta': _encodeMeta(env.meta)},
    (payload) {
      final m =
          payload is Map ? Map<String, dynamic>.from(payload) : const {};
      final data = m['data'] is Map
          ? Map<String, dynamic>.from(m['data'] as Map)
          : <String, dynamic>{};
      return ApiEnvelope<Map<String, dynamic>>(
          data: data, meta: _decodeMeta(m['meta']));
    },
  );

  /// Envelope of parsed matches — uses the faithful [CricketMatch.toCacheJson]/
  /// [CricketMatch.fromCacheJson] round-trip: `/matches/{live,upcoming,recent}`.
  static final _CacheCodec<ApiEnvelope<List<CricketMatch>>>
      _matchListEnvelopeCodec = _CacheCodec(
    (env) => <String, dynamic>{
      'data': [for (final m in env.data) m.toCacheJson()],
      'meta': _encodeMeta(env.meta),
    },
    (payload) {
      final m =
          payload is Map ? Map<String, dynamic>.from(payload) : const {};
      final list = m['data'] is List ? (m['data'] as List) : const [];
      return ApiEnvelope<List<CricketMatch>>(
        data: [
          for (final e in list)
            if (e is Map)
              CricketMatch.fromCacheJson(Map<String, dynamic>.from(e)),
        ],
        meta: _decodeMeta(m['meta']),
      );
    },
  );

  /// Envelope of raw JSON list rows (left in provider shape): `/series`, `/news`.
  static final _CacheCodec<ApiEnvelope<List<dynamic>>> _rawListEnvelopeCodec =
      _CacheCodec(
    (env) => <String, dynamic>{'data': env.data, 'meta': _encodeMeta(env.meta)},
    (payload) {
      final m =
          payload is Map ? Map<String, dynamic>.from(payload) : const {};
      final list =
          m['data'] is List ? List<dynamic>.from(m['data'] as List) : <dynamic>[];
      return ApiEnvelope<List<dynamic>>(data: list, meta: _decodeMeta(m['meta']));
    },
  );
}

class _CacheEntry<T> {
  const _CacheEntry(this.value, this.expiresAt);

  final T value;
  final DateTime expiresAt;
}

/// Pairs an encoder (cached value → JSON-safe payload) with a decoder
/// (payload → cached value) for [PersistentCache]. Kept private to the
/// repository so persistence stays a repository-owned concern.
class _CacheCodec<T> {
  const _CacheCodec(this.encode, this.decode);

  final Object? Function(T value) encode;
  final T Function(Object? payload) decode;
}
