import 'package:flutter/foundation.dart';

/// In-memory, per-match commentary accumulator.
///
/// Live cricket feeds (Cricbuzz included) sometimes return fewer commentary
/// items on one poll than the previous poll, which would make already-seen
/// commentary blink out and reappear. This cache fixes that: it MERGES every
/// fresh response into the items it has already seen for a match and never
/// removes a previously-seen item just because the provider temporarily omitted
/// it.
///
/// Behaviour:
/// * The merged set is sorted deterministically newest-first (innings, then
///   over.ball, then provider timestamp), so newer overs always lead even when
///   a later poll re-emits an older/partial page. Order does NOT depend on the
///   response's own ordering.
/// * An existing item is updated in place when a later response carries more
///   complete text for the same ball/id (no duplicate row).
/// * Items the latest response dropped are kept (no-removal), re-sorted into
///   their correct freshness position, so the list only ever grows during a
///   live match and never traps stale data at the top.
/// * The cache for a match is cleared automatically when a different match is
///   opened (a different [matchId] for the same [bucket]).
///
/// Two independent buckets are kept per match: the full Commentary tab feed and
/// the compact Live-tab preview use different item shapes, so they must not mix.
class CommentaryCache {
  CommentaryCache._();
  static final CommentaryCache instance = CommentaryCache._();

  /// Bucket for the full Commentary tab feed (`/match/:id/full-commentary`).
  static const String bucketFull = 'full';

  /// Bucket for the compact Live-tab commentary preview (live-center).
  static const String bucketLive = 'live';

  final Map<String, _MatchBucket> _buckets = {};

  String _bucketKey(String matchId, String bucket) => '$matchId|$bucket';

  /// Merges [incoming] (newest-first) into the cache for [matchId]/[bucket] and
  /// returns the merged, newest-first list. Pass [hardReset] to drop the
  /// accumulated items first (used for a clean final load or an explicit hard
  /// refresh that is known to carry the complete feed).
  List<Map<String, dynamic>> merge(
    String matchId,
    String bucket,
    List<Map<String, dynamic>> incoming, {
    bool hardReset = false,
  }) {
    if (matchId.isEmpty) return incoming;
    final key = _bucketKey(matchId, bucket);
    final store = _buckets.putIfAbsent(key, () => _MatchBucket());
    if (hardReset) store.clear();

    // Upsert each incoming item into the store. We DO NOT trust the response's
    // own order: a live provider sometimes re-emits an older/partial page
    // (e.g. overs 6.1–6.3) on a later poll. The previous implementation floated
    // whatever the latest response carried to the top, which trapped that stale
    // page above already-seen newer deliveries (9.x) — exactly the "commentary
    // 2+ overs behind" bug. Instead we merge everything, then sort the whole set
    // by a real freshness key so newer overs always lead, regardless of which
    // poll delivered them. Old items are still never removed (no-removal cache).
    var added = 0;
    var updated = 0;
    for (final item in incoming) {
      final k = _keyFor(item);
      final existing = store.items[k];
      if (existing == null) {
        added++;
      } else {
        updated++;
      }
      store.items[k] = existing == null ? item : _mergeItem(existing, item);
    }

    // Keep every key we know about (incoming + previously retained), de-duped.
    final allKeys = <String>{...store.order, ...store.items.keys}
        .where(store.items.containsKey)
        .toList();

    // Stable, deterministic newest-first sort: innings desc, over.ball desc,
    // timestamp desc, with the prior display index as the final tie-break so
    // equal-rank rows keep their relative order (no list blink). Notes (no
    // over) sit just above the ball that shares their timestamp, matching the
    // provider's own "post-over note on top" convention.
    final priorIndex = <String, int>{
      for (var i = 0; i < store.order.length; i++) store.order[i]: i,
    };
    int rankOf(String k) => priorIndex[k] ?? store.order.length;
    allKeys.sort((ka, kb) {
      final a = store.items[ka]!;
      final b = store.items[kb]!;
      final innA = _inningsOf(a), innB = _inningsOf(b);
      if (innA != innB) return innB.compareTo(innA); // higher innings = newer
      final ovA = _overValueOf(a), ovB = _overValueOf(b);
      if (ovA != null && ovB != null && ovA != ovB) {
        return ovB.compareTo(ovA); // higher over.ball = newer
      }
      final tsA = _timestampOf(a), tsB = _timestampOf(b);
      if (tsA != tsB) return tsB.compareTo(tsA); // newer timestamp first
      // A note (null over) at the same timestamp as a ball is the newer event.
      if (ovA == null && ovB != null) return -1;
      if (ovA != null && ovB == null) return 1;
      return rankOf(ka).compareTo(rankOf(kb)); // stable fallback
    });

    store.order = allKeys;

    final latest = store.order.isEmpty ? null : store.items[store.order.first];
    if (kDebugMode) {
      final lo = latest == null ? '-' : _overValueOf(latest)?.toString() ?? 'note';
      debugPrint(
          'CricProCommentaryMerge: bucket=$bucket match=$matchId incoming=${incoming.length} added=$added updated=$updated kept=${store.order.length - added} total=${store.order.length} latest=$lo');
    }

    return [for (final k in store.order) store.items[k]!];
  }

