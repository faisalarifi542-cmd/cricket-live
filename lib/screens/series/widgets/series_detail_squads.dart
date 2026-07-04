part of '../series_detail_screen.dart';

class _MatchesTab extends StatelessWidget {
  const _MatchesTab({required this.matches, required this.onOpenMatch});

  final List<CricketMatch> matches;
  final ValueChanged<String> onOpenMatch;

  @override
  Widget build(BuildContext context) {
    if (matches.isEmpty) {
      return const SeriesEmptyState(
        title: 'No matches yet',
        message: 'Matches for this series have not been announced yet.',
        icon: Icons.event_busy_rounded,
      );
    }
    final ordered = [...matches]..sort((a, b) =>
        (a.startDateTime ?? DateTime(2100))
            .compareTo(b.startDateTime ?? DateTime(2100)));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < ordered.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _SeriesMatchCard(
              match: ordered[i],
              index: i + 1,
              onTap: () => onOpenMatch(ordered[i].id),
            ),
          ),
      ],
    );
  }
}

class _SeriesMatchCard extends StatelessWidget {
  const _SeriesMatchCard({
    required this.match,
    required this.index,
    required this.onTap,
  });

  final CricketMatch match;
  final int index;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final phone = context.w <= 430;
    final logoSize = phone ? 46.0 : 50.0;
    // Route through the shared status resolver so a stumps/lunch/tea/innings-
    // break match badges as STUMPS/LUNCH/TEA/INN BREAK (no pulsing dot) instead
    // of a pulsing "Live" pill next to a "Stumps Day 1" note — the badge and
    // the note can no longer disagree.
    final status = MatchStatusDisplay.of(context, match);
    final (statusLabel, statusColor, isLive) =
        (status.badge, status.color, status.subPhase == MatchSubPhase.live);
    final fmt = _formatTag(match);
    final desc = match.matchDesc.isNotEmpty
        ? 'MATCH $index • ${match.matchDesc.toUpperCase()}'
        : 'MATCH $index';

    return PremiumGlassPanel(
      bgAsset: SAsset.matchCardBg,
      bgRemoteKey: 'series_match_card_bg',
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SeriesOutlineChip(label: fmt, icon: Icons.sports_cricket_rounded),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    desc,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: c.onImageText,
                      fontWeight: FontWeight.w800,
                      fontSize: phone ? 10 : 11,
                      letterSpacing: .3,
                    ),
                  ),
                ),
              ),
              SeriesStatusPill(
                label: statusLabel,
                color: statusColor,
                live: isLive,
                dense: true,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: phone ? 66 : 74,
                child: PremiumTeamColumn(
                  name: match.teamA,
                  short: match.teamAShort,
                  logo: match.teamALogo,
                  logoSize: logoSize,
                  codeSize: phone ? 15 : 16,
                  accent: c.cyan,
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    PremiumVsBadge(
                      width: phone ? 50 : 54,
                      height: phone ? 34 : 38,
                    ),
                    const SizedBox(height: 8),
                    if (match.startDateTime != null)
                      Text(
                        _dateOnlyYear(match.startDateTime!).toUpperCase(),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.text,
                          fontWeight: FontWeight.w800,
                          fontSize: phone ? 11 : 12,
                        ),
                      ),
                    if (match.venue.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.location_on_outlined,
                              color: c.cyan, size: 11),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              match.venue,
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: c.onImageText,
                                fontWeight: FontWeight.w600,
                                fontSize: 10.5,
                                height: 1.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(
                width: phone ? 66 : 74,
                child: PremiumTeamColumn(
                  name: match.teamB,
                  short: match.teamBShort,
                  logo: match.teamBLogo,
                  logoSize: logoSize,
                  codeSize: phone ? 15 : 16,
                  accent: c.warning,
                ),
              ),
            ],
          ),
          // Match note (countdown / result) as a centered full-width row BELOW
          // both team columns, so the two columns are equal height and the VS
          // badge + date/venue centre column stays vertically balanced (the old
          // layout had the note only under the right team, making that column
          // taller and the left logo sit higher than the right block).
          const SizedBox(height: 8),
          _MatchRightNote(match: match),
        ],
      ),
    );
  }

  static String _formatTag(CricketMatch m) {
    final t = m.matchDesc.toUpperCase();
    if (t.contains('TEST')) return 'TEST';
    if (t.contains('T20')) return 'T20';
    if (t.contains('ODI')) return 'ODI';
    if (t.contains('FINAL')) return 'FINAL';
    return 'MATCH';
  }
}

