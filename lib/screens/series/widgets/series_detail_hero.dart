part of '../series_detail_screen.dart';

class _DetailAppBar extends StatelessWidget {
  const _DetailAppBar({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final logoSize = context.w <= 400 ? 28.0 : 31.0;
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          GestureDetector(
            onTap: onBack,
            behavior: HitTestBehavior.opaque,
            // 44×44 hit area (was a bare 26px icon — a sub-minimum touch
            // target). Left-aligned so the icon stays at the screen edge while
            // the tap box extends inward.
            child: SizedBox(
              width: 44,
              height: 44,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Icon(Icons.arrow_back_rounded, color: c.text, size: 26),
              ),
            ),
          ),
          const Spacer(),
          // Shared CRICPRO wordmark — same renderer as Home/Matches/More.
          CricLogo(size: logoSize),
          const Spacer(),
          const _BellWithBadge(),
          const SizedBox(width: 6),
          Icon(Icons.more_vert_rounded, color: c.text, size: 24),
        ],
      ),
    );
  }
}

class _BellWithBadge extends StatelessWidget {
  const _BellWithBadge();

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Icon(Icons.notifications_none_rounded, color: c.text, size: 25),
          Positioned(
            top: 2,
            right: 2,
            child: Container(
              // A dot-only unread indicator — never a fake hardcoded count.
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: c.live,
                shape: BoxShape.circle,
                border: Border.all(color: c.bg, width: 1.5),
                boxShadow: c.isDark
                    ? [
                        BoxShadow(color: c.live.withValues(alpha: .6), blurRadius: 8),
                      ]
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Premium series detail hero banner
// ---------------------------------------------------------------------------

class SeriesDetailHero extends StatelessWidget {
  const SeriesDetailHero({
    super.key,
    required this.title,
    this.tourLabel,
    this.season,
    this.dateRange = '',
    this.formats = const [],
    this.left,
    this.right,
  });

  final String title;
  final String? tourLabel;
  final String? season;
  final String dateRange;
  final List<String> formats;
  final SeriesTeamRef? left;
  final SeriesTeamRef? right;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final phone = context.w <= 430;
    final logoSize = phone ? 56.0 : 64.0;
    final (small, big) = _splitTitle();
    final formatLine = formats.isEmpty ? '' : formats.join('  •  ');
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
            color: c.isDark
                ? c.cyan.withValues(alpha: .55)
                : c.cyan.withValues(alpha: .3),
            width: 1.2),
        boxShadow: c.isDark
            ? [
                BoxShadow(
                  color: c.cyan.withValues(alpha: .18),
                  blurRadius: 28,
                  spreadRadius: -8,
                ),
                ...c.heroShadow.skip(1),
              ]
            : c.heroShadow,
      ),
      child: Stack(
        children: [
          const Positioned.fill(
            child: StadiumImage(
              SAsset.detailHeroBg,
              hero: true,
              remoteKey: 'series_hero_bg',
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
          const TopCyanHighlight(),
          Padding(
            padding:
                EdgeInsets.symmetric(horizontal: phone ? 12 : 16, vertical: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _HeroTeam(team: left, size: logoSize, accent: c.cyan),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (small.isNotEmpty)
                        Text(
                          small.toUpperCase(),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: c.onImageText,
                            fontWeight: FontWeight.w700,
                            fontStyle: FontStyle.italic,
                            fontSize: context.sp(phone ? 10.5 : 12),
                            letterSpacing: .5,
                            height: 1.15,
                          ),
                        ),
                      Text(
                        big.toUpperCase(),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.text,
                          fontWeight: FontWeight.w900,
                          fontStyle: FontStyle.italic,
                          fontSize: context.sp(phone ? 19 : 23),
                          height: 1.04,
                          shadows: c.isDark
                              ? [
                                  Shadow(
                                      color: c.cyan.withValues(alpha: .4),
                                      blurRadius: 12),
                                ]
                              : null,
                        ),
                      ),
                      if (dateRange.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.calendar_today_rounded,
                                  color: c.cyan, size: 12),
                              const SizedBox(width: 5),
                              Text(
                                dateRange.toUpperCase(),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                style: TextStyle(
                                  color: c.cyan,
                                  fontWeight: FontWeight.w800,
                                  fontSize: phone ? 10.5 : 11.5,
                                  letterSpacing: .3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (formatLine.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: c.cyan.withValues(alpha: .12),
                            borderRadius: BorderRadius.circular(999),
                            border:
                                Border.all(color: c.cyan.withValues(alpha: .5)),
                          ),
                          child: Text(
                            formatLine,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: c.text,
                              fontWeight: FontWeight.w800,
                              fontSize: phone ? 11 : 12,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                _HeroTeam(team: right, size: logoSize, accent: c.warning),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Splits "Afghanistan Tour of India 2026" into ("Afghanistan Tour of",
  /// "India 2026"). Handles the "to"/"vs"/"in" connectors too (not just the
  /// literal "tour of"), and cleans dangling punctuation so a wrapped season
  /// never reads "GERMANY," on its own line. Falls back to (tourLabel, season)
  /// or ('', title).
  (String, String) _splitTitle() {
    final raw = shortSeriesTitle(title);
    final full = season != null && !raw.contains(season!) ? '$raw $season' : raw;
    // Split on the connector phrase joining the two sides of a tour/bilateral
    // title ("… tour of …", "… to …", "… vs …", "… in …").
    final m = RegExp(r'^(.*?\b(?:tour of|to|vs)\b)\s+(.*)$',
            caseSensitive: false)
        .firstMatch(full);
    if (m != null) {
      final small = _cleanTitlePart(m.group(1)!);
      final big = _cleanTitlePart(m.group(2)!);
      if (small.isNotEmpty && big.isNotEmpty) return (small, big);
    }
    if (season != null && full.endsWith(season!)) {
      final base = _cleanTitlePart(full.substring(0, full.length - season!.length));
      if (base.isNotEmpty) return (base, season!);
    }
    return ('', _cleanTitlePart(full));
  }

  /// Trims trailing/leading punctuation and collapses a ", <year>" so a season
  /// never wraps onto its own line as a bare "GERMANY," fragment.
  static String _cleanTitlePart(String s) => s
      .replaceAll(RegExp(r',\s*(?=\d{4}\b)'), ' ') // "Germany, 2026" -> "Germany 2026"
      .replaceAll(RegExp(r'^[\s,–-]+|[\s,–-]+$'), '') // strip edge punctuation
      .replaceAll(RegExp(r'\s{2,}'), ' ')
      .trim();
}

class _HeroTeam extends StatelessWidget {
  const _HeroTeam(
      {required this.team, required this.size, required this.accent});

  final SeriesTeamRef? team;
  final double size;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final t = team;
    final label =
        (t?.name.isNotEmpty == true ? t!.name : (t?.shortName ?? 'TBD'))
            .toUpperCase();
    return SizedBox(
      width: size + 22,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PremiumTeamLogo(
            name: t?.name ?? 'TBD',
            short: t?.shortName ?? 'TBD',
            logo: t?.logoUrl,
            size: size,
            accent: accent,
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: c.text,
                fontWeight: FontWeight.w900,
                fontSize: 12.5,
                letterSpacing: .3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Series context — derived series-level metadata
// ---------------------------------------------------------------------------

