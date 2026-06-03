import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:cricpro_flutter/api_models.dart';
import 'package:cricpro_flutter/core/api/api_client.dart';

typedef NotificationDeepLinkHandler = void Function(Map<String, dynamic> data);

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final ApiClient _client = ApiClient();
  bool _initialized = false;
  NotificationDeepLinkHandler? _deepLinkHandler;

  Future<void> initialize(
    AppConfig config, {
    NotificationDeepLinkHandler? onDeepLink,
  }) async {
    _deepLinkHandler = onDeepLink ?? _deepLinkHandler;
    final notifications = config.notifications;
    final enabled = apiBool(
      notifications['enabled'] ?? config.values['enableNotifications'],
      true,
    );
    final appId = config.oneSignalAppId;
    if (!enabled || appId == null || appId.isEmpty || kIsWeb) return;

    if (!_initialized) {
      OneSignal.initialize(appId);
      OneSignal.Notifications.addClickListener((event) {
        _deepLinkHandler?.call(apiMap(event.notification.additionalData));
      });
      _initialized = true;
    }

    final promptMode = apiString(notifications['permissionPromptMode'], 'later');
    if (promptMode == 'startup' || promptMode == 'immediate') {
      await OneSignal.Notifications.requestPermission(true);
    }
    await registerDevice();
  }

  Future<void> registerDevice() async {
    if (!_initialized || kIsWeb) return;
    final packageInfo = await PackageInfo.fromPlatform();
    final subscription = OneSignal.User.pushSubscription;
    final subscriptionId = subscription.id;
    if (subscriptionId == null || subscriptionId.isEmpty) return;
    final platform = Platform.isIOS
        ? 'ios'
        : Platform.isAndroid
            ? 'android'
            : 'other';
    await _client.post('/app/device/register', body: {
      'subscriptionId': subscriptionId,
      'pushToken': subscription.token,
      'platform': platform,
      'appVersion': packageInfo.version,
      'buildNumber': packageInfo.buildNumber,
      'language': Platform.localeName,
      'permissionStatus': OneSignal.Notifications.permission ? 'granted' : 'denied',
    }, allowFailure: true);
  }

  Future<void> updatePermissionStatus() async {
    if (!_initialized || kIsWeb) return;
    final subscriptionId = OneSignal.User.pushSubscription.id;
    if (subscriptionId == null || subscriptionId.isEmpty) return;
    await _client.put('/app/device/update', body: {
      'subscriptionId': subscriptionId,
      'permissionStatus': OneSignal.Notifications.permission ? 'granted' : 'denied',
    }, allowFailure: true);
  }
}
