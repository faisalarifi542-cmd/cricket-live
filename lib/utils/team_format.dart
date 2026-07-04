// App-wide cricket text formatters — the single source of truth for team
// codes, compact names, status/result shortening, match-format casing and
// toss grammar. Every screen (Home, Matches, Schedule, Series, Match Details,
// minimized score bar) renders through these so codes/labels look identical
// everywhere: `NZ W`, `IRE W`, `IND A`, `AFG A`, `IND U19` — never the cramped
// `NZW` / `INDA` / `AFGA`.
import '../models/cricket_match.dart';

/// Spaces a trailing team-variant suffix in a CODE so it reads `IND W`,
/// `IND A`, `IND U19` instead of the cramped `INDW` / `INDA` / `INDU19`.
/// Leaves plain men's codes (`IND`, `WI`, `SA`, `UAE`, `USA`) and placeholders
/// untouched.
String formatTeamCode(String code) {
  var c = code.trim().toUpperCase();
  if (c.isEmpty || c == 'TBC' || c == 'TBD') return c;
  if (c.contains(' ')) return c; // already spaced (e.g. "IND W").

  // U19 first (longest suffix). Base must be a real letters-only code.
  final u19 = RegExp(r'^([A-Z]{2,})U19$').firstMatch(c);
  if (u19 != null) return '${u19.group(1)} U19';

  // U23 / U17 / U16 variants seen in some domestic feeds.
  final uAge = RegExp(r'^([A-Z]{2,})U(\d{2})$').firstMatch(c);
  if (uAge != null) return '${uAge.group(1)} U${uAge.group(2)}';

  // Women's `W` — base ≥ 2 letters so we never split a 2-char code like "WI".
  final w = RegExp(r'^([A-Z]{2,})W$').firstMatch(c);
  if (w != null) return '${w.group(1)} W';

  // A team `A` — base ≥ 2 letters.
  final a = RegExp(r'^([A-Z]{2,})A$').firstMatch(c);
  if (a != null) return '${a.group(1)} A';

  return c;
}

/// Known long full-team names mapped to their broadcast short codes, so a
/// compact card can show `AFG A` even when the API only sent the long name
/// `Afghanistan A` with no short code.
const Map<String, String> _kNameToCode = {
  'afghanistan': 'AFG',
  'australia': 'AUS',
  'bangladesh': 'BAN',
  'england': 'ENG',
  'india': 'IND',
  'ireland': 'IRE',
  'new zealand': 'NZ',
  'pakistan': 'PAK',
  'south africa': 'SA',
  'sri lanka': 'SL',
  'west indies': 'WI',
  'zimbabwe': 'ZIM',
  'netherlands': 'NED',
  'scotland': 'SCO',
  'nepal': 'NEP',
  'united arab emirates': 'UAE',
  'united states': 'USA',
  'united states of america': 'USA',
  // Associate / emerging nations seen in women's, A-team and league feeds.
  'rwanda': 'RWA',
  'brazil': 'BRA',
  'cyprus': 'CYP',
  'malta': 'MAL',
  'kenya': 'KEN',
  'namibia': 'NAM',
  'oman': 'OMA',
  'hong kong': 'HK',
  'papua new guinea': 'PNG',
  'canada': 'CAN',
  'jersey': 'JER',
  'guernsey': 'GUE',
  'uganda': 'UGA',
  'tanzania': 'TAN',
  'nigeria': 'NGA',
  'germany': 'GER',
  'italy': 'ITA',
  'france': 'FRA',
  'spain': 'ESP',
  'austria': 'AUT',
  'argentina': 'ARG',
  'thailand': 'THA',
  'malaysia': 'MAS',
  'singapore': 'SGP',
  'bahrain': 'BHR',
  'qatar': 'QAT',
  'kuwait': 'KUW',
  'saudi arabia': 'KSA',
  'bhutan': 'BHU',
  'maldives': 'MDV',
  'botswana': 'BOT',
  'zambia': 'ZAM',
  'mozambique': 'MOZ',
  'eswatini': 'SWZ',
  'isle of man': 'IOM',
  'denmark': 'DEN',
  'norway': 'NOR',
  'sweden': 'SWE',
  'belgium': 'BEL',
  'portugal': 'POR',
  'czech republic': 'CZE',
  'romania': 'ROM',
  'finland': 'FIN',
  'fiji': 'FIJ',
  'vanuatu': 'VAN',
  'samoa': 'SAM',
  'cayman islands': 'CAY',
  'bermuda': 'BMU',
  'cook islands': 'COK',
  'philippines': 'PHI',
  'indonesia': 'INA',
  'japan': 'JPN',
  'south korea': 'KOR',
  'china': 'CHN',
  'mexico': 'MEX',
  'peru': 'PER',
  'panama': 'PAN',
  'gibraltar': 'GIB',
  'turkey': 'TUR',
  'greece': 'GRE',
  'hungary': 'HUN',
  'bulgaria': 'BUL',
  'serbia': 'SRB',
  'croatia': 'CRO',
  'estonia': 'EST',
  'luxembourg': 'LUX',
  'switzerland': 'SUI',
  'ghana': 'GHA',
  'sierra leone': 'SLE',
  'cameroon': 'CMR',
  'lesotho': 'LES',
  'malawi': 'MWI',
  'st helena': 'SHN',
  'seychelles': 'SEY',
};

