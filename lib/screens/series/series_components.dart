import 'package:flutter/material.dart';

import 'package:cricpro_flutter/app_theme.dart';
import 'package:cricpro_flutter/api_models.dart';
import 'package:cricpro_flutter/components.dart';
import 'package:cricpro_flutter/screens/series/series_premium.dart';
import 'package:cricpro_flutter/utils/team_format.dart';

/// Shared premium building blocks for the Series module (list + details).
/// All widgets follow the CricPro dark-navy/cyan glassmorphism design.

// ---------------------------------------------------------------------------
// Series view model — derives premium display fields from API data.
// ---------------------------------------------------------------------------

/// [unknown] = the series has no reliable start/end date AND no definitive
/// provider status, so it cannot be honestly placed in Ongoing/Upcoming/
/// Completed. Such series surface ONLY under the "All" filter (filterSeries
/// never matches them to a specific status facet) — this is what keeps undated
/// editions out of the Upcoming filter.
enum SeriesStatus { ongoing, upcoming, completed, unknown }

enum SeriesCategory { international, league, domestic, women }

/// A normalized, display-ready series model assembled from the lightweight
/// `/series` list entries and (when available) the richer match data.
class SeriesView {
  const SeriesView({
    required this.id,
    required this.name,
    required this.status,
    required this.category,
    this.startDate,
    this.endDate,
    this.formats = const [],
    this.formatLabel = '',
    this.matchCount,
    this.host,
    this.teams = const [],
    this.liveCount = 0,
  });

  final String id;
  final String name;
  final SeriesStatus status;
  final SeriesCategory category;
  final DateTime? startDate;
  final DateTime? endDate;
  final List<String> formats;

  /// Pre-formatted, count-aware label from the backend, e.g. "1 Test • 3 ODIs
  /// • 3 T20Is". Preferred over [formats] when present.
  final String formatLabel;
  final int? matchCount;
  final String? host;
  final List<SeriesTeamRef> teams;
  final int liveCount;

  String get cleanName => cleanSeriesText(name);

  /// Card-title variant of [cleanName] with a redundant trailing ", YYYY"
  /// removed so long tour names never ellipsize mid-word (the year still shows
  /// in the date-range meta). See [compactSeriesTitle].
  String get compactName => compactSeriesTitle(cleanName);

  String get statusLabel => switch (status) {
        SeriesStatus.ongoing => 'Ongoing',
        SeriesStatus.upcoming => 'Upcoming',
        SeriesStatus.completed => 'Completed',
        SeriesStatus.unknown => 'TBD',
      };

  String get categoryLabel => switch (category) {
        SeriesCategory.international => 'International',
        SeriesCategory.league => 'League',
        SeriesCategory.domestic => 'Domestic',
        SeriesCategory.women => 'Women',
      };

  String get dateRangeLabel {
    final s = startDate;
    final e = endDate;
    if (s == null && e == null) return '';
    if (s != null && e != null) {
      return '${_shortDate(s)} – ${_shortDate(e)}';
    }
    return _shortDate(s ?? e!);
  }

  /// Compact, non-truncating range like "9 – 20 Jun 2026", "20 Jun – 31 Jul
  /// 2025" or "28 Dec 2025 – 4 Jan 2026". Used on cards/carousels where space
  /// is tight so the date never gets cut off mid-string.
  String get shortDateRange {
    const m = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec' //
    ];
    final s = startDate;
    final e = endDate;
    if (s == null && e == null) return '';
    if (s != null && e != null) {
      if (s.year == e.year && s.month == e.month) {
        return '${s.day} – ${e.day} ${m[e.month - 1]} ${e.year}';
      }
      if (s.year == e.year) {
        return '${s.day} ${m[s.month - 1]} – ${e.day} ${m[e.month - 1]} ${e.year}';
      }
      return '${s.day} ${m[s.month - 1]} ${s.year} – '
          '${e.day} ${m[e.month - 1]} ${e.year}';
    }
    final d = s ?? e!;
    return '${d.day} ${m[d.month - 1]} ${d.year}';
  }

  /// "3 ODIs • 3 T20Is" style chip text. Prefers the backend's count-aware
  /// label, falling back to the format tokens parsed from the name.
  String get formatSummary {
    if (formatLabel.contains(RegExp(r'\d'))) return formatLabel;
    return formats.isEmpty ? '' : formats.join(' • ');
  }

  factory SeriesView.fromApi(ApiSeries series) {
    final start = _parseDate(series.startDate);
    final end = _parseDate(series.endDate);
    final cleanName = cleanSeriesText(series.name);
    // Prefer the provider's teams array; when it carries fewer than two teams
    // (common for tour series that omit it), derive the participating nations
    // from the series title so the card shows real teams instead of TBD vs TBD.
    var teams = _teamsFromApi(series.teams);
    if (teams.length < 2) {
      teams = _mergeTeams(teams, _teamsFromTitle(cleanName));
    }
    return SeriesView(
      id: series.id,
      name: cleanName,
      status: classifySeriesStatus(series.status, start, end),
      category: seriesCategoryOf(series.name, series.format,
          backendCategory: series.category),
      startDate: start,
      endDate: end,
      formats: _formatsFromText('${series.format ?? ''} ${series.name}'),
      formatLabel: (series.format ?? '').trim(),
      matchCount: series.matchCount,
      // Host: prefer the backend country/host; otherwise derive it from a
      // bilateral "X tour of Y" title (the host is Y). Tournaments/leagues that
      // don't yield a host stay null so the card hides the location item.
      host: ((series.country ?? '').trim().isNotEmpty)
          ? series.country!.trim()
          : _seriesHostFromTitle(cleanName),
      teams: teams,
    );
  }

  /// True for bilateral series where we have two real participating sides; used
  /// to decide between a two-team layout and a tournament/trophy layout so the
  /// card never reads as a single fixture with TBD placeholders.
  bool get isBilateral => teams.length >= 2;

  /// Real participating-team count derived from the provider's teams array
  /// (only padded to two from the title when the provider gives fewer). Used
  /// by multi-team tournament/league cards for the "N Teams" metadata and the
  /// "+N" logo-strip overflow. Never a fabricated value.
  int get teamCount => teams.length;
}

