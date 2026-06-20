import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lightweight, disk-backed JSON cache (Phase F1).
///
/// This is a thin persistence layer that sits UNDER the repository's existing
/// in-memory cache. It is NOT a competing cache path: the repository's
/// `_cached` method is the single owner of the flow
/// (memory → persistent → network → write both). Widgets never touch this
/// directly.
///
/// Design goals:
/// * Survive cold start / app restart so the first frame can show the last
///   saved data instead of a spinner.
/// * Be completely fail-safe: any read/write/parse error degrades to "no
///   cache" and NEVER throws into the app.
/// * Keep the raw payload shape unchanged — values are stored exactly as the
///   provided encoder produced them, wrapped in a small versioned envelope.
///
/// Stored envelope shape (per key):
/// ```json
/// {
///   "version": 1,
///   "key": "app:home",
///   "savedAt": "2026-06-18T00:00:00.000Z",
///   "payload": { ... raw, unmodified ... }
/// }
/// ```
class PersistentCache {
  PersistentCache._();
  static final PersistentCache instance = PersistentCache._();

  /// Bump to invalidate every persisted entry after an incompatible format
  /// change. An envelope whose `version` differs is treated as a miss (and the
  /// stale key is dropped on read), so old data can never be mis-parsed.
  static const int version = 1;

  /// Namespacing prefix so cache entries never collide with other
  /// `SharedPreferences` keys (favourites, notification settings, analytics).
  static const String _prefix = 'cache_v1:';

  SharedPreferences? _prefs;
  Future<SharedPreferences>? _prefsFuture;

  /// Lazily obtains the shared `SharedPreferences` instance. Cached after the
  /// first resolve so subsequent reads are synchronous-fast.
  Future<SharedPreferences?> _instance() async {
    if (_prefs != null) return _prefs;
    try {
      _prefsFuture ??= SharedPreferences.getInstance();
      _prefs = await _prefsFuture;
      return _prefs;
    } catch (e) {
      // Plugin unavailable (e.g. early startup / unsupported platform). Treat
      // as "no cache" rather than crashing.
      if (kDebugMode) {
        debugPrint('PersistentCache: prefs unavailable: $e');
      }
      return null;
    }
  }

  String _storageKey(String key) => '$_prefix$key';

  /// Reads and decodes the payload for [key]. Returns `null` on miss, version
  /// mismatch, corrupt JSON, or any error. A corrupt / outdated entry is
  /// deleted in place so it can't keep failing.
  Future<T?> read<T>(String key, T Function(Object? payload) decode) async {
    final prefs = await _instance();
    if (prefs == null) return null;
    final storageKey = _storageKey(key);
    String? raw;
    try {
      raw = prefs.getString(storageKey);
    } catch (_) {
      return null;
    }
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        await _deleteKey(prefs, storageKey);
        return null;
      }
      if (decoded['version'] != version) {
        // Format changed under us — drop the stale entry, report a miss.
        await _deleteKey(prefs, storageKey);
        return null;
      }
      if (!decoded.containsKey('payload')) {
        await _deleteKey(prefs, storageKey);
        return null;
      }
      return decode(decoded['payload']);
    } catch (e) {
      // Corrupt JSON or a decoder that threw on unexpected shape: delete ONLY
      // this bad key and continue safely.
      if (kDebugMode) {
        debugPrint('PersistentCache: corrupt entry "$key" dropped: $e');
      }
      await _deleteKey(prefs, storageKey);
      return null;
    }
  }

  /// Encodes and writes [payload] for [key] inside the versioned envelope.
  /// Best-effort: a failure is swallowed (logged in debug) so a cache write can
  /// never break a successful network response from reaching the UI.
  Future<void> write(String key, Object? payload, {DateTime? savedAt}) async {
    final prefs = await _instance();
    if (prefs == null) return;
    try {
      final envelope = <String, dynamic>{
        'version': version,
        'key': key,
        'savedAt': (savedAt ?? DateTime.now()).toUtc().toIso8601String(),
        'payload': payload,
      };
      final encoded = jsonEncode(envelope);
      await prefs.setString(_storageKey(key), encoded);
    } catch (e) {
      // Non-encodable payload or storage failure — never propagate.
      if (kDebugMode) {
        debugPrint('PersistentCache: write failed for "$key": $e');
      }
    }
  }

  /// Removes a single cached entry. Safe no-op on error.
  Future<void> remove(String key) async {
    final prefs = await _instance();
    if (prefs == null) return;
    await _deleteKey(prefs, _storageKey(key));
  }

  Future<void> _deleteKey(SharedPreferences prefs, String storageKey) async {
    try {
      await prefs.remove(storageKey);
    } catch (_) {
      // Ignore — a failed delete just means a retry on the next read.
    }
  }
}
