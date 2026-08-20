// Shared test harness for MatchDetailsScreen widget tests.
//
// This is NOT a general testing framework. It encapsulates exactly the setup
// requirements that were each discovered by a test SILENTLY PASSING while
// measuring the wrong thing. Every rule below is load-bearing; the comment on
// each one records the failure it prevents. `match_details_harness_test.dart`
// is the regression check that proves the harness itself still works.
//
// ---------------------------------------------------------------------------
// THE SEVEN GOTCHAS THIS ENCAPSULATES
// ---------------------------------------------------------------------------
//
// 1. NO REAL SOCKET SERVER. `flutter_test` runs each test body inside a
//    FakeAsync zone that does not drive real I/O. A real `HttpServer` stub
//    handshakes never complete while the fake clock is advanced, so every
//    request timed out and every request counter read 0 — the test still
//    passed, having rendered an empty screen. An `HttpOverrides` stub resolves
//    through plain Futures, which FakeAsync *does* drive.
//
// 2. HttpOverrides IS INSTALLED ONCE, AT FILE SCOPE. Assigning
//    `HttpOverrides.global` inside each `testWidgets` body does not reliably
//    win: the observed symptom was the FIRST test's stub answering EVERY later
//    test's requests, so later tests asserted against stale fixture data and
//    passed. The override is installed once by [useMatchDetailsHttpStub] and
//    always delegates to a mutable [MatchDetailsStub] that each test selects
//    explicitly via [MatchDetailsStub.install].
//
// 3. CLEANUP MUST PREVENT INHERITANCE. The active stub is cleared in BOTH
//    `setUp` and `tearDown`, and an unserved request throws instead of
//    returning a default. A test that forgets to install a stub therefore FAILS
//    LOUDLY rather than quietly inheriting the previous test's data.
//
// 4. SharedPreferences MUST BE MOCKED. `CricketRepository` serves matchDetail
//    through `PersistentCache`, which awaits `SharedPreferences.getInstance()`.
//    Without `setMockInitialValues` that future never completes, so
//    `_configurePolling` is never reached and THE POLL TIMER NEVER ARMS. A
//    polling test then advances the clock against a dead screen and passes.
//
// 5. SINGLETON CACHES MUST BE ISOLATED. `CommentaryCache` and the repository's
//    response cache are process-wide singletons, and the repository TTL is read
//    from the real wall clock while the test runs on a fake clock — so an entry
//    written by an earlier test never expires and is served to a later one.
//    Each test MUST use a unique match id; [pumpMatchDetails] enforces this and
//    clears the commentary bucket on both entry and exit.
//
// 6. WIDGET COUNTS MUST BE SCOPED. `MDBallChip` is also emitted by the Overs
//    legend (`md_panels.dart`) and the recent-balls strip (`md_timeline.dart`).
//    Counting it globally silently inflates the "mounted commentary rows"
//    number, which is the exact figure the lazy-rendering milestone is judged
//    on. Counts here are scoped to the commentary row list's subtree.
//
// 7. ERROR SUPPRESSION MUST BE NARROW. See [ignoreAhemOverflow].

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cricpro_flutter/screens/match_details/match_details_screen.dart';
import 'package:cricpro_flutter/screens/match_details/widgets/match_details_ui.dart';
import 'package:cricpro_flutter/services/commentary_cache.dart';

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

/// One real delivery, shaped like the backend normalizer's output.
///
/// `over` doubles as the row's visible label and, via `CommentaryCache`, as part
/// of its identity.
Map<String, dynamic> ball({
  required double over,
  required int timestamp,
  String type = 'run',
  int runs = 1,
  int innings = 2,
  String? text,
}) =>
    <String, dynamic>{
      'innings': innings,
      'over': over.toStringAsFixed(1),
      'team': 'India',
      'teamShort': 'IND',
      'score': '148/3',
      'type': type,
      'label': switch (type) {
        'wicket' => 'WICKET',
        'six' => 'SIX',
        'four' => 'FOUR',
        'dot' => 'DOT BALL',
        _ => '$runs RUNS',
      },
      'text': text ??
          'Ball at over ${over.toStringAsFixed(1)} — driven through the '
              'covers for a comfortable single as the fielder gives chase.',
      'isBall': true,
      'isWicket': type == 'wicket',
      'isBoundary': type == 'four' || type == 'six',
      'isKeyEvent': type == 'wicket' || type == 'six',
      'runs': runs,
      'timestamp': timestamp,
    };

