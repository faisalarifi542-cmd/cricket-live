import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../widgets/custom_header.dart';
import '../widgets/glass_card.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final notifications = [
      {'title': 'SRH won by 5 wickets!', 'desc': 'Match 63 \u2022 IPL 2026 has ended', 'time': '2h ago', 'icon': Icons.sports_cricket, 'color': AppColors.green},
      {'title': 'MI vs RR starts in 1 hour', 'desc': 'Match 64 \u2022 IPL 2026', 'time': '3h ago', 'icon': Icons.timer, 'color': AppColors.orange},
      {'title': 'Ishan Kishan hits 50!', 'desc': 'SRH vs CSK \u2022 64* off 42 balls', 'time': '4h ago', 'icon': Icons.star, 'color': AppColors.cyan},
      {'title': 'Wicket! Travis Head dismissed', 'desc': 'SRH 85/3 in 11.2 overs', 'time': '5h ago', 'icon': Icons.sports_baseball, 'color': AppColors.red},
      {'title': 'Points Table Updated', 'desc': 'IPL 2026 standings after Match 63', 'time': '6h ago', 'icon': Icons.leaderboard, 'color': AppColors.blue},
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
                child: Text('Notifications', style: TextStyle(color: AppColors.textPrimary, fontSize: 22, fontWeight: FontWeight.w700)),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: notifications.length,
                  itemBuilder: (context, index) {
                    final n = notifications[index];
                    return GlassCard(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(14),
                      borderRadius: 14,
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: (n['color'] as Color).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(n['icon'] as IconData, color: n['color'] as Color, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(n['title'] as String, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 2),
                                Text(n['desc'] as String, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                              ],
                            ),
                          ),
                          Text(n['time'] as String, style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
