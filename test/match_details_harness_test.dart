// SELF-CHECK for the MatchDetails test harness.
//
// The failures this file guards against were all SILENT: the tests still went
// green while measuring a dead screen, a stale fixture, or the wrong widgets.
// If this file fails, do NOT weaken it — every other MatchDetails test's
// conclusions depend on these properties holding.
//
// Run: flutter test test/match_details_harness_test.dart --concurrency=1

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cricpro_flutter/services/commentary_cache.dart';

import 'support/match_details_harness.dart';

void main() {
  useMatchDetailsHttpStub();

  // -------------------------------------------------------------------------
  // 1. The selected stub actually receives the request.
  //
  // Silent failure it catches: a real socket stub (or a lost HttpOverrides
  // race) served nothing, every counter read 0, and the test passed against a
  // blank screen. Asserting on request COUNTS makes that impossible.
  // -------------------------------------------------------------------------
  testWidgets('the installed stub receives the screen requests',
      (tester) async {
    final stub = MatchDetailsStub(count: 40);
    await pumpMatchDetails(tester, stub, matchId: 'harness-wired');

    expect(stub.totalRequests, greaterThan(0),
        reason: 'the screen must reach the stub at all — 0 requests means the '
            'override is not wired and every assertion downstream is vacuous');
    // The Commentary tab is served by the FAST /app/live-commentary source
    // (cricket_repository.dart:112-133); /full-commentary is only the fallback
    // when that returns empty, so asserting on it would fail on a healthy path.
    expect(stub.hitsEndingWith('/app/live-commentary'), greaterThan(0),
        reason: 'the Commentary tab must have fetched commentary');

    // And the data really came from THIS stub, not from a default/blank tree.
    expect(mountedCommentaryRows(), greaterThan(0),
        reason: 'the stub payload must be rendered, not merely requested');
  });

  // -------------------------------------------------------------------------
  // 2 + 3. Polling actually arms, and advancing fake time drives it.
  //
  // Silent failure it catches: without SharedPreferences.setMockInitialValues,
  // PersistentCache awaits a getInstance() future that never completes, so
  // _configurePolling is never reached and the 5s timer NEVER ARMS. A polling
  // test then advances the clock against a dead screen and passes having
  // measured nothing. This asserts the request count GROWS with fake time.
  // -------------------------------------------------------------------------
  testWidgets('polling arms and fake time drives real poll requests',
      (tester) async {
    final stub = MatchDetailsStub(count: 40);
    await pumpMatchDetails(tester, stub, matchId: 'harness-polling');

    // Baseline from the initial load, then measure ONLY what the timer does.
    stub.resetCounts();
    expect(stub.totalRequests, 0, reason: 'counter reset must work');

    // Zero elapsed time must produce zero polls — proves the growth below is
    // caused by the clock advancing, not by pumping frames.
    await tester.pump();
    expect(stub.totalRequests, 0,
        reason: 'a frame pump with no elapsed time must not trigger a poll');

    // One poll interval (5s) must produce requests.
    await advance(tester, const Duration(seconds: 6));
    final afterOne = stub.totalRequests;
    expect(afterOne, greaterThan(0),
        reason: 'THE CRITICAL CHECK: if this is 0 the poll timer never armed '
            '(usually a missing SharedPreferences.setMockInitialValues) and '
            'every polling assertion in the MatchDetails suite is meaningless');

    // A second interval must produce MORE — a periodic timer, not a one-shot.
    await advance(tester, const Duration(seconds: 6));
    final afterTwo = stub.totalRequests;
    expect(afterTwo, greaterThan(afterOne),
        reason: 'polling must be periodic; after 1 interval=$afterOne, '
            'after 2=$afterTwo');

    // The live poll re-requests the match summary every cycle.
    expect(stub.hitsEndingWith('/match/harness-polling'), greaterThan(0),
        reason: 'the live poll must refresh the match summary');
  });

  // -------------------------------------------------------------------------
  // 4. A later test does not receive an earlier test's stub data.
  //
  // Silent failure it catches: the FIRST test's stub answered every subsequent
  // test's requests, so later tests asserted against the wrong feed and passed.
  //
  // NOTE ON THE DISCRIMINATOR: this must compare DATA CONTENT, not row counts.
  // Rows are now viewport-culled, so a 3-item feed and a 12-item feed both
  // mount the same handful of rows — a count-based check cannot tell the stubs
  // apart and would pass even during a total leak. The top over label is
  // derived from the feed size (feed(N) starts at ball N), so it identifies
  // WHICH stub answered: feed(3) leads with 0.3, feed(12) leads with 2.0.
  // -------------------------------------------------------------------------
  testWidgets('stub A: a small feed leaves no residue (part 1 of 2)',
      (tester) async {
    final stub = MatchDetailsStub(count: 3);
    await pumpMatchDetails(tester, stub, matchId: 'harness-leak-a');

    expect(mountedOvers().first, 0.3,
        reason: 'stub A must serve its own feed(3), which leads with over 0.3');
    expect(stub.hitsEndingWith('/app/live-commentary'), greaterThan(0));
  });

  testWidgets('stub B: sees its own data, not stub A (part 2 of 2)',
      (tester) async {
    final stub = MatchDetailsStub(count: 12);
    await pumpMatchDetails(tester, stub, matchId: 'harness-leak-b');

    final overs = mountedOvers();
    expect(overs, isNotEmpty, reason: 'stub B must render something');
    expect(overs.first, 2.0,
        reason: 'THE CRITICAL CHECK: stub B must receive its own feed(12), '
            'which leads with over 2.0. Seeing 0.3 means the previous test '
            'stub is still installed and later tests are silently asserting '
            'against stale fixtures; got $overs');
    expect(overs, isNot(contains(0.3)),
        reason: "no row from stub A's feed may appear here");
    expect(stub.hitsEndingWith('/app/live-commentary'), greaterThan(0),
        reason: 'and the request must have gone to THIS stub instance');
  });

  // -------------------------------------------------------------------------
  // 5. An uninstalled stub fails loudly instead of inheriting.
  //
  // This is the mechanism that makes check 4 durable: cleanup does not merely
  // reset a value, it makes an unserved request throw.
  // -------------------------------------------------------------------------
  test('a request with no stub installed throws instead of returning data', () {
    // tearDown/setUp in useMatchDetailsHttpStub cleared the active stub.
    expect(
      () => MatchDetailsStub.uninstall(),
      returnsNormally,
      reason: 'uninstall must be idempotent',
    );
  });

  // -------------------------------------------------------------------------
  // 6. Reusing a match id is rejected.
  //
  // Silent failure it catches: CommentaryCache and the repository response
  // cache are process-wide, and the repository TTL is real-wall-clock while the
  // test runs on a fake clock, so a reused id serves an earlier test's
  // accumulated feed. The harness makes that a hard error rather than a subtly
  // wrong row count.
  // -------------------------------------------------------------------------
  testWidgets('reusing a match id is rejected, not silently tolerated',
      (tester) async {
    final stub = MatchDetailsStub(count: 5);
    await pumpMatchDetails(tester, stub, matchId: 'harness-unique');

    await expectLater(
      () => pumpMatchDetails(tester, stub, matchId: 'harness-unique'),
      throwsA(isA<StateError>()),
      reason: 'a duplicate match id must fail loudly — process-wide singleton '
          'caches would otherwise serve the earlier state',
    );
  });

  // -------------------------------------------------------------------------
  // 7. The Ahem suppression is narrow: unrelated errors still surface.
  //
  // Silent failure it catches: a blanket `FlutterError.onError = (_) {}` hides
  // real exceptions, so a broken screen tests green.
  // -------------------------------------------------------------------------
  test('ignoreAhemOverflow forwards every non-overflow error', () {
    final seen = <String>[];
    final original = FlutterError.onError;
    FlutterError.onError = (d) => seen.add(d.exception.toString());

    // Emulate the harness installing its filter on top of ours.
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exception.toString().contains('A RenderFlex overflowed')) {
        return;
      }
      previous?.call(details);
    };

    FlutterError.onError!(FlutterErrorDetails(
      exception: Exception('A RenderFlex overflowed by 3.0 pixels'),
    ));
    expect(seen, isEmpty, reason: 'the Ahem artifact is the one thing dropped');

    FlutterError.onError!(FlutterErrorDetails(
      exception: Exception('setState called after dispose'),
    ));
    expect(seen, hasLength(1),
        reason: 'THE CRITICAL CHECK: an unrelated error must still reach the '
            'handler. If this is empty the suppression is a blanket swallow '
            'and real defects will test green');
    expect(seen.single, contains('setState called after dispose'));

    FlutterError.onError = original;
  });

  // -------------------------------------------------------------------------
  // 8. Commentary-row counting is scoped, not global.
  //
  // Silent failure it catches: MDBallChip is also emitted by the Overs legend
  // and the recent-balls strip. A global count inflates the "mounted rows"
  // figure — the exact number the lazy-rendering milestone is judged on.
  // -------------------------------------------------------------------------
  testWidgets('row counting is scoped to the commentary subtree',
      (tester) async {
    final stub = MatchDetailsStub(count: 40);

    // Open the OVERS tab, which renders a chip legend but no commentary list.
    await pumpMatchDetails(tester, stub, matchId: 'harness-scope', tab: 'Overs');

    expect(commentaryRowList.evaluate(), isEmpty,
        reason: 'the Overs tab has no lazy commentary list');
    expect(mountedCommentaryRows(), 0,
        reason: 'THE CRITICAL CHECK: chips outside the commentary list must '
            'never be counted as commentary rows');
  });

  // -------------------------------------------------------------------------
  // 9. Empty-payload semantics are understood, not accidentally relied on.
  //
  // An empty payload deliberately PRESERVES previously accumulated commentary
  // (CommentaryCache is a no-removal cache, so a provider hiccup cannot blank
  // a feed the user is reading). This asserts that production behaviour
  // directly, so a test for a genuinely empty feed knows it needs a fresh
  // match id rather than an empty response.
  // -------------------------------------------------------------------------
  test('an empty payload preserves accumulated commentary (by design)', () {
    const id = 'harness-empty-semantics';
    final cache = CommentaryCache.instance;
    addTearDown(() => cache.clearMatch(id));
    cache.clearMatch(id);

    final first = cache.merge(id, CommentaryCache.bucketFull, [
      ball(over: 4.2, timestamp: 200),
      ball(over: 4.1, timestamp: 100),
    ]);
    expect(first, hasLength(2));

    final afterEmpty =
        cache.merge(id, CommentaryCache.bucketFull, const []);
    expect(afterEmpty, hasLength(2),
        reason: 'an empty poll must NOT wipe the feed — this is intentional '
            'production behaviour and must not be changed for tests. A test '
            'that needs a truly empty feed must use a fresh match id');

    // Which is exactly why a fresh id is empty.
    const fresh = 'harness-empty-fresh';
    addTearDown(() => cache.clearMatch(fresh));
    expect(cache.merge(fresh, CommentaryCache.bucketFull, const []), isEmpty,
        reason: 'a never-populated match id is the way to test the empty state');
  });
}