/// A non-ball note (no over ⇒ the other identity branch in `CommentaryCache`).
Map<String, dynamic> note({required int timestamp, int innings = 2, String? text}) =>
    <String, dynamic>{
      'innings': innings,
      'over': null,
      'type': 'note',
      'label': 'DRINKS',
      'text': text ?? 'Drinks break! India need 42 from the last 8 overs.',
      'isBall': false,
      'isWicket': false,
      'isBoundary': false,
      'isKeyEvent': true,
      'timestamp': timestamp,
    };

/// Newest-first feed of [count] deliveries: descending over, one note per 36.
List<Map<String, dynamic>> feed(int count) {
  final items = <Map<String, dynamic>>[];
  var b = count;
  var ts = 1755600000000;
  for (var i = 0; i < count; i++) {
    final over = (b / 6).floor() + (b % 6) / 10.0;
    final type = switch (i % 17) {
      0 || 8 => 'four',
      3 => 'six',
      11 => 'wicket',
      1 || 5 => 'dot',
      _ => 'run',
    };
    items.add(ball(
      over: over,
      timestamp: ts,
      type: type,
      runs: switch (type) {
        'four' => 4,
        'six' => 6,
        'dot' || 'wicket' => 0,
        _ => 1,
      },
    ));
    if (i % 36 == 35) items.add(note(timestamp: ts - 1));
    b--;
    ts -= 32000;
  }
  return items;
}

/// A live-match summary payload.
Map<String, dynamic> liveSummary(String matchId) => <String, dynamic>{
      'match_id': matchId,
      'status': 'live',
      'state': 'live',
      'match_format': 'T20',
      'series_name': 'Test Series',
      'match_desc': 'Only T20',
      'venue': {'name': 'Wankhede', 'city': 'Mumbai'},
      'status_text': 'India need 42 runs',
      'team1': {
        'name': 'India',
        'short': 'IND',
        'innings': [
          {'runs': 148, 'wickets': 3, 'overs': '24.4'},
        ],
      },
      'team2': {
        'name': 'Australia',
        'short': 'AUS',
        'innings': [
          {'runs': 189, 'wickets': 7, 'overs': '20.0'},
        ],
      },
    };

// ---------------------------------------------------------------------------
// The stub
// ---------------------------------------------------------------------------

/// The stub the CURRENTLY RUNNING test wants requests served from.
///
/// See gotcha 2/3 in the file header: `HttpOverrides.global` is installed once
/// and always delegates here, so switching stubs is a plain field write that
/// cannot lose a race with another test's zone.
MatchDetailsStub? _activeStub;

/// Match ids already used in this process. See gotcha 5.
final Set<String> _usedMatchIds = <String>{};

/// In-memory cricket API for one test.
class MatchDetailsStub {
  MatchDetailsStub({this.count = 80, this.empty = false});

  /// How many commentary items the commentary endpoints return.
  int count;

  /// When true the commentary endpoints return an EMPTY item list.
  ///
  /// Note that an empty payload does NOT clear previously accumulated
  /// commentary — `CommentaryCache.merge` deliberately keeps what it already
  /// has so a provider hiccup cannot blank the feed the user is reading. A test
  /// that wants a genuinely empty feed must therefore use a FRESH match id that
  /// has never accumulated anything (which [pumpMatchDetails] enforces).
  bool empty;

  /// Match id echoed in the commentary payload; set by [pumpMatchDetails].
  String matchId = 'harness';

  /// Extra newest-first items injected to emulate a poll delivering new balls.
  final List<Map<String, dynamic>> extra = [];

