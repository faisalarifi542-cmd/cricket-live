import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../widgets/custom_header.dart';
import '../widgets/glass_card.dart';

class PlayerProfileScreen extends StatelessWidget {
  final String playerName;
  final String? team;
  final String? role;

  const PlayerProfileScreen({
    super.key,
    required this.playerName,
    this.team,
    this.role,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
        child: SafeArea(
          child: Column(
            children: [
              const CustomHeader(showBackButton: true),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      const SizedBox(height: 8),
                      _buildProfileHeader(),
                      const SizedBox(height: 16),
                      _buildStatsGrid(),
                      const SizedBox(height: 16),
                      _buildCareerStats(),
                      const SizedBox(height: 16),
                      _buildRecentForm(),
                      const SizedBox(height: 16),
                      _buildBio(),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileHeader() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1A3A6C),
            const Color(0xFF0D2247),
            const Color(0xFF081838),
          ],
        ),
        border: Border.all(color: AppColors.borderColor.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(color: AppColors.blue.withOpacity(0.1), blurRadius: 20, offset: const Offset(0, 8)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [AppColors.blue.withOpacity(0.4), AppColors.cyan.withOpacity(0.2)],
              ),
              border: Border.all(color: AppColors.cyan.withOpacity(0.5), width: 2),
            ),
            child: const Icon(Icons.person, color: Colors.white, size: 40),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  playerName,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                if (team != null)
                  Text(team!, style: const TextStyle(color: AppColors.textMuted, fontSize: 13)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.blue.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.blue.withOpacity(0.3)),
                  ),
                  child: Text(
                    role ?? 'Batter',
                    style: const TextStyle(color: AppColors.blue, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsGrid() {
    final stats = [
      {'label': 'Matches', 'value': '156'},
      {'label': 'Runs', 'value': '4,832'},
      {'label': 'Average', 'value': '38.5'},
      {'label': 'Strike Rate', 'value': '135.2'},
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: stats.map((s) {
          return Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.cardBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.borderColor.withOpacity(0.4)),
              ),
              child: Column(
                children: [
                  Text(s['value']!, style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(s['label']!, style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCareerStats() {
    return GlassCard(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(14),
      borderRadius: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Career Stats', style: TextStyle(color: AppColors.cyan, fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          _buildStatRow('T20I Matches', '78'),
          _buildStatRow('T20I Runs', '2,105'),
          _buildStatRow('T20I Highest', '89*'),
          _buildStatRow('IPL Matches', '78'),
          _buildStatRow('IPL Runs', '2,727'),
          _buildStatRow('IPL Highest', '99'),
          _buildStatRow('50s / 100s', '18 / 1'),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          Text(value, style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildRecentForm() {
    return GlassCard(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(14),
      borderRadius: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Recent Form', style: TextStyle(color: AppColors.cyan, fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: ['64*', '23', '45', '12', '78'].map((score) {
              final value = int.tryParse(score.replaceAll('*', '')) ?? 0;
              return Column(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: value >= 50
                          ? AppColors.green.withOpacity(0.2)
                          : value >= 30
                              ? AppColors.orange.withOpacity(0.15)
                              : AppColors.cardBg2,
                      border: Border.all(
                        color: value >= 50
                            ? AppColors.green.withOpacity(0.5)
                            : value >= 30
                                ? AppColors.orange.withOpacity(0.4)
                                : AppColors.borderColor.withOpacity(0.3),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        score,
                        style: TextStyle(
                          color: value >= 50 ? AppColors.green : AppColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text('IPL', style: TextStyle(color: AppColors.textMuted, fontSize: 9)),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildBio() {
    return GlassCard(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(14),
      borderRadius: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('About', style: TextStyle(color: AppColors.cyan, fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(
            '$playerName is a dynamic cricket player known for explosive batting and quick-fire innings. With a proven track record in both domestic and international cricket, they have established themselves as one of the premier batters in the modern game.',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.6),
          ),
        ],
      ),
    );
  }
}
