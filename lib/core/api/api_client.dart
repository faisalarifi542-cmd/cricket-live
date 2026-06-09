import 'dart:convert';
import 'dart:async';

import 'package:http/http.dart' as http;

import 'api_config.dart';

class ApiClientException implements Exception {
  const ApiClientException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  Future<Map<String, dynamic>> get(
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
          'The cricket data service is taking too long to respond.');
    } on http.ClientException catch (error) {
      throw ApiClientException(error.message);
    } catch (_) {
      throw const ApiClientException(
          'Unable to connect to the cricket data service.');
    }

    final contentType = response.headers['content-type'] ?? '';
    if (!contentType.contains('application/json')) {
      throw ApiClientException(
        'The cricket data service returned an invalid response.',
        statusCode: response.statusCode,
      );
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
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
        decoded['error']?.toString() ?? 'Unable to load cricket data.',
        statusCode: response.statusCode,
      );
    }

    return decoded;
  }

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
          'The cricket data service is taking too long to respond.');
    } on http.ClientException catch (error) {
      throw ApiClientException(error.message);
    } catch (_) {
      throw const ApiClientException(
          'Unable to connect to the cricket data service.');
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
