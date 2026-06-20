import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../widgets/custom_header.dart';
import '../widgets/glass_card.dart';

class RewardsScreen extends StatelessWidget {
  const RewardsScreen({super.key});

  @override
  Widget build(BuildContext context) {
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
                child: Text('Earn Rewards', style: TextStyle(color: AppColors.textPrimary, fontSize: 22, fontWeight: FontWeight.w700)),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      // Points balance
                      GlassCard(
                        padding: const EdgeInsets.all(20),
                        borderRadius: 18,
                        child: Column(
                          children: [
                            const Text('Your Points', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                            const SizedBox(height: 4),
                            const Text('2,450', style: TextStyle(color: AppColors.cyan, fontSize: 36, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 4),
                            const Text('points', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Daily tasks
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Daily Tasks', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(height: 10),
                      _buildTask('Open the app daily', '+10 pts', true),
                      _buildTask('Watch a video highlight', '+20 pts', false),
                      _buildTask('Read 2 articles', '+15 pts', false),
                      _buildTask('Predict a match result', '+25 pts', false),
                      const SizedBox(height: 16),
                      // Redeem
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Redeem', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(height: 10),
                      _buildRedeemCard('1 Week Premium', '500 pts'),
                      _buildRedeemCard('1 Month Premium', '1,500 pts'),
                      _buildRedeemCard('Exclusive Badge', '1,000 pts'),
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

  Widget _buildTask(String task, String points, bool completed) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(12),
      borderRadius: 12,
      child: Row(
        children: [
          Icon(completed ? Icons.check_circle : Icons.radio_button_unchecked, color: completed ? AppColors.green : AppColors.textMuted, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(task, style: TextStyle(color: completed ? AppColors.textMuted : AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500, decoration: completed ? TextDecoration.lineThrough : null)),
          ),
          Text(points, style: TextStyle(color: completed ? AppColors.textMuted : AppColors.cyan, fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _buildRedeemCard(String title, String cost) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      borderRadius: 12,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.purple.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.card_giftcard, color: AppColors.purple, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.cyan.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.cyan.withOpacity(0.3)),
            ),
            child: Text(cost, style: const TextStyle(color: AppColors.cyan, fontSize: 11, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}
