import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../widgets/custom_header.dart';
import '../widgets/glass_card.dart';

class HelpSupportScreen extends StatelessWidget {
  const HelpSupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final faqs = [
      {'q': 'How do I set match alerts?', 'a': 'Go to More > Match Alerts and toggle alerts for upcoming matches.'},
      {'q': 'How do I download videos?', 'a': 'Premium members can download videos by tapping the download icon on any video.'},
      {'q': 'How do I change my profile?', 'a': 'Go to More > tap your profile card at the top to edit your details.'},
      {'q': 'Is CricketZone free?', 'a': 'CricketZone is free with ads. Go Premium for an ad-free experience with extra features.'},
    ];

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
                child: Text('Help & Support', style: TextStyle(color: AppColors.textPrimary, fontSize: 22, fontWeight: FontWeight.w700)),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      // Contact
                      GlassCard(
                        padding: const EdgeInsets.all(16),
                        borderRadius: 14,
                        child: Column(
                          children: [
                            Icon(Icons.headset_mic, color: AppColors.cyan, size: 36),
                            const SizedBox(height: 8),
                            const Text('Need help?', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            const Text('Our support team is available 24/7', style: TextStyle(color: AppColors.textMuted, fontSize: 12), textAlign: TextAlign.center),
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: AppColors.blue.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.blue.withOpacity(0.4)),
                              ),
                              child: const Text('Contact Support', textAlign: TextAlign.center, style: TextStyle(color: AppColors.blue, fontSize: 13, fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text('FAQ', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 12),
                      ...faqs.map((faq) => _buildFaqItem(faq['q']!, faq['a']!)),
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

  Widget _buildFaqItem(String question, String answer) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      borderRadius: 12,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(question, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(answer, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.4)),
        ],
      ),
    );
  }
}
