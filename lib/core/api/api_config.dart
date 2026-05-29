import 'package:flutter/foundation.dart';

class ApiConfig {
  const ApiConfig._();

  static const String baseUrl = String.fromEnvironment(
    'CRICKET_API_BASE_URL',
    defaultValue: 'https://api.webcrichd.co',
  );

  static bool get allowDemoFallback =>
      kDebugMode || const bool.fromEnvironment('CRICPRO_ALLOW_DEMO_DATA');

  static Uri uri(String path, [Map<String, dynamic>? query]) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final params = <String, String>{};
    query?.forEach((key, value) {
      if (value != null) params[key] = value.toString();
    });
    return Uri.parse('$baseUrl$normalizedPath').replace(
      queryParameters: params.isEmpty ? null : params,
    );
  }
}