/// Resolves the best short code for a team given its (possibly empty) short
/// field and full name. Prefers the supplied short code (spaced via
/// [formatTeamCode]); otherwise derives one from a known long name plus its
/// variant suffix (`Afghanistan A` -> `AFG A`, `India Women` -> `IND W`).
String teamCodeOf(String short, String name) {
  final s = short.trim();
  if (s.isNotEmpty) return formatTeamCode(s.toUpperCase());

  // No short code — try to derive from the full name.
  final n = name.trim();
  if (n.isEmpty) return '';
  final lower = n.toLowerCase();

  // Detect + strip a trailing variant suffix from the NAME.
  String suffix = '';
  String base = lower;
  final u19 = RegExp(r'\s+u-?19$').firstMatch(lower);
  final women = RegExp(r"\s+(women'?s|women|w)$").firstMatch(lower);
  final aTeam = RegExp(r'\s+a$').firstMatch(lower);
  if (u19 != null) {
    suffix = ' U19';
    base = lower.substring(0, u19.start);
  } else if (women != null) {
    suffix = ' W';
    base = lower.substring(0, women.start);
  } else if (aTeam != null) {
    suffix = ' A';
    base = lower.substring(0, aTeam.start);
  }

  final code = _kNameToCode[base.trim()];
  if (code != null) return '$code$suffix';

  // Unknown long name: fall back to the upper-cased name as-is so we never
  // invent a wrong code. Caller decides whether to show this or the name.
  return n.toUpperCase();
}

/// Best-effort extraction of the two participating teams from a SERIES title
/// when the provider omits a teams array (common for tour/bilateral series):
///   "Afghanistan Tour Of India 2026"      -> Afghanistan (AFG), India (IND)
///   "Australia tour of Bangladesh 2026"   -> Australia (AUS), Bangladesh (BAN)
///   "Sri Lanka Women U19 tour of India"   -> Sri Lanka W U19, India W U19
/// Scans the title for KNOWN nation names only (never invents a team), in order
/// of appearance, and applies a Women / U19 suffix when the title indicates it.
/// Returns up to two `(name, code)` pairs; empty when no known nation is found.
List<({String name, String code})> seriesTeamsFromTitle(String title) {
  final raw = title.trim();
  if (raw.isEmpty) return const [];
  final lower = raw.toLowerCase();
  // Shared variant suffix derived once from the whole title (tour series almost
  // always share it across both sides, e.g. both Women, both U19).
  final isWomen = RegExp(r"\bwomen'?s?\b").hasMatch(lower);
  final isU19 = RegExp(r'\bu-?19\b').hasMatch(lower);
  String suffixName = '';
  String suffixCode = '';
  if (isWomen) {
    suffixName += ' Women';
    suffixCode += ' W';
  }
  if (isU19) {
    suffixName += ' U19';
    suffixCode += ' U19';
  }

  // Longest names first so "united states of america" wins over "united states".
  final names = _kNameToCode.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  final hits = <({int at, String base})>[];
  final usedCodes = <String>{};
  for (final n in names) {
    final code = _kNameToCode[n]!;
    if (usedCodes.contains(code)) continue;
    final at = lower.indexOf(RegExp(r'\b' + RegExp.escape(n) + r'\b'));
    if (at >= 0) {
      hits.add((at: at, base: n));
      usedCodes.add(code);
    }
  }
  hits.sort((a, b) => a.at.compareTo(b.at));
  return [
    for (final h in hits.take(2))
      () {
        // Title-case the matched nation for display, then append the suffix.
        final display = h.base
            .split(' ')
            .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
            .join(' ');
        return (
          name: '$display$suffixName'.trim(),
          code: '${_kNameToCode[h.base]}$suffixCode'.trim(),
        );
      }(),
  ];
}

