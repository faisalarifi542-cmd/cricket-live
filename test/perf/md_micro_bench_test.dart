// M6 PERFORMANCE MEASUREMENT — non-production instrumentation.
//
// Microbenchmarks for the three "cost" claims that need isolated timing rather
// than frame timing:
//   1. CommentaryCache.merge — the real sort, at realistic feed sizes, at the
//      real call frequency (once per poll, NOT per build).
//   2. RegExp construction — allocation cost vs. the work around it.
//   3. jsonDeepEquals change detection over a full commentary payload.
//
// Run: flutter test test/perf/md_micro_bench_test.dart --concurrency=1
//
// These are Dart-VM (JIT) numbers. AOT/release is materially faster, so every
// figure here is a PESSIMISTIC upper bound — which is the safe direction when
// the conclusion is "this is negligible".
//
// DELETE THIS DIRECTORY once the measurement milestone is signed off.

import 'package:flutter_test/flutter_test.dart';

import 'package:cricpro_flutter/services/commentary_cache.dart';
import 'package:cricpro_flutter/utils/json_diff.dart';

import 'md_fixtures.dart';

final List<List<String>> _rows = [];

void _record(String claim, String metric, String value) {
  _rows.add([claim, metric, value]);
  // ignore: avoid_print
  print('MICRO | $claim | $metric | $value');
}

/// Median of [runs] timed iterations of [body], in microseconds.
({int median, int p95, int max, int min}) _bench(
    int runs, void Function() body) {
  // Warm up the JIT so we measure steady state, not first-call compilation.
  for (var i = 0; i < 20; i++) {
    body();
  }
  final samples = <int>[];
  final sw = Stopwatch();
  for (var i = 0; i < runs; i++) {
    sw.reset();
    sw.start();
    body();
    sw.stop();
    samples.add(sw.elapsedMicroseconds);
  }
  samples.sort();
  return (
    median: samples[samples.length ~/ 2],
    p95: samples[(samples.length * 0.95).floor()],
    max: samples.last,
    min: samples.first,
  );
}

void main() {
  // ---------------------------------------------------------------------------
  // CLAIM: "sorting inside build()".
  // The sort actually lives in CommentaryCache.merge, on the NETWORK RESPONSE
  // path (cricket_repository.dart:163), i.e. once per poll — not once per build.
  // Measure its true cost at realistic and pathological feed sizes.
  // ---------------------------------------------------------------------------
  test('sort: CommentaryCache.merge cost by feed size', () {
    for (final size in const [20, 80, 200, 500, 1000]) {
      final feed = commentaryFeed(size);
      final cache = CommentaryCache.instance;
      // Steady state: the cache already holds the feed, and a poll re-merges an
      // overlapping page — the real live-match case.
      cache.clearMatch('bench');
      cache.merge('bench', CommentaryCache.bucketFull, feed);
      final incoming = feed.take(12).toList(); // a fresh poll's new page

      final r = _bench(200, () {
        cache.merge('bench', CommentaryCache.bucketFull, incoming);
      });
      _record('SORT', 'merge+sort $size items — median (us)', '${r.median}');
      _record('SORT', 'merge+sort $size items — p95 (us)', '${r.p95}');
      cache.clearMatch('bench');
    }
    _record('SORT', 'real call frequency', 'once per poll (5s), not per build');
  });

  // ---------------------------------------------------------------------------
  // CLAIM: "non-hoisted RegExp".
  // Measure the cost of CONSTRUCTING a RegExp vs. using a pre-built one, at the
  // frequency the code actually does it.
  // ---------------------------------------------------------------------------
  test('regexp: construction cost vs hoisted, per call', () {
    const sample = '148/3';
    final hoisted = RegExp(r'^(\d+)\s*/\s*(\d+)');

    // 80 rows x 1 construction each = the Commentary tab's worst case.
    final fresh = _bench(500, () {
      for (var i = 0; i < 80; i++) {
        RegExp(r'^(\d+)\s*/\s*(\d+)').firstMatch(sample);
      }
    });
    final reused = _bench(500, () {
      for (var i = 0; i < 80; i++) {
        hoisted.firstMatch(sample);
      }
    });
    _record('REGEXP', '80x construct+match — median (us)', '${fresh.median}');
    _record('REGEXP', '80x hoisted match only — median (us)',
        '${reused.median}');
    _record('REGEXP', 'saving per 80-row rebuild (us)',
        '${fresh.median - reused.median}');

    // Single-call cost, to reason about the per-row hot path.
    final one = _bench(2000, () {
      RegExp(r'^(\d+)\s*/\s*(\d+)').firstMatch(sample);
    });
    _record('REGEXP', 'single construct+match — median (us)', '${one.median}');
  });

  // ---------------------------------------------------------------------------
  // Change detection on the poll path (runs twice per poll:
  // match_details_screen.dart:579 and :581).
  // ---------------------------------------------------------------------------
  test('change detection: jsonDeepEquals over a live payload', () {
    final a = liveCommentaryPayload(80);
    final b = liveCommentaryPayload(80);
    // Worst case: identical payloads => full walk, no early exit.
    final same = _bench(300, () => jsonDeepEquals(a, b));
    // Typical case: the newest score changed => exits early.
    final c = liveCommentaryPayload(80);
    (c['items'] as List<Map<String, dynamic>>).first['score'] = '999/9';
    final diff = _bench(300, () => jsonDeepEquals(a, c));
    _record('DIFF', 'identical 80-item payload — median (us)',
        '${same.median}');
    _record('DIFF', 'changed 80-item payload — median (us)', '${diff.median}');
    _record('DIFF', 'calls per poll', '2 (screen :579 and :581)');
  });

  tearDownAll(() {
    // ignore: avoid_print
    print('\n===== M6 MICROBENCH TABLE =====');
    for (final r in _rows) {
      // ignore: avoid_print
      print('${r[0]}\t${r[1]}\t${r[2]}');
    }
  });
}
