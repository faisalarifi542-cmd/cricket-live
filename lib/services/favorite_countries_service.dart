import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/cricket_match.dart';
import 'notification_service.dart';

/// A selectable cricket nation for the Favorite Countries screen.
class FavoriteCountry {
  const FavoriteCountry({
    required this.code,
    required this.name,
    required this.aliases,
  });

  /// Stable id persisted locally and compared against match team codes
  /// (e.g. `AFG`, `IND`). Always uppercase.
  final String code;

  /// Display name, e.g. `Afghanistan`.
  final String name;

  /// Extra short codes / spellings that the provider sometimes uses for this
  /// team so matching is robust (e.g. `NED`/`NL` for Netherlands).
  final List<String> aliases;

  /// Two-letter initials fallback used when no flag asset is available.
  String get initials {
    final parts =
        name.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) {
      return (parts[0][0] + parts[1][0]).toUpperCase();
    }
    return name.substring(0, name.length.clamp(0, 2)).toUpperCase();
  }
}

/// Local-only favourite cricket countries. No login required — selections are
/// persisted with [SharedPreferences] and used to prioritise matches on Home
/// and the Matches screen.
///
/// A [ValueNotifier] mirrors the saved set so widgets (e.g. the More row count
/// badge and the Home/Matches ordering) can react immediately without a reload.
class FavoriteCountriesService {
  FavoriteCountriesService._();
  static final FavoriteCountriesService instance =
      FavoriteCountriesService._();

  static const String _key = 'favorite_country_codes';

  /// Reactive snapshot of the currently selected country codes (uppercase).
  /// Starts empty (normal sorting) until [load] resolves.
  final ValueNotifier<Set<String>> selected =
      ValueNotifier<Set<String>>(<String>{});

  bool _loaded = false;

  /// The full catalogue shown on the selection screen. Codes are chosen to
  /// match the provider's team short codes wherever possible.
  static const List<FavoriteCountry> catalog = [
    FavoriteCountry(code: 'AFG', name: 'Afghanistan', aliases: ['AFGHANISTAN']),
    FavoriteCountry(code: 'IND', name: 'India', aliases: ['INDIA']),
    FavoriteCountry(code: 'PAK', name: 'Pakistan', aliases: ['PAKISTAN']),
    FavoriteCountry(
        code: 'BAN', name: 'Bangladesh', aliases: ['BAN', 'BDESH', 'BANGLADESH']),
    FavoriteCountry(
        code: 'SL', name: 'Sri Lanka', aliases: ['SRL', 'SRI', 'SRI LANKA']),
    FavoriteCountry(code: 'AUS', name: 'Australia', aliases: ['AUSTRALIA']),
    FavoriteCountry(code: 'ENG', name: 'England', aliases: ['ENGLAND']),
    FavoriteCountry(
        code: 'NZ', name: 'New Zealand', aliases: ['NZL', 'NEW ZEALAND']),
    FavoriteCountry(
        code: 'SA', name: 'South Africa', aliases: ['RSA', 'SAF', 'SOUTH AFRICA']),
    FavoriteCountry(
        code: 'WI', name: 'West Indies', aliases: ['WIN', 'WINDIES', 'WEST INDIES']),
    FavoriteCountry(
        code: 'NED', name: 'Netherlands', aliases: ['NL', 'NETHERLANDS']),
    FavoriteCountry(code: 'IRE', name: 'Ireland', aliases: ['IRL', 'IRELAND']),
    FavoriteCountry(code: 'ZIM', name: 'Zimbabwe', aliases: ['ZIMBABWE']),
    FavoriteCountry(code: 'NEP', name: 'Nepal', aliases: ['NPL', 'NEPAL']),
    FavoriteCountry(
        code: 'UAE', name: 'United Arab Emirates', aliases: ['U.A.E', 'UAE']),
    FavoriteCountry(
        code: 'USA', name: 'United States', aliases: ['US', 'USA', 'UNITED STATES']),
    FavoriteCountry(code: 'OMA', name: 'Oman', aliases: ['OMN', 'OMAN']),
    FavoriteCountry(code: 'SCO', name: 'Scotland', aliases: ['SCOTLAND']),
    FavoriteCountry(code: 'NAM', name: 'Namibia', aliases: ['NAMIBIA']),
    FavoriteCountry(code: 'CAN', name: 'Canada', aliases: ['CAN', 'CANADA']),
  ];

  /// Lazy lookup from any known code/alias/name → canonical country code.
  static final Map<String, String> _aliasToCode = _buildAliasIndex();

  static Map<String, String> _buildAliasIndex() {
    final map = <String, String>{};
    for (final country in catalog) {
      map[country.code.toUpperCase()] = country.code;
      map[country.name.toUpperCase()] = country.code;
      for (final a in country.aliases) {
        map[a.toUpperCase()] = country.code;
      }
    }
    return map;
  }

  /// Loads the saved selection once at startup. Safe to call repeatedly.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final codes = prefs.getStringList(_key) ?? const <String>[];
      selected.value = codes.map((c) => c.toUpperCase()).toSet();
    } catch (_) {
      // Defaults to empty (normal sorting) if prefs are unavailable.
    }
    _syncFavoriteTags();
  }

  bool isSelected(String code) => selected.value.contains(code.toUpperCase());

  /// Toggles a country and persists the new set. Returns the updated set.
  Future<void> toggle(String code) async {
    final next = Set<String>.from(selected.value);
    final upper = code.toUpperCase();
    if (!next.remove(upper)) next.add(upper);
    await _save(next);
  }

  Future<void> _save(Set<String> next) async {
    selected.value = next;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_key, next.toList());
    } catch (_) {
      // Selection still applies in-memory this session even if persist fails.
    }
    _syncFavoriteTags();
  }

  /// Pushes the current favourite codes to OneSignal as `fav_<CODE>` tags so the
  /// backend can target favourite-only pushes. Clears deselected codes to '0'.
  void _syncFavoriteTags() {
    NotificationService.instance.syncFavoriteTags(
      selected.value,
      catalog.map((c) => c.code),
    );
  }

  /// Resolves a team's short code or name to a catalogue country code, or null
  /// if the team is not a recognised nation (e.g. a franchise/league team).
  String? _codeForTeam(String shortName, String fullName) {
    final s = shortName.trim().toUpperCase();
    if (s.isNotEmpty && _aliasToCode.containsKey(s)) return _aliasToCode[s];
    final f = fullName.trim().toUpperCase();
    if (f.isNotEmpty && _aliasToCode.containsKey(f)) return _aliasToCode[f];
    return null;
  }

  /// True when either team in [match] is one of the user's favourite countries.
  bool isFavoriteMatch(CricketMatch match) {
    final favs = selected.value;
    if (favs.isEmpty) return false;
    final a = _codeForTeam(match.teamAShort, match.teamA);
    final b = _codeForTeam(match.teamBShort, match.teamB);
    return (a != null && favs.contains(a)) || (b != null && favs.contains(b));
  }
}
