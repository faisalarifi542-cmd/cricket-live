import 'dart:convert';

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
  ApiClient({http.Client? httpClient}) : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, dynamic>? query,
  }) async {
    final response = await _httpClient
        .get(
          ApiConfig.uri(path, query),
          headers: const {
            'Accept': 'application/json',
          },
        )
        .timeout(const Duration(seconds: 12));

    final contentType = response.headers['content-type'] ?? '';
    if (!contentType.contains('application/json')) {
      throw ApiClientException(
        'The cricket data service returned an invalid response.',
        statusCode: response.statusCode,
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw ApiClientException(
        'The cricket data service returned unexpected data.',
        statusCode: response.statusCode,
      );
    }

    final success = decoded['success'] != false;
    if (response.statusCode >= 400 || !success) {
      throw ApiClientException(
        decoded['error']?.toString() ?? 'Unable to load cricket data.',
        statusCode: response.statusCode,
      );
    }

    return decoded;
  }

  void close() => _httpClient.close();
}
