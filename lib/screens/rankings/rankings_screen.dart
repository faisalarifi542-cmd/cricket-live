import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:cricpro_flutter/app_theme.dart';
import 'package:cricpro_flutter/api_models.dart';
import 'package:cricpro_flutter/components.dart';
import 'package:cricpro_flutter/models/api_response.dart';
import 'package:cricpro_flutter/repositories/cricket_repository.dart';
import 'package:cricpro_flutter/screens/player/player_detail_screen.dart';

class RankingsScreen extends StatefulWidget {
  const RankingsScreen({
    super.key,
    this.initialGender = 'men',
    this.initialCategory = 'batting',
    this.initialFormat = 'test',
  });

  /// 'men' or 'women' — selects which ICC ranking set to open with.
  final String initialGender;

  /// 'batting' | 'bowling' | 'allrounder' | 'teams' — the category to open with.
  /// Women rankings open on 'teams' by default (team rankings are the primary
  /// women dataset).
  final String initialCategory;

  /// 'test' | 'odi' | 't20'. Women rankings default to 'odi' since ICC women's
  /// tables are published for ODI / T20I (no women's Test table).
  final String initialFormat;

  @override
  State<RankingsScreen> createState() => _RankingsScreenState();
}

class _RankingsScreenState extends State<RankingsScreen> {
  final CricketRepository _repository = CricketRepository();
  late String gender = widget.initialGender == 'women' ? 'women' : 'men';
  late String category = widget.initialCategory;
  late String format = widget.initialFormat;
  late Future<ApiEnvelope<List<RankingEntry>>> _rankings;

