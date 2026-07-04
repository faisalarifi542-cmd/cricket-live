import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cricpro_flutter/core/api/api_client.dart';
import 'package:cricpro_flutter/core/api/api_config.dart';

/// Privacy-safe, fire-and-forget analytics.
///
/// - Anonymous random device_id (persisted) + session_id (per app start).
/// - No name/email/phone/IMEI/GPS — only screen names, match ids, quality, etc.
/// - Events are queued in memory and flushed in batches. Every public method is
///   wrapped so analytics can NEVER throw into the UI or block navigation.
/// - If the network is down, events stay queued (capped) and retry on next flush.
class AnalyticsService {
  AnalyticsService._();
  static final AnalyticsService instance = AnalyticsService._();

  static const String _deviceIdKey = 'analytics_device_id';
  static const String _installIdKey = 'analytics_install_id';
  static const String _sessionIdKey = 'analytics_session_id';
  static const String _sessionLastSeenKey = 'analytics_session_last_seen_ms';
  static const int _flushAt = 10; // flush when queue reaches this many events
  static const int _maxQueue = 200; // hard cap; oldest dropped beyond this
  static const Duration _flushInterval = Duration(seconds: 30);
  // Realtime presence ping while the app is foregrounded. The backend stores it
  // in a short Redis window (~120s) so the admin "Active users now" stays live.
  static const Duration _heartbeatInterval = Duration(seconds: 45);
  // A session ends after this much inactivity. Re-opening / resuming within the
  // window continues the SAME session; beyond it a fresh session starts.
  static const Duration _sessionTimeout = Duration(minutes: 30);

  final ApiClient _client = ApiClient();
  final List<Map<String, dynamic>> _queue = [];
  final Random _rng = Random.secure();

  String? _deviceId;
  String? _installId;
  String? _sessionId;
  Timer? _flushTimer;
  Timer? _heartbeatTimer;
  bool _initialized = false;
  bool _flushing = false;