/// Filters a series list by category and status. A null facet means "All".
/// Final list = category ∩ status, mirroring the Cricbuzz Series tabs combined
/// with the app's Ongoing/Upcoming/Completed segments. Pure + testable.
List<SeriesView> filterSeries(
  List<SeriesView> all,
  SeriesCategory? category,
  SeriesStatus? status,
) {
  return all
      .where((s) => category == null || s.category == category)
      .where((s) => status == null || s.status == status)
      .toList(growable: false);
}

/// Sorts a series list into the canonical display order: Ongoing first, then
/// Upcoming, then Completed (`unknown`/TBD tails last). Within each section:
///   • Ongoing — series with live matches ([SeriesView.liveCount] > 0) first,
///     then the rest by start date descending (most-recently-started first).
///   • Upcoming — by start date ascending (soonest first).
///   • Completed — by end date descending (most-recently-finished first).
/// Undated series keep their relative input order within their section. Pure +
/// testable; does not mutate the input.
List<SeriesView> sortSeriesByStatus(List<SeriesView> all) {
  int sectionRank(SeriesStatus s) => switch (s) {
        SeriesStatus.ongoing => 0,
        SeriesStatus.upcoming => 1,
        SeriesStatus.completed => 2,
        SeriesStatus.unknown => 3,
      };
  final sorted = [...all]..sort((a, b) {
      final sa = sectionRank(a.status);
      final sb = sectionRank(b.status);
      if (sa != sb) return sa.compareTo(sb);
      switch (a.status) {
        case SeriesStatus.ongoing:
          // Live matches first (descending liveCount), then start date desc.
          final liveCmp = b.liveCount.compareTo(a.liveCount);
          if (liveCmp != 0) return liveCmp;
          return _nullLastDesc(a.startDate, b.startDate);
        case SeriesStatus.upcoming:
          return _nullLastAsc(a.startDate, b.startDate);
        case SeriesStatus.completed:
          return _nullLastDesc(a.endDate, b.endDate);
        case SeriesStatus.unknown:
          return 0;
      }
    });
  return sorted;
}

/// Ascending comparator that keeps null/undated values AFTER dated ones (so an
/// undated upcoming series never jumps ahead of a dated one).
int _nullLastAsc(DateTime? a, DateTime? b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return a.compareTo(b);
}

/// Descending comparator (most-recent first) that keeps null values last.
int _nullLastDesc(DateTime? a, DateTime? b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return b.compareTo(a);
}

class SeriesTeamRef {
  const SeriesTeamRef({
    required this.name,
    required this.shortName,
    this.logoUrl,
  });

  final String name;
  final String shortName;
  final String? logoUrl;
}

/// Admin-managed Series hero banner, parsed from `GET /app/series-hero`.
///
/// Every field is optional so a partially-configured hero still renders
/// cleanly. [hasContent] is used by the Series screen to decide whether to use
/// the admin hero or fall back to a hero derived from the live series list.
class SeriesHeroData {
  const SeriesHeroData({
    this.seriesId = '',
    this.title = '',
    this.subtitle = '',
    this.formatText = '',
    this.dateRange = '',
    this.backgroundImage,
    this.ctaLabel = 'View Series',
    this.teamA,
    this.teamB,
  });

