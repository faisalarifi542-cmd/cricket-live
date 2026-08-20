// M6 PERFORMANCE MEASUREMENT — non-production instrumentation.
//
// In-memory stub of the cricket API, installed via `HttpOverrides`.
//
// WHY NOT A REAL SOCKET SERVER: `flutter_test` runs each test inside a
// FakeAsync zone and blocks real HTTP. Real socket I/O can never complete
// while the fake clock is being advanced, so every request timed out and every
// counter read 0. An HttpOverrides stub resolves through plain Futures/Streams,
// which FakeAsync *does* drive — so `tester.pump(5s)` deterministically
// advances the real 5-second polling loop and the responses actually land.
//
// This lets the REAL MatchDetailsScreen + REAL CricketRepository + REAL polling
// timers run unmodified, with deterministic payloads and exact request counts.
//
// DELETE THIS DIRECTORY once the measurement milestone is signed off.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'md_fixtures.dart';

class StubApi {
  StubApi({
    this.commentaryCount = 80,
    this.terminal = false,
    this.latency = Duration.zero,
  });

  /// How many commentary items the commentary endpoints return.
  int commentaryCount;

  /// When true the summary reports a completed match (polling must stop).
  bool terminal;

  /// Artificial per-request delay (scenario G: slow network). Resolved with
  /// `Future.delayed`, so the fake clock drives it.
  Duration latency;

  /// Request counts per path — direct evidence of polling frequency.
  final Map<String, int> hits = {};

  /// Mutating counter so each poll returns genuinely CHANGED data, forcing the
  /// screen's `_jsonChanged` guard to accept the change (worst-case rebuild).
  int _tick = 0;

  int get totalRequests => hits.values.fold(0, (a, b) => a + b);

  void install() => HttpOverrides.global = _StubOverrides(this);

  static void uninstall() => HttpOverrides.global = null;

  void resetCounts() => hits.clear();

  Future<List<int>> respond(Uri uri) async {
    hits[uri.path] = (hits[uri.path] ?? 0) + 1;
    if (latency > Duration.zero) {
      await Future<void>.delayed(latency);
    }
    return utf8.encode(jsonEncode(_route(uri.path, uri.queryParameters)));
  }

  Map<String, dynamic> _route(String path, Map<String, String> query) {
    Map<String, dynamic> ok(Object? data) => {
          'success': true,
          'data': data,
          'meta': {
            'lastUpdated': DateTime.now().toUtc().toIso8601String(),
            'stale': false,
          },
        };

    if (path == '/app/live-commentary') {
      _tick++;
      final payload = liveCommentaryPayload(commentaryCount);
      final items = payload['items'] as List<Map<String, dynamic>>;
      if (items.isNotEmpty) items.first['score'] = '${148 + _tick}/3';
      return ok([
        {'match_id': query['ids'] ?? 'perf-1', ...payload}
      ]);
    }
    if (path.endsWith('/live-center')) {
      _tick++;
      final data = liveCenterPayload();
      (data['partnership'] as Map)['runs'] = '${58 + _tick}';
      return ok(data);
    }
    if (path.endsWith('/scorecard')) return ok(scorecardPayload());
    if (path.endsWith('/squads')) return ok(squadsPayload());
    if (path.endsWith('/overs')) return ok(oversPayload());
    if (path.endsWith('/full-commentary')) {
      return ok(liveCommentaryPayload(commentaryCount));
    }
    if (path.endsWith('/streams')) {
      return ok({'hasStream': false, 'streams': <dynamic>[]});
    }
    if (path == '/app/config') return ok({'liveStreamingEnabled': false});
    if (path.startsWith('/match/')) {
      _tick++;
      final data =
          terminal ? completedSummary() : liveSummary(runs: 148 + _tick);
      return ok(data);
    }
    return ok(const <String, dynamic>{});
  }
}

// ---------------------------------------------------------------------------
// Minimal dart:io HttpClient stub. Only the surface package:http's IOClient
// touches is implemented; everything else forwards through noSuchMethod.
// ---------------------------------------------------------------------------

class _StubOverrides extends HttpOverrides {
  _StubOverrides(this.api);
  final StubApi api;

  @override
  HttpClient createHttpClient(SecurityContext? context) => _StubClient(api);
}

class _StubClient implements HttpClient {
  _StubClient(this.api);
  final StubApi api;

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
      _StubRequest(method, url, api);

  @override
  Future<HttpClientRequest> getUrl(Uri url) => openUrl('GET', url);

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _StubRequest implements HttpClientRequest {
  _StubRequest(this.method, this.uri, this.api);

  @override
  final String method;
  @override
  final Uri uri;
  final StubApi api;

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
  Future<HttpClientResponse> close() async =>
      _StubResponse(await api.respond(uri));

  @override
  Future<HttpClientResponse> get done => close();

  @override
  void add(List<int> data) {}

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await stream.drain<void>();
  }

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
  int? port;
  @override
  bool persistentConnection = true;

  @override
  List<String>? operator [](String name) => _map[name.toLowerCase()];

  @override
  String? value(String name) => _map[name.toLowerCase()]?.first;

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) =>
      _map[name.toLowerCase()] = [value.toString()];

  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) =>
      (_map[name.toLowerCase()] ??= []).add(value.toString());

  @override
  void remove(String name, Object value) => _map.remove(name.toLowerCase());

  @override
  void removeAll(String name) => _map.remove(name.toLowerCase());

  @override
  void forEach(void Function(String name, List<String> values) action) =>
      _map.forEach(action);

  @override
  void clear() => _map.clear();

  @override
  void noFolding(String name) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