/// Right-aligned note under the right team: countdown (upcoming), result
/// (completed) or live status.
class _MatchRightNote extends StatelessWidget {
  const _MatchRightNote({required this.match});

  final CricketMatch match;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    if (match.isUpcoming && match.startDateTime != null) {
      final raw = _countdown(match.startDateTime);
      final soon = raw == 'Soon' || raw == 'TBC';
      if (soon) {
        return Text(
          'STARTING SOON',
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: c.cyan,
            fontWeight: FontWeight.w900,
            fontSize: 10.5,
            height: 1.15,
            letterSpacing: .3,
          ),
        );
      }
      return Column(
        children: [
          Text(
            'STARTS IN',
            style: TextStyle(
              color: c.muted,
              fontWeight: FontWeight.w700,
              fontSize: 8.5,
              letterSpacing: .3,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            raw.replaceAll('In ', '').toUpperCase(),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: c.cyan,
              fontWeight: FontWeight.w900,
              fontSize: 11,
            ),
          ),
        ],
      );
    }
    if (match.isFinished && match.resultText.isNotEmpty) {
      return Text(
        match.resultText,
        textAlign: TextAlign.center,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: c.success,
          fontWeight: FontWeight.w700,
          fontSize: 9.5,
          height: 1.15,
        ),
      );
    }
    if (match.isLive) {
      // Use the shared phase label so a stoppage (stumps/lunch/tea/innings
      // break) reads "Day 1 Stumps"/"Innings break" instead of the misleading
      // "LIVE NOW", and drops the red live styling while paused.
      final note = MatchStatusDisplay.of(context, match).phaseLabel;
      return Text(
        note.isNotEmpty ? note : 'LIVE',
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: c.live,
          fontWeight: FontWeight.w800,
          fontSize: 9.5,
          height: 1.15,
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

// ---------------------------------------------------------------------------
// Squads tab
// ---------------------------------------------------------------------------

class _SquadsTab extends StatefulWidget {
  const _SquadsTab({required this.formats});

  final List<SquadFormat> formats;

  @override
  State<_SquadsTab> createState() => _SquadsTabState();
}

class _SquadsTabState extends State<_SquadsTab> {
  int _format = 0;
  int _team = 0;

  @override
  Widget build(BuildContext context) {
    final formats = widget.formats;
    final hasAny = formats.any((f) => f.teams.any((t) => t.players.isNotEmpty));
    if (!hasAny) {
      return const SeriesEmptyState(
        title: 'Squads not announced',
        message:
            'Squads for this series are not available from the provider yet.',
        icon: Icons.groups_rounded,
      );
    }

    final fIndex = _format.clamp(0, formats.length - 1);
    final format = formats[fIndex];
    final teams = format.teams;
    final tIndex = _team.clamp(0, teams.length - 1);
    final team = teams[tIndex];
    final showFormatSelector =
        formats.length > 1 && formats.any((f) => f.format.isNotEmpty);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            if (showFormatSelector) ...[
              Flexible(
                child: _SquadToggle(
                  items: [
                    for (final f in formats)
                      _ToggleItem(label: _formatLabel(f.format))
                  ],
                  selected: fIndex,
                  onChanged: (v) => setState(() {
                    _format = v;
                    _team = 0;
                  }),
                ),
              ),
              const SizedBox(width: 10),
            ],
            if (teams.length > 1)
              Flexible(
                child: _SquadToggle(
                  items: [
                    for (final t in teams)
                      _ToggleItem(
                        label: t.shortName.isNotEmpty ? t.shortName : t.name,
                        team: t,
                      )
                  ],
                  selected: tIndex,
                  onChanged: (v) => setState(() => _team = v),
                ),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (team.players.isEmpty)
          const SeriesEmptyState(
            title: 'Squad not announced yet',
            message: 'This team\'s squad for this format has not been '
                'announced yet.',
            icon: Icons.groups_rounded,
          )
        else
          _SquadGroups(
            key: ValueKey('squad-${format.format}-${team.identityKey}'),
            team: team,
          ),
      ],
    );
  }

  static String _formatLabel(String format) {
    final f = format.trim();
    if (f.isEmpty) return 'Squad';
    return f;
  }
}

class _ToggleItem {
  const _ToggleItem({required this.label, this.team});
  final String label;
  final SquadTeam? team;
}

/// Glass segmented toggle used for the format + team selectors. Active
/// segment is a cyan glass pill; team items show a small logo.
class _SquadToggle extends StatelessWidget {
  const _SquadToggle({
    required this.items,
    required this.selected,
    required this.onChanged,
  });

  final List<_ToggleItem> items;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      height: 46,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.isDark ? c.card.withValues(alpha: .5) : c.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: c.cyan.withValues(alpha: .4)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(i),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  height: 38,
                  decoration: BoxDecoration(
                    gradient: i == selected
                        ? const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xff35e2ff), Color(0xff0a86ff)],
                          )
                        : null,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: i == selected && c.isDark
                        ? [
                            BoxShadow(
                              color: c.cyan.withValues(alpha: .45),
                              blurRadius: 12,
                              spreadRadius: -2,
                            ),
                          ]
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (items[i].team != null) ...[
                        TeamLogoWidget(
                          logoUrl: items[i].team!.logoUrl,
                          teamName: items[i].team!.name,
                          abbreviation: items[i].label,
                          color: c.cyan,
                          size: 20,
                        ),
                        const SizedBox(width: 6),
                      ],
                      Flexible(
                        child: Text(
                          items[i].label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: i == selected ? Colors.white : c.muted,
                            fontWeight: i == selected
                                ? FontWeight.w800
                                : FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SquadGroups extends StatelessWidget {
  const _SquadGroups({super.key, required this.team});

  final SquadTeam team;

  static const _meta = <(String, IconData)>[
    ('Batters', Icons.sports_cricket_rounded),
    ('Wicketkeepers', Icons.back_hand_outlined),
    ('All-Rounders', Icons.change_circle_outlined),
    ('Bowlers', Icons.sports_baseball_outlined),
    ('Reserves / Bench', Icons.event_seat_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final groups = _group(team.players);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final m in _meta)
          if ((groups[m.$1] ?? const []).isNotEmpty) ...[
            _SquadSection(
              title: m.$1,
              icon: m.$2,
              players: groups[m.$1]!,
              team: team,
            ),
            const SizedBox(height: 14),
          ],
      ],
    );
  }

  /// Groups players into the real squad categories. Substitutes/bench players
  /// (when the backend provides them) are pulled into a dedicated Reserves /
  /// Bench section; everyone else is classified by the backend `category`
  /// field, falling back to role-text heuristics for legacy payloads.
  Map<String, List<SquadPlayer>> _group(List<SquadPlayer> players) {
    final batters = <SquadPlayer>[];
    final keepers = <SquadPlayer>[];
    final allRounders = <SquadPlayer>[];
    final bowlers = <SquadPlayer>[];
    final reserves = <SquadPlayer>[];

    for (final p in players) {
      if (p.isSubstitute) {
        reserves.add(p);
        continue;
      }
      final cat = p.category.toLowerCase();
      if (cat.isNotEmpty) {
        switch (cat) {
          case 'wicketkeepers':
            keepers.add(p);
            break;
          case 'allrounders':
            allRounders.add(p);
            break;
          case 'bowlers':
            bowlers.add(p);
            break;
          default:
            batters.add(p);
        }
        continue;
      }
      final role = p.role.toLowerCase();
      if (p.isWicketKeeper || role.contains('wk') || role.contains('keeper')) {
        keepers.add(p);
      } else if (role.contains('all') && role.contains('round')) {
        allRounders.add(p);
      } else if (role.contains('bowl')) {
        bowlers.add(p);
      } else {
        batters.add(p);
      }
    }
    return {
      'Batters': batters,
      'Wicketkeepers': keepers,
      'All-Rounders': allRounders,
      'Bowlers': bowlers,
      'Reserves / Bench': reserves,
    };
  }
}