  final String seriesId;
  final String title;
  final String subtitle;
  final String formatText;
  final String dateRange;
  final String? backgroundImage;
  final String ctaLabel;
  final SeriesTeamRef? teamA;
  final SeriesTeamRef? teamB;

  bool get hasContent => title.trim().isNotEmpty || (teamA != null && teamB != null);

  static SeriesTeamRef? _team(dynamic value) {
    final map = apiMap(value);
    final name = apiString(map['name'] ?? map['teamName'] ?? map['team_name']);
    final short = apiString(
        map['shortName'] ?? map['short_name'] ?? map['teamShortName']);
    final logo = apiString(map['logoUrl'] ?? map['logo_url'] ?? map['logo']);
    if (name.isEmpty && short.isEmpty && logo.isEmpty) return null;
    return SeriesTeamRef(
      name: name.isEmpty ? short : name,
      shortName: short.isEmpty ? name : short,
      logoUrl: logo.isEmpty ? null : logo,
    );
  }

  static SeriesHeroData? fromJson(dynamic value) {
    if (value == null) return null;
    final map = apiMap(value);
    if (map.isEmpty) return null;
    final hero = SeriesHeroData(
      seriesId: apiString(map['seriesId'] ?? map['series_id']),
      title: cleanSeriesText(apiString(map['title'])),
      subtitle: apiString(map['subtitle']),
      formatText: apiString(map['formatText'] ?? map['format_text']),
      dateRange: apiString(map['dateRange'] ?? map['date_range']),
      backgroundImage: apiString(map['backgroundImage'] ?? map['image_url'])
              .isEmpty
          ? null
          : apiString(map['backgroundImage'] ?? map['image_url']),
      ctaLabel: apiString(map['ctaLabel'] ?? map['cta_label'], 'View Series'),
      teamA: _team(map['teamA'] ?? map['team_a']),
      teamB: _team(map['teamB'] ?? map['team_b']),
    );
    return hero.hasContent ? hero : null;
  }
}

