part of '../home_screen.dart';

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.onBell});

  final VoidCallback onBell;

  @override
  Widget build(BuildContext context) {
    // Consistent header dimensions on every phone width (target reads the same
    // at both scales): a slightly larger logo and steady top/bottom padding, so
    // the wordmark and bell carry more visual weight and breathe from the top.
    const logoSize = 36.0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 16, 2, 10),
      child: SizedBox(
        height: 56,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Shared CRICPRO wordmark — same renderer as Matches/Series/More so
            // the logo is identical across every screen (no per-screen size/
            // letterSpacing/glow divergence).
            const CricLogo(size: logoSize),
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
    return Semantics(
      button: true,
      label: 'Notifications',
      child: Tooltip(
        message: 'Notifications',
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Material(
              color: Colors.transparent,
              shape: CircleBorder(
                side: BorderSide(
                  color: c.cyan.withValues(alpha: .72),
                  width: 1.2,
                ),
              ),
              child: InkWell(
                onTap: onTap,
                customBorder: const CircleBorder(),
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(
                    Icons.notifications_none_rounded,
                    color: c.text,
                    size: 25,
                  ),
                ),
              ),
            ),
            // Unread dot — cyan, bordered with the page bg so it punches through
            // the circular button cleanly.
            Positioned(
              top: 1,
              right: 1,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: c.cyan,
                  shape: BoxShape.circle,
                  border: Border.all(color: c.bg, width: 1.4),
                  boxShadow: [
                    BoxShadow(
                      color: c.cyan.withValues(alpha: .55),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hero (featured) match carousel
// ---------------------------------------------------------------------------
