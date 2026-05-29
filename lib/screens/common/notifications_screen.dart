import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../components.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final today = [
      (
        'Match Alert',
        'India vs Australia starts in 30 minutes',
        Icons.notifications_active_outlined
      ),
      (
        'Wicket Alert',
        'Bumrah removes Smith for 12',
        Icons.sports_cricket_rounded
      ),
      (
        'Reminder',
        'Series calendar sync confirmed',
        Icons.calendar_month_rounded
      ),
    ];
    final yesterday = [
      (
        'Four Alert',
        'Rohit Sharma reaches 100 with a boundary',
        Icons.flash_on_rounded
      ),
      (
        'Six Alert',
        'Pant launches Starc into the second tier',
        Icons.local_fire_department_outlined
      ),
    ];
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
                trailing: [
                  TextButton(
                      onPressed: () {}, child: const Text('Mark all as read'))
                ],
              ),
              const SizedBox(height: 22),
              _NotificationGroup(title: 'Today', items: today),
              const SizedBox(height: 22),
              _NotificationGroup(title: 'Yesterday', items: yesterday),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationGroup extends StatelessWidget {
  const _NotificationGroup({required this.title, required this.items});

  final String title;
  final List<(String, String, IconData)> items;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: TextStyle(
                color: c.text, fontSize: 22, fontWeight: FontWeight.w900)),
        const SizedBox(height: 12),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: PremiumCard(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                      radius: 22,
                      backgroundColor: c.card2,
                      child: Icon(item.$3, color: c.cyan)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.$1,
                            style: TextStyle(
                                color: c.text, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        Text(item.$2,
                            style: TextStyle(color: c.muted, height: 1.45)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          )
      ],
    );
  }
}