  final categories = const [
    _FilterOption('Batsmen', 'batting', Icons.person_outline_rounded),
    _FilterOption('Bowlers', 'bowling', Icons.sports_baseball_rounded),
    _FilterOption('All-rounders', 'allrounder', Icons.auto_awesome_rounded),
    _FilterOption('Teams', 'teams', Icons.groups_rounded),
  ];
  final formats = const [
    _FilterOption('Test', 'test', Icons.sports_cricket_rounded),
    _FilterOption('ODI', 'odi', Icons.sports_cricket_rounded),
    _FilterOption('T20', 't20', Icons.sports_cricket_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _rankings = _load();
  }

  Future<ApiEnvelope<List<RankingEntry>>> _load(
      {bool forceRefresh = false}) async {
    if (kDebugMode) {
      debugPrint('RANKINGS selectedCategory=$category selectedFormat=$format');
      debugPrint(
          'RANKINGS GET /rankings?gender=$gender&category=$category&format=$format');
    }
    final response = await _repository.rankings(
      gender: gender,
      category: category,
      format: format,
      forceRefresh: forceRefresh,
    );
    if (kDebugMode) {
      final first = response.data.isEmpty ? '' : response.data.first.name;
      debugPrint('RANKINGS rows=${response.data.length} first=$first');
    }
    return response;
  }

  void _reload({bool forceRefresh = false}) {
    setState(() {
      _rankings = _load(forceRefresh: forceRefresh);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final currentCategory = categories.firstWhere((x) => x.value == category);
    final currentFormat = formats.firstWhere((x) => x.value == format);
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: c.bgGradient),
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: () async => _reload(forceRefresh: true),
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                context.horizontalPadding,
                18,
                context.horizontalPadding,
                context.detailBottomPadding,
              ),
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      tooltip: 'Back',
                      icon: Icon(Icons.arrow_back_rounded,
                          color: c.text, size: 28),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'ICC ${gender == 'women' ? 'Women' : 'Men'}\'s Ranking',
                        style: TextStyle(
                          color: c.text,
                          fontWeight: FontWeight.w900,
                          fontSize: context.sp(28),
                        ),
                      ),
                    ),
                    GlowIconButton(
                      icon: Icons.tune_rounded,
                      onTap: _showGenderPicker,
                      tooltip: 'Filter rankings',
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: _DropdownPill(
                        icon: currentCategory.icon,
                        label: currentCategory.label.toUpperCase(),
                        onTap: () => _pickFilter(categories, category, (value) {
                          category = value;
                        }),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _DropdownPill(
                        icon: currentFormat.icon,
                        label: currentFormat.label.toUpperCase(),
                        onTap: () => _pickFilter(formats, format, (value) {
                          format = value;
                        }),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                FutureBuilder<ApiEnvelope<List<RankingEntry>>>(
                  key: ValueKey('rankings:$gender:$category:$format'),
                  future: _rankings,
                  builder: (context, snapshot) {
                    final rows = snapshot.data?.data ?? const <RankingEntry>[];
                    if (snapshot.connectionState == ConnectionState.waiting &&
                        rows.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 42),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (snapshot.hasError) {
                      return _RankingStateCard(
                        title: 'Unable to load rankings',
                        subtitle:
                            'The ranking service is temporarily unavailable. Pull to refresh or try again later.',
                        onRetry: () => _reload(forceRefresh: true),
                      );
                    }
                    if (rows.isEmpty) {
                      return _RankingStateCard(
                        title: 'No ${currentCategory.label.toLowerCase()} '
                            'ranking available for ${currentFormat.label} yet',
                        subtitle:
                            'Try a different category or format. New rankings appear here once the ICC source updates.',
                        onRetry: () => _reload(forceRefresh: true),
                      );
                    }
                    return Column(
                      children: [
                        for (final row in rows)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: _RankingTapTarget(
                              entry: row,
                              child: _PremiumRankingCard(entry: row),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickFilter(
    List<_FilterOption> options,
    String selected,
    ValueChanged<String> onSelected,
  ) async {
    final value = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _PickerSheet(
        options: options,
        selected: selected,
      ),
    );
    if (!mounted || value == null || value.isEmpty || value == selected) return;
    onSelected(value);
    _reload(forceRefresh: true);
  }

  void _showGenderPicker() {
    _pickFilter(
      const [
        _FilterOption('Men', 'men', Icons.male_rounded),
        _FilterOption('Women', 'women', Icons.female_rounded),
      ],
      gender,
      (value) {
        gender = value;
      },
    );
  }
}

class _RankingTapTarget extends StatelessWidget {
  const _RankingTapTarget({required this.entry, required this.child});

  final RankingEntry entry;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final id = entry.playerId;
    if (entry.isTeam || id == null || id.isEmpty) return child;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PlayerDetailScreen(playerId: id),
            settings: RouteSettings(
              arguments: {
                'playerId': id,
                'name': entry.name,
                'rank': entry.rank,
                'points': entry.points,
                'imageUrl': entry.imageUrl,
                'country': entry.country,
              },
            ),
          ),
        ),
        child: child,
      ),
    );
  }
}

class _FilterOption {
  const _FilterOption(this.label, this.value, this.icon);
  final String label;
  final String value;
  final IconData icon;
}

class _PickerSheet extends StatelessWidget {
  const _PickerSheet({
    required this.options,
    required this.selected,
  });

  final List<_FilterOption> options;
  final String selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.cric.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final option in options)
            ListTile(
              leading: Icon(option.icon, color: context.cric.cyan),
              title: Text(option.label,
                  style: TextStyle(
                      color: context.cric.text, fontWeight: FontWeight.w800)),
              trailing: selected == option.value
                  ? Icon(Icons.check, color: context.cric.cyan)
                  : null,
              onTap: () {
                Navigator.pop(context, option.value);
              },
            ),
        ],
      ),
    );
  }
}

class _DropdownPill extends StatelessWidget {
  const _DropdownPill({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(28),
      child: Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: c.isDark ? c.card.withValues(alpha: .7) : c.card,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: c.border, width: 1.2),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: c.cyan.withValues(alpha: .15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: c.cyan, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: c.text,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.keyboard_arrow_down_rounded, color: c.muted, size: 24),
          ],
        ),
      ),
    );
  }
}

class _PremiumRankingCard extends StatelessWidget {
  const _PremiumRankingCard({required this.entry});

