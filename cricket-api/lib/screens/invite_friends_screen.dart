import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../widgets/custom_header.dart';
import '../widgets/glass_card.dart';

class InviteFriendsScreen extends StatelessWidget {
  const InviteFriendsScreen({super.key});

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
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      const SizedBox(height: 24),
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.cyan.withOpacity(0.15),
                          border: Border.all(color: AppColors.cyan.withOpacity(0.4), width: 2),
                        ),
                        child: const Icon(Icons.group_add, color: AppColors.cyan, size: 36),
                      ),
                      const SizedBox(height: 16),
                      const Text('Invite Friends', style: TextStyle(color: AppColors.textPrimary, fontSize: 22, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      const Text(
                        'Share CricketZone with your friends and earn rewards!',
                        style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      // Referral code
                      GlassCard(
                        padding: const EdgeInsets.all(16),
                        borderRadius: 14,
                        child: Column(
                          children: [
                            const Text('Your Referral Code', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              decoration: BoxDecoration(
                                color: AppColors.cardBg2,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: AppColors.cyan.withOpacity(0.3)),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Text('CRICKET2026', style: TextStyle(color: AppColors.cyan, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 2)),
                                  const SizedBox(width: 12),
                                  Icon(Icons.copy, color: AppColors.cyan, size: 18),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Share buttons
                      Row(
                        children: [
                          Expanded(child: _buildShareButton(Icons.message, 'WhatsApp', const Color(0xFF25D366))),
                          const SizedBox(width: 10),
                          Expanded(child: _buildShareButton(Icons.telegram, 'Telegram', const Color(0xFF0088CC))),
                          const SizedBox(width: 10),
                          Expanded(child: _buildShareButton(Icons.share, 'More', AppColors.blue)),
                        ],
                      ),
                      const SizedBox(height: 24),
                      // Rewards
                      GlassCard(
                        padding: const EdgeInsets.all(16),
                        borderRadius: 14,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Rewards', style: TextStyle(color: AppColors.cyan, fontSize: 14, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 12),
                            _buildRewardRow('Invite 3 friends', '1 month free Premium', false),
                            _buildRewardRow('Invite 5 friends', 'Exclusive badge', false),
                            _buildRewardRow('Invite 10 friends', '3 months free Premium', false),
                          ],
                        ),
                      ),
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

  Widget _buildShareButton(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildRewardRow(String target, String reward, bool claimed) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(claimed ? Icons.check_circle : Icons.circle_outlined, color: claimed ? AppColors.green : AppColors.textMuted, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(target, style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
                Text(reward, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
