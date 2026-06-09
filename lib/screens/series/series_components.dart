import 'package:flutter/material.dart';

import 'package:cricpro_flutter/app_theme.dart';
import 'package:cricpro_flutter/api_models.dart';
import 'package:cricpro_flutter/components.dart';
import 'package:cricpro_flutter/screens/series/series_premium.dart';

/// Shared premium building blocks for the Series module (list + details).
/// All widgets follow the CricPro dark-navy/cyan glassmorphism design.

// ---------------------------------------------------------------------------
// Series view model — derives premium display fields from API data.
// ---------------------------------------------------------------------------

enum SeriesStatus { ongoing, upcoming, completed }

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

  String get statusLabel => switch (status) {
        SeriesStatus.ongoing => 'Ongoing',
        SeriesStatus.upcoming => 'Upcoming',
        SeriesStatus.completed => 'Completed',
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
    return SeriesView(
      id: series.id,
      name: cleanSeriesText(series.name),
      status: _normalizeStatus(series.status, start, end),
      category: _categoryFor(series.name, series.format),
      startDate: start,
      endDate: end,
      formats: _formatsFromText('${series.format ?? ''} ${series.name}'),
      formatLabel: (series.format ?? '').trim(),
      matchCount: series.matchCount,
      host: series.country,
      teams: _teamsFromApi(series.teams),
    );
  }
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

/// Normalizes a series status using the backend's status text first, then the
/// date window. Mirrors the backend `computeSeriesStatus` rules so a finished
/// edition (endDate in the past) is never shown as Upcoming — unless the API
/// explicitly says it is live/ongoing.
SeriesStatus _normalizeStatus(String? raw, DateTime? start, DateTime? end) {
  final low = (raw ?? '').toLowerCase();
  final saysLive = low.contains('live') ||
      low.contains('ongoing') ||
      low.contains('progress');
  final saysDone = low.contains('complete') ||
      low.contains('finish') ||
      low.contains('result') ||
      low.contains('concluded');
  if (saysLive) return SeriesStatus.ongoing;
  if (saysDone) return SeriesStatus.completed;

  final now = DateTime.now();
  if (end != null && end.isBefore(now)) return SeriesStatus.completed;
  if (start != null && start.isAfter(now)) return SeriesStatus.upcoming;
  if (start != null &&
      end != null &&
      !start.isAfter(now) &&
      !end.isBefore(now)) {
    return SeriesStatus.ongoing;
  }
  if (start != null && !start.isAfter(now)) return SeriesStatus.ongoing;
  return SeriesStatus.upcoming;
}

SeriesCategory _categoryFor(String name, String? format) {
  final text = '${format ?? ''} $name'.toLowerCase();
  if (text.contains('women') || text.contains(' w ') || text.contains('-w ')) {
    return SeriesCategory.women;
  }
  if (text.contains('premier league') ||
      text.contains('ipl') ||
      text.contains('psl') ||
      text.contains('bbl') ||
      text.contains('cpl') ||
      text.contains('the hundred') ||
      text.contains(' t10') ||
      text.contains('league')) {
    return SeriesCategory.league;
  }
  if (text.contains('ranji') ||
      text.contains('county') ||
      text.contains('domestic') ||
      text.contains('shield') ||
      text.contains('trophy') && !text.contains('tour')) {
    return SeriesCategory.domestic;
  }
  return SeriesCategory.international;
}

List<SeriesTeamRef> _teamsFromApi(List<dynamic> raw) {
  final teams = <SeriesTeamRef>[];
  for (final entry in raw) {
    final map = apiMap(entry);
    final name = apiString(map['name'] ?? map['teamName'] ?? map['team_name']);
    if (name.isEmpty) continue;
    final shortName = apiString(
        map['shortName'] ?? map['short_name'] ?? map['teamShortName']);
    final logo = apiString(map['logoUrl'] ?? map['logo_url'] ?? map['logo']);
    teams.add(SeriesTeamRef(
      name: name,
      shortName: shortName.isEmpty ? name : shortName,
      logoUrl: logo.isEmpty ? null : logo,
    ));
  }
  return teams;
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
                color: isSel ? null : Colors.white.withValues(alpha: .02),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: isSel ? c.cyan.withValues(alpha: .7) : c.border,
                ),
                boxShadow: isSel
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

class SeriesListCard extends StatelessWidget {
  const SeriesListCard({super.key, required this.series, required this.onTap});

