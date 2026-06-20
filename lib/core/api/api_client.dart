import 'dart:convert';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_config.dart';

class ApiClientException implements Exception {
  const ApiClientException(this.message,
      {this.statusCode, this.isNetwork = false, this.isRetryable = false});

  final String message;
  final int? statusCode;

  /// True when the failure was a connectivity / timeout problem (no internet or
  /// an unreachable server) rather than a server-side or data error. The UI
  /// uses this to show "No internet connection" instead of a generic error.
  final bool isNetwork;

  /// True when the failure is transient and safe to retry: connectivity /
  /// timeout problems, or a temporary upstream server error (500/502/503/504).
  /// Non-transient failures (4xx, invalid JSON, business-logic errors) are
  /// NEVER marked retryable so the client doesn't hammer a request that will
  /// keep failing the same way.
  final bool isRetryable;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  /// Conservative retry budget for safe GET requests on flaky networks.
  /// Total attempts = 1 initial + [_maxRetries] retries.
  static const int _maxRetries = 2;

  /// Per-attempt backoff before retry N (1-based). Short, with a touch of
  /// jitter so concurrent callers don't all retry on the same beat. Kept small
  /// so a transient blip recovers quickly without a battery/data-draining loop.
  static Duration _backoffFor(int retryAttempt) {
    // retryAttempt 1 → ~400-700ms, retryAttempt 2 → ~1200-1800ms.
    final base = retryAttempt == 1 ? 400 : 1200;
    final span = retryAttempt == 1 ? 300 : 600;
    final jitter = (math.Random().nextDouble() * span).round();
    return Duration(milliseconds: base + jitter);
  }

  /// Safe GET with a conservative retry-on-transient-error policy.
  ///
  /// Only TRANSIENT failures (no connectivity, timeout, or a 5xx upstream
  /// error) are retried, at most [_maxRetries] times with short exponential
  /// backoff. Non-transient failures (4xx, invalid JSON, business errors) throw
  /// immediately — retrying them would just repeat the same failure. The actual
  /// request/parse logic is unchanged; it lives in [_getOnce].
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
    bool allowFailure = false,
  }) async {
    var attempt = 0;
    while (true) {
      try {
        return await _getOnce(path, query: query, allowFailure: allowFailure);
      } on ApiClientException catch (e) {
        if (!e.isRetryable || attempt >= _maxRetries) rethrow;
        attempt++;
        final delay = _backoffFor(attempt);
        if (kDebugMode) {
          // Minimal, secret-free: method + path only, no query/headers/body.
          debugPrint('ApiClient: retry $attempt/$_maxRetries GET $path '
              'in ${delay.inMilliseconds}ms (${e.isNetwork ? 'network' : 'server ${e.statusCode}'})');
        }
        await Future<void>.delayed(delay);
      }
    }
  }

  Future<Map<String, dynamic>> _getOnce(
    String path, {
    Map<String, dynamic>? query,
    bool allowFailure = false,
  }) async {
    late final http.Response response;
    try {
      response = await _httpClient.get(
        ApiConfig.uri(path, query),
        headers: {
          'Accept': 'application/json',
          ...ApiConfig.securityHeaders(),
        },
      ).timeout(const Duration(seconds: 12));
    } on TimeoutException {
      throw const ApiClientException(
          'The cricket data service is taking too long to respond.',
          isNetwork: true,
          isRetryable: true);
    } on http.ClientException catch (error) {
      throw ApiClientException(error.message,
          isNetwork: true, isRetryable: true);
    } catch (_) {
      throw const ApiClientException(
          'Unable to connect to the cricket data service.',
          isNetwork: true,
          isRetryable: true);
    }

    final contentType = response.headers['content-type'] ?? '';
    if (!contentType.contains('application/json')) {
      throw ApiClientException(
        'The cricket data service returned an invalid response.',
        statusCode: response.statusCode,
        // A 5xx without JSON is a transient upstream hiccup — safe to retry.
        isRetryable: _isTransientStatus(response.statusCode),
      );
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      // Invalid JSON is a data problem, not a transient one — do not retry.
      throw ApiClientException(
        'The cricket data service returned invalid JSON.',
        statusCode: response.statusCode,
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw ApiClientException(
        'The cricket data service returned unexpected data.',
        statusCode: response.statusCode,
      );
    }

    final success = decoded['success'] != false;
    if (response.statusCode >= 400 || (!success && !allowFailure)) {
      throw ApiClientException(
        decoded['error']?.toString() ?? 'Unable to load cricket data.',
        statusCode: response.statusCode,
        // Retry only transient upstream errors (500/502/503/504). 4xx and
        // business-logic failures (success:false with a 2xx) are NOT retried.
        isRetryable: _isTransientStatus(response.statusCode),
      );
    }

    return decoded;
  }

  /// Transient HTTP status codes worth retrying: standard upstream/gateway
  /// failures. Everything else (incl. all 4xx) is treated as terminal.
  static bool _isTransientStatus(int statusCode) =>
      statusCode == 500 ||
      statusCode == 502 ||
      statusCode == 503 ||
      statusCode == 504;

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
    bool allowFailure = false,
  }) =>
      _send('POST', path, body: body, allowFailure: allowFailure);

  Future<Map<String, dynamic>> put(
    String path, {
    Map<String, dynamic>? body,
    bool allowFailure = false,
  }) =>
      _send('PUT', path, body: body, allowFailure: allowFailure);

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool allowFailure = false,
  }) async {
    late final http.Response response;
    final headers = {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      ...ApiConfig.securityHeaders(),
    };
    try {
      final uri = ApiConfig.uri(path);
      final payload = body == null ? null : jsonEncode(body);
      response = method == 'PUT'
          ? await _httpClient.put(uri, headers: headers, body: payload)
          : await _httpClient.post(uri, headers: headers, body: payload);
    } on TimeoutException {
      throw const ApiClientException(
          'The cricket data service is taking too long to respond.',
          isNetwork: true);
    } on http.ClientException catch (error) {
      throw ApiClientException(error.message, isNetwork: true);
    } catch (_) {
      throw const ApiClientException(
          'Unable to connect to the cricket data service.',
          isNetwork: true);
    }

    final dynamic decoded;
    try {
      decoded = response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body);
    } on FormatException {
      throw ApiClientException(
        'The cricket data service returned invalid JSON.',
        statusCode: response.statusCode,
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw ApiClientException(
        'The cricket data service returned unexpected data.',
        statusCode: response.statusCode,
      );
    }
    final success = decoded['success'] != false;
    if (response.statusCode >= 400 || (!success && !allowFailure)) {
      throw ApiClientException(
        decoded['error']?.toString() ?? 'Unable to update cricket data.',
        statusCode: response.statusCode,
      );
    }
    return decoded;
  }

  void close() => _httpClient.close();
}
