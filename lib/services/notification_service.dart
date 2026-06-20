import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:cricpro_flutter/api_models.dart';
import 'package:cricpro_flutter/core/api/api_client.dart';
import 'package:cricpro_flutter/services/analytics_service.dart';

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
        final data = apiMap(event.notification.additionalData);
        AnalyticsService.instance.track('notification_open', {
          'notification_type': (data['type'] ?? 'unknown').toString(),
        });
        _deepLinkHandler?.call(data);
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
      // Stable install identity so the backend dedupes on it instead of the
      // OneSignal subscription id, which rotates when the OS refreshes the push
      // token — the historical cause of one install counting as many devices.
      'installId': AnalyticsService.instance.installId,
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

  /// Whether OneSignal has been initialised. Tag syncs and permission requests
  /// are no-ops until this is true, so callers (first-run prompt, settings) can
  /// avoid burning a one-shot prompt before init completes.
  bool get isInitialized => _initialized;

  /// Whether the OS-level notification permission is currently granted. Returns
  /// false on web or before OneSignal is initialised.
  bool get permissionGranted {
    if (!_initialized || kIsWeb) return false;
    return OneSignal.Notifications.permission;
  }

  /// Requests the OS notification permission (user-initiated from the settings
  /// screen or first-run prompt). Returns the resulting grant state, syncs it to
  /// the backend, and — on grant — immediately mirrors the user's saved
  /// category + favourite choices to OneSignal tags. This is what makes a FRESH
  /// install targetable by category/favourite sends without the user having to
  /// open the settings or favourites screen first.
  Future<bool> requestPermission() async {
    if (!_initialized || kIsWeb) return false;
    final granted = await OneSignal.Notifications.requestPermission(true);
    await updatePermissionStatus();
    if (granted) _onTagsSync?.call();
    return granted;
  }

  /// Callback wired at startup that re-pushes category + favourite tags from
  /// their services. Kept as a hook so this service does not depend on the
  /// settings/favourite services directly (avoids an import cycle).
  void Function()? _onTagsSync;
  // ignore: use_setters_to_change_properties
  void registerTagsSync(void Function() sync) => _onTagsSync = sync;

  /// Pushes all tags now if initialised — used at startup once OneSignal is up
  /// and whenever permission is already granted.
  void syncAllTags() => _onTagsSync?.call();

  /// Mirrors the user's per-category notification choices to OneSignal tags so
  /// server-side sends can be filtered by category. Each tag is '1' (on) or
  /// '0' (off). No-op until OneSignal is initialised.
  void syncCategoryTags(Map<String, bool> categories) {
    if (!_initialized || kIsWeb) return;
    final tags = <String, String>{
      for (final entry in categories.entries)
        'notif_${entry.key}': entry.value ? '1' : '0',
    };
    if (tags.isEmpty) return;
    try {
      OneSignal.User.addTags(tags);
    } catch (_) {
      // Tag sync is best-effort; local prefs remain the source of truth.
    }
  }

  /// Mirrors the user's favourite country/team codes to OneSignal `fav_<CODE>`
  /// tags so the backend can target favourite-only pushes. [selected] are the
  /// chosen codes (uppercase); [allCodes] is the full catalogue so deselected
  /// codes are explicitly cleared to '0' rather than left stale. No-op until
  /// OneSignal is initialised.
  void syncFavoriteTags(Set<String> selected, Iterable<String> allCodes) {
    if (!_initialized || kIsWeb) return;
    final tags = <String, String>{
      for (final code in allCodes)
        'fav_${code.toUpperCase()}': selected.contains(code.toUpperCase())
            ? '1'
            : '0',
    };
    if (tags.isEmpty) return;
    try {
      OneSignal.User.addTags(tags);
    } catch (_) {
      // Best-effort; local prefs remain the source of truth.
    }
  }
}
