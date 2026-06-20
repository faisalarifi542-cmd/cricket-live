import 'package:flutter/foundation.dart';

/// The four team-logo sources, mirroring the backend `team_logo_source_order`
/// setting (see cricket-api/src/lib/team-logos.js).
///
/// * [admin]    — the Admin-Panel uploaded logo (resolved server-side).
/// * [local]    — a logo bundled in the app (rounded flag asset). Client-only.
/// * [api]      — the Cricbuzz/provider logo (resolved server-side).
/// * [initials] — no logo; render the team's initials.
enum TeamLogoSource { admin, local, api, initials }

TeamLogoSource? _sourceFromString(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'admin':
      return TeamLogoSource.admin;
    case 'local':
      return TeamLogoSource.local;
    case 'api':
      return TeamLogoSource.api;
    case 'initials':
      return TeamLogoSource.initials;
    default:
      return null;
  }
}

/// Single global source of truth for the team-logo source priority order.
///
/// The backend already resolves the admin-vs-api logo server-side and reports
/// which source it chose via `logoSource` on each team object. This resolver is
/// the client-side authority that:
///   1. inserts the client-only [TeamLogoSource.local] (bundled flag asset) at
///      the admin-configured position, and
///   2. enforces an `initials`-first / logos-disabled choice so the app never
///      shows a logo (or a local flag) the admin intentionally turned off.
///
/// Default order is `admin → local → api → initials` and logos are enabled, so
/// out of the box an admin logo always wins, then a bundled flag, then the
/// provider logo, then initials. Set the order once when app config loads (and
/// again on refresh) via [TeamLogoResolver.updateFromConfig].
class TeamLogoResolver {
  TeamLogoResolver._();

  static const List<TeamLogoSource> _defaultOrder = [
    TeamLogoSource.admin,
    TeamLogoSource.local,
    TeamLogoSource.api,
    TeamLogoSource.initials,
  ];

  static List<TeamLogoSource> _order = List.of(_defaultOrder);
  static bool _enabled = true;

  /// Current configured order. Always contains all four sources.
  static List<TeamLogoSource> get order => List.unmodifiable(_order);

  /// Whether team logos are enabled at all. When false, everything is initials.
  static bool get enabled => _enabled;

  /// Updates the global order + enable flag from the backend `/app/config`.
  /// No-op safe: invalid/partial input falls back to the default order.
  static void updateFromConfig(dynamic rawOrder, {bool? enabled}) {
    final next = <TeamLogoSource>[];
    if (rawOrder is List) {
      for (final item in rawOrder) {
        final s = _sourceFromString(item?.toString() ?? '');
        if (s != null && !next.contains(s)) next.add(s);
      }
    } else if (rawOrder is String && rawOrder.trim().isNotEmpty) {
      for (final item in rawOrder.split(RegExp(r'[,>\s]+'))) {
        final s = _sourceFromString(item);
        if (s != null && !next.contains(s)) next.add(s);
      }
    }
    // Append any missing sources in default order so the list is always total.
    for (final s in _defaultOrder) {
      if (!next.contains(s)) next.add(s);
    }
    _order = next;
    if (enabled != null) _enabled = enabled;
    if (kDebugMode) {
      debugPrint('CricProTeamLogo: order=${_order.map((e) => e.name).join('>')} '
          'enabled=$_enabled');
    }
  }

  static bool _isHttp(String? url) {
    final u = url?.trim();
    return u != null && u.isNotEmpty && (u.startsWith('http://') || u.startsWith('https://'));
  }

  /// Whether the configured order allows falling back to a bundled local flag
  /// asset at all (i.e. `local` appears before `initials` and logos are on).
  /// Used by the widget to decide whether a name-derived flag may be shown when
  /// no resolved URL is available.
  static bool get allowsLocalFallback {
    if (!_enabled) return false;
    final li = _order.indexOf(TeamLogoSource.local);
    final ii = _order.indexOf(TeamLogoSource.initials);
    return li != -1 && (ii == -1 || li < ii);
  }

  /// Whether the configuration forces initials before any logo (initials first,
  /// or logos disabled).
  static bool get forcesInitials {
    if (!_enabled) return true;
    final ii = _order.indexOf(TeamLogoSource.initials);
    if (ii == -1) return false;
    final ai = _order.indexOf(TeamLogoSource.admin);
    final pi = _order.indexOf(TeamLogoSource.api);
    final li = _order.indexOf(TeamLogoSource.local);
    return (ai == -1 || ii < ai) && (pi == -1 || ii < pi) && (li == -1 || ii < li);
  }

  /// Resolves the team logo to render, honoring the configured order.
  ///
  /// - [serverRemote] is the URL the backend already resolved (admin or api per
  ///   the server-side order), or null when it chose initials/disabled.
  /// - [logoSource] is the backend's reported source for [serverRemote]
  ///   (`admin` | `api` | `initials` | `none`), used to place the client-only
  ///   `local` source relative to admin vs api.
  /// - [localAsset] is a bundled flag asset path for the team, or null.
  ///
  /// Returns an http URL, a local asset path, or null (→ initials).
  static String? resolve({
    String? serverRemote,
    String? logoSource,
    String? localAsset,
  }) {
    if (!_enabled) return null;
    final remote = _isHttp(serverRemote) ? serverRemote!.trim() : null;
    final source = (logoSource ?? '').trim().toLowerCase();
    final local = (localAsset != null && localAsset.trim().isNotEmpty)
        ? localAsset.trim()
        : null;
    // The server reports which source `remote` represents. When it didn't report
    // one, infer: a resolved remote with an admin-shaped source is admin, else
    // treat it as api (provider).
    final remoteIsAdmin = remote != null && source == 'admin';
    final remoteIsApi = remote != null && source != 'admin';

    for (final src in _order) {
      switch (src) {
        case TeamLogoSource.admin:
          if (remoteIsAdmin) return remote;
          break;
        case TeamLogoSource.api:
          if (remoteIsApi) return remote;
          break;
        case TeamLogoSource.local:
          if (local != null) return local;
          break;
        case TeamLogoSource.initials:
          return null;
      }
    }
    // Order exhausted without an explicit initials stop: last-ditch use whatever
    // remote/local we have so a logo never disappears unintentionally.
    return remote ?? local;
  }
}
