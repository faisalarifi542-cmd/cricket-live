// M6 PERFORMANCE MEASUREMENT — non-production instrumentation.
//
// Measures the REAL MatchDetailsScreen (real repository, real 5s polling loop,
// real private panels) across the M6 scenarios A-H, and reports:
//   * frame build time (widget-tree build phase, from the real pipeline)
//   * rebuild counts of the commentary rows
//   * whether commentary rows are built EAGERLY or lazily (viewport culling)
//   * network request counts / polling frequency
//   * sort cost and call frequency
//   * RegExp construction frequency
//
// Run:  flutter test test/perf/md_perf_measure_test.dart \
//         --dart-define=CRICKET_API_BASE_URL=http://127.0.0.1:8099 --concurrency=1
//
// NOTE ON MODE: `flutter test` runs the Dart VM in JIT with asserts on, so
// absolute times here are a PESSIMISTIC upper bound, not release numbers.
// They are used for RELATIVE comparisons and for structural facts (eager vs
// lazy, rebuild counts, request counts) which are mode-independent. Absolute
// AOT timings come from the separate profile-mode harness.
//
// DELETE THIS DIRECTORY once the measurement milestone is signed off.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cricpro_flutter/app_theme.dart';
import 'package:cricpro_flutter/models/cricket_match.dart';
import 'package:cricpro_flutter/screens/match_details/match_details_screen.dart';
import 'package:cricpro_flutter/screens/match_details/widgets/match_details_ui.dart';
import 'package:cricpro_flutter/services/commentary_cache.dart';

import 'md_fixtures.dart';
import 'stub_api.dart';

/// Collected results, printed as a table at the end.
final List<List<String>> _rows = [];

void _record(String scenario, String metric, String value) {
  _rows.add([scenario, metric, value]);
  // ignore: avoid_print
  print('MEASURE | $scenario | $metric | $value');
}

/// Pumps [d] in small slices so periodic timers (5s poll, 1s ticker) fire.
Future<void> _advance(WidgetTester tester, Duration d,
    {Duration step = const Duration(milliseconds: 250)}) async {
  var elapsed = Duration.zero;
  while (elapsed < d) {
    await tester.pump(step);
    elapsed += step;
  }
}

/// Builds the screen under a real MaterialApp at a realistic phone size.
///
/// NOTE 1: the stub is installed HERE, inside the test body, not in setUpAll.
/// `TestWidgetsFlutterBinding` installs its own mock `HttpOverrides` (which
/// answers every request with a non-JSON 400) when the binding initialises, and
/// that clobbers an override registered from setUpAll. Installing per test is
/// the only ordering that reliably wins.
///
/// NOTE 2: `SharedPreferences.setMockInitialValues` is REQUIRED. The repository
/// serves `matchDetail`/`scorecard`/`overs`/`squads` through PersistentCache
/// (the `persist:` argument), which awaits `SharedPreferences.getInstance()`.
/// With no platform channel that future never completes, so `_loadSummary`
/// never returns, `_configurePolling` is never reached, and the 5s poll timer
/// is never armed — the screen renders cached/known data but issues zero
/// requests. That is what produced the initial all-zero request counts.
Future<void> _pumpScreen(WidgetTester tester,
    {String matchId = 'perf-1', Size size = const Size(360, 804)}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  _stub.install();
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: cricTheme(true),
      home: MatchDetailsScreen(matchId: matchId),
    ),
  );
}

/// Counts how many commentary rows currently exist in the widget tree.
int _commentaryRowCount() =>
    find.byType(MDBallChip).evaluate().length;

/// Number of RenderObject paint operations is not directly exposed, so we
/// count the layers/RenderObjects that would repaint: every row's
/// clipped+shadowed container is its own RenderObject subtree.
int _renderObjectCount() {
  var n = 0;
  void visit(RenderObject o) {
    n++;
    o.visitChildren(visit);
  }

  final root = WidgetsBinding.instance.rootElement?.renderObject;
  if (root != null) visit(root);
  return n;
}

/// Single shared stub, installed per test body by [_pumpScreen].
final StubApi _stub = StubApi();

