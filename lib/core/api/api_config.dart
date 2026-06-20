import 'package:flutter/foundation.dart';

class ApiConfig {
  const ApiConfig._();

  static const String baseUrl = String.fromEnvironment(
    'CRICKET_API_BASE_URL',
    defaultValue: 'https://api.webcrichd.co',
  );

  /// Public app API key. Sent as `X-API-Key` on every request so the backend
  /// API-security layer can identify this as an approved app client.
  ///
  /// This matches the backend's seeded default (APP_PUBLIC_API_KEY). For
  /// production, issue a fresh client + key from the Admin Panel and inject it
  /// here at build time with:
  ///   --dart-define=CRICKET_API_KEY=csk_xxx
  static const String apiKey = String.fromEnvironment(
    'CRICKET_API_KEY',
    defaultValue: 'csk_live_cricpro_app_8f3a2b1c9d',
  );

  /// App version reported via `X-App-Version` (used for version checks).
  static const String appVersion = String.fromEnvironment(
    'CRICKET_APP_VERSION',
    defaultValue: '1.0.0',
  );

  /// Android package name / iOS bundle id reported to the backend so it can
  /// enforce the client's allowed package list.
  static const String packageName = String.fromEnvironment(
    'CRICKET_PACKAGE_NAME',
    defaultValue: 'com.cric.pro',
  );

  /// Optional device id (set at startup if available, e.g. from a plugin).
  static String? deviceId;

  /// Client type: android | ios | web | server. Web-safe (no dart:io).
  static String get clientType {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      default:
        return 'web';
    }
  }

  /// Headers that identify this approved app client on every API request.
  static Map<String, String> securityHeaders() {
    final headers = <String, String>{
      'X-API-Key': apiKey,
      'X-Client-Type': clientType,
      'X-App-Version': appVersion,
      'X-Package-Name': packageName,
    };
    if (clientType == 'ios') {
      headers['X-Bundle-Id'] = packageName;
    }
    final id = deviceId;
    if (id != null && id.isNotEmpty) {
      headers['X-Device-Id'] = id;
    }
    return headers;
  }

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