  /// Request count per path — the direct evidence that polling is alive.
  final Map<String, int> hits = <String, int>{};

  int get totalRequests => hits.values.fold(0, (a, b) => a + b);

  /// Hits whose path ends with [suffix] (paths are match-id scoped).
  int hitsEndingWith(String suffix) => hits.entries
      .where((e) => e.key.endsWith(suffix))
      .fold(0, (a, e) => a + e.value);

  void resetCounts() => hits.clear();

  /// Selects this stub for the running test. See gotcha 2.
  void install() => _activeStub = this;

  /// Deselects whatever stub is active. See gotcha 3.
  static void uninstall() => _activeStub = null;

  List<Map<String, dynamic>> items() =>
      empty ? const [] : [...extra, ...feed(count)];

  Future<List<int>> respond(Uri uri) async {
    hits[uri.path] = (hits[uri.path] ?? 0) + 1;
    return utf8.encode(jsonEncode(_route(uri.path)));
  }

  Map<String, dynamic> _route(String path) {
    Map<String, dynamic> ok(Object? data) => {
          'success': true,
          'data': data,
          'meta': {
            'lastUpdated': DateTime.now().toUtc().toIso8601String(),
            'stale': false,
          },
        };

    if (path == '/app/live-commentary') {
      return ok([
        {'match_id': matchId, 'items': items()},
      ]);
    }
    if (path.endsWith('/full-commentary')) return ok({'items': items()});
    if (path.endsWith('/live-center')) return ok({'match_state': 'live'});
    if (path.endsWith('/scorecard')) return ok({'innings': <dynamic>[]});
    if (path.endsWith('/squads')) return ok({'team1': <dynamic>[]});
    if (path.endsWith('/overs')) return ok({'overs': <dynamic>[]});
    if (path.endsWith('/streams')) {
      return ok({'hasStream': false, 'streams': <dynamic>[]});
    }
    if (path == '/app/config') return ok({'liveStreamingEnabled': false});
    if (path.startsWith('/match/')) return ok(liveSummary(matchId));
    return ok(const <String, dynamic>{});
  }
}

/// Wires the file-scoped HTTP override and the per-test stub cleanup.
///
/// Call ONCE at the top of `main()`. Do not assign `HttpOverrides.global`
/// anywhere else in the file — see gotcha 2.
void useMatchDetailsHttpStub() {
  // Must be installed AFTER the test binding initialises (the binding installs
  // its own override that answers every request with a non-JSON 400), which
  // `setUpAll` guarantees.
  setUpAll(() => HttpOverrides.global = _StubOverrides());
  tearDownAll(() => HttpOverrides.global = null);

  // Belt and braces (gotcha 3): clearing on BOTH sides means a test that never
  // installs a stub hits the StateError below instead of silently inheriting
  // the previous test's fixture data.
  setUp(MatchDetailsStub.uninstall);
  tearDown(MatchDetailsStub.uninstall);
}

// ---------------------------------------------------------------------------
// Booting the screen
// ---------------------------------------------------------------------------

/// Boots [MatchDetailsScreen] with [stub] selected and opens [tab].
///
/// [matchId] MUST be unique per test in this process (gotcha 5); reuse throws.
/// Defaults to the Commentary tab.
Future<void> pumpMatchDetails(
  WidgetTester tester,
  MatchDetailsStub stub, {
  required String matchId,
  String tab = 'Comm',
  Size surface = const Size(390, 844),
  Duration settle = const Duration(seconds: 2),
}) async {
  if (!_usedMatchIds.add(matchId)) {
    throw StateError(
      'match id "$matchId" was already used in this test process. '
      'CommentaryCache and the repository response cache are process-wide '
      'singletons whose TTL never expires under the fake clock, so a reused id '
      "would serve the earlier test's data to this one. Use a unique id.",
    );
  }

  ignoreAhemOverflow();

  // Gotcha 4 — without this the poll timer never arms and the test measures a
  // dead screen. `match_details_harness_test.dart` proves polling is live.
  SharedPreferences.setMockInitialValues(<String, Object>{});

  // Gotcha 5 — start from a clean commentary bucket, and leave one behind.
  CommentaryCache.instance.clearMatch(matchId);
  addTearDown(() => CommentaryCache.instance.clearMatch(matchId));

  stub.matchId = matchId;
  stub.install();
  addTearDown(MatchDetailsStub.uninstall);

  await tester.binding.setSurfaceSize(surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(home: MatchDetailsScreen(matchId: matchId)),
  );
  await advance(tester, settle);
  if (tab.isNotEmpty) {
    await tester.tap(find.text(tab));
    await advance(tester, settle);
  }
}

