import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../widgets/custom_header.dart';
import '../widgets/glass_card.dart';

class MatchAlertsScreen extends StatefulWidget {
  const MatchAlertsScreen({super.key});

  @override
  State<MatchAlertsScreen> createState() => _MatchAlertsScreenState();
}

class _MatchAlertsScreenState extends State<MatchAlertsScreen> {
  final Map<String, bool> _alerts = {
    'MI vs RR \u2022 Match 64': true,
    'RCB vs KKR \u2022 Match 65': true,
    'DC vs LSG \u2022 Match 66': false,
    'PBKS vs GT \u2022 Match 67': false,
  };

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
                child: Text('Match Alerts', style: TextStyle(color: AppColors.textPrimary, fontSize: 22, fontWeight: FontWeight.w700)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text('Get notified before matches start', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: _alerts.entries.map((entry) {
                    return GlassCard(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      borderRadius: 14,
                      child: Row(
                        children: [
                          Icon(Icons.notifications_active, color: entry.value ? AppColors.cyan : AppColors.textMuted, size: 22),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(entry.key, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 2),
                                Text('IPL 2026 \u2022 7:30 PM', style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                              ],
                            ),
                          ),
                          Switch(
                            value: entry.value,
                            onChanged: (val) => setState(() => _alerts[entry.key] = val),
                            activeColor: AppColors.cyan,
                            inactiveTrackColor: AppColors.cardBg2,
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