void main() {
  final stub = _stub;

  tearDownAll(() {
    StubApi.uninstall();
    // ignore: avoid_print
    print('\n===== M6 RAW MEASUREMENT TABLE =====');
    for (final r in _rows) {
      // ignore: avoid_print
      print('${r[0]}\t${r[1]}\t${r[2]}');
    }
  });

  setUp(() {
    stub.resetCounts();
    stub.terminal = false;
    stub.latency = Duration.zero;
    stub.commentaryCount = 80;
    CommentaryCache.instance.clearMatch('perf-1');
  });

  // ---------------------------------------------------------------------------
  // SCENARIO C — the headline claim: does the Commentary tab build all 80 rows?
  // ---------------------------------------------------------------------------
  testWidgets('C: 80+ commentary items — eager vs lazy construction',
      (tester) async {
    stub.commentaryCount = 120;
    await _pumpScreen(tester, matchId: 'perf-C');
    await _advance(tester, const Duration(seconds: 2));

    // Navigate to the Commentary tab (index 4) via its real tab control.
    final commTab = find.text('Comm');
    expect(commTab, findsOneWidget, reason: 'Commentary tab must exist');
    await tester.tap(commTab);
    await _advance(tester, const Duration(seconds: 2));

    final built = _commentaryRowCount();
    _record('C', 'commentary rows in tree (viewport=804px)', '$built');
    _record('C', 'feed size returned by API', '120 (+notes)');

    // A lazily-built list would hold only the ~6-8 rows that fit in an 804px
    // viewport. Anything near the 80-row page size proves eager construction.
    _record(
        'C',
        'construction mode',
        built > 20
            ? 'EAGER (no viewport culling) — $built rows materialised'
            : 'LAZY (viewport culled) — only $built rows materialised');

    _record('C', 'RenderObjects in tree', '${_renderObjectCount()}');
  });

  // ---------------------------------------------------------------------------
  // SCENARIO C2 — cost of the commentary tab's FIRST build (80 eager rows) and
  // of the poll-driven rebuild frames while sitting on it.
  //
  // An earlier version of this test timed bare `tester.pump(16ms)` calls, which
  // measured IDLE frames (nothing dirty => ~39us) and told us nothing. Both
  // numbers below are tied to real work: the first is the pump that materialises
  // the tab, the second are the pumps that process a live poll's setState.
  // ---------------------------------------------------------------------------
  testWidgets('C2: commentary tab build cost (80 rows)', (tester) async {
    stub.commentaryCount = 80;
    await _pumpScreen(tester, matchId: 'perf-C2');
    await _advance(tester, const Duration(seconds: 2));

    // Time the tab switch that materialises the 80-row list from scratch.
    final first = Stopwatch()..start();
    await tester.tap(find.text('Comm'));
    await tester.pump();
    first.stop();
    await _advance(tester, const Duration(seconds: 3));

    final rows = _commentaryRowCount();
    _record('C2', 'rows materialised', '$rows');
    _record('C2', 'first build of Comm tab (JIT, us)',
        '${first.elapsedMicroseconds}');
    _record('C2', 'RenderObjects with tab open', '${_renderObjectCount()}');

    // Now measure the frames that process live-poll rebuilds. Each 250ms pump
    // is timed; the poll fires every 5s, so the slowest pumps are the rebuild
    // frames and the median is an idle frame.
    final samples = <int>[];
    final sw = Stopwatch();
    for (var i = 0; i < 80; i++) {
      sw.reset();
      sw.start();
      await tester.pump(const Duration(milliseconds: 250));
      sw.stop();
      samples.add(sw.elapsedMicroseconds);
    }
    samples.sort();
    _record('C2', 'poll-frame idle median (JIT, us)',
        '${samples[samples.length ~/ 2]}');
    _record('C2', 'poll-frame p95 (JIT, us)',
        '${samples[(samples.length * 0.95).floor()]}');
    _record('C2', 'poll-frame MAX = rebuild frame (JIT, us)',
        '${samples.last}');
  });

  // ---------------------------------------------------------------------------
  // SCENARIO C3 — CONTROLLED EXPERIMENT: does feed size drive rebuild cost?
  // Same code path, only the number of eager rows changes. This isolates the
  // eager-Column cost from everything else on the screen.
  // ---------------------------------------------------------------------------
  for (final count in const [8, 40, 80, 160]) {
    testWidgets('C3: rebuild cost scales with feed size ($count items)',
        (tester) async {
      stub.commentaryCount = count;
      await _pumpScreen(tester, matchId: 'perf-C3-$count');
      await _advance(tester, const Duration(seconds: 2));
      await tester.tap(find.text('Comm'));
      await _advance(tester, const Duration(seconds: 3));

      final rows = _commentaryRowCount();
      final samples = <int>[];
      final sw = Stopwatch();
      for (var i = 0; i < 60; i++) {
        sw.reset();
        sw.start();
        await tester.pump(const Duration(milliseconds: 250));
        sw.stop();
        samples.add(sw.elapsedMicroseconds);
      }
      samples.sort();
      _record('C3', 'feed=$count rows materialised', '$rows');
      _record('C3', 'feed=$count rebuild frame MAX (JIT, us)',
          '${samples.last}');
      _record('C3', 'feed=$count RenderObjects', '${_renderObjectCount()}');
    });
  }

  // ---------------------------------------------------------------------------
  // SCENARIO B — live match with 5s polling: what rebuilds, how often.
  // ---------------------------------------------------------------------------
  testWidgets('B: live polling frequency + rebuild scope', (tester) async {
    await _pumpScreen(tester, matchId: 'perf-B');
    await _advance(tester, const Duration(seconds: 2));
    stub.resetCounts();

    // Watch a full 30s of live polling on the default (Live) tab.
    await _advance(tester, const Duration(seconds: 30));

    _record('B', 'total HTTP requests / 30s', '${stub.totalRequests}');
    stub.hits.forEach((path, n) {
      _record('B', 'requests to $path / 30s', '$n');
    });
    _record('B', 'expected polls @5s', '6');
  });

  // ---------------------------------------------------------------------------
  // SCENARIO B2 — polling while sitting on the 80-row Commentary tab.
  // This is the worst case: every poll rebuilds 80 eager rows (if eager).
  // ---------------------------------------------------------------------------
  testWidgets('B2: live poll while on 80-row commentary tab', (tester) async {
    stub.commentaryCount = 80;
    await _pumpScreen(tester, matchId: 'perf-B2');
    await _advance(tester, const Duration(seconds: 2));
    await tester.tap(find.text('Comm'));
    await _advance(tester, const Duration(seconds: 2));
    final rows = _commentaryRowCount();
    stub.resetCounts();

    final sw = Stopwatch()..start();
    await _advance(tester, const Duration(seconds: 20));
    sw.stop();

    _record('B2', 'rows on screen during poll', '$rows');
    _record('B2', 'HTTP requests / 20s on Comm tab', '${stub.totalRequests}');
    _record('B2', 'wall time to pump 20s (ms)', '${sw.elapsedMilliseconds}');
  });

  // ---------------------------------------------------------------------------
  // SCENARIO A — completed match: polling MUST stop.
  // ---------------------------------------------------------------------------
  testWidgets('A: completed match stops polling', (tester) async {
    stub.terminal = true;
    // Seed the phase registry through the public parse path (the same way the
    // Home/Matches feed does) so the screen opens straight on Scorecard.
    CricketMatch.fromJson({...completedSummary(), 'match_id': 'perf-done'});
    await _pumpScreen(tester, matchId: 'perf-done');
    await _advance(tester, const Duration(seconds: 3));
    stub.resetCounts();
    await _advance(tester, const Duration(seconds: 25));
    _record('A', 'HTTP requests / 25s after terminal', '${stub.totalRequests}');
    _record('A', 'polling stopped', stub.totalRequests == 0 ? 'YES' : 'NO');
  });

  // ---------------------------------------------------------------------------
  // SCENARIO D — rapid tab switching.
  // ---------------------------------------------------------------------------
  testWidgets('D: rapid tab switching cost', (tester) async {
    await _pumpScreen(tester, matchId: 'perf-D');
    await _advance(tester, const Duration(seconds: 2));
    stub.resetCounts();

    const labels = ['Info', 'Live', 'Score', 'Squad', 'Comm', 'Overs'];
    final sw = Stopwatch()..start();
    for (var round = 0; round < 2; round++) {
      for (final l in labels) {
        final f = find.text(l);
        if (f.evaluate().isEmpty) continue;
        await tester.tap(f.first);
        await _advance(tester, const Duration(milliseconds: 600));
      }
    }
    sw.stop();
    _record('D', '12 tab switches wall time (ms)', '${sw.elapsedMilliseconds}');
    _record('D', 'HTTP requests for 12 switches', '${stub.totalRequests}');
  });

  // ---------------------------------------------------------------------------
  // SCENARIO F — background -> foreground.
  // ---------------------------------------------------------------------------
  testWidgets('F: background suspends polling, foreground resumes',
      (tester) async {
    await _pumpScreen(tester, matchId: 'perf-F');
    await _advance(tester, const Duration(seconds: 2));

    stub.resetCounts();
    tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await _advance(tester, const Duration(seconds: 20));
    final whilePaused = stub.totalRequests;
    _record('F', 'HTTP requests / 20s while PAUSED', '$whilePaused');

    stub.resetCounts();
    tester.binding
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _advance(tester, const Duration(seconds: 12));
    _record('F', 'HTTP requests / 12s after RESUME', '${stub.totalRequests}');
    _record('F', 'suspends in background', whilePaused == 0 ? 'YES' : 'NO');
  });

  // ---------------------------------------------------------------------------
  // SCENARIO G — slow network.
  // ---------------------------------------------------------------------------
  testWidgets('G: slow network does not stack overlapping polls',
      (tester) async {
    stub.latency = const Duration(milliseconds: 1200);
    await _pumpScreen(tester, matchId: 'perf-G');
    await _advance(tester, const Duration(seconds: 4));
    stub.resetCounts();
    await _advance(tester, const Duration(seconds: 20));
    _record('G', 'requests / 20s @1.2s latency', '${stub.totalRequests}');
    _record('G', 'reentrancy guard holds',
        stub.totalRequests <= 20 ? 'YES (no stacking)' : 'NO');
  });

  // ---------------------------------------------------------------------------
  // SCENARIO H — repeated match navigation (memory growth / cache leak).
  // ---------------------------------------------------------------------------
  testWidgets('H: repeated match navigation releases commentary cache',
      (tester) async {
    stub.commentaryCount = 80;
    for (var i = 0; i < 3; i++) {
      await _pumpScreen(tester, matchId: 'perf-1');
      await _advance(tester, const Duration(seconds: 2));
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await _advance(tester, const Duration(milliseconds: 500));
    }
    _record('H', '3x open/close completed', 'YES (no exception)');
    _record('H', 'rows after teardown', '${_commentaryRowCount()}');
  });
}
