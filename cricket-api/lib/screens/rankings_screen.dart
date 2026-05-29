import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../data/mock_data.dart';
import '../models/ranking_model.dart';
import '../widgets/custom_header.dart';
import '../widgets/glass_card.dart';
import 'player_profile_screen.dart';

class RankingsScreen extends StatefulWidget {
  const RankingsScreen({super.key});

  @override
  State<RankingsScreen> createState() => _RankingsScreenState();
}

class _RankingsScreenState extends State<RankingsScreen> {
  int _activeSegment = 0;
  final _segments = ['Batting', 'Bowling', 'All Rounders'];

  @override
  Widget build(BuildContext context) {
    final rankings = _activeSegment == 0
        ? MockData.battingRankings
        : MockData.bowlingRankings;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CustomHeader(showBackButton: true),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  'Player Rankings',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _buildSegmentedControl(),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: rankings.length,
                  itemBuilder: (context, index) {
                    return _buildRankingRow(rankings[index]);
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: Text(
                    'Rankings updated after every match',
                    style: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSegmentedControl() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borderColor.withOpacity(0.4)),
      ),
      child: Row(
        children: _segments.asMap().entries.map((entry) {
          final isActive = entry.key == _activeSegment;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _activeSegment = entry.key),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isActive ? AppColors.blue.withOpacity(0.2) : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  border: isActive ? Border.all(color: AppColors.blue.withOpacity(0.4)) : null,
                ),
                child: Text(
                  entry.value,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isActive ? AppColors.textPrimary : AppColors.textMuted,
                    fontSize: 13,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildRankingRow(RankingModel player) {
    Color changeColor;
    IconData changeIcon;
    if (player.change > 0) {
      changeColor = AppColors.green;
      changeIcon = Icons.arrow_upward;
    } else if (player.change < 0) {
      changeColor = AppColors.red;
      changeIcon = Icons.arrow_downward;
    } else {
      changeColor = AppColors.textMuted;
      changeIcon = Icons.remove;
    }

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => PlayerProfileScreen(
            playerName: player.name,
            team: player.country,
            role: _activeSegment == 0 ? 'Batter' : _activeSegment == 1 ? 'Bowler' : 'All-Rounder',
          ),
        ));
      },
      child: GlassCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      borderRadius: 14,
      child: Row(
        children: [
          // Rank
          SizedBox(
            width: 28,
            child: Text(
              '${player.rank}',
              style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          // Player avatar
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.cardBg2,
              border: Border.all(color: AppColors.borderColor.withOpacity(0.4)),
            ),
            child: const Icon(Icons.person, color: AppColors.textMuted, size: 22),
          ),
          const SizedBox(width: 12),
          // Name & team
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  player.name,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      width: 14,
                      height: 10,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(2),
                        color: AppColors.cardBg2,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${player.teamShort} \u2022 ${player.country}',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Rating
          Text(
            '${player.rating}',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 8),
          // Change
          Row(
            children: [
              Icon(changeIcon, color: changeColor, size: 14),
              if (player.change != 0)
                Text(
                  '${player.change.abs()}',
                  style: TextStyle(color: changeColor, fontSize: 12, fontWeight: FontWeight.w600),
                ),
            ],
          ),
        ],
      ),
    ),
    );
  }
}