  final RankingEntry entry;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final isFirst = entry.rank == 1;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: c.cardGradient,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isFirst ? c.cyan.withValues(alpha: .8) : c.border,
          width: isFirst ? 2.0 : 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: c.isDark
                ? Colors.black.withValues(alpha: .28)
                : const Color(0xff4a7fb5).withValues(alpha: .10),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
          if (isFirst && c.isDark)
            BoxShadow(
              color: c.cyan.withValues(alpha: .25),
              blurRadius: 20,
              spreadRadius: 2,
            ),
        ],
      ),
      child: Row(
        children: [
          SizedBox(
            width: 42,
            child: Column(
              children: [
                if (isFirst)
                  Icon(Icons.emoji_events_rounded, color: c.cyan, size: 26),
                if (isFirst) const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '${entry.rank}',
                    style: TextStyle(
                      color: isFirst ? c.cyan : c.text,
                      fontWeight: FontWeight.w900,
                      fontSize: 28,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Allow the player name up to 2 lines so a long name wraps
                // instead of truncating mid-surname (the "Travis ..." bug) —
                // the row has room now that the rank column is tighter.
                Text(
                  entry.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.text,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                if (entry.country.isNotEmpty)
                  Text(
                    entry.country,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.muted,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  children: [
                    _Metric(label: 'RATING', value: '${entry.rating}'),
                    if (entry.points != null)
                      _Metric(label: 'PTS', value: '${entry.points}'),
                    if ((entry.matches ?? 0) > 0)
                      _Metric(label: 'MAT', value: '${entry.matches}'),
                  ],
                ),
              ],
            ),
          ),
          if (entry.movement != 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: entry.movement > 0
                    ? Colors.green.withValues(alpha: .15)
                    : Colors.red.withValues(alpha: .15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    entry.movement > 0
                        ? Icons.arrow_upward_rounded
                        : Icons.arrow_downward_rounded,
                    color: entry.movement > 0 ? Colors.green : Colors.red,
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${entry.movement.abs()}',
                    style: TextStyle(
                      color: entry.movement > 0 ? Colors.green : Colors.red,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(width: 12),
          _RankingImage(entry: entry),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
              color: context.cric.cyan,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: context.cric.muted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );
}

class _RankingImage extends StatelessWidget {
  const _RankingImage({required this.entry});

  final RankingEntry entry;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    // Honor the global player-image mode (admin/provider/initials) instead of
    // always trusting the raw ranking image URL.
    final image = resolvePlayerImageUrl(entry.imageUrl);
    return Container(
      // Slightly smaller avatar so the player name column gets more width and
      // long names wrap instead of truncating.
      width: 64,
      height: 64,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border, width: 1.5),
        color: c.card2,
      ),
      // The rank, player name and country are all adjacent text in this row, so
      // the avatar is redundant and stays out of the accessibility tree.
      child: ExcludeSemantics(
        child: image == null || image.isEmpty
            ? _Initial(entry.name)
            : CachedNetworkImage(
                imageUrl: image,
                fit: BoxFit.cover,
                fadeInDuration: Duration.zero,
                placeholder: (context, _) => _Initial(entry.name),
                errorWidget: (_, __, ___) => _Initial(entry.name),
              ),
      ),
    );
  }
}

class _Initial extends StatelessWidget {
  const _Initial(this.name);

  final String name;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Center(
      child: Text(
        initial,
        style: TextStyle(
          color: context.cric.text,
          fontWeight: FontWeight.w900,
          fontSize: 32,
        ),
      ),
    );
  }
}

class _RankingStateCard extends StatelessWidget {
  const _RankingStateCard({
    required this.title,
    required this.onRetry,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        children: [
          Icon(Icons.leaderboard_rounded, color: c.cyan, size: 38),
          const SizedBox(height: 12),
          Text(title,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: c.text, fontWeight: FontWeight.w900, fontSize: 18)),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(subtitle!,
                textAlign: TextAlign.center,
                style: TextStyle(color: c.muted, height: 1.4, fontSize: 13)),
          ],
          const SizedBox(height: 16),
          GradientButton(
              label: 'Retry', icon: Icons.refresh_rounded, onTap: onRetry),
        ],
      ),
    );
  }
}
