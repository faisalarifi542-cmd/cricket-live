import 'package:flutter/material.dart';

import 'package:cricpro_flutter/app_theme.dart';
import 'package:cricpro_flutter/api_models.dart';
import 'package:cricpro_flutter/components.dart';

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

  /// "3 ODIs • 3 T20Is" style chip text derived from formats.
  String get formatSummary => formats.isEmpty ? '' : formats.join(' • ');

  factory SeriesView.fromApi(ApiSeries series) {
    return SeriesView(
      id: series.id,
      name: cleanSeriesText(series.name),
      status: _statusFromText(series.status),
      category: _categoryFor(series.name, series.format),
      startDate: _parseDate(series.startDate),
      endDate: _parseDate(series.endDate),
      formats: _formatsFromText('${series.format ?? ''} ${series.name}'),
      matchCount: series.matchCount,
      host: series.country,
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
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
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

SeriesStatus _statusFromText(String? raw) {
  final low = (raw ?? '').toLowerCase();
  if (low.contains('complete') || low.contains('finish') || low.contains('result')) {
    return SeriesStatus.completed;
  }
  if (low.contains('live') ||
      low.contains('ongoing') ||
      low.contains('progress')) {
    return SeriesStatus.ongoing;
  }
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

List<String> _formatsFromText(String raw) {
  final text = raw.toUpperCase();
  final formats = <String>[];
  if (text.contains('TEST')) formats.add('Test');
  if (text.contains('ODI')) formats.add('ODI');
  if (text.contains('T20')) formats.add(text.contains('T20I') ? 'T20I' : 'T20');
  return formats;
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
    final formatLine = series.formatSummary;
    final dateLine = series.dateRangeLabel;
    final left = series.teams.isNotEmpty ? series.teams.first : null;
    final right = series.teams.length > 1 ? series.teams[1] : null;

    return TapScale(
      onTap: onTap,
      borderRadius: 24,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xff0a1f3a),
              c.card.withValues(alpha: .96),
              const Color(0xff071726),
            ],
          ),
          border: Border.all(color: c.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .30),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            // Left mini matchup tile (flags) — premium stadium gradient.
            _MatchupThumb(left: left, right: right),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    series.cleanName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.text,
                      fontWeight: FontWeight.w900,
                      fontSize: 16.5,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (formatLine.isNotEmpty)
                    Text(
                      formatLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.muted,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  if (dateLine.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      dateLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.muted.withValues(alpha: .85),
                        fontWeight: FontWeight.w600,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _MiniStatusChip(label: series.statusLabel, color: statusColor),
                      const SizedBox(width: 8),
                      _MiniTypeChip(label: series.categoryLabel),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Right side: team logos stacked like the reference.
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (left != null)
                  _SeriesTeamLogo(team: left, size: 30),
                if (right != null) ...[
                  const SizedBox(height: 6),
                  _SeriesTeamLogo(team: right, size: 30),
                ],
                const SizedBox(height: 6),
                Icon(Icons.chevron_right_rounded, color: c.muted, size: 20),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MatchupThumb extends StatelessWidget {
  const _MatchupThumb({this.left, this.right});

  final SeriesTeamRef? left;
  final SeriesTeamRef? right;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      width: 84,
      height: 84,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xff123a5e), Color(0xff05101f)],
        ),
        border: Border.all(color: c.border),
      ),
      child: left == null && right == null
          ? Icon(Icons.emoji_events_rounded, color: c.cyan.withValues(alpha: .7), size: 34)
          : Stack(
              children: [
                if (left != null)
                  Positioned(
                    left: 10,
                    top: 14,
                    child: _SeriesTeamLogo(team: left!, size: 36),
                  ),
                if (right != null)
                  Positioned(
                    right: 10,
                    bottom: 14,
                    child: _SeriesTeamLogo(team: right!, size: 36),
                  ),
              ],
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

class _MiniStatusChip extends StatelessWidget {
  const _MiniStatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .55)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _MiniTypeChip extends StatelessWidget {
  const _MiniTypeChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .04),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.border),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: c.muted,
          fontWeight: FontWeight.w800,
          fontSize: 11,
        ),
      ),
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
        border: Border.all(color: c.cyan.withValues(alpha: .28)),
        boxShadow: [
          BoxShadow(
            color: c.cyan.withValues(alpha: .12),
            blurRadius: 28,
            spreadRadius: -6,
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
                    const Color(0xff04122a).withValues(alpha: .82),
                    const Color(0xff05101f).withValues(alpha: .92),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                _HeroTeamColumn(team: left),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (tourLabel != null && tourLabel!.isNotEmpty)
                        Text(
                          tourLabel!.toUpperCase(),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: c.cyan,
                            fontWeight: FontWeight.w900,
                            fontSize: 11,
                            letterSpacing: .5,
                          ),
                        ),
                      const SizedBox(height: 4),
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
                            fontSize: 15,
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
                                maxLines: 1,
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
              fit: BoxFit.cover,
              gaplessPlayback: true,
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
