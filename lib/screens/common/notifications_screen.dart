import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../components.dart';

/// Notifications are not yet wired to a real backend feed. Until a push /
/// `/notifications` API is exposed we render a clean empty state instead of
/// fabricating Smith/Bumrah/Rohit/Pant alerts so the app stays real-data
/// driven.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: c.bgGradient),
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.fromLTRB(context.horizontalPadding, 18,
                context.horizontalPadding, context.detailBottomPadding),
            children: [
              AppHeader(
                leading: IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.arrow_back_rounded, color: c.text)),
                title: 'Notifications',
              ),
              const SizedBox(height: 40),
              PremiumCard(
                padding: const EdgeInsets.all(28),
                child: Column(
                  children: [
                    Icon(Icons.notifications_off_outlined,
                        color: c.cyan, size: 56),
                    const SizedBox(height: 14),
                    Text(
                      'No notifications yet',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: c.text,
                        fontWeight: FontWeight.w900,
                        fontSize: context.sp(22),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "We'll alert you here when matches you follow have wickets, milestones or important updates.",
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
