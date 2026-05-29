import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';

class LoadingWidget extends StatelessWidget {
  final String? message;

  const LoadingWidget({super.key, this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation(AppColors.cyan),
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: 14),
            Text(
              message!,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

class ErrorRetryWidget extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const ErrorRetryWidget({
    super.key,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.red.withOpacity(0.15),
                border: Border.all(color: AppColors.red.withOpacity(0.3)),
              ),
              child: const Icon(Icons.wifi_off_rounded, color: AppColors.red, size: 26),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w500),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 18),
            GestureDetector(
              onTap: onRetry,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [AppColors.blue, Color(0xFF00C6FF)]),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(color: AppColors.blue.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2)),
                  ],
                ),
                child: const Text(
                  'Retry',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EmptyStateWidget extends StatelessWidget {
  final String message;
  final IconData icon;

  const EmptyStateWidget({
    super.key,
    required this.message,
    this.icon = Icons.sports_cricket,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.cardBg,
                border: Border.all(color: AppColors.borderColor.withOpacity(0.3)),
              ),
              child: Icon(icon, color: AppColors.textMuted, size: 26),
            ),
            const SizedBox(height: 14),
            Text(
              message,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class MatchCardShimmer extends StatefulWidget {
  const MatchCardShimmer({super.key});

  @override
  State<MatchCardShimmer> createState() => _MatchCardShimmerState();
}

class _MatchCardShimmerState extends State<MatchCardShimmer> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        final shimmer = AppColors.cardBg.withOpacity(0.3 + 0.3 * _controller.value);
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.cardBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.borderColor.withOpacity(0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _bar(shimmer, 100, 10),
              const SizedBox(height: 14),
              Row(
                children: [
                  _circle(shimmer, 28),
                  const SizedBox(width: 10),
                  _bar(shimmer, 60, 12),
                  const Spacer(),
                  _bar(shimmer, 50, 14),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _circle(shimmer, 28),
                  const SizedBox(width: 10),
                  _bar(shimmer, 60, 12),
                  const Spacer(),
                  _bar(shimmer, 50, 14),
                ],
              ),
              const SizedBox(height: 10),
              _bar(shimmer, 180, 10),
            ],
          ),
        );
      },
    );
  }

  Widget _bar(Color c, double w, double h) => Container(
        width: w,
        height: h,
        decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(4)),
      );

  Widget _circle(Color c, double s) => Container(
        width: s,
        height: s,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      );
}

class FallbackBanner extends StatelessWidget {
  final String message;
  const FallbackBanner({super.key, this.message = 'Data not available from API'});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFF9800).withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFF9800).withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: const Color(0xFFFF9800), size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Color(0xFFFF9800), fontSize: 11, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
