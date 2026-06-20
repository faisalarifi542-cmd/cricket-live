import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:cricpro_flutter/core/api/api_config.dart';
import 'package:cricpro_flutter/models/cricket_match.dart';

/// Permission/availability state for the optional Android floating-score overlay.
enum FloatingScoreStatus {
  /// Not Android, or the device cannot host an overlay.
  unsupported,

  /// Android device, but the "Display over other apps" permission isn't granted.
  permissionNeeded,

  /// Permission granted — the overlay can be shown.
  enabled,
}

/// Thin Dart wrapper over the native Android overlay bridge
/// (`cricpro/overlay_bridge`). Android-only; every call is a graceful no-op on
/// other platforms so callers never need a platform check.
///
/// This does NOT replace the in-app [MinimizedScoreController] — it is the
/// optional "Floating Score over other apps" advanced feature. The native side
/// owns the bubble UI + its own 5s poll of `/app/live-scores`, so the overlay
/// keeps updating while CricPro is backgrounded.
class FloatingScoreOverlay {
  FloatingScoreOverlay._();
  static final FloatingScoreOverlay instance = FloatingScoreOverlay._();

  static const MethodChannel _channel =
      MethodChannel('cricpro/overlay_bridge');

  /// Set by [registerOpenMatchHandler]; invoked when the user taps the bubble.
  ValueChanged<String>? _onOpenMatch;

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Wire the deep-link callback once (from the app shell) so a bubble tap can
  /// open Match Details. Safe to call on any platform.
  void registerOpenMatchHandler(ValueChanged<String> onOpenMatch) {
    _onOpenMatch = onOpenMatch;
    if (!_isAndroid) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openMatch') {
        final id = call.arguments?.toString() ?? '';
        if (id.isNotEmpty) {
          _log('open match=$id');
          _onOpenMatch?.call(id);
        }
      }
      return null;
    });
  }

  /// Whether this device can host the overlay at all (Android only).
  Future<bool> isSupported() async {
    if (!_isAndroid) return false;
    try {
      return (await _channel.invokeMethod<bool>('isSupported')) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Whether "Display over other apps" is currently granted.
  Future<bool> hasPermission() async {
    if (!_isAndroid) return false;
    try {
      final granted =
          (await _channel.invokeMethod<bool>('hasPermission')) ?? false;
      _log('permission status=$granted');
      return granted;
    } catch (_) {
      return false;
    }
  }

  /// Combined availability + permission status for settings UI.
  Future<FloatingScoreStatus> status() async {
    if (!await isSupported()) return FloatingScoreStatus.unsupported;
    return await hasPermission()
        ? FloatingScoreStatus.enabled
        : FloatingScoreStatus.permissionNeeded;
  }

  /// Opens the system overlay-permission screen for this package. Only call this
  /// after the user has explicitly tapped "Enable Floating Score". Returns the
  /// permission state immediately after the request was launched (the user may
  /// still be on the settings screen, so re-check with [hasPermission] on
  /// resume).
  Future<bool> requestPermission() async {
    if (!_isAndroid) return false;
    _log('request permission');
    try {
      return (await _channel.invokeMethod<bool>('requestPermission')) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Starts the floating bubble for [match]. Seeds the bubble with the current
  /// score so it shows instantly; the native service then polls
  /// `/app/live-scores?ids=<id>` every 5s. Returns false if unsupported, the
  /// permission is missing, or the service refused to start (caller should fall
  /// back to the in-app minimizer).
  Future<bool> start(CricketMatch match) async {
    if (!_isAndroid) return false;
    if (match.id.isEmpty) return false;
    if (!await hasPermission()) {
      _log('start aborted — permission missing');
      return false;
    }
    _log('start match=${match.id}');
    try {
      final ok = await _channel.invokeMethod<bool>('start', <String, dynamic>{
        'matchId': match.id,
        'baseUrl': ApiConfig.baseUrl,
        'apiKey': ApiConfig.apiKey,
        'clientType': ApiConfig.clientType,
        'appVersion': ApiConfig.appVersion,
        'packageName': ApiConfig.packageName,
        'teamA': _teamLine(match.teamAShort, match.teamA, match.teamAScoreText),
        'teamB': _teamLine(match.teamBShort, match.teamB, match.teamBScoreText),
        'status': _shortStatus(match),
        'isLive': match.isLive && !match.isFinished,
      });
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Removes the bubble and stops the native poll/service. Safe to call anytime.
  Future<void> stop() async {
    if (!_isAndroid) return;
    _log('stop');
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (_) {}
  }

  /// Whether the native overlay service currently reports as running.
  Future<bool> isRunning() async {
    if (!_isAndroid) return false;
    try {
      return (await _channel.invokeMethod<bool>('isRunning')) ?? false;
    } catch (_) {
      return false;
    }
  }

  // ── Seed formatting (mirrors the in-app bar / native rules) ───────────────

  String _teamLine(String short, String name, String scoreText) {
    final code = _formatCode(short.isEmpty ? name : short);
    final score = scoreText.trim();
    if (score.isEmpty) return code;
    return '$code  $score';
  }

  String _shortStatus(CricketMatch m) {
    if (m.resultText.trim().isNotEmpty) return m.resultText.trim();
    return m.statusText.trim();
  }

  /// "INDA" -> "IND A", "SLA" -> "SL A", "INDU19" -> "IND U19".
  String _formatCode(String raw) {
    final c = raw.trim().toUpperCase();
    if (c.isEmpty || c == 'TBC' || c == 'TBD' || c.contains(' ')) return c;
    final u19 = RegExp(r'^([A-Z]{2,})U19$').firstMatch(c);
    if (u19 != null) return '${u19.group(1)} U19';
    final w = RegExp(r'^([A-Z]{2,})W$').firstMatch(c);
    if (w != null) return '${w.group(1)} W';
    final a = RegExp(r'^([A-Z]{2,})A$').firstMatch(c);
    if (a != null) return '${a.group(1)} A';
    return c;
  }

  void _log(String message) {
    if (kDebugMode) debugPrint('CricProFloatingScore: $message');
  }
}
