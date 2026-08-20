// M6 PERFORMANCE MEASUREMENT — non-production instrumentation.
//
// Measures the COMPOUNDING case the audit did not consider: `_CommentaryPanel`
// starts at `_shown = 80` and each "View More Commentary" tap does
// `_shown += 80` (md_panels.dart:746-748, :834) while rows are built EAGERLY in
// a Column (:822-827). So a user paging through a long Test-match feed drives
// 80 -> 160 -> 240 simultaneously-mounted rows, and every 5s live poll rebuilds
// all of them.
//
// Run: flutter test test/perf/md_paging_growth_test.dart --concurrency=1
//
// (Same flutter_test font-overflow caveat as the other harness files: the
// RenderFlex overflow assertions are Ahem-font artifacts, absent in AOT.)
//
// DELETE THIS DIRECTORY once the measurement milestone is signed off.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cricpro_flutter/screens/match_details/match_details_screen.dart';
import 'package:cricpro_flutter/screens/match_details/widgets/match_details_ui.dart';

import 'stub_api.dart';

final StubApi _stub = StubApi();
final List<List<String>> _rows = [];

void _record(String metric, String value) {
  _rows.add([metric, value]);
  // ignore: avoid_print
  print('PAGING | $metric | $value');
}

int _renderObjects() {
  var n = 0;
  void visit(RenderObject o) {
    n++;
    o.visitChildren(visit);
  }

  final root = WidgetsBinding.instance.rootElement?.renderObject;
  if (root != null) visit(root);
  return n;
}

void main() {
  tearDownAll(() {
    StubApi.uninstall();
    // ignore: avoid_print
    print('\n===== M6 PAGING-GROWTH TABLE =====');
    for (final r in _rows) {
      // ignore: avoid_print
      print('${r[0]}\t${r[1]}');
    }
  });

  testWidgets('View More paging grows eagerly-mounted rows 80 -> 160 -> 240',
      (tester) async {
    _stub.commentaryCount = 400; // long Test-match style feed
    SharedPreferences.setMockInitialValues(<String, Object>{});
    _stub.install();
    await tester.binding.setSurfaceSize(const Size(360, 804));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(
      home: MatchDetailsScreen(matchId: 'paging-1'),
    ));

    Future<void> settle(Duration d) async {
      var e = Duration.zero;
      while (e < d) {
        await tester.pump(const Duration(milliseconds: 250));
        e += const Duration(milliseconds: 250);
      }
    }

    await settle(const Duration(seconds: 2));
    await tester.tap(find.text('Comm'));
    await settle(const Duration(seconds: 3));

    /// Times the most expensive frame across [n] pumps (poll rebuild frames).
    Future<int> worstFrame(int n) async {
      var worst = 0;
      final sw = Stopwatch();
      for (var i = 0; i < n; i++) {
        sw.reset();
        sw.start();
        await tester.pump(const Duration(milliseconds: 250));
        sw.stop();
        if (sw.elapsedMicroseconds > worst) worst = sw.elapsedMicroseconds;
      }
      return worst;
    }

    for (var page = 1; page <= 3; page++) {
      // Scoped to the lazy commentary list. MDBallChip is ALSO emitted by the
      // Overs legend and the recent-balls strip, so a global count silently
      // inflates the very figure this milestone is judged on. Before M7 there
      // was no lazy list to scope to, hence the fallback to a global count.
      final commList = find.byWidgetPredicate(
        (w) => w is SliverList && w.delegate is SliverChildBuilderDelegate,
      );
      final mounted = commList.evaluate().isEmpty
          ? find.byType(MDBallChip).evaluate().length
          : find
              .descendant(of: commList, matching: find.byType(MDBallChip))
              .evaluate()
              .length;
      final ro = _renderObjects();
      final worst = await worstFrame(40);
      _record('page $page — rows mounted', '$mounted');
      _record('page $page — RenderObjects', '$ro');
      _record('page $page — worst rebuild frame (JIT, us)', '$worst');

      if (page < 3) {
        // M7: "View More" is no longer eagerly built — it sits below the fold
        // until the viewport approaches it, which is the whole point of the
        // lazy list. Scroll to the end of the page to reach it. (Before M7 it
        // was always mounted, so the original harness found it immediately.)
        final scrollable = find.byType(Scrollable).first;
        for (var i = 0; i < 80; i++) {
          if (find.text('View More Commentary').evaluate().isNotEmpty) break;
          await tester.drag(scrollable, const Offset(0, -3000));
          await tester.pump();
        }
        final more = find.text('View More Commentary');
        if (more.evaluate().isEmpty) {
          _record('page $page', 'no View More button — stopping');
          break;
        }
        await tester.tap(more.first, warnIfMissed: false);
        await settle(const Duration(seconds: 2));
      }
    }
  });
}
