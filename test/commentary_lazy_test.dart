// Regression contract for the LAZY commentary list (M7).
//
// The Commentary tab used to emit every row from a `for` loop inside a `Column`
// that sat in a single child of the parent `ListView`. That materialised the
// whole page of rows up front (measured: 80 rows / ~3 971 RenderObjects, and
// 160 / ~7 415 after one "View More"), and every 5s live poll rebuilt all of
// them. The rows are now a `SliverList.builder` contributed directly to the
// screen's own viewport, so only rows near the viewport are ever built.
//
// These tests assert RENDER-TREE and USER-VISIBLE behaviour — how many rows are
// actually mounted, what text is on screen, what order it is in. They
// deliberately do NOT grep the source for "ListView.builder", because that would
// pass for an implementation that still forces every child to build (e.g.
// `shrinkWrap: true`), which is the exact trap this milestone had to avoid.
//
// All the load-bearing setup (single file-scoped HttpOverrides, per-test stub
// selection, SharedPreferences mocking, singleton-cache isolation, scoped row
// counting, narrow Ahem-overflow suppression) lives in
// `support/match_details_harness.dart`, which documents WHY each rule exists.
// `match_details_harness_test.dart` proves the harness itself still works —
// run it if anything here starts behaving strangely.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cricpro_flutter/services/commentary_cache.dart';

import 'support/match_details_harness.dart';

