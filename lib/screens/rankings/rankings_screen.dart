import 'package:flutter/material.dart';
import '../../app_theme.dart';

class RankingsScreen extends StatefulWidget {
  const RankingsScreen({super.key});

  @override
  State<RankingsScreen> createState() => _RankingsScreenState();
}

class _RankingsScreenState extends State<RankingsScreen> {
  String category = 'BATSMEN';
  String format = 'TEST';

  final categories = ['BATSMEN', 'BOWLERS', 'ALL-ROUNDERS', 'TEAMS'];
  final formats = ['TEST', 'ODI', 'T20'];

  List<RankingPlayerData> get players {
    // Premium ranking data based on category and format
    if (category == 'BATSMEN' && format == 'TEST') {
      return [
        RankingPlayerData(1, 'Joe Root', '🏴 England',
            'assets/images/player_joe_root.png', 908, 0),
        RankingPlayerData(2, 'Harry Brook', '🏴 England',
            'assets/images/player_harry_brook.png', 868, 1),
        RankingPlayerData(3, 'Kane Williamson', '🇳🇿 New Zealand',
            'assets/images/player_kane_williamson.png', 850, -1),
        RankingPlayerData(4, 'Steven Smith', '🇦🇺 Australia',
            'assets/images/player_steven_smith.png', 816, 0),
        RankingPlayerData(5, 'Yashasvi Jaiswal', '🇮🇳 India',
            'assets/images/player_yashasvi_jaiswal.png', 791, 2),
        RankingPlayerData(6, 'Kamindu Mendis', '🇱🇰 Sri Lanka',
            'assets/images/player_kamindu_mendis.png', 781, 1),
      ];
    }
    // Default fallback
    return [
      RankingPlayerData(1, 'Rohit Sharma', '🇮🇳 India',
          'assets/images/player_rohit_sharma.png', 781, 0),
      RankingPlayerData(2, 'Ibrahim Zadran', '🇦🇫 Afghanistan',
          'assets/images/player_ibrahim_zadran.png', 774, 1),
      RankingPlayerData(3, 'Daryl Mitchell', '🇳🇿 New Zealand',
          'assets/images/player_daryl_mitchell.png', 746, -1),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: c.bgGradient),
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              context.horizontalPadding,
              18,
              context.horizontalPadding,
              context.detailBottomPadding,
            ),
            children: [
              // Header
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon:
                        Icon(Icons.arrow_back_rounded, color: c.text, size: 28),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'ICC Men\'s Ranking',
                      style: TextStyle(
                        color: c.text,
                        fontWeight: FontWeight.w900,
                        fontSize: context.sp(28),
                      ),
                    ),
                  ),
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: c.card.withValues(alpha: .5),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: c.border),
                    ),
                    child: Icon(Icons.tune_rounded, color: c.cyan, size: 24),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Dropdown Pills Row
              Row(
                children: [
                  Expanded(
                    child: _DropdownPill(
                      icon: Icons.person_outline_rounded,
                      label: category,
                      onTap: () => _showCategoryPicker(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _DropdownPill(
                      icon: Icons.sports_cricket_rounded,
                      label: format,
                      onTap: () => _showFormatPicker(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Ranking Cards
              for (final player in players)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _PremiumRankingCard(player: player),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCategoryPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: context.cric.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final cat in categories)
              ListTile(
                title: Text(cat, style: TextStyle(color: context.cric.text)),
                trailing: category == cat
                    ? Icon(Icons.check, color: context.cric.cyan)
                    : null,
                onTap: () {
                  setState(() => category = cat);
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _showFormatPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: context.cric.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final fmt in formats)
              ListTile(
                title: Text(fmt, style: TextStyle(color: context.cric.text)),
                trailing: format == fmt
                    ? Icon(Icons.check, color: context.cric.cyan)
                    : null,
                onTap: () {
                  setState(() => format = fmt);
                  Navigator.pop(context);
                },
              ),
          ],
        ),
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
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: c.card.withValues(alpha: .7),
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
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: c.text,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
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
  const _PremiumRankingCard({required this.player});

  final RankingPlayerData player;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final isFirst = player.rank == 1;

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
            color: Colors.black.withValues(alpha: .28),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
          if (isFirst)
            BoxShadow(
              color: c.cyan.withValues(alpha: .25),
              blurRadius: 20,
              spreadRadius: 2,
            ),
        ],
      ),
      child: Row(
        children: [
          // Rank with crown for #1
          SizedBox(
            width: 50,
            child: Column(
              children: [
                if (isFirst)
                  Icon(Icons.emoji_events_rounded, color: c.cyan, size: 28),
                if (isFirst) const SizedBox(height: 4),
                Text(
                  '${player.rank}',
                  style: TextStyle(
                    color: isFirst ? c.cyan : c.text,
                    fontWeight: FontWeight.w900,
                    fontSize: 32,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),

          // Player Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  player.name,
                  style: TextStyle(
                    color: c.text,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  player.country,
                  style: TextStyle(
                    color: c.muted,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      '${player.rating}',
                      style: TextStyle(
                        color: c.cyan,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'RATING',
                      style: TextStyle(
                        color: c.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Movement indicator
          if (player.movement != 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: player.movement > 0
                    ? Colors.green.withValues(alpha: .15)
                    : Colors.red.withValues(alpha: .15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    player.movement > 0
                        ? Icons.arrow_upward_rounded
                        : Icons.arrow_downward_rounded,
                    color: player.movement > 0 ? Colors.green : Colors.red,
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${player.movement.abs()}',
                    style: TextStyle(
                      color: player.movement > 0 ? Colors.green : Colors.red,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(width: 12),

          // Player Image
          Container(
            width: 80,
            height: 80,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.border, width: 1.5),
              color: c.card2,
            ),
            child: Image.asset(
              player.asset,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Center(
                child: Text(
                  player.name.substring(0, 1),
                  style: TextStyle(
                    color: c.text,
                    fontWeight: FontWeight.w900,
                    fontSize: 32,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class RankingPlayerData {
  final int rank;
  final String name;
  final String country;
  final String asset;
  final int rating;
  final int movement; // positive = up, negative = down, 0 = no change

  RankingPlayerData(
    this.rank,
    this.name,
    this.country,
    this.asset,
    this.rating,
    this.movement,
  );
}
