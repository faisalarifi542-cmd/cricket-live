// Verifies the F5 slow-internet retry policy in ApiClient: transient failures
// (network errors, timeouts, 5xx) are retried a bounded number of times, while
// terminal failures (4xx, invalid JSON) are NOT retried.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:cricpro_flutter/core/api/api_client.dart';

http.Response _json(Object body, int status) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

void main() {
  test('retries a transient 503 then succeeds', () async {
    var calls = 0;
    final mock = MockClient((request) async {
      calls++;
      if (calls < 3) {
        return _json({'success': false, 'error': 'upstream'}, 503);
      }
      return _json({'success': true, 'data': []}, 200);
    });

    final result = await ApiClient(httpClient: mock).get('/matches/live');
    expect(result['success'], true);
    expect(calls, 3); // 1 initial + 2 retries, third attempt succeeds.
  });

  test('does NOT retry a 404', () async {
    var calls = 0;
    final mock = MockClient((request) async {
      calls++;
      return _json({'success': false, 'error': 'not found'}, 404);
    });

    await expectLater(
      ApiClient(httpClient: mock).get('/match/nope'),
      throwsA(isA<ApiClientException>()),
    );
    expect(calls, 1); // terminal — no retry.
  });

  test('does NOT retry invalid JSON', () async {
    var calls = 0;
    final mock = MockClient((request) async {
      calls++;
      return http.Response('not-json{{', 200,
          headers: {'content-type': 'application/json'});
    });

    await expectLater(
      ApiClient(httpClient: mock).get('/app/home'),
      throwsA(isA<ApiClientException>()),
    );
    expect(calls, 1); // data error — no retry.
  });

  test('retries network errors up to the cap then rethrows', () async {
    var calls = 0;
    final mock = MockClient((request) async {
      calls++;
      throw http.ClientException('connection reset');
    });

    await expectLater(
      ApiClient(httpClient: mock).get('/matches/live'),
      throwsA(isA<ApiClientException>()
          .having((e) => e.isNetwork, 'isNetwork', true)),
    );
    expect(calls, 3); // 1 initial + 2 retries, all fail → rethrow.
  });

  test('does NOT retry a business-logic failure on a 200', () async {
    var calls = 0;
    final mock = MockClient((request) async {
      calls++;
      return _json({'success': false, 'error': 'no data'}, 200);
    });

    await expectLater(
      ApiClient(httpClient: mock).get('/match/x/scorecard'),
      throwsA(isA<ApiClientException>()),
    );
    expect(calls, 1); // success:false on 2xx is terminal — no retry.
  });
}