/// Collapses verbose women's-team names so compact cards stay tidy:
/// "India Women" -> "India W", "New Zealand Women" -> "New Zealand W".
String compactTeamName(String name) {
  final s = name.trim();
  if (s.isEmpty) return s;
  final lower = s.toLowerCase();
  if (lower.endsWith(' women')) {
    return '${s.substring(0, s.length - ' women'.length).trim()} W';
  }
  if (lower.endsWith(' womens') || lower.endsWith(" women's")) {
    final cut = lower.endsWith(" women's") ? " women's" : ' womens';
    return '${s.substring(0, s.length - cut.length).trim()} W';
  }
  return s;
}

/// Common long city/region prefixes in franchise names, mapped to their broadcast
/// short form so a long club name fits without an ugly mid-word ellipsis.
const Map<String, String> _kCityPrefixShort = {
  'los angeles': 'LA',
  'san francisco': 'SF',
  'new york': 'NY',
  'washington': 'DC',
  'seattle': 'Seattle',
  'texas': 'Texas',
  'sunrisers': 'Sunrisers',
};

/// Shortens a long club/franchise name so it fits a compact card line instead of
/// truncating to "Los Angeles Kni…". Abbreviates a known long city prefix
/// ("Los Angeles Knight Riders" -> "LA Knight Riders"); if still too long the
/// trailing words collapse to initials ("LA KR"). Names already short, country
/// names and unknown long names are returned unchanged (the caller may ellipsize).
String shortenTeamName(String name, {int maxLen = 16}) {
  final n = name.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (n.length <= maxLen) return n;
  final lower = n.toLowerCase();
  for (final entry in _kCityPrefixShort.entries) {
    if (lower.startsWith('${entry.key} ')) {
      final rest = n.substring(entry.key.length).trim();
      final candidate = '${entry.value} $rest';
      if (candidate.length <= maxLen) return candidate;
      final initials = rest
          .split(' ')
          .where((w) => w.isNotEmpty)
          .map((w) => w[0].toUpperCase())
          .join();
      return '${entry.value} $initials';
    }
  }
  return n;
}

/// Known long competition titles mapped to compact forms so list/hero cards
/// stay one line. Falls back to generic ICC-prefix shorteners.
String shortSeriesTitle(String title) {
  final t = title.trim();
  if (t.isEmpty) return t;
  final lower = t.toLowerCase();
  const exact = <String, String>{
    "icc women's t20 world cup 2026": "Women's T20 WC 2026",
    'icc cricket world cup league two 2023-27': 'CWC League Two',
    'madhya pradesh premier league 2026': 'MP Premier League 2026',
  };
  final hit = exact[lower];
  if (hit != null) return hit;
  var s = t;
  s = s.replaceAll(
      RegExp(r"^ICC\s+Women'?s\s+", caseSensitive: false), "Women's ");
  s = s.replaceAll(RegExp(r'^ICC\s+', caseSensitive: false), '');
  return s;
}