String cleanSeriesText(String value) {
  return value
      .replaceAll(r'\\', '')
      .replaceAll(r'\', '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _shortDate(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}

DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  final text = value.toString().trim();
  if (text.isEmpty) return null;
  final parsed = DateTime.tryParse(text);
  if (parsed != null) return parsed;
  final epoch = int.tryParse(text);
  if (epoch != null && epoch > 1000000000000) {
    return DateTime.fromMillisecondsSinceEpoch(epoch, isUtc: true).toLocal();
  }
  return null;
}

/// Strips a [DateTime] to its LOCAL calendar day (midnight, no time-of-day) so
/// status is decided by DATE, not by the hour. Without this a series starting
/// later *today* reads as Upcoming, and an edition that ended earlier today
/// reads as still-ongoing — both wrong on the Series filters.
DateTime _localDay(DateTime d) {
  final l = d.toLocal();
  return DateTime(l.year, l.month, l.day);
}

/// Central, testable series-status classifier. Compares at LOCAL-DATE
/// granularity (time-of-day ignored). Rules, in strict priority:
///   1. Ongoing  — a genuine live match ([liveCount] > 0).
///   2. Completed — real [end] date's day is BEFORE today (a past end date
///      ALWAYS wins, even over a stale provider "ongoing"/"upcoming" string).
///   3. Upcoming — real [start] date's day is AFTER today.
///   4. Ongoing  — today falls within [start]..[end] inclusive, or only a start
///      day is known and it is today/past.
///   5. No usable dates → provider text (done / live / upcoming).
///   6. No usable dates AND no DEFINITIVE provider status (live/completed) →
///      Unknown. This is the Afghanistan/IPL case: an edition the upcoming-
///      biased backend feeds dropped. A bare "upcoming" string with NO dates is
///      treated as Unknown (NOT Upcoming), so undated series can never pollute
///      the Upcoming filter — they surface only under "All". Logged in debug.
/// [now] is injectable for tests.
SeriesStatus classifySeriesStatus(
  String? raw,
  DateTime? start,
  DateTime? end, {
  int liveCount = 0,
  DateTime? now,
}) {
  final today = _localDay(now ?? DateTime.now());
  final startDay = start == null ? null : _localDay(start);
  final endDay = end == null ? null : _localDay(end);

  final low = (raw ?? '').toLowerCase();
  final saysLive = low.contains('live') ||
      low.contains('ongoing') ||
      low.contains('progress');
  final saysDone = low.contains('complete') ||
      low.contains('finish') ||
      low.contains('result') ||
      low.contains('concluded');

  // 1. A genuinely live match (real-time signal) always wins.
  if (liveCount > 0) return SeriesStatus.ongoing;

  // 2-4. Real series dates are authoritative and beat any stale provider text.
  if (endDay != null && endDay.isBefore(today)) return SeriesStatus.completed;
  if (startDay != null && startDay.isAfter(today)) return SeriesStatus.upcoming;
  if (startDay != null &&
      endDay != null &&
      !startDay.isAfter(today) &&
      !endDay.isBefore(today)) {
    return SeriesStatus.ongoing;
  }
  // Only one real date known but it doesn't put the series in the past/future:
  // a started-and-not-ended series is ongoing.
  if (startDay != null && !startDay.isAfter(today)) return SeriesStatus.ongoing;
  if (endDay != null && !endDay.isBefore(today) && startDay == null) {
    return SeriesStatus.ongoing;
  }

  // 5. No usable dates — only a DEFINITIVE provider signal may classify it.
  //    (A "upcoming"/"scheduled" string is NOT definitive without a real start
  //    date, so it deliberately falls through to Unknown below.)
  if (saysDone) return SeriesStatus.completed;
  if (saysLive) return SeriesStatus.ongoing;

  // 6. No dates and no definitive status → Unknown (All-only; never Upcoming).
  assert(() {
    // ignore: avoid_print
    print('[series] classifySeriesStatus: no dates / no definitive status for '
        '"$raw" → Unknown (shown only under All).');
    return true;
  }());
  return SeriesStatus.unknown;
}

/// Resolves a series' Cricbuzz-style category. Priority:
///   1. Women override — a women's title/format always belongs in the Women tab
///      (Cricbuzz's Women tab cross-cuts international/league/domestic).
///   2. Authoritative [backendCategory] from the API (the category feed the
///      series was listed under) when recognized.
///   3. Name/format heuristic fallback.
/// Testable; used by [SeriesView.fromApi].
SeriesCategory seriesCategoryOf(String name, String? format,
    {String? backendCategory}) {
  final text = '${format ?? ''} $name'.toLowerCase();
  final womenTitle = text.contains('women') ||
      RegExp(r'\bwomen').hasMatch(text) ||
      text.contains(' w ') ||
      text.endsWith(' w') ||
      text.contains('-w ');

  // 1. Women override wins regardless of the backend bucket.
  if (womenTitle) return SeriesCategory.women;

  // 2. Trust the backend category feed when it gives a clear bucket.
  final back = (backendCategory ?? '').toLowerCase();
  if (back.isNotEmpty) {
    if (back.contains('women')) return SeriesCategory.women;
    if (back.contains('league') || back.contains('t20 league')) {
      return SeriesCategory.league;
    }
    if (back.contains('domestic')) return SeriesCategory.domestic;
    if (back.contains('international')) return SeriesCategory.international;
  }

  // 3. Heuristic fallback from the name/format.
  if (text.contains('premier league') ||
      text.contains('ipl') ||
      text.contains('psl') ||
      text.contains('bbl') ||
      text.contains('cpl') ||
      text.contains('mlc') ||
      text.contains('major league cricket') ||
      text.contains('the hundred') ||
      text.contains('super smash') ||
      text.contains('blast') ||
      text.contains(' t10') ||
      text.contains('league')) {
    return SeriesCategory.league;
  }
  if (text.contains('ranji') ||
      text.contains('county') ||
      text.contains('sheffield shield') ||
      text.contains('plunket shield') ||
      text.contains('vijay hazare') ||
      text.contains('syed mushtaq') ||
      text.contains('domestic') ||
      text.contains('first-class') ||
      text.contains('first class')) {
    return SeriesCategory.domestic;
  }
  // Tours, bilateral series, World Cups, Champions Trophy, Asia Cup, etc.
  return SeriesCategory.international;
}

/// For a bilateral "X tour of Y" title, the HOST nation is Y (the second team
/// in title order). Returns null for non-tour titles (tournaments / leagues /
/// World Cups) where a host can't be reliably derived from the name — the card
/// then hides the location item rather than showing a guessed value.
String? _seriesHostFromTitle(String title) {
  if (!RegExp(r'\btour of\b', caseSensitive: false).hasMatch(title)) {
    return null;
  }
  final teams = seriesTeamsFromTitle(title);
  if (teams.length < 2) return null;
  return teams[1].name;
}

List<SeriesTeamRef> _teamsFromApi(List<dynamic> raw) {
  final teams = <SeriesTeamRef>[];
  for (final entry in raw) {
    final map = apiMap(entry);
    final name = apiString(map['name'] ?? map['teamName'] ?? map['team_name']);
    if (name.isEmpty) continue;
    final shortName = apiString(
        map['shortName'] ?? map['short_name'] ?? map['teamShortName']);
    // Resolve the logo through the SAME admin→local→api→initials order the rest
    // of the app uses (resolveTeamLogoUrl), instead of the raw provider URL — so
    // an admin-configured logo wins on Series cards too.
    final resolved = resolveTeamLogoUrl(map);
    teams.add(SeriesTeamRef(
      name: name,
      shortName: shortName.isEmpty ? name : shortName,
      logoUrl: resolved,
    ));
  }
  return teams;
}

/// Builds team refs from nations parsed out of the series TITLE (used only when
/// the provider omits/doesn't fully populate the teams array). Logos still go
/// through [resolveTeamLogoUrl] so admin logos win and known nations fall back
/// to their local flag via TeamLogoWidget.
List<SeriesTeamRef> _teamsFromTitle(String title) {
  return [
    for (final t in seriesTeamsFromTitle(title))
      SeriesTeamRef(
        name: t.name,
        shortName: t.code,
        logoUrl: resolveTeamLogoUrl(<String, dynamic>{
          'name': t.name,
          'teamName': t.name,
          'shortName': t.code,
        }),
      ),
  ];
}

/// Keeps provider teams first, then fills up to two slots from the title-derived
/// teams (skipping any whose code already appears), so we never duplicate a side
/// or overwrite richer provider data.
List<SeriesTeamRef> _mergeTeams(
    List<SeriesTeamRef> primary, List<SeriesTeamRef> extra) {
  final out = [...primary];
  final seen = primary
      .map((t) => t.shortName.toUpperCase())
      .where((s) => s.isNotEmpty)
      .toSet();
  for (final t in extra) {
    if (out.length >= 2) break;
    if (seen.add(t.shortName.toUpperCase())) out.add(t);
  }
  return out;
}

List<String> _formatsFromText(String raw) {
  final text = raw.toUpperCase();
  final formats = <String>[];
  if (text.contains('TEST')) formats.add('Test');
  if (text.contains('ODI')) formats.add('ODI');
  if (text.contains('T20')) formats.add(text.contains('T20I') ? 'T20I' : 'T20');
  return formats;
}

/// Section header used on the Series landing ("Ongoing Series" + "View All").
class SeriesSectionHeader extends StatelessWidget {
  const SeriesSectionHeader({super.key, required this.title, this.onViewAll});

  final String title;
  final VoidCallback? onViewAll;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: TextStyle(
            color: c.text,
            fontWeight: FontWeight.w900,
            fontSize: 18,
            letterSpacing: .2,
          ),
        ),
        if (onViewAll != null)
          TapScale(
            onTap: onViewAll!,
            borderRadius: 8,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(
                'View All',
                style: TextStyle(
                  color: c.cyan,
                  fontWeight: FontWeight.w800,
                  fontSize: 13.5,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Premium pill row (category + status filters)
// ---------------------------------------------------------------------------

class SeriesFilterPills extends StatelessWidget {
  const SeriesFilterPills({
    super.key,
    required this.items,
    required this.selected,
    required this.onChanged,
  });

  final List<String> items;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final isSel = i == selected;
          return TapScale(
            onTap: () => onChanged(i),
            borderRadius: 24,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              padding: const EdgeInsets.symmetric(horizontal: 20),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: isSel ? c.primaryGradient : null,
                color: isSel ? null : c.subtleSurface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: isSel ? c.cyan.withValues(alpha: .7) : c.border,
                ),
                boxShadow: isSel && c.isDark
                    ? [
                        BoxShadow(
                          color: c.cyan.withValues(alpha: .25),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        )
                      ]
                    : null,
              ),
              child: Text(
                items[i],
                style: TextStyle(
                  color: isSel ? Colors.white : c.muted,
                  fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
                  fontSize: 14.5,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Premium Series card (used in the Series list)
// ---------------------------------------------------------------------------

/// Premium vertical Series card — matches the Matches-screen card visual
/// language (stadium texture, cyan border + top glow, glowing VS centerpiece)
/// in a stacked layout: status badge + date on top, centered title + format
/// summary, the two teams flanking a glowing VS badge, then a full-width
/// "View Series" action.
class SeriesListCard extends StatelessWidget {
  const SeriesListCard({super.key, required this.series, required this.onTap});

  final SeriesView series;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    // Status colour mapping per the target: Ongoing = green, Upcoming = cyan,
    // Completed = grey.
    final (statusColor, isLive) = switch (series.status) {
      SeriesStatus.ongoing => (c.success, true),
      SeriesStatus.upcoming => (c.cyan, false),
      SeriesStatus.completed => (c.muted, false),
      SeriesStatus.unknown => (c.muted, false),
    };
    final phone = context.w <= 430;
    final tight = context.w <= 360;
    final formatLine = series.formatSummary.isNotEmpty
        ? series.formatSummary
        : (series.matchCount != null && series.matchCount! > 0
            ? '${series.matchCount} Matches'
            : '');
    final dateLine = series.shortDateRange;
    // Host/location is optional: shown only when known and not a placeholder,
    // otherwise the metadata item is hidden (never a wrong/guessed value).
    final hostLine =
        (series.host != null && !isPlaceholderText(series.host)) ? series.host!.trim() : '';
    final left = series.teams.isNotEmpty ? series.teams.first : null;
    final right = series.teams.length > 1 ? series.teams[1] : null;
    final logoSize = tight ? 46.0 : (phone ? 52.0 : 56.0);
    final codeSize = tight ? 14.0 : 15.5;

    return TapScale(
      onTap: onTap,
      borderRadius: 22,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
              color: c.isDark ? c.cyan.withValues(alpha: .5) : c.border,
              width: 1.1),
          boxShadow: c.isDark
              ? [
                  BoxShadow(
                    color: c.cyan.withValues(alpha: .16),
                    blurRadius: 24,
                    spreadRadius: -6,
                  ),
                  ...c.heroShadow.skip(1),
                ]
              : c.heroShadow,
        ),
        child: Stack(
          children: [
            const Positioned.fill(
              child: StadiumImage(
                SAsset.listCardBg,
                hero: true,
                alignment: Alignment.center,
                remoteKey: 'series_list_card_bg',
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: c.heroOverlayColors,
                  ),
                ),
              ),
            ),
            // Subtle cyan bloom centred on the VS for extra premium depth.
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0, .35),
                      radius: .85,
                      colors: [
                        c.cyan.withValues(alpha: .1),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const TopCyanHighlight(),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Row 1 — status badge (left) and favourite star (right).
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SeriesStatusPill(
                        label: series.statusLabel,
                        color: statusColor,
                        live: isLive,
                        dense: true,
                      ),
                      const Spacer(),
                      _FavoriteStar(seriesId: series.id),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Centered series title.
                  Text(
                    series.cleanName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: c.text,
                      fontWeight: FontWeight.w900,
                      fontSize: tight ? 14.5 : 16,
                      height: 1.12,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Centre block represents the SERIES, not a single fixture:
                  // two real teams for bilateral series flanking a small, quiet
                  // VS badge (not the large glowing match-screen VS), or a
                  // tournament emblem otherwise — never a TBD-vs-TBD placeholder.
                  if (series.isBilateral)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: PremiumTeamColumn(
                            name: left!.name,
                            short: left.shortName,
                            logo: left.logoUrl,
                            logoSize: logoSize,
                            codeSize: codeSize,
                            accent: c.cyan,
                            showFullName: false,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Text(
                            'v',
                            style: TextStyle(
                              fontSize: tight ? 11 : 12,
                              color: Colors.white24,
                              fontWeight: FontWeight.w600,
                              letterSpacing: .5,
                            ),
                          ),
                        ),
                        Expanded(
                          child: PremiumTeamColumn(
                            name: right!.name,
                            short: right.shortName,
                            logo: right.logoUrl,
                            logoSize: logoSize,
                            codeSize: codeSize,
                            accent: c.warning,
                            showFullName: false,
                          ),
                        ),
                      ],
                    )
                  else
                    _SeriesEmblem(team: left, size: logoSize),
                  const SizedBox(height: 12),
                  // Compact metadata row: date range • format/count • host.
                  // Each item is hidden when its value is unavailable.
                  _SeriesMetaRow(
                    date: dateLine,
                    format: formatLine,
                    host: hostLine,
                  ),
                  const SizedBox(height: 12),
                  // Full-width "View Series" action.
                  _ViewSeriesButton(onTap: onTap),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Favourite star shown top-right of a Series card. Tapping toggles the
/// filled/outline state locally so the control is interactive and matches the
/// target design. It deliberately keeps its own lightweight state and does not
/// touch any other system (scores, logos, nav) — a future persistent
/// favourites store can be wired in here without changing the card layout.
class _FavoriteStar extends StatefulWidget {
  const _FavoriteStar({required this.seriesId});

  final String seriesId;

  @override
  State<_FavoriteStar> createState() => _FavoriteStarState();
}

class _FavoriteStarState extends State<_FavoriteStar> {
  bool _on = false;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return GestureDetector(
      onTap: () => setState(() => _on = !_on),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.only(left: 8),
        child: Icon(
          _on ? Icons.star_rounded : Icons.star_border_rounded,
          size: 24,
          color: _on ? c.warning : c.onImageText.withValues(alpha: .7),
        ),
      ),
    );
  }
}

/// Compact 3-item metadata row under the teams: calendar/date range •
/// cricket-ball/format • location-pin/host. Items with an empty value are
/// dropped entirely (no wrong/placeholder data), and thin dividers separate
/// only the items that actually render. Each label is flexible + ellipsised so
/// the row never overflows on small (360dp) devices.
class _SeriesMetaRow extends StatelessWidget {
  const _SeriesMetaRow({
    required this.date,
    required this.format,
    required this.host,
  });

  final String date;
  final String format;
  final String host;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final tight = context.w <= 360;
    final items = <(IconData, String)>[
      if (date.isNotEmpty) (Icons.calendar_today_rounded, date),
      if (format.isNotEmpty) (Icons.sports_cricket, format),
      if (host.isNotEmpty) (Icons.location_on_rounded, host),
    ];
    if (items.isEmpty) return const SizedBox.shrink();

    final children = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      if (i != 0) {
        children.add(Container(
          width: 1,
          height: 14,
          margin: const EdgeInsets.symmetric(horizontal: 8),
          color: c.onImageText.withValues(alpha: .3),
        ));
      }
      children.add(Flexible(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(items[i].$1, size: tight ? 12 : 13, color: c.cyan),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                items[i].$2,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: c.onImageText,
                  fontWeight: FontWeight.w600,
                  fontSize: tight ? 10.5 : 11.5,
                ),
              ),
            ),
          ],
        ),
      ));
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: children,
    );
  }
}

