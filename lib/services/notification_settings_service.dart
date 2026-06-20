import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notification_service.dart';

/// A user-controllable notification category shown on the Notification Settings
/// screen. [key] is the stable id persisted locally and used as the OneSignal
/// tag name so the backend can filter sends per category.
class NotificationCategory {
  const NotificationCategory({
    required this.key,
    required this.title,
    required this.description,
    required this.defaultOn,
  });

  final String key;
  final String title;
  final String description;
  final bool defaultOn;
}

/// Local-first notification preferences. Choices persist with
/// [SharedPreferences] and, when OneSignal is available, are mirrored to user
/// tags so server-side sends can respect each category. No login required.
///
/// Defaults follow the product rule: match/live/favourite categories ON,
/// marketing/announcements OFF until the user opts in.
class NotificationSettingsService {
  NotificationSettingsService._();
  static final NotificationSettingsService instance =
      NotificationSettingsService._();

  static const String _keyPrefix = 'notif_pref_';

  /// The full set of toggleable categories, in display order.
  static const List<NotificationCategory> categories = [
    NotificationCategory(
      key: 'live_scores',
      title: 'Live match score updates',
      description: 'Score changes while a match you follow is in play.',
      defaultOn: true,
    ),
    NotificationCategory(
      key: 'match_start',
      title: 'Match start reminders',
      description: 'A heads-up shortly before a match begins.',
      defaultOn: true,
    ),
    NotificationCategory(
      key: 'toss',
      title: 'Toss updates',
      description: 'Who won the toss and chose to bat or bowl.',
      defaultOn: true,
    ),
    NotificationCategory(
      key: 'wickets',
      title: 'Wickets & milestones',
      description: 'Wickets, fifties, hundreds and other key moments.',
      defaultOn: true,
    ),
    NotificationCategory(
      key: 'innings_result',
      title: 'Innings break & result',
      description: 'Innings breaks and the final result.',
      defaultOn: true,
    ),
    NotificationCategory(
      key: 'live_stream',
      title: 'Live stream available',
      description: 'When a live stream is available to watch.',
      defaultOn: true,
    ),
    NotificationCategory(
      key: 'favorite_team',
      title: 'Favourite team match alerts',
      description: 'Alerts for matches involving your favourite teams.',
      defaultOn: true,
    ),
    NotificationCategory(
      key: 'news',
      title: 'News & general updates',
      description: 'Cricket news and general updates.',
      defaultOn: true,
    ),
    NotificationCategory(
      key: 'announcements',
      title: 'App announcements & promotions',
      description: 'Occasional product news and offers.',
      defaultOn: false,
    ),
  ];

  /// Reactive snapshot of category key → enabled. Seeded with defaults so the
  /// UI renders correctly before [load] resolves.
  final ValueNotifier<Map<String, bool>> values =
      ValueNotifier<Map<String, bool>>({
    for (final category in categories) category.key: category.defaultOn,
  });

  bool _loaded = false;

  bool isEnabled(String key) =>
      values.value[key] ??
      categories
          .firstWhere((c) => c.key == key,
              orElse: () => const NotificationCategory(
                  key: '', title: '', description: '', defaultOn: true))
          .defaultOn;

  /// Loads saved choices once. Missing keys fall back to each category default.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final next = <String, bool>{};
      for (final category in categories) {
        next[category.key] =
            prefs.getBool('$_keyPrefix${category.key}') ?? category.defaultOn;
      }
      values.value = next;
    } catch (_) {
      // Keep defaults if prefs are unavailable.
    }
    // Mirror the loaded state to OneSignal tags (no-op if not initialised).
    NotificationService.instance.syncCategoryTags(values.value);
  }

  /// Toggles a category, persists it, and syncs the tag set.
  Future<void> setEnabled(String key, bool enabled) async {
    final next = Map<String, bool>.from(values.value);
    next[key] = enabled;
    values.value = next;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('$_keyPrefix$key', enabled);
    } catch (_) {
      // Choice still applies in-memory this session even if persist fails.
    }
    NotificationService.instance.syncCategoryTags(next);
  }
}