  /// Stable identity for a commentary item, safe for use as a widget key.
  ///
  /// Exposes the SAME canonical key the merge uses internally, so UI state that
  /// must follow a specific delivery (e.g. which commentary row the user
  /// expanded) stays attached to that delivery even as newer balls are prepended
  /// and the list re-sorts. Keying such state positionally is wrong: index 0 is
  /// a different ball after every poll.
  ///
  /// Purely additive — merge/sort behaviour is unchanged.
  String identityFor(Map<String, dynamic> item) => _keyFor(item);

  /// Drops everything cached for a match (both buckets). Call when a match is
  /// known to be fully reloaded cleanly.
  void clearMatch(String matchId) {
    _buckets.remove(_bucketKey(matchId, bucketFull));
    _buckets.remove(_bucketKey(matchId, bucketLive));
  }

  /// Stable de-dup key for a commentary item. For a real delivery we key on
  /// innings + canonical over.ball (NOT the provider id): the fast `/comm`
  /// source and the full-commentary fallback assign different ids to the same
  /// ball (timestamp-only vs composite) and encode the over differently
  /// (`8` + `ball:4` vs `"8.4"`), so an id- or raw-field-based key would dupe
  /// the same delivery across sources. A canonical over.ball collapses them so
  /// a re-sent ball with fuller text updates the same row. Notes carry no over,
  /// so they fall back to an explicit id, then to a text hash.
  String _keyFor(Map<String, dynamic> m) {
    final inn = _inningsOf(m).toString();
    final over = _overValueOf(m); // canonical over.ball (e.g. 8.4), or null
    final event = (m['event'] ?? m['type'] ?? '').toString().toLowerCase();

    if (over != null) {
      // Ball rows: key on innings + canonical over.ball so the same delivery
      // from either source collapses to one row, independent of text/id.
      return 'b:$inn:${over.toStringAsFixed(1)}';
    }

    // Notes / non-ball commentary: prefer an explicit id, else a text hash so
    // distinct notes stay distinct.
    final id =
        (m['id'] ?? m['commentaryId'] ?? m['comm_id'] ?? m['commentary_id'])
            ?.toString();
    if (id != null && id.trim().isNotEmpty) return 'n:$inn:id:$id';
    final text = (m['text'] ?? m['commentary'] ?? '').toString();
    return 'n:$inn:$event:${text.hashCode}';
  }

  /// Innings number for ordering. Higher innings is newer. Unknown → 0.
  int _inningsOf(Map<String, dynamic> m) {
    final v = m['inningsId'] ??
        m['innings'] ??
        m['innings_id'] ??
        m['innings_number'] ??
        m['inningsNumber'];
    if (v is num) return v.toInt();
    return int.tryParse('${v ?? ''}'.trim()) ?? 0;
  }

  /// Combined over.ball as a sortable double (e.g. "8.4" → 8.4). Notes carry no
  /// over → null, so they tie-break on timestamp instead. Accepts either a
  /// combined `over` ("8.4") or separate over + ball fields.
  double? _overValueOf(Map<String, dynamic> m) {
    final overRaw = m['over'] ?? m['overNumber'] ?? m['over_number'];
    final ballRaw = m['ball'] ?? m['ballNumber'] ?? m['ball_number'];
    final overStr = '${overRaw ?? ''}'.trim();
    if (overStr.isEmpty) return null;
    final overNum = double.tryParse(overStr);
    if (overNum == null) return null;
    // If `over` already encodes the ball ("8.4"), use it directly. Otherwise
    // fold a separate integer ball count in as tenths.
    if (overStr.contains('.')) return overNum;
    final ball = int.tryParse('${ballRaw ?? ''}'.trim()) ?? 0;
    return overNum + ball / 10.0;
  }

  /// Provider timestamp (ms) for final tie-break ordering. Unknown → 0.
  int _timestampOf(Map<String, dynamic> m) {
    final v = m['timestamp'] ?? m['ts'] ?? m['time'];
    if (v is num) return v.toInt();
    return int.tryParse('${v ?? ''}'.trim()) ?? 0;
  }

  /// Merges a newer response for the same key onto the existing item: takes the
  /// fresher fields but keeps the longer (more complete) commentary text.
  Map<String, dynamic> _mergeItem(
      Map<String, dynamic> existing, Map<String, dynamic> incoming) {
    final merged = <String, dynamic>{...existing, ...incoming};
    final exText = (existing['text'] ?? existing['commentary'] ?? '').toString();
    final inText = (incoming['text'] ?? incoming['commentary'] ?? '').toString();
    if (exText.length > inText.length) {
      if (existing.containsKey('text')) merged['text'] = existing['text'];
      if (existing.containsKey('commentary')) {
        merged['commentary'] = existing['commentary'];
      }
    }
    return merged;
  }
}

class _MatchBucket {
  final Map<String, Map<String, dynamic>> items = {};
  List<String> order = [];

  void clear() {
    items.clear();
    order = [];
  }
}
