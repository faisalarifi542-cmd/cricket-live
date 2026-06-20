// Verifies the central ApiClient attaches the API-security headers
// (X-API-Key, X-Client-Type, X-App-Version, X-Package-Name) to every request
// so the backend recognizes the app as an approved client.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:cricpro_flutter/core/api/api_client.dart';
import 'package:cricpro_flutter/core/api/api_config.dart';

void main() {
  test('GET requests include X-API-Key and client headers', () async {
    late http.Request captured;
    final mock = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode({'success': true, 'data': []}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final client = ApiClient(httpClient: mock);
    await client.get('/matches/live');

    expect(captured.headers['X-API-Key'], ApiConfig.apiKey);
    expect(captured.headers['X-API-Key'], isNotEmpty);
    expect(captured.headers['X-Client-Type'], isNotEmpty);
    expect(captured.headers['X-App-Version'], ApiConfig.appVersion);
    expect(captured.headers['X-Package-Name'], ApiConfig.packageName);
  });

  test('POST requests (device register) include the API key', () async {
    late http.Request captured;
    final mock = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode({'success': true}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final client = ApiClient(httpClient: mock);
    await client.post('/app/device/register', body: {'subscriptionId': 'abc'});

    expect(captured.headers['X-API-Key'], ApiConfig.apiKey);
    expect(captured.headers['Content-Type'], contains('application/json'));
  });

  test('optional X-Device-Id is sent only when set', () async {
    final headersNoDevice = ApiConfig.securityHeaders();
    expect(headersNoDevice.containsKey('X-Device-Id'), isFalse);

    ApiConfig.deviceId = 'device-123';
    final headersWithDevice = ApiConfig.securityHeaders();
    expect(headersWithDevice['X-Device-Id'], 'device-123');
    ApiConfig.deviceId = null;
  });
}