/// Pumps in 250ms slices so the real 5s poll timer and 1s ticker actually fire.
///
/// A single `pump(d)` jumps the clock once and a periodic timer scheduled inside
/// that window can be missed; slicing drives every intermediate callback.
Future<void> advance(WidgetTester tester, Duration d) async {
  var elapsed = Duration.zero;
  const slice = Duration(milliseconds: 250);
  while (elapsed < d) {
    await tester.pump(slice);
    elapsed += slice;
  }
}

/// Ignores the `RenderFlex overflowed` layout assertion for the current test.
///
/// WHY THIS EXISTS (gotcha 7): `flutter_test` substitutes the Ahem test font,
/// whose glyph metrics differ from the shipped font, so the fixed-width gutters
/// in the commentary rows overflow by a few logical pixels UNDER THE TEST
/// BINDING ONLY. The M6 AOT measurement with real fonts recorded zero overflow,
/// and the identical assertions fire on the pre-M7 `Column` implementation — so
/// this is a test-environment artifact, not a defect the tests should mask.
///
/// The suppression is deliberately narrow: ONLY that one message is dropped and
/// every other Flutter error is forwarded to the previous handler, so a real
/// exception still fails the test. Never widen this into a blanket swallow.
void ignoreAhemOverflow() {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    if (details.exception.toString().contains('A RenderFlex overflowed')) {
      return;
    }
    previous?.call(details);
  };
  addTearDown(() => FlutterError.onError = previous);
}

// ---------------------------------------------------------------------------
// Scoped measurement (gotcha 6)
// ---------------------------------------------------------------------------

/// The lazy commentary row list specifically.
///
/// The screen hosts two `SliverList`s: the page's fixed children (a
/// `SliverChildListDelegate`) and the commentary rows (a lazy
/// `SliverChildBuilderDelegate`). Matching on the delegate type picks the right
/// one without depending on tree order.
final Finder commentaryRowList = find.byWidgetPredicate(
  (w) => w is SliverList && w.delegate is SliverChildBuilderDelegate,
  description: 'lazy commentary SliverList',
);

Finder _chipsInCommentary() =>
    find.descendant(of: commentaryRowList, matching: find.byType(MDBallChip));

/// Commentary rows currently MOUNTED in the render tree.
///
/// Scoped to [commentaryRowList] so the Overs legend and recent-balls strip —
/// which also emit `MDBallChip` — can never inflate the count (gotcha 6).
int mountedCommentaryRows() {
  if (commentaryRowList.evaluate().isEmpty) return 0;
  return _chipsInCommentary().evaluate().length;
}

/// The chip labels of the mounted commentary rows (e.g. `W`, `4`, `6`).
List<String> mountedChipLabels() {
  if (commentaryRowList.evaluate().isEmpty) return const [];
  return _chipsInCommentary()
      .evaluate()
      .map((e) => (e.widget as MDBallChip).label)
      .toList();
}

/// The over labels of the mounted commentary rows, top to bottom.
List<double> mountedOvers() {
  final overs = <double>[];
  if (commentaryRowList.evaluate().isEmpty) return overs;
  for (final chip in _chipsInCommentary().evaluate().toList()) {
    // The over label is the first Text in the row's left gutter.
    final row = find.ancestor(
      of: find.byWidget(chip.widget),
      matching: find.byType(IntrinsicHeight),
    );
    if (row.evaluate().isEmpty) continue;
    final texts =
        find.descendant(of: row.first, matching: find.byType(Text)).evaluate();
    if (texts.isEmpty) continue;
    final parsed = double.tryParse((texts.first.widget as Text).data ?? '');
    if (parsed != null) overs.add(parsed);
  }
  return overs;
}