class _SquadSection extends StatelessWidget {
  const _SquadSection({
    required this.title,
    required this.icon,
    required this.players,
    required this.team,
  });

  final String title;
  final IconData icon;
  final List<SquadPlayer> players;
  final SquadTeam team;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumGlassPanel(
      bgAsset: SAsset.squadSectionBg,
      bgRemoteKey: 'series_squad_section_bg',
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: c.cyan, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.text,
                    fontWeight: FontWeight.w900,
                    fontStyle: FontStyle.italic,
                    fontSize: 13,
                    letterSpacing: .4,
                  ),
                ),
              ),
              Text(
                '${players.length} PLAYER${players.length == 1 ? '' : 'S'}',
                style: TextStyle(
                  color: c.cyan,
                  fontWeight: FontWeight.w800,
                  fontSize: 10.5,
                  letterSpacing: .3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _PlayerGrid(team: team, players: players),
        ],
      ),
    );
  }
}

class _PlayerGrid extends StatelessWidget {
  const _PlayerGrid({required this.team, required this.players});

  final SquadTeam team;
  final List<SquadPlayer> players;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 10.0;
        // Narrow phones get 2 columns so names like "Niroshan Dickwella" have
        // room instead of being crushed into a cramped 3-up grid; tablets keep
        // 3–4 columns.
        final w = constraints.maxWidth;
        final cols = w >= 440
            ? 4
            : w >= 340
                ? 3
                : 2;
        final width = (w - (cols - 1) * spacing) / cols;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final p in players)
              SizedBox(
                width: width,
                child: _SquadPlayerCard(
                  key: ValueKey(
                    '${team.identityKey}-'
                    '${p.id.isNotEmpty ? p.id : _normalizedPlayerKey(p.name)}',
                  ),
                  player: p,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SquadPlayerCard extends StatelessWidget {
  const _SquadPlayerCard({super.key, required this.player});

  final SquadPlayer player;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final roleTag = _roleTag(player);
    final captainTag = player.isCaptain
        ? 'C'
        : player.isViceCaptain
            ? 'VC'
            : null;
    final (first, last) = _splitName(player.name);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: c.isDark ? c.card.withValues(alpha: .45) : c.card,
        border: Border.all(color: c.cyan.withValues(alpha: .28)),
      ),
      child: Column(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              SeriesPlayerAvatar(
                name: player.name,
                imageUrl: player.imageUrl,
                size: 56,
              ),
              if (captainTag != null)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    width: 19,
                    height: 19,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: captainTag == 'C' ? c.warning : c.cyan,
                      shape: BoxShape.circle,
                      border: Border.all(color: c.bg, width: 1.5),
                    ),
                    child: Text(
                      captainTag,
                      style: TextStyle(
                        color: captainTag == 'C'
                            ? c.text
                            : Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 8.5,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            first,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: c.onImageText,
              fontWeight: FontWeight.w600,
              fontSize: 11,
              height: 1.05,
            ),
          ),
          Text(
            last.isEmpty ? ' ' : last,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: c.text,
              fontWeight: FontWeight.w900,
              fontSize: 12,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 7),
          if (roleTag != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: roleTag.$2.withValues(alpha: .16),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: roleTag.$2.withValues(alpha: .6)),
              ),
              child: Text(
                roleTag.$1,
                style: TextStyle(
                  color: roleTag.$2,
                  fontWeight: FontWeight.w900,
                  fontSize: 9,
                  letterSpacing: .3,
                ),
              ),
            ),
        ],
      ),
    );
  }

  static (String, String) _splitName(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return ('', '');
    if (parts.length == 1) return ('', parts.first);
    return (parts.first, parts.sublist(1).join(' '));
  }

  (String, Color)? _roleTag(SquadPlayer p) {
    switch (p.roleCode.toUpperCase()) {
      case 'WK':
        return ('WK', const Color(0xfff59e0b));
      case 'AR':
        return ('AR', const Color(0xff14b8a6));
      case 'BOWL':
        return ('BOWL', const Color(0xff60a5fa));
      case 'BAT':
        return ('BAT', const Color(0xff22d3ee));
    }
    final role = p.role.toLowerCase();
    if (p.isWicketKeeper || role.contains('wk') || role.contains('keeper')) {
      return ('WK', const Color(0xfff59e0b));
    }
    if (role.contains('all') && role.contains('round')) {
      return ('AR', const Color(0xff14b8a6));
    }
    if (role.contains('bowl')) {
      return ('BOWL', const Color(0xff60a5fa));
    }
    if (role.contains('bat')) {
      return ('BAT', const Color(0xff22d3ee));
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// Stats tab
// ---------------------------------------------------------------------------

