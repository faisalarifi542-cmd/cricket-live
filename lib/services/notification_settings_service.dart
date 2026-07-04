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
  ///
  /// Product rule (admin-automation spec): the live stream category is ON by
  /// default (and new-innings rides it). Every OTHER category is opt-in (OFF)
  /// so non-stream notifications are never forced. The backend can override
  /// these defaults via `/app/config` → notifications.preferences.defaults
  /// (see [applyConfigDefaults]).
  static const List<NotificationCategory> categories = [
    NotificationCategory(
      key: 'live_scores',
      title: 'Live match score updates',
      description: 'Score changes while a match you follow is in play.',
      defaultOn: false,
    ),
    NotificationCategory(
      key: 'match_start',
      title: 'Match start reminders',
      description: 'A heads-up shortly before a match begins.',
      defaultOn: false,
    ),
    NotificationCategory(
      key: 'toss',
      title: 'Toss updates',
      description: 'Who won the toss and chose to bat or bowl.',
      defaultOn: false,
    ),
    NotificationCategory(
      key: 'wickets',
      title: 'Wickets & milestones',
      description: 'Wickets, fifties, hundreds and other key moments.',
      defaultOn: false,
    ),
    NotificationCategory(
      key: 'innings_result',
      title: 'Innings break & result',
      description: 'Innings breaks and the final result.',
      defaultOn: false,
    ),
    NotificationCategory(
      key: 'live_stream',
      title: 'Live stream available',
      description: 'When a live stream (and new innings) is available to watch.',
      defaultOn: true,
    ),
    NotificationCategory(
      key: 'favorite_team',
      title: 'Favourite team match alerts',
      description: 'Alerts for matches involving your favourite teams.',
      defaultOn: false,
    ),
    NotificationCategory(
      key: 'news',
      title: 'News & general updates',
      description: 'Cricket news and general updates.',
      defaultOn: false,
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

  /// Keys the user has explicitly chosen (persisted). Backend config defaults
  /// never override an explicit user choice.
  final Set<String> _userSet = {};

  /// Backend-provided defaults (from /app/config). Applied to any category the
  /// user hasn't explicitly set.
  final Map<String, bool> _configDefaults = {};

  bool isEnabled(String key) =>
      values.value[key] ??
      categories
          .firstWhere((c) => c.key == key,
              orElse: () => const NotificationCategory(
                  key: '', title: '', description: '', defaultOn: true))
          .defaultOn;

  /// Loads saved choices once. Missing keys fall back to the backend config
  /// default (if known) then the category default.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final next = <String, bool>{};
      for (final category in categories) {
        final storedKey = '$_keyPrefix${category.key}';
        if (prefs.containsKey(storedKey)) {
          _userSet.add(category.key);
          next[category.key] = prefs.getBool(storedKey) ?? category.defaultOn;
        } else {
          next[category.key] =
              _configDefaults[category.key] ?? category.defaultOn;
        }
      }
      values.value = next;
    } catch (_) {
      // Keep defaults if prefs are unavailable.
    }
    // Mirror the loaded state to OneSignal tags (no-op if not initialised).
    NotificationService.instance.syncCategoryTags(values.value);
  }

  /// Apply backend default ON/OFF states from `/app/config`
  /// (notifications.preferences.defaults). Only affects categories the user has
  /// NOT explicitly toggled, so a user choice always wins. Safe to call on every
  /// config load.
  void applyConfigDefaults(Map<String, bool> defaults) {
    if (defaults.isEmpty) return;
    var changed = false;
    final next = Map<String, bool>.from(values.value);
    for (final entry in defaults.entries) {
      _configDefaults[entry.key] = entry.value;
      if (!_userSet.contains(entry.key) && next[entry.key] != entry.value) {
        next[entry.key] = entry.value;
        changed = true;
      }
    }
    if (changed) {
      values.value = next;
      NotificationService.instance.syncCategoryTags(next);
    }
  }

  /// Toggles a category, persists it, and syncs the tag set.
  Future<void> setEnabled(String key, bool enabled) async {
    final next = Map<String, bool>.from(values.value);
    next[key] = enabled;
    values.value = next;
    _userSet.add(key);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('$_keyPrefix$key', enabled);
    } catch (_) {
      // Choice still applies in-memory this session even if persist fails.
    }
    NotificationService.instance.syncCategoryTags(next);
  }
}