/// Centerpiece for TOURNAMENT / LEAGUE series (World Cups, MLC, etc.) where two
/// opposing nations can't be derived. Shows a trophy emblem — and a single
/// representative team logo when one is available — instead of a misleading
/// TBD-vs-TBD fixture.
class _SeriesEmblem extends StatelessWidget {
  const _SeriesEmblem({required this.team, required this.size});

  final SeriesTeamRef? team;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final crest = Container(
      width: size + 6,
      height: size + 6,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: c.warning.withValues(alpha: .14),
        border: Border.all(color: c.warning.withValues(alpha: .55)),
        boxShadow: c.isDark
            ? [
                BoxShadow(
                  color: c.warning.withValues(alpha: .3),
                  blurRadius: 16,
                  spreadRadius: -3,
                ),
              ]
            : null,
      ),
      alignment: Alignment.center,
      child: Icon(Icons.emoji_events_rounded,
          color: c.warning, size: (size + 6) * .5),
    );
    final t = team;
    if (t == null) {
      return Center(child: crest);
    }
    // One representative side known: show it alongside the trophy.
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: PremiumTeamColumn(
            name: t.name,
            short: t.shortName,
            logo: t.logoUrl,
            logoSize: size,
            codeSize: 15,
            accent: c.cyan,
            showFullName: false,
          ),
        ),
        const SizedBox(width: 18),
        crest,
      ],
    );
  }
}

