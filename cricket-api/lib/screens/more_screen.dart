import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../widgets/custom_header.dart';
import '../widgets/glass_card.dart';
import 'rankings_screen.dart';
import 'series_screen.dart';
import 'saved_screen.dart';
import 'downloads_screen.dart';
import 'match_alerts_screen.dart';
import 'settings_screen.dart';
import 'help_support_screen.dart';
import 'invite_friends_screen.dart';
import 'edit_profile_screen.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
      child: Column(
        children: [
          const CustomHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 90),
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const EditProfileScreen()),
                    ),
                    child: _buildProfileCard(),
                  ),
                  const SizedBox(height: 16),
                  _buildStatsRow(),
                  const SizedBox(height: 20),
                  _buildMenuList(context),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1A3A6C),
            Color(0xFF0D2247),
            Color(0xFF081838),
          ],
        ),
        border: Border.all(
          color: AppColors.borderColor.withOpacity(0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.blue.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [AppColors.blue.withOpacity(0.4), AppColors.cyan.withOpacity(0.2)],
              ),
              border: Border.all(color: AppColors.cyan.withOpacity(0.5), width: 2),
            ),
            child: const Icon(Icons.person, color: Colors.white, size: 32),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Arjun Reddy',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.verified, color: AppColors.cyan, size: 16),
                  ],
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.green.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.green.withOpacity(0.3)),
                  ),
                  child: const Text(
                    'Premium Member',
                    style: TextStyle(color: AppColors.green, fontSize: 10, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'arjun.reddy@email.com',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow() {
    final stats = [
      {'label': 'Matches\nFollowed', 'value': '24'},
      {'label': 'Saved\nItems', 'value': '56'},
      {'label': 'Downloads', 'value': '12'},
      {'label': 'Alerts', 'value': '8'},
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
                  Text(
                    s['value']!,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    s['label']!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMenuList(BuildContext context) {
    final items = [
      {'icon': Icons.bookmark_outline, 'label': 'Saved / Bookmarks', 'trailing': null},
      {'icon': Icons.download_outlined, 'label': 'Downloads', 'trailing': null},
      {'icon': Icons.notifications_outlined, 'label': 'Match Alerts', 'trailing': null},
      {'icon': Icons.settings_outlined, 'label': 'Settings', 'trailing': null},
      {'icon': Icons.help_outline, 'label': 'Help & Support', 'trailing': null},
      {'icon': Icons.star_outline, 'label': 'Rate CricketZone', 'trailing': null},
      {'icon': Icons.share_outlined, 'label': 'Invite Friends', 'trailing': 'Earn Rewards'},
    ];

    return GlassCard(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      borderRadius: 16,
      child: Column(
        children: [
          // Rankings shortcut
          _buildMenuRow(
            Icons.leaderboard_outlined,
            'Player Rankings',
            null,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const RankingsScreen()),
              );
            },
          ),
          _divider(),
          // Series shortcut
          _buildMenuRow(
            Icons.emoji_events_outlined,
            'Series',
            null,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SeriesScreen()),
              );
            },
          ),
          _divider(),
          ...items.asMap().entries.map((entry) {
            final item = entry.value;
            return Column(
              children: [
                _buildMenuRow(
                  item['icon'] as IconData,
                  item['label'] as String,
                  item['trailing'] as String?,
                  onTap: () => _onMenuTap(context, item['label'] as String),
                ),
                if (entry.key < items.length - 1) _divider(),
              ],
            );
          }),
        ],
      ),
    );
  }

  void _onMenuTap(BuildContext context, String label) {
    switch (label) {
      case 'Saved / Bookmarks':
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SavedScreen()));
        break;
      case 'Downloads':
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DownloadsScreen()));
        break;
      case 'Match Alerts':
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MatchAlertsScreen()));
        break;
      case 'Settings':
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
        break;
      case 'Help & Support':
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HelpSupportScreen()));
        break;
      case 'Rate CricketZone':
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.cardBg,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Rate CricketZone', style: TextStyle(color: AppColors.textPrimary)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Enjoying CricketZone? Rate us!', style: TextStyle(color: AppColors.textSecondary)),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (i) => Icon(Icons.star, color: i < 4 ? AppColors.orange : AppColors.textMuted, size: 32)),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Later', style: TextStyle(color: AppColors.textMuted))),
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Submit', style: TextStyle(color: AppColors.cyan))),
            ],
          ),
        );
        break;
      case 'Invite Friends':
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const InviteFriendsScreen()));
        break;
    }
  }

  Widget _buildMenuRow(IconData icon, String label, String? trailing, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: AppColors.textSecondary, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (trailing != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.cyan.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.cyan.withOpacity(0.3)),
                ),
                child: Text(
                  trailing,
                  style: const TextStyle(color: AppColors.cyan, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, color: AppColors.textMuted, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _divider() {
    return Divider(
      height: 1,
      color: AppColors.borderColor.withOpacity(0.2),
      indent: 52,
    );
  }
}
