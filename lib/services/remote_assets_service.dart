import 'package:flutter/foundation.dart';

import 'package:cricpro_flutter/repositories/cricket_repository.dart';

/// One admin-managed remote asset entry resolved from `GET /app/assets`.
@immutable
class RemoteAsset {
  const RemoteAsset({
    required this.key,
    required this.theme,
    required this.url,
    this.version,
    this.universalSafe = false,
  });

  final String key;
  final String theme; // 'light' | 'dark' | 'both'
  final String url;
  final String? version;

  /// When true, a `theme: both` upload is explicitly declared safe to show in
  /// BOTH dark and light mode. When false (the default for cards/panels/
  /// backgrounds), a `both` asset is treated as dark-only and is NEVER shown in
  /// light mode — light falls back to the bundled light/local design instead.
  final bool universalSafe;
}

/// Resolves admin-managed decorative image URLs at runtime.
///
/// Loaded once at startup (best-effort). If the backend is unreachable or has
/// no row for a key, [urlFor] returns null and the caller renders its bundled
/// fallback asset. Memory-only cache — no extra plugin dependency. Image bytes
/// are cached on disk by Flutter's own [Image.network] cache.
class RemoteAssetsService {
  RemoteAssetsService._();
  static final RemoteAssetsService instance = RemoteAssetsService._();

  /// Keys for LARGE static decorative backgrounds that must ALWAYS load from the
  /// bundled local WebP asset, never from the admin/remote server.
  ///
  /// Rationale: these are heavy, full-bleed stadium/hero/card/panel backgrounds
  /// shown on core screens (Home, Matches, Schedule, Series, Match Details, Live
  /// Player). Serving them remotely would mean every user pulls several MB of
  /// static art from the API on app open — a bandwidth spike and a slow first
  /// paint on poor networks. They already ship as optimized local WebP, so we
  /// force-resolve them locally. [urlFor] returns null for these keys regardless
  /// of any admin upload, so the caller renders its bundled fallback.
  ///
  /// Remote/admin assets remain available for any FUTURE genuinely-dynamic key
  /// that is NOT in this set (small, optional, intentionally server-driven).
  static const Set<String> _localFirstKeys = {
    'stadium_bg_generic',
    'home_backdrop',
    'home_hero_bg_dark',
    'home_hero_bg_light',
    'home_featured_card_bg',
    'match_card_live_bg',
    'match_card_upcoming_bg',
    'match_card_finished_bg',
    'matches_backdrop',
    'live_player_bg_dark',
    'live_player_bg_light',
    'player_surface_bg',
    'match_details_header_bg',
    'schedule_backdrop',
    'schedule_match_card_bg',
    'series_backdrop',
    'series_hero_bg',
    'series_list_card_bg',
    'series_match_card_bg',
    'series_overview_panel_bg',
    'series_squad_section_bg',
    'series_stats_table_bg',
    'series_empty_state_bg',
  };

  final CricketRepository _repository = CricketRepository();

  // key -> theme('light'|'dark'|'both') -> RemoteAsset
  final Map<String, Map<String, RemoteAsset>> _byKey = {};
  // key -> true when ANY variant of the key is declared universal-safe by the
  // backend catalog. Gates whether a `both` asset may be used in light mode.
  final Map<String, bool> _universalSafe = {};
  bool _loaded = false;

  bool get isLoaded => _loaded;

  /// Fetches the asset catalog. Safe to call multiple times; never throws.
  Future<void> load({bool forceRefresh = false}) async {
    try {
      final response = await _repository.appAssets(forceRefresh: forceRefresh);
      final data = response.data;
      final list = data['assets'];
      if (list is! List) {
        _loaded = true;
        return;
      }
      _byKey.clear();
      _universalSafe.clear();
      for (final raw in list) {
        if (raw is! Map) continue;
        final key = raw['key']?.toString();
        final url = raw['url']?.toString();
        if (key == null || key.isEmpty || url == null || url.isEmpty) continue;
        final theme = (raw['theme']?.toString() ?? 'both').toLowerCase();
        // Accept bool true or string 'true'/'1' for forward/back compat.
        final rawSafe = raw['universalSafe'];
        final universalSafe = rawSafe == true ||
            rawSafe == 1 ||
            rawSafe?.toString().toLowerCase() == 'true' ||
            rawSafe?.toString() == '1';
        if (universalSafe) _universalSafe[key] = true;
        _byKey.putIfAbsent(key, () => {})[theme] = RemoteAsset(
          key: key,
          theme: theme,
          url: url,
          version: raw['version']?.toString(),
          universalSafe: universalSafe,
        );
      }
      _loaded = true;
    } catch (e) {
      // Backend down / endpoint missing — keep whatever we had, fall back to
      // bundled assets. Never blocks app startup.
      if (kDebugMode) debugPrint('[RemoteAssets] load failed: $e');
      _loaded = true;
    }
  }

  /// Returns the remote URL for [key] honoring theme, or null if none.
  ///
  /// Dark request: exact 'dark' → 'both' (unchanged — dark uses the uploaded
  /// `both` image as before).
  ///
  /// Light request: exact 'light' ONLY. A `both` asset is used in light mode
  /// *solely* when the backend catalog declares the key universal-safe
  /// (`universalSafe: true`). Otherwise light returns null so the caller renders
  /// its bundled light/local design — a dark `both` upload never bleeds into
  /// light mode (cards, panels, decorative stadium backgrounds).
  String? urlFor(String key, {required bool isDark}) {
    // Large static backgrounds always use the bundled local WebP — never the
    // remote server — to avoid an API/bandwidth spike on app open. See
    // [_localFirstKeys].
    if (_localFirstKeys.contains(key)) return null;

    final variants = _byKey[key];
    if (variants == null || variants.isEmpty) return null;

    if (isDark) {
      return variants['dark']?.url ?? variants['both']?.url;
    }

    // Light mode.
    final light = variants['light']?.url;
    if (light != null && light.isNotEmpty) return light;
    if (_universalSafe[key] == true) {
      final both = variants['both']?.url;
      if (both != null && both.isNotEmpty) return both;
    }
    return null; // → caller renders bundled light/local fallback.
  }
}
