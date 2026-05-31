import 'package:flutter/material.dart';
import '../../app_theme.dart';
import '../../components.dart';

/// Highlights remains in the navigation as a destination, but no real
/// Cricbuzz `/highlights` endpoint is exposed by the backend yet. Until that
/// data is available we render a clean empty state instead of fake video rows
/// so the rest of the app stays real-data-driven.
class HighlightsScreen extends StatelessWidget {
  const HighlightsScreen({
    super.key,
    required this.onOpenNotifications,
  });

  final VoidCallback onOpenNotifications;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: c.bgGradient),
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              context.horizontalPadding,
              18,
              context.horizontalPadding,
              context.detailBottomPadding,
            ),
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon:
                        Icon(Icons.arrow_back_rounded, color: c.text, size: 28),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Highlights',
                          style: TextStyle(
                            color: c.text,
                            fontWeight: FontWeight.w900,
                            fontSize: context.sp(28),
                          ),
                        ),
                        Text(
                          'Relive the best cricket moments',
                          style: TextStyle(
                            color: c.muted,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  GlowIconButton(
                    icon: Icons.notifications_none_rounded,
                    onTap: onOpenNotifications,
                  ),
                ],
              ),
              const SizedBox(height: 40),
              PremiumCard(
                padding: const EdgeInsets.all(28),
                child: Column(
                  children: [
                    Icon(Icons.movie_filter_outlined,
                        color: c.cyan, size: 56),
                    const SizedBox(height: 14),
                    Text(
                      'Highlights coming soon',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: c.text,
                        fontWeight: FontWeight.w900,
                        fontSize: context.sp(22),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Match highlights and short-form clips will appear here once they are available from the data provider.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: c.muted,
                        height: 1.5,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
