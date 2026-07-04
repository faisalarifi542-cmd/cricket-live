part of '../home_screen.dart';

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.onBell});

  final VoidCallback onBell;

  @override
  Widget build(BuildContext context) {
    final logoSize = context.w <= 400 ? 30.0 : 34.0;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: SizedBox(
        height: 48,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Shared CRICPRO wordmark — same renderer as Matches/Series/More so
            // the logo is identical across every screen (no per-screen size/
            // letterSpacing/glow divergence).
            CricLogo(size: logoSize),
            const Spacer(),
            _NotificationButton(onTap: onBell),
          ],
        ),
      ),
    );
  }
}

/// Notification bell built on the shared [GlowIconButton] so it matches the
/// bell used on Matches/Series/More, with a cyan unread dot overlaid to retain
/// the Home screen's "new notifications" indicator.
class _NotificationButton extends StatelessWidget {
  const _NotificationButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        GlowIconButton(
          icon: Icons.notifications_none_rounded,
          onTap: onTap,
        ),
        // Unread dot — cyan, bordered with the page bg so it punches through
        // the circular button cleanly.
        Positioned(
          top: 2,
          right: 2,
          child: Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: c.cyan,
              shape: BoxShape.circle,
              border: Border.all(color: c.bg, width: 1.5),
              boxShadow: [
                BoxShadow(color: c.cyan.withValues(alpha: .85), blurRadius: 7),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Hero (featured) match carousel
// ---------------------------------------------------------------------------