/// Shortens a verbose match status/result so it fits a pill or the minimized
/// score bar, using team codes and trimming filler:
///   "West Indies need 126 runs in 87 balls"        -> "WI need 126 in 87"
///   "India Women opt to bat"                         -> "IND W opt to bat"
///   "Match tied (Sri Lanka A won the Super Over)"    -> "Match tied • SL A won SO"
///   "Sri Lanka A won by 5 wickets"                   -> "SL A won by 5 wickets"
///
/// [keepUnits] keeps the natural cricket wording ("126 runs in 87 balls")
/// instead of the compact "126 in 87" — use it in full-width status notes that
/// have room; leave it false for tight pills / the minimized score bar.
String shortMatchStatus(String status, CricketMatch match,
    {bool keepUnits = false}) {
  var s = status.trim();
  if (s.isEmpty) return s;

  // Replace full team names with their (variant-aware) codes.
  final replacements = <String, String>{};
  void addPair(String name, String short) {
    final n = name.trim();
    final code = teamCodeOf(short, name);
    if (n.isNotEmpty && code.isNotEmpty) replacements[n] = code;
    final wName = compactTeamName(n); // "India W" form too.
    if (wName.isNotEmpty && wName != n) replacements[wName] = code;
  }

  addPair(match.teamA, match.teamAShort);
  addPair(match.teamB, match.teamBShort);
  // Longest names first so "New Zealand Women" wins over "New Zealand".
  final names = replacements.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  for (final n in names) {
    s = s.replaceAll(
        RegExp(RegExp.escape(n), caseSensitive: false), replacements[n]!);
  }

  // Super Over -> SO.
  s = s.replaceAll(
      RegExp(r'\bthe\s+super\s+over\b', caseSensitive: false), 'SO');
  s = s.replaceAll(RegExp(r'\bsuper\s+over\b', caseSensitive: false), 'SO');

  // "tied (X)" -> "tied • X" (drops the closing paren too).
  s = s.replaceAllMapped(
      RegExp(r'tied\s*\(([^)]*)\)', caseSensitive: false),
      (m) => 'tied • ${m.group(1)!.trim()}');

  // Drop "runs"/"balls" filler: "126 runs in 87 balls" -> "126 in 87".
  // Skipped when [keepUnits] is set so full-width notes read naturally.
  if (!keepUnits) {
    s = s.replaceAll(RegExp(r'\bruns\b', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'\bballs?\b', caseSensitive: false), '');
  }
  s = s.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  // Tidy any stray " )" / " •" leftovers.
  s = s.replaceAll(RegExp(r'\s+\)'), ')').replaceAll(RegExp(r'•\s*$'), '').trim();
  // Finally, un-cram any compressed team code the feed embedded directly
  // ("RSAW won" -> "RSA W won").
  s = _spaceTeamCodes(s, match);
  return s;
}

/// Replaces a cramped team code the feed embeds in status/result strings
/// (`RSAW`, `INDA`, `NZW`) with its spaced, professional form (`RSA W`,
/// `IND A`, `NZ W`). Only codes that map to one of THIS match's teams are
/// touched, matched whole-word and case-insensitively, so full result
/// sentences ("South Africa Women won by 6 wickets") pass through unchanged.
String _spaceTeamCodes(String input, CricketMatch match) {
  var s = input;
  for (final team in <(String, String)>[
    (match.teamAShort, match.teamA),
    (match.teamBShort, match.teamB),
  ]) {
    final pro = teamCodeOf(team.$1, team.$2); // e.g. "RSA W"
    if (!pro.contains(' ')) continue; // only variant codes can be cramped
    final cramped = pro.replaceAll(' ', ''); // "RSAW"
    if (cramped.length < 3 || cramped == pro) continue;
    s = s.replaceAllMapped(
      RegExp(r'\b' + RegExp.escape(cramped) + r'\b', caseSensitive: false),
      (_) => pro,
    );
  }
  return s;
}

/// Professional result text for a finished match. Keeps the provider's full
/// result when it gives one ("South Africa Women won by 6 wickets") and only
/// un-crams an embedded team code ("RSAW won" -> "RSA W won"). NEVER invents a
/// winning margin the feed didn't supply.
String formatResultText(String result, CricketMatch match) =>
    _spaceTeamCodes(result.trim(), match);

