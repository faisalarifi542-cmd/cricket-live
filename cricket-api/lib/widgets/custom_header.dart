import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../screens/premium_screen.dart';
import '../screens/notifications_screen.dart';
import 'app_logo.dart';

class CustomHeader extends StatelessWidget {
  final bool showBackButton;
  final bool showPremiumButton;
  final VoidCallback? onBack;

  const CustomHeader({
    super.key,
    this.showBackButton = false,
    this.showPremiumButton = false,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: SizedBox(
        height: 40,
        child: Row(
          children: [
            if (showBackButton)
              GestureDetector(
                onTap: onBack ?? () => Navigator.of(context).pop(),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.cardBg.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppColors.borderColor.withOpacity(0.4),
                    ),
                  ),
                  child: const Icon(
                    Icons.arrow_back_ios_new,
                    color: AppColors.textPrimary,
                    size: 14,
                  ),
                ),
              ),
            if (showBackButton) const SizedBox(width: 6),
            const Expanded(child: AppLogo(compact: true)),
            if (showPremiumButton) ...[
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PremiumScreen())),
                child: _buildPremiumButton(),
              ),
            ],
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsScreen())),
              child: _buildNotificationBell(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPremiumButton() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.blue, Color(0xFF00C6FF)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.cyan.withOpacity(0.5),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.blue.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('👑', style: TextStyle(fontSize: 12)),
          SizedBox(width: 4),
          Text(
            'Go Premium',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationBell() {
    return Stack(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppColors.cardBg.withOpacity(0.4),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            Icons.notifications_outlined,
            color: AppColors.textPrimary,
            size: 20,
          ),
        ),
        Positioned(
          right: 5,
          top: 5,
          child: Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: AppColors.cyan,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.cyan.withOpacity(0.6),
                  blurRadius: 3,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