  final SeriesView series;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final statusColor = switch (series.status) {
      SeriesStatus.ongoing => c.live,
      SeriesStatus.upcoming => c.cyan,
      SeriesStatus.completed => c.success,
    };
    final phone = context.w <= 430;
    final tight = context.w <= 360;
    final formatLine = series.formatSummary.isNotEmpty
        ? series.formatSummary
        : (series.matchCount != null && series.matchCount! > 0
            ? '${series.matchCount} Matches'
            : '');
    final dateLine = series.shortDateRange;
    final left = series.teams.isNotEmpty ? series.teams.first : null;
    final right = series.teams.length > 1 ? series.teams[1] : null;
    final logoSize = phone ? 42.0 : 46.0;

    return TapScale(
      onTap: onTap,
      borderRadius: 22,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: c.cyan.withValues(alpha: .42), width: 1),
          boxShadow: [
            BoxShadow(
              color: c.cyan.withValues(alpha: .1),
              blurRadius: 18,
              spreadRadius: -8,
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: .38),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                SAsset.listCardBg,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      const Color(0xff04142b).withValues(alpha: .7),
                      const Color(0xff051226).withValues(alpha: .8),
                      const Color(0xff020a18).withValues(alpha: .9),
                    ],
                  ),
                ),
              ),
            ),
            const TopCyanHighlight(),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
              child: Row(
                children: [
                  PremiumTeamLogo(
                    name: left?.name ?? series.cleanName,
                    short: left?.shortName ?? '',
                    logo: left?.logoUrl,
                    size: logoSize,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          series.cleanName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: c.text,
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                            height: 1.14,
                          ),
                        ),
                        if (formatLine.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            formatLine,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: .8),
                              fontWeight: FontWeight.w700,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                        if (dateLine.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.calendar_today_rounded,
                                  color: c.cyan, size: 11),
                              const SizedBox(width: 5),
                              Flexible(
                                child: Text(
                                  dateLine,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: .7),
                                    fontWeight: FontWeight.w600,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 7),
                        Wrap(
                          spacing: 6,
                          runSpacing: 5,
                          children: [
                            SeriesStatusPill(
                              label: series.statusLabel,
                              color: statusColor,
                              live: series.status == SeriesStatus.ongoing,
                              dense: true,
                            ),
                            SeriesOutlineChip(label: series.categoryLabel),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  PremiumVsBadge(
                    width: tight ? 38 : 42,
                    height: tight ? 26 : 28,
                    intensity: .85,
                  ),
                  const SizedBox(width: 6),
                  PremiumTeamLogo(
                    name: right?.name ?? series.cleanName,
                    short: right?.shortName ?? '',
                    logo: right?.logoUrl,
                    size: logoSize,
                    accent: c.warning,
                  ),
                  Icon(Icons.chevron_right_rounded,
                      color: c.cyan, size: tight ? 18 : 20),
                ],
              ),
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
        border: Border.all(color: c.cyan.withValues(alpha: .42)),
        boxShadow: [
          BoxShadow(
            color: c.cyan.withValues(alpha: .18),
            blurRadius: 34,
            spreadRadius: -7,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: .34),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/images/stadium_live.png',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  const ColoredBox(color: Color(0xff071726)),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    const Color(0xff031028).withValues(alpha: .76),
                    const Color(0xff061934).withValues(alpha: .88),
                    const Color(0xff020914).withValues(alpha: .96),
                  ],
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
        color: Colors.white.withValues(alpha: .02),
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
                    boxShadow: [
                      BoxShadow(
                        color: c.cyan.withValues(alpha: .28),
                        blurRadius: 16,
                        spreadRadius: 1,
                      ),
                    ],
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
    final c = context.cric;
    final hasImage = imageUrl != null && imageUrl!.trim().isNotEmpty;
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            c.cyan.withValues(alpha: .22),
            const Color(0xff071726),
          ],
        ),
        border: Border.all(
          color: borderColor ?? c.cyan.withValues(alpha: .45),
          width: 2,
        ),
      ),
      child: hasImage
          ? Image.network(
              imageUrl!,
              // Key by the URL so a changed image always rebuilds a fresh
              // element — never displays a stale (previous player's) frame.
              key: ValueKey(imageUrl),
              fit: BoxFit.cover,
              webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return _initials(context);
              },
              errorBuilder: (_, __, ___) => _initials(context),
            )
          : _initials(context),
    );
  }

  Widget _initials(BuildContext context) {
    final c = context.cric;
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    final initials = parts.isEmpty
        ? '?'
        : parts.length == 1
            ? parts.first.substring(0, 1).toUpperCase()
            : (parts.first[0] + parts.last[0]).toUpperCase();
    return Center(
      child: Text(
        initials,
        style: TextStyle(
          color: c.text,
          fontWeight: FontWeight.w900,
          fontSize: size * .32,
        ),
      ),
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
          colors: [c.card.withValues(alpha: .96), const Color(0xff081a30)],
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