/// Full-width bordered "View Series" button — centered cyan label with a
/// trailing chevron, matching the target and the Matches action-button glass
/// language.
class _ViewSeriesButton extends StatelessWidget {
  const _ViewSeriesButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 40,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: c.cyan.withValues(alpha: .06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.cyan.withValues(alpha: .4)),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Text(
              'View Series',
              style: TextStyle(
                color: c.cyan,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
            Positioned(
              right: 12,
              child: Icon(Icons.chevron_right_rounded, color: c.cyan, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}

class _SeriesTeamLogo extends StatelessWidget {
  const _SeriesTeamLogo({required this.team, this.size = 32});

  final SeriesTeamRef team;
  final double size;

  @override
  Widget build(BuildContext context) {
    return TeamLogoWidget(
      logoUrl: team.logoUrl,
      teamName: team.name,
      abbreviation: team.shortName.isNotEmpty ? team.shortName : team.name,
      color: const Color(0xff22d3ee),
      size: size,
    );
  }
}

// ---------------------------------------------------------------------------
// Premium Series hero (shared across Series Detail tabs)
// ---------------------------------------------------------------------------

class SeriesHeroCard extends StatelessWidget {
  const SeriesHeroCard({
    super.key,
    required this.title,
    this.season,
    this.dateRange = '',
    this.formats = const [],
    this.status = '',
    this.left,
    this.right,
    this.tourLabel,
  });

  final String title;
  final String? season;
  final String dateRange;
  final List<String> formats;
  final String status;
  final SeriesTeamRef? left;
  final SeriesTeamRef? right;
  final String? tourLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final formatLine = formats.isEmpty ? '' : formats.join('  •  ');
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
            color: c.isDark ? c.cyan.withValues(alpha: .42) : c.border),
        boxShadow: c.isDark
            ? [
                BoxShadow(
                  color: c.cyan.withValues(alpha: .18),
                  blurRadius: 34,
                  spreadRadius: -7,
                ),
                ...c.heroShadow.skip(1),
              ]
            : c.heroShadow,
      ),
      child: Stack(
        children: [
          const Positioned.fill(
            child: StadiumImage(
              'assets/images/stadium_live.webp',
              hero: true,
              alignment: Alignment.center,
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: c.heroOverlayColors,
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: .78,
                  colors: [
                    c.cyan.withValues(alpha: .10),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
            child: Row(
              children: [
                _HeroTeamColumn(team: left),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 17,
                          height: 1.15,
                        ),
                      ),
                      if (season != null && season!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          season!,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: c.cyan,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                      ],
                      if (dateRange.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.calendar_today_rounded,
                                color: c.cyan, size: 13),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                dateRange,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: c.cyan,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (formatLine.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          formatLine,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .92),
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                _HeroTeamColumn(team: right),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroTeamColumn extends StatelessWidget {
  const _HeroTeamColumn({this.team});

  final SeriesTeamRef? team;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return SizedBox(
      width: 78,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (team != null)
            _SeriesTeamLogo(team: team!, size: 58)
          else
            TeamLogoWidget(
              logoUrl: null,
              teamName: 'TBD',
              abbreviation: 'TBD',
              color: c.cyan,
              size: 58,
            ),
          const SizedBox(height: 8),
          Text(
            (team?.shortName.isNotEmpty == true
                    ? team!.shortName
                    : team?.name ?? 'TBD')
                .toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Premium segmented tab bar (Overview / Matches / Squads / Stats)
// ---------------------------------------------------------------------------

class SeriesTabBar extends StatelessWidget {
  const SeriesTabBar({
    super.key,
    required this.items,
    required this.selected,
    required this.onChanged,
  });

  final List<String> items;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      height: 52,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: c.subtleSurface,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: c.border),
      ),
      child: LayoutBuilder(
        builder: (ctx, constraints) {
          final segWidth = constraints.maxWidth / items.length;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                left: segWidth * selected.clamp(0, items.length - 1),
                top: 0,
                bottom: 0,
                width: segWidth,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: c.primaryGradient,
                    borderRadius: BorderRadius.circular(26),
                    boxShadow: c.isDark
                        ? [
                            BoxShadow(
                              color: c.cyan.withValues(alpha: .28),
                              blurRadius: 16,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  ),
                ),
              ),
              Row(
                children: [
                  for (var i = 0; i < items.length; i++)
                    Expanded(
                      child: TapScale(
                        onTap: () => onChanged(i),
                        borderRadius: 26,
                        child: Center(
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 220),
                            style: TextStyle(
                              color: i == selected ? Colors.white : c.muted,
                              fontWeight: i == selected
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              fontSize: 14,
                            ),
                            child: Text(items[i]),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Player avatar (circular face photo with initials fallback)
// ---------------------------------------------------------------------------

class SeriesPlayerAvatar extends StatelessWidget {
  const SeriesPlayerAvatar({
    super.key,
    required this.name,
    this.imageUrl,
    this.size = 64,
    this.borderColor,
  });

  final String name;
  final String? imageUrl;
  final double size;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    // Delegate to the shared PlayerAvatarWidget so player photos resolve
    // identically (admin → provider → initials, never a broken icon)
    // everywhere they appear.
    return PlayerAvatarWidget(
      name: name,
      imageUrl: imageUrl,
      size: size,
      borderColor: borderColor,
    );
  }
}

// ---------------------------------------------------------------------------
// Generic premium section card + state cards
// ---------------------------------------------------------------------------

class SeriesSectionCard extends StatelessWidget {
  const SeriesSectionCard({
    super.key,
    required this.title,
    required this.child,
    this.titleColor,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Color? titleColor;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: c.isDark
              ? [c.card.withValues(alpha: .96), const Color(0xff081a30)]
              : [c.card, c.card2],
        ),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: TextStyle(
                    color: titleColor ?? c.cyan,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    letterSpacing: .5,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class SeriesStateCard extends StatelessWidget {
  const SeriesStateCard({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.emoji_events_outlined,
    this.onRetry,
  });

  final String title;
  final String message;
  final IconData icon;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.cyan.withValues(alpha: .12),
            ),
            child: Icon(icon, color: c.cyan, size: 30),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: c.text, fontWeight: FontWeight.w900, fontSize: 17),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: c.muted, height: 1.4),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            GradientButton(
              label: 'Retry',
              icon: Icons.refresh_rounded,
              onTap: onRetry!,
            ),
          ],
        ],
      ),
    );
  }
}

class SeriesLoading extends StatelessWidget {
  const SeriesLoading({super.key, this.height = 200});

  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return SizedBox(
      height: height,
      child: Center(
        child: SizedBox(
          width: 34,
          height: 34,
          child: CircularProgressIndicator(color: c.cyan, strokeWidth: 3),
        ),
      ),
    );
  }
}
