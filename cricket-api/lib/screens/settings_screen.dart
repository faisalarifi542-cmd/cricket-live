import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../widgets/custom_header.dart';
import '../widgets/glass_card.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _pushNotifications = true;
  bool _matchAlerts = true;
  bool _darkMode = true;
  bool _autoPlayVideos = false;

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
                child: Text('Settings', style: TextStyle(color: AppColors.textPrimary, fontSize: 22, fontWeight: FontWeight.w700)),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      const Text('Notifications', style: TextStyle(color: AppColors.cyan, fontSize: 14, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      _buildToggle('Push Notifications', _pushNotifications, (v) => setState(() => _pushNotifications = v)),
                      _buildToggle('Match Alerts', _matchAlerts, (v) => setState(() => _matchAlerts = v)),
                      const SizedBox(height: 20),
                      const Text('Appearance', style: TextStyle(color: AppColors.cyan, fontSize: 14, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      _buildToggle('Dark Mode', _darkMode, (v) => setState(() => _darkMode = v)),
                      const SizedBox(height: 20),
                      const Text('Media', style: TextStyle(color: AppColors.cyan, fontSize: 14, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      _buildToggle('Auto-Play Videos', _autoPlayVideos, (v) => setState(() => _autoPlayVideos = v)),
                      const SizedBox(height: 20),
                      const Text('General', style: TextStyle(color: AppColors.cyan, fontSize: 14, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      _buildMenuRow(Icons.language, 'Language', 'English'),
                      _buildMenuRow(Icons.data_usage, 'Data Usage', 'Wi-Fi only'),
                      _buildMenuRow(Icons.storage, 'Clear Cache', '24 MB'),
                      _buildMenuRow(Icons.info_outline, 'App Version', '1.0.0'),
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

  Widget _buildToggle(String label, bool value, ValueChanged<bool> onChanged) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      borderRadius: 12,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500)),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.cyan,
            inactiveTrackColor: AppColors.cardBg2,
          ),
        ],
      ),
    );
  }

  Widget _buildMenuRow(IconData icon, String label, String value) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      borderRadius: 12,
      child: Row(
        children: [
          Icon(icon, color: AppColors.textSecondary, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500))),
          Text(value, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right, color: AppColors.textMuted, size: 18),
        ],
      ),
    );
  }
}
