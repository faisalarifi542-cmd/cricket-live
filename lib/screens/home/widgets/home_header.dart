part of '../home_screen.dart';

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.onBell});

  final VoidCallback onBell;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final logoSize = context.w <= 400 ? 30.0 : 34.0;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: SizedBox(
        height: 48,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            RichText(
              text: TextSpan(
                style: TextStyle(
                  fontSize: logoSize,
                  fontWeight: FontWeight.w900,
                  fontStyle: FontStyle.italic,
                  letterSpacing: -1.2,
                  height: 1.1,
                ),
                children: [
                  TextSpan(text: 'CRIC', style: TextStyle(color: c.text)),
                  TextSpan(
                    text: 'PRO',
                    style: TextStyle(
                      color: c.cyan,
                      shadows: [
                        Shadow(
                            color: c.cyan.withValues(alpha: .6), blurRadius: 18),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            _NotificationButton(onTap: onBell),
          ],
        ),
      ),
    );
  }
}

/// Circular glass icon button used in the header. The notification button is a
/// separate widget because it also paints the unread dot.
class _NotificationButton extends StatelessWidget {
  const _NotificationButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 42,
        height: 42,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c.isDark ? c.card.withValues(alpha: .42) : c.card,
                border: Border.all(
                    color: c.cyan.withValues(alpha: .75), width: 1.3),
                boxShadow: c.isDark
                    ? [
                        BoxShadow(
                          color: c.cyan.withValues(alpha: .14),
                          blurRadius: 14,
                          spreadRadius: -3,
                        ),
                      ]
                    : null,
              ),
              alignment: Alignment.center,
              child: Icon(Icons.notifications_none_rounded,
                  color: c.text, size: 21),
            ),
            // Notification dot.
            Positioned(
              top: 9,
              right: 10,
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: c.cyan,
                  shape: BoxShape.circle,
                  border: Border.all(color: c.bg, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                        color: c.cyan.withValues(alpha: .85), blurRadius: 7),
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

