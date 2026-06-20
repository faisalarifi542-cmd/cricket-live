import 'package:flutter/foundation.dart';

/// Global player-image resolution modes, mirroring the backend
/// `player_image_mode` setting (see cricket-api/src/lib/player-images.js).
enum PlayerImageMode {
  /// admin photo → provider photo → initials.
  adminFirst,

  /// provider photo → admin photo → initials.
  cricbuzzFirst,

  /// admin photo → initials. Never a provider/Cricbuzz photo.
  adminOnly,

  /// provider photo → initials.
  cricbuzzOnly,

  /// initials only — never any remote photo.
  initialsOnly;

  /// Whether this mode permits loading a provider (Cricbuzz/API) player photo.
  bool get allowsProviderImage =>
      this == PlayerImageMode.adminFirst ||
      this == PlayerImageMode.cricbuzzFirst ||
      this == PlayerImageMode.cricbuzzOnly;

  /// Whether this mode permits any remote photo at all (admin or provider).
  bool get allowsAnyRemoteImage => this != PlayerImageMode.initialsOnly;

  static PlayerImageMode fromString(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'cricbuzz_first':
        return PlayerImageMode.cricbuzzFirst;
      case 'admin_only':
        return PlayerImageMode.adminOnly;
      case 'cricbuzz_only':
        return PlayerImageMode.cricbuzzOnly;
      case 'initials_only':
        return PlayerImageMode.initialsOnly;
      case 'admin_first':
      default:
        return PlayerImageMode.adminFirst;
    }
  }
}

/// Single global source of truth for how player avatars resolve across the app.
///
/// The backend already enriches every player object server-side (sets the
/// correct `imageUrl`/`image_url` and clears raw provider id fields when the
/// mode forbids a photo). This client-side resolver is the safety net that
/// guarantees the app NEVER rebuilds a provider photo URL the admin mode
/// disallows — e.g. from a stale `imageId`/`faceImageId` that slipped through.
///
/// Set the mode once when app config loads (and again on refresh) via
/// [PlayerImageResolver.updateModeFromString]. All player avatar code paths read
/// the resolved URL through [PlayerImageResolver.resolve] / [resolveServerImage]
/// instead of building Cricbuzz URLs themselves.
class PlayerImageResolver {
  PlayerImageResolver._();

  static PlayerImageMode _mode = PlayerImageMode.adminFirst;

  /// Current global mode. Defaults to adminFirst until app config sets it.
  static PlayerImageMode get mode => _mode;

  /// Updates the global mode from the backend setting string. No-op safe.
  static void updateModeFromString(String? raw) {
    final next = PlayerImageMode.fromString(raw);
    if (next != _mode) {
      _mode = next;
      if (kDebugMode) {
        debugPrint('CricProPlayerImage: mode set to ${_mode.name}');
      }
    }
  }

  static bool _isHttp(String? url) {
    final u = url?.trim();
    return u != null && u.isNotEmpty && u.startsWith('http');
  }

  /// Resolves the final player image URL to display, honoring the global mode.
  ///
  /// - [serverImageUrl] is the URL the backend already resolved for this player
  ///   (the only trusted remote source). It is admin-or-provider depending on
  ///   the server-side mode/override logic.
  /// - [adminImageUrl] is an explicit admin photo if a screen has it separately.
  ///
  /// Returns `null` when the avatar must show initials only. Critically, this
  /// NEVER constructs a provider URL from a raw image id — if the mode forbids a
  /// remote image, the result is `null` regardless of any id on the node.
  static String? resolve({
    String? serverImageUrl,
    String? adminImageUrl,
    String? playerName,
  }) {
    String? result;
    switch (_mode) {
      case PlayerImageMode.initialsOnly:
        result = null;
        break;
      case PlayerImageMode.adminOnly:
        // Admin photo only. The server already sends only the admin photo (or
        // null) in this mode, so the server URL is safe to use as the admin
        // photo. An explicit adminImageUrl wins if a screen provides one.
        result = _isHttp(adminImageUrl)
            ? adminImageUrl!.trim()
            : (_isHttp(serverImageUrl) ? serverImageUrl!.trim() : null);
        break;
      case PlayerImageMode.adminFirst:
      case PlayerImageMode.cricbuzzFirst:
      case PlayerImageMode.cricbuzzOnly:
        // Remote photos allowed. Trust the server-resolved URL (it already
        // applied admin/provider priority); fall back to an explicit admin URL.
        result = _isHttp(serverImageUrl)
            ? serverImageUrl!.trim()
            : (_isHttp(adminImageUrl) ? adminImageUrl!.trim() : null);
        break;
    }
    if (kDebugMode) {
      final source = result == null
          ? 'initials'
          : (result == adminImageUrl?.trim() ? 'admin' : 'server');
      debugPrint(
        'CricProPlayerImage: mode=${_mode.name} source=$source '
        'player=${playerName ?? '?'}',
      );
    }
    return result;
  }

  /// Convenience: gate an already-server-resolved URL by the current mode.
  /// Used by model parsers that only have the server URL. Returns the URL when
  /// the mode allows a remote image, else null (→ initials).
  static String? resolveServerImage(String? serverImageUrl,
      {String? playerName}) {
    return resolve(serverImageUrl: serverImageUrl, playerName: playerName);
  }
}
