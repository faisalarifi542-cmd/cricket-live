// M6 PERFORMANCE MEASUREMENT — non-production instrumentation.
//
// Two memory questions the audit did not cover:
//
// 1. UNBOUNDED ACCUMULATION: CommentaryCache is a no-removal accumulator
//    (commentary_cache.dart:45-118) with NO cap. Over a long Test match the
//    merged list only grows. Measure how merge cost scales as the accumulated
//    set grows, since the sort is O(n log n) over EVERYTHING held, and it runs
//    once per 5s poll for the whole match duration.
//
// 2. PER-MATCH RELEASE: does browsing many matches leak? The screen clears the
//    cache in dispose() (match_details_screen.dart:131-133).
//
// Run: flutter test test/perf/md_memory_growth_test.dart --concurrency=1
//
// DELETE THIS DIRECTORY once the measurement milestone is signed off.

import 'package:flutter_test/flutter_test.dart';

import 'package:cricpro_flutter/services/commentary_cache.dart';

import 'md_fixtures.dart';

final List<List<String>> _rows = [];
void _record(String metric, String value) {
  _rows.add([metric, value]);
  // ignore: avoid_print
  print('MEM | $metric | $value');
}

void main() {
  tearDownAll(() {
    // ignore: avoid_print
    print('\n===== M6 MEMORY-GROWTH TABLE =====');
    for (final r in _rows) {
      // ignore: avoid_print
      print('${r[0]}\t${r[1]}');
    }
  });

  test('accumulator growth: merge cost as the retained set grows', () {
    final cache = CommentaryCache.instance;
    cache.clearMatch('mem');

    // Simulate a long match: feed 6 new balls per poll, forever. A T20 innings
    // is ~120 balls; a Test day is ~540; a full Test ~2700 (with notes, more).
    var totalRetained = 0;
    for (final target in const [120, 540, 1200, 2700]) {
      // Fill up to `target` retained items in 6-ball pages, like real polling.
      while (totalRetained < target) {
        final page = commentaryFeed(6, innings: 1 + (totalRetained ~/ 600));
        // Shift over numbers so each page is genuinely new (no key collisions).
        for (var i = 0; i < page.length; i++) {
          page[i]['over'] =
              ((totalRetained + i) / 6).toStringAsFixed(1);
          page[i]['ballNbr'] = totalRetained + i;
          page[i]['timestamp'] = 1755600000000 + (totalRetained + i) * 30000;
        }
        cache.merge('mem', CommentaryCache.bucketFull, page);
        totalRetained += 6;
      }

      // Steady-state poll cost at this retained size.
      final incoming = commentaryFeed(6, innings: 9);
      for (var i = 0; i < incoming.length; i++) {
        incoming[i]['over'] = ((totalRetained + i) / 6).toStringAsFixed(1);
        incoming[i]['ballNbr'] = totalRetained + i;
      }
      final samples = <int>[];
      final sw = Stopwatch();
      for (var r = 0; r < 40; r++) {
        sw.reset();
        sw.start();
        final out = cache.merge('mem', CommentaryCache.bucketFull, incoming);
        sw.stop();
        samples.add(sw.elapsedMicroseconds);
        if (r == 0) {
          _record('retained ~$target — merged list length', '${out.length}');
        }
      }
      samples.sort();
      _record('retained ~$target — merge+sort median (us)',
          '${samples[samples.length ~/ 2]}');
      _record('retained ~$target — merge+sort p95 (us)',
          '${samples[(samples.length * .95).floor()]}');
    }
    _record('cap on retained items', 'NONE (no eviction in CommentaryCache)');
    cache.clearMatch('mem');
  });

  test('per-match release: clearMatch frees the accumulated feed', () {
    final cache = CommentaryCache.instance;
    // Browse 25 matches, accumulating 80 items each, clearing on dispose.
    for (var i = 0; i < 25; i++) {
      cache.merge('m$i', CommentaryCache.bucketFull, commentaryFeed(80));
      cache.clearMatch('m$i'); // what dispose() does
    }
    // A cleared match must come back empty (proves the bucket was dropped).
    final after = cache.merge('m0', CommentaryCache.bucketFull, const []);
    _record('after 25 open/close cycles, m0 retained', '${after.length}');
    _record('dispose() releases per-match feed',
        after.isEmpty ? 'YES' : 'NO — LEAK');

    // And without clearing, the bucket persists (the growth path).
    cache.merge('keep', CommentaryCache.bucketFull, commentaryFeed(80));
    final kept = cache.merge('keep', CommentaryCache.bucketFull, const []);
    _record('un-cleared match retains items', '${kept.length}');
    cache.clearMatch('keep');
  });
}