  /// Generate a random hex id (anonymous, not derived from any device hardware).
  String _randomId([int bytes = 16]) {
    final b = List<int>.generate(bytes, (_) => _rng.nextInt(256));
    return b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Stable anonymous install identity (UUID-like hex), generated once on first
  /// run and reused for the life of the install. Exposed so device registration
  /// can dedupe on it instead of the rotating OneSignal subscription id.
  String? get installId => _installId;

  /// Call once at app start. Loads/creates the device + install ids, resumes or
  /// starts a session (30-min timeout), schedules periodic flushing, and records
  /// app_open. Idempotent: a second call is a no-op so duplicate startup paths
  /// (splash, config load, resume) can't double-count a launch.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      var id = prefs.getString(_deviceIdKey);
      if (id == null || id.isEmpty) {
        id = _randomId();
        await prefs.setString(_deviceIdKey, id);
      }
      _deviceId = id;
      // Surface the anonymous id on API headers (X-Device-Id) for parity.
      ApiConfig.deviceId = id;

      // Stable install id (separate from the analytics device id so it can also
      // key device registration). Generated once, persisted forever.
      var install = prefs.getString(_installIdKey);
      if (install == null || install.isEmpty) {
        install = _randomId();
        await prefs.setString(_installIdKey, install);
      }
      _installId = install;

      _flushTimer = Timer.periodic(_flushInterval, (_) => _flush());

      // Resume the persisted session if the last activity was within the
      // timeout, otherwise begin a fresh one. This is what keeps "Sessions" from
      // inflating when the same user opens/resumes the app repeatedly.
      await _resumeOrStartSession(prefs);

      // app_open counts every cold start (separate metric from users/sessions).
      track('app_open', {
        'app_version': ApiConfig.appVersion,
        'platform': ApiConfig.clientType,
      });

      // Begin realtime presence heartbeats while foregrounded.
      _startHeartbeat();
    } catch (_) {
      // Never let analytics init affect app start.
    }
  }

  /// Continue the stored session if still inside the inactivity window, else
  /// start a new one. Records session_start only when a NEW session begins.
  Future<void> _resumeOrStartSession(SharedPreferences prefs) async {
    final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    final stored = prefs.getString(_sessionIdKey);
    final lastSeen = prefs.getInt(_sessionLastSeenKey) ?? 0;
    final fresh = stored == null ||
        stored.isEmpty ||
        (nowMs - lastSeen) > _sessionTimeout.inMilliseconds;
    if (fresh) {
      await _beginSession(prefs, nowMs);
    } else {
      _sessionId = stored;
      await prefs.setInt(_sessionLastSeenKey, nowMs);
    }
  }

  Future<void> _beginSession(SharedPreferences prefs, int nowMs) async {
    _sessionId = _randomId();
    await prefs.setString(_sessionIdKey, _sessionId!);
    await prefs.setInt(_sessionLastSeenKey, nowMs);
    track('session_start', {'app_version': ApiConfig.appVersion});
  }

  /// Marks the current session active "now" and persists the timestamp. Cheap;
  /// safe to call on every tracked event and on app resume.
  Future<void> _touchSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        _sessionLastSeenKey,
        DateTime.now().toUtc().millisecondsSinceEpoch,
      );
    } catch (_) {/* ignore */}
  }

  /// Called when the app returns to the foreground. Starts a new session only if
  /// the inactivity window elapsed; otherwise records another app_open and keeps
  /// the existing session. Never creates a new user.
  Future<void> onAppForeground() async {
    if (!_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
      final lastSeen = prefs.getInt(_sessionLastSeenKey) ?? 0;
      if ((nowMs - lastSeen) > _sessionTimeout.inMilliseconds) {
        await _beginSession(prefs, nowMs);
      } else {
        await prefs.setInt(_sessionLastSeenKey, nowMs);
      }
      track('app_open', {
        'app_version': ApiConfig.appVersion,
        'platform': ApiConfig.clientType,
      });
      // Resume presence heartbeats on foreground.
      _startHeartbeat();
    } catch (_) {/* ignore */}
  }

  /// Begin a fresh session unconditionally (e.g. explicit reset). Safe anytime.
  void startSession() {
    try {
      _sessionId = _randomId();
      SharedPreferences.getInstance().then((prefs) {
        prefs.setString(_sessionIdKey, _sessionId!);
        prefs.setInt(
          _sessionLastSeenKey,
          DateTime.now().toUtc().millisecondsSinceEpoch,
        );
      });
      track('session_start', {'app_version': ApiConfig.appVersion});
    } catch (_) {/* ignore */}
  }

  /// Queue an event. Fire-and-forget; never throws.
  void track(String eventName, [Map<String, dynamic>? payload]) {
    try {
      final event = <String, dynamic>{
        'event_name': eventName,
        'device_id': _deviceId,
        'session_id': _sessionId,
        'payload': payload ?? const {},
        'ts': DateTime.now().toUtc().toIso8601String(),
      };
      _queue.add(event);
      // Keep the session's inactivity clock fresh on any activity.
      _touchSession();
      // Drop oldest if over cap so memory stays bounded.
      if (_queue.length > _maxQueue) {
        _queue.removeRange(0, _queue.length - _maxQueue);
      }
      if (_queue.length >= _flushAt) {
        _flush();
      }
    } catch (_) {/* ignore */}
  }

  /// Convenience: a screen view (caller dedupes — fire once per screen open).
  void screenView(String screenName) =>
      track('screen_view', {'screen_name': screenName});

  /// A match details/center was opened.
  void matchOpen(String matchId) => track('match_open', {'match_id': matchId});

  /// A live stream/player was opened for a match.
  void streamOpen(String matchId) =>
      track('live_stream_open', {'match_id': matchId});

  /// A push notification was opened/tapped.
  void notificationOpen(String type, {String? id}) =>
      track('notification_open', {'type': type, if (id != null) 'id': id});

  /// Flush on app background so queued events aren't lost.
  void onAppBackground() {
    _stopHeartbeat();
    _flush();
  }

  // --- Realtime presence heartbeat ----------------------------------------
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) => _sendHeartbeat());
    _sendHeartbeat();
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  Future<void> _sendHeartbeat() async {
    if (_deviceId == null) return;
    try {
      await _client.post(
        '/analytics/heartbeat',
        body: {
          'device_id': _deviceId,
          'session_id': _sessionId,
          'app_version': ApiConfig.appVersion,
          'platform': ApiConfig.clientType,
        },
        allowFailure: true,
      );
    } catch (_) {/* presence is best-effort */}
  }

  Future<void> _flush() async {
    if (_flushing || _queue.isEmpty) return;
    _flushing = true;
    // Take a snapshot; only remove from the queue on success.
    final batch = List<Map<String, dynamic>>.from(_queue.take(_maxQueue));
    try {
      await _client.post(
        '/analytics/events',
        body: {'events': batch},
        allowFailure: true,
      );
      // Success: drop the flushed events (anything added during the await stays).
      _queue.removeRange(0, batch.length.clamp(0, _queue.length));
    } catch (_) {
      // Offline / server error: keep events queued for the next flush.
    } finally {
      _flushing = false;
    }
  }

  /// For tests / shutdown.
  @visibleForTesting
  void dispose() {
    _flushTimer?.cancel();
    _flushTimer = null;
    _stopHeartbeat();
    _initialized = false;
  }

  @visibleForTesting
  int get queueLength => _queue.length;

  @visibleForTesting
  String? get debugSessionId => _sessionId;
}