/// Total RenderObjects in the tree — the structural cost proxy M6 measured.
int countRenderObjects() {
  var n = 0;
  void visit(RenderObject o) {
    n++;
    o.visitChildren(visit);
  }

  final root = WidgetsBinding.instance.rootElement?.renderObject;
  if (root != null) visit(root);
  return n;
}

// ---------------------------------------------------------------------------
// Minimal dart:io HttpClient stub. Only the surface package:http's IOClient
// touches is implemented; everything else forwards through noSuchMethod.
// ---------------------------------------------------------------------------

class _StubOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _StubClient();
}

class _StubClient implements HttpClient {
  @override
  bool autoUncompress = true;
  @override
  Duration? connectionTimeout;
  @override
  Duration idleTimeout = const Duration(seconds: 15);
  @override
  int? maxConnectionsPerHost;
  @override
  String? userAgent;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      _StubRequest(method, url);
  @override
  Future<HttpClientRequest> getUrl(Uri url) => openUrl('GET', url);
  @override
  void close({bool force = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _StubRequest implements HttpClientRequest {
  _StubRequest(this.method, this.uri);

  @override
  final String method;
  @override
  final Uri uri;
  @override
  bool followRedirects = true;
  @override
  int maxRedirects = 5;
  @override
  int contentLength = -1;
  @override
  bool persistentConnection = true;
  @override
  bool bufferOutput = true;
  @override
  final HttpHeaders headers = _StubHeaders();

  @override
  Future<HttpClientResponse> close() async {
    final stub = _activeStub;
    if (stub == null) {
      // Gotcha 3: fail loudly instead of returning a default that a test could
      // mistake for its own fixture data.
      throw StateError(
        'no MatchDetailsStub is installed, but ${uri.path} was requested. '
        'Call MatchDetailsStub.install() (pumpMatchDetails does it for you).',
      );
    }
    return _StubResponse(await stub.respond(uri));
  }

  @override
  Future<HttpClientResponse> get done => close();
  @override
  void add(List<int> data) {}
  @override
  Future<void> addStream(Stream<List<int>> stream) async =>
      stream.drain<void>();
  @override
  Future<void> flush() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _StubResponse extends Stream<List<int>> implements HttpClientResponse {
  _StubResponse(this.bytes);
  final List<int> bytes;

  @override
  int get statusCode => 200;
  @override
  String get reasonPhrase => 'OK';
  @override
  int get contentLength => bytes.length;
  @override
  bool get isRedirect => false;
  @override
  bool get persistentConnection => false;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  final HttpHeaders headers = _StubHeaders()
    ..set('content-type', 'application/json; charset=utf-8');
  @override
  List<Cookie> get cookies => const [];
  @override
  List<RedirectInfo> get redirects => const [];

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      Stream<List<int>>.value(bytes).listen(onData,
          onError: onError, onDone: onDone, cancelOnError: cancelOnError);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _StubHeaders implements HttpHeaders {
  final Map<String, List<String>> _map = {};

  @override
  bool chunkedTransferEncoding = false;
  @override
  int contentLength = -1;
  @override
  ContentType? contentType;
  @override
  DateTime? date;
  @override
  DateTime? expires;
  @override
  String? host;
  @override
  DateTime? ifModifiedSince;
  @override
  bool persistentConnection = true;
  @override
  int? port;

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) =>
      _map.putIfAbsent(name.toLowerCase(), () => []).add('$value');
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) =>
      _map[name.toLowerCase()] = ['$value'];
  @override
  String? value(String name) => _map[name.toLowerCase()]?.first;
  @override
  List<String>? operator [](String name) => _map[name.toLowerCase()];
  @override
  void forEach(void Function(String name, List<String> values) action) =>
      _map.forEach(action);
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