/// Match format with broadcast casing: `odi` -> `ODI`, `t20i` -> `T20I`,
/// `test` -> `Test`. Unknown short tokens are upper-cased; longer labels are
/// left as-is.
String formatMatchFormat(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return s;
  const map = <String, String>{
    'odi': 'ODI',
    'odis': 'ODI',
    't20': 'T20',
    't20i': 'T20I',
    't10': 'T10',
    'test': 'Test',
    'tests': 'Test',
    'first class': 'First Class',
    'first-class': 'First Class',
    'list a': 'List A',
    'the hundred': 'The Hundred',
    '100 ball': 'The Hundred',
    't20 blast': 'T20 Blast',
  };
  final hit = map[s.toLowerCase()];
  if (hit != null) return hit;
  // Short, code-like token (e.g. "odi", "t20i") -> upper-case.
  if (s.length <= 4 && !s.contains(' ')) return s.toUpperCase();
  return s;
}

/// Fixes the common "-ing" toss grammar bug from the feed:
///   "chose to bowling" -> "chose to bowl", "opt to batting" -> "opt to bat".
String fixTossGrammar(String raw) {
  var s = raw;
  s = s.replaceAll(RegExp(r'\bto\s+bowling\b', caseSensitive: false), 'to bowl');
  s = s.replaceAll(RegExp(r'\bto\s+batting\b', caseSensitive: false), 'to bat');
  s = s.replaceAll(
      RegExp(r'\bto\s+fielding\b', caseSensitive: false), 'to field');
  return s;
}

/// Shortens a venue for tight metadata rows: keeps the city/last segment when a
/// long "Stadium, City" string would otherwise be trimmed mid-word. Returns ''
/// for placeholder venues so callers can hide the row instead of showing junk.
String shortVenue(String venue) {
  var v = venue.trim();
  if (v.isEmpty || isPlaceholderText(v)) return '';
  // Drop a trailing ", City" / ", City, Country" so the distinctive stadium
  // name leads and never gets ellipsized mid-word
  // ("Emirates Old Trafford, Manchester" -> "Emirates Old Trafford").
  final comma = v.indexOf(',');
  if (comma > 0) v = v.substring(0, comma).trim();
  // When the remaining name is still long, strip a generic trailing descriptor
  // so the recognisable part shows ("Rangiri Dambulla International Stadium" ->
  // "Rangiri Dambulla"). Short names ("Grand Prairie Stadium") are kept intact.
  if (v.length > 22) {
    final stripped = v.replaceFirst(
      RegExp(r'\s+International(\s+Cricket)?\s+(Stadium|Ground)$',
          caseSensitive: false),
      '',
    );
    if (stripped.trim().length >= 4) v = stripped.trim();
  }
  return v;
}

/// Compacts a long player name so it doesn't ellipsize mid-surname in tight
/// rows: "Niroshan Dickwella" (when over [maxLen]) -> "N. Dickwella". Short
/// names and single-word names pass through unchanged.
String compactPlayerName(String name, {int maxLen = 14}) {
  final n = name.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (n.isEmpty || n.length <= maxLen) return n;
  final parts = n.split(' ');
  if (parts.length < 2) return n;
  final initial = parts.first.isNotEmpty ? parts.first[0].toUpperCase() : '';
  final last = parts.last;
  return '$initial. $last';
}

/// True when a string is a raw epoch/timestamp-like number (≥ 6 consecutive
/// digits, e.g. `1782073800000`) that must NEVER be shown to the user as
/// score/status/time text. Used to guard fallbacks that would otherwise leak a
/// provider's raw `start_time` millis into a card.
bool looksLikeRawTimestamp(String? value) {
  final v = (value ?? '').trim();
  return v.length >= 6 && RegExp(r'^\d+$').hasMatch(v);
}

/// True for placeholder/junk metadata strings that should never be shown
/// (`TBD`, `Unknown`, `null`, empty).
bool isPlaceholderText(String? value) {
  final v = (value ?? '').trim().toLowerCase();
  return v.isEmpty ||
      v == 'tbd' ||
      v == 'tbc' ||
      v == 'venue tbd' ||
      v == 'venue tbc' ||
      v == 'unknown' ||
      v == 'null';
}
