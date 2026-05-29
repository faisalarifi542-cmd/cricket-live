import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../models/api/api_match_detail_model.dart';
import '../../models/api/api_scorecard_model.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/api_state_widgets.dart';

class FantasyTab extends StatelessWidget {
  final ApiMatchDetail? matchDetail;
  final ApiScorecard? scorecard;

  const FantasyTab({super.key, this.matchDetail, this.scorecard});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 105),
      child: Column(
        children: [
          const SizedBox(height: 12),
          const FallbackBanner(message: 'Fantasy data not available from API — showing sample data'),
          const SizedBox(height: 6),
          _buildPitchReport(),
          const SizedBox(height: 12),
          _buildCaptainPicks(),
          const SizedBox(height: 12),
          _buildFantasyXI(),
          const SizedBox(height: 12),
          _buildTeamBalance(),
          const SizedBox(height: 12),
          _buildPlayerCredits(),
        ],
      ),
    );
  }

  Widget _buildPitchReport() {
    return GlassCard(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      borderRadius: 12,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Pitch Report', style: TextStyle(color: AppColors.cyan, fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          _buildPitchRow('Pace', 0.65, AppColors.green),
          const SizedBox(height: 8),
          _buildPitchRow('Spin', 0.45, AppColors.purple),
          const SizedBox(height: 8),
          _buildPitchRow('Batting', 0.75, AppColors.orange),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.cardBg2.withOpacity(0.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: AppColors.cyan, size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Good batting surface with some help for pace bowlers in early overs.',
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPitchRow(String label, double value, Color color) {
    return Row(
      children: [
        SizedBox(width: 60, child: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12))),
        const SizedBox(width: 8),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: value,
              backgroundColor: AppColors.cardBg2,
              valueColor: AlwaysStoppedAnimation(color),
              minHeight: 6,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text('${(value * 100).toInt()}%', style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildCaptainPicks() {
    return GlassCard(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      borderRadius: 12,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Captain & Vice Captain Picks', style: TextStyle(color: AppColors.cyan, fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          _buildPickCard('Captain Pick', 'Ishan Kishan', 'WK \u2022 SRH', '10.5 Cr', AppColors.orange),
          const SizedBox(height: 8),
          _buildPickCard('Vice Captain', 'Abhishek Sharma', 'BAT \u2022 SRH', '9.0 Cr', AppColors.blue),
          const SizedBox(height: 8),
          _buildPickCard('Differential', 'Abdul Samad', 'AR \u2022 SRH', '7.5 Cr', AppColors.purple),
        ],
      ),
    );
  }

  Widget _buildPickCard(String role, String name, String info, String credits, Color color) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withOpacity(0.2),
              border: Border.all(color: color.withOpacity(0.4)),
            ),
            child: const Icon(Icons.person, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(role, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
                Text(name, style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
                Text(info, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
              ],
            ),
          ),
          Text(credits, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _buildFantasyXI() {
    final players = [
      {'name': 'Ishan Kishan', 'role': 'WK', 'team': 'SRH', 'credits': '10.5'},
      {'name': 'Abhishek Sharma', 'role': 'BAT', 'team': 'SRH', 'credits': '9.0'},
      {'name': 'Travis Head', 'role': 'BAT', 'team': 'SRH', 'credits': '9.5'},
      {'name': 'Ruturaj Gaikwad', 'role': 'BAT', 'team': 'CSK', 'credits': '9.0'},
      {'name': 'Aiden Markram', 'role': 'AR', 'team': 'SRH', 'credits': '8.5'},
      {'name': 'R. Jadeja', 'role': 'AR', 'team': 'CSK', 'credits': '9.0'},
      {'name': 'Abdul Samad', 'role': 'AR', 'team': 'SRH', 'credits': '7.5'},
      {'name': 'T. Deshpande', 'role': 'BOWL', 'team': 'CSK', 'credits': '8.0'},
      {'name': 'M. Theekshana', 'role': 'BOWL', 'team': 'CSK', 'credits': '8.5'},
      {'name': 'B. Kumar', 'role': 'BOWL', 'team': 'SRH', 'credits': '8.5'},
      {'name': 'M. Pathirana', 'role': 'BOWL', 'team': 'CSK', 'credits': '8.0'},
    ];

    return GlassCard(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      borderRadius: 12,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Fantasy XI', style: TextStyle(color: AppColors.cyan, fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          ...players.map((p) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.cardBg2,
                  ),
                  child: const Icon(Icons.person, color: AppColors.textMuted, size: 16),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(p['name']!, style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w500)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.blue.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(p['role']!, style: const TextStyle(color: AppColors.blue, fontSize: 10, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 8),
                Text('${p['credits']} Cr', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ],
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildTeamBalance() {
    return GlassCard(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      borderRadius: 12,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Team Balance', style: TextStyle(color: AppColors.cyan, fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildRoleBadge('WK', '1', AppColors.green),
              _buildRoleBadge('BAT', '3', AppColors.orange),
              _buildRoleBadge('AR', '3', AppColors.purple),
              _buildRoleBadge('BOWL', '4', AppColors.blue),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('SRH: 6 players', style: TextStyle(color: AppColors.orange, fontSize: 12, fontWeight: FontWeight.w600)),
              const Text('CSK: 5 players', style: TextStyle(color: Color(0xFFFFCC00), fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRoleBadge(String role, String count, Color color) {
    return Column(
      children: [
        Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withOpacity(0.15),
            border: Border.all(color: color.withOpacity(0.4)),
          ),
          child: Center(
            child: Text(count, style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(height: 4),
        Text(role, style: const TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildPlayerCredits() {
    return GlassCard(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      borderRadius: 12,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Credits Used', style: TextStyle(color: AppColors.cyan, fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total Credits', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              const Text('96.0 / 100', style: TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: 0.96,
              backgroundColor: AppColors.cardBg2,
              valueColor: const AlwaysStoppedAnimation(AppColors.cyan),
              minHeight: 8,
            ),
          ),
        ],
      ),
    );
  }
}