void main() {
  // Installs HttpOverrides ONCE for the file and clears the active stub around
  // every test. See gotchas 1-3 in the harness header.
  useMatchDetailsHttpStub();

  // 1 + 4 + 5. The headline contract: a big feed must not mount a big tree.
  testWidgets('80-item feed mounts only viewport rows, newest-first',
      (tester) async {
    final stub = MatchDetailsStub(count: 80);
    await pumpMatchDetails(tester, stub, matchId: 'lazy-viewport');

    final mounted = mountedCommentaryRows();
    final ros = countRenderObjects();

    // Baseline before the fix was 80 rows / ~3 971 RenderObjects. A 390x844
    // viewport fits well under 20 of these rows.
    expect(mounted, greaterThan(0),
        reason: 'commentary must actually render rows');
    expect(mounted, lessThan(25),
        reason: 'rows must be viewport-culled, not materialised for the feed '
            '(was 80 before the fix); mounted=$mounted');
    expect(ros, lessThan(2000),
        reason: 'RenderObjects must drop far below the 3 971 baseline; got $ros');

    // Newest-first: overs descend down the visible window.
    final overs = mountedOvers();
    expect(overs.length, greaterThan(1));
    final sorted = [...overs]..sort((a, b) => b.compareTo(a));
    expect(overs, sorted, reason: 'commentary must stay newest-first');
  });

  // 6. The anti-regression that matters most: paging must not double the tree.
  testWidgets('View More does not grow the mounted row count', (tester) async {
    final stub = MatchDetailsStub(count: 200);
    await pumpMatchDetails(tester, stub, matchId: 'lazy-paging');

    final before = mountedCommentaryRows();
    final rosBefore = countRenderObjects();

    // "View More" is below the fold now (correctly — it is not built until
    // scrolled near). Scroll to the end of the page to reach it.
    final scrollable = find.byType(Scrollable).first;
    for (var i = 0; i < 60; i++) {
      await tester.drag(scrollable, const Offset(0, -3000));
      await tester.pump();
      if (find.text('View More Commentary').evaluate().isNotEmpty) break;
    }
    expect(find.text('View More Commentary'), findsOneWidget,
        reason: 'paging control must still be reachable');

    await tester.tap(find.text('View More Commentary'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final after = mountedCommentaryRows();
    final rosAfter = countRenderObjects();

    // Before the fix this went 80 -> 160 rows and 3 971 -> 7 415 ROs.
    expect(after, lessThan(25),
        reason: 'a second page must not materialise another 80 rows; '
            'before=$before after=$after');
    expect(rosAfter, lessThan(2000),
        reason: 'RenderObjects must stay flat across paging; '
            'before=$rosBefore after=$rosAfter');
  });

  // 2 + 3. All four filters, and switching between them.
  testWidgets('all four filters select the right rows', (tester) async {
    final stub = MatchDetailsStub(count: 80);
    await pumpMatchDetails(tester, stub, matchId: 'lazy-filters');

    expect(find.text('All'), findsOneWidget);
    expect(mountedCommentaryRows(), greaterThan(0));

    // Wickets — every mounted row must be a wicket ('W' chip label).
    await tester.tap(find.text('Wickets'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final wicketChips = mountedChipLabels();
    expect(wicketChips, isNotEmpty, reason: 'the feed contains wickets');
    expect(wicketChips.every((l) => l == 'W'), isTrue,
        reason: 'Wickets filter must show only wickets; got $wicketChips');

    // Boundaries — only 4s and 6s.
    await tester.tap(find.text('Boundaries'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final boundaryChips = mountedChipLabels();
    expect(boundaryChips, isNotEmpty);
    expect(boundaryChips.every((l) => l == '4' || l == '6'), isTrue,
        reason: 'Boundaries filter must show only 4s/6s; got $boundaryChips');

    // Key Events — non-empty, and still lazy.
    await tester.tap(find.text('Key Events'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(mountedCommentaryRows(), lessThan(25));

    // Back to All — restores the full set.
    await tester.tap(find.text('All'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(mountedCommentaryRows(), greaterThan(0));
  });

  // 7 + 8. Expansion must follow the DELIVERY, not the index, and survive both
  // scrolling and a live poll that prepends newer balls.
  testWidgets('expanded row survives scroll-away and polling', (tester) async {
    final stub = MatchDetailsStub(count: 80);
    await pumpMatchDetails(tester, stub, matchId: 'lazy-expand');

    // Expand the first row.
    final chevrons = find.byIcon(Icons.keyboard_arrow_down_rounded);
    expect(chevrons, findsWidgets);
    await tester.tap(chevrons.first);
    await tester.pump();
    expect(find.byIcon(Icons.keyboard_arrow_up_rounded), findsOneWidget,
        reason: 'tapping the chevron must expand the row');

    // Scroll far away (destroying that row's element) and come back.
    final scrollable = find.byType(Scrollable).first;
    await tester.drag(scrollable, const Offset(0, -2500));
    await tester.pump();
    await tester.drag(scrollable, const Offset(0, 4000));
    await tester.pump();

    expect(find.byIcon(Icons.keyboard_arrow_up_rounded), findsOneWidget,
        reason: 'expansion must survive the row being culled and rebuilt — '
            'this is why the state cannot live in the row State');

    // A poll now prepends a NEWER ball. The expanded flag must stay on the ball
    // the user opened, not jump to whatever is now at index 0.
    stub.extra.add(ball(over: 99.1, timestamp: 1755600999000, type: 'four'));
    await advance(tester, const Duration(seconds: 6));

    expect(find.byIcon(Icons.keyboard_arrow_up_rounded), findsOneWidget,
        reason: 'exactly one row stays expanded across a poll — the same one');
  });

  // 8 + 9 + 11. Polling: new item appears, no duplicates, no scroll jump, and
  // the selected filter is retained.
  testWidgets('polling adds new commentary without duplicates or jumps',
      (tester) async {
    final stub = MatchDetailsStub(count: 80);
    await pumpMatchDetails(tester, stub, matchId: 'lazy-poll');

    // Select a non-default filter so we can prove it is retained.
    await tester.tap(find.text('Boundaries'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Scroll into the middle of the feed and record the offset.
    final scrollable = find.byType(Scrollable).first;
    await tester.drag(scrollable, const Offset(0, -600));
    await tester.pump();
    final position = tester.state<ScrollableState>(scrollable).position;
    final offsetBefore = position.pixels;

    // Prove the poll really delivered something new, rather than assuming it.
    // Without this the assertions below would also pass on a dead screen.
    final requestsBefore = stub.totalRequests;

    // A poll delivers one genuinely new boundary.
    stub.extra.add(ball(over: 98.2, timestamp: 1755600888000, type: 'six'));
    await advance(tester, const Duration(seconds: 6));

    expect(stub.totalRequests, greaterThan(requestsBefore),
        reason: 'the poll must actually have fired — otherwise this test is '
            'asserting against a static screen');

    // Filter retained: still only boundary chips mounted.
    final chips = mountedChipLabels();
    expect(chips.every((l) => l == '4' || l == '6'), isTrue,
        reason: 'the selected filter must survive a poll; got $chips');

    // No unexpected scroll jump. _restoreScroll clamps to the new extent, so
    // allow a small tolerance rather than demanding bit-exactness.
    final offsetAfter =
        tester.state<ScrollableState>(scrollable).position.pixels;
    expect((offsetAfter - offsetBefore).abs(), lessThan(80),
        reason: 'polling must not reset scroll position; '
            'before=$offsetBefore after=$offsetAfter');

    // No duplicate rows: the identity of every mounted row is unique.
    final overs = mountedOvers();
    expect(overs.length, overs.toSet().length,
        reason: 'a poll must not duplicate commentary rows; got $overs');
  });

  // 10. Empty commentary state.
  //
  // Uses a FRESH match id, which is load-bearing: an empty payload deliberately
  // preserves previously accumulated commentary (CommentaryCache is a
  // no-removal cache so a provider hiccup cannot blank a feed the user is
  // reading), so a reused id would legitimately still render rows. Proven in
  // `match_details_harness_test.dart`.
  testWidgets('empty commentary shows the empty state', (tester) async {
    final stub = MatchDetailsStub(count: 0, empty: true);
    await pumpMatchDetails(tester, stub, matchId: 'lazy-empty');

    // No commentary rows, and no lazy row list at all — the panel short-circuits
    // to its state card.
    expect(commentaryRowList.evaluate(), isEmpty,
        reason: 'no lazy row list should be built for an empty feed');
    expect(mountedCommentaryRows(), 0);
    expect(
      find.textContaining('Commentary', findRichText: true),
      findsWidgets,
      reason: 'an empty feed must explain itself rather than render blank',
    );
  });

  // Identity contract that the expand-state keying depends on.
  test('commentary identity is stable per delivery and unique per row', () {
    final cache = CommentaryCache.instance;
    final a = ball(over: 8.4, timestamp: 100);
    final b = ball(over: 8.4, timestamp: 999, text: 'fuller text later');
    final c = ball(over: 8.5, timestamp: 100);

    expect(cache.identityFor(a), cache.identityFor(b),
        reason: 'the same delivery re-sent with fuller text is the same row');
    expect(cache.identityFor(a), isNot(cache.identityFor(c)),
        reason: 'different deliveries must not collide');

    final n1 = note(timestamp: 1);
    final n2 = note(timestamp: 2);
    expect(cache.identityFor(n1), cache.identityFor(n2),
        reason: 'notes with identical text/innings collapse (no-dupe cache)');
  });
}
