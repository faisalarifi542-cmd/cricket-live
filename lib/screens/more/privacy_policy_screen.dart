import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../components.dart';
import 'simple_info_screen.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  static const _content =
      'CricPro respects your privacy. This Privacy Policy explains how the app handles information.\n\n'
      'CricPro may collect basic app usage information, device information, crash logs, advertising identifiers, notification tokens, and preferences needed to provide app features, improve performance, show ads, and send notifications.\n\n'
      'We do not sell your personal information.\n\n'
      'The app may use third-party services such as advertising networks, analytics, notification services, and cricket data providers. These services may collect information according to their own privacy policies.\n\n'
      'If notifications are enabled, CricPro may store a notification token so we can send match alerts, live stream alerts, reminders, and app updates. You can disable notifications from your device settings at any time.\n\n'
      'If ads are enabled, advertising partners may use device identifiers or similar technologies to show ads, measure performance, and prevent abuse. You can control ad personalization from your device or Google/Apple account settings.\n\n'
      'CricPro may use internet access to load live scores, match data, images, player photos, team logos, series information, and live streams.\n\n'
      'We take reasonable steps to protect app data, but no online service can be guaranteed to be 100% secure.\n\n'
      'Children should use the app only with guidance from a parent or guardian.\n\n'
      'We may update this Privacy Policy when app features change. Continued use of the app means you accept the updated policy.\n\n'
      'For privacy questions or support, contact CricPro support from the Contact Us section inside the app.\n\n'
      'Last updated: 6 June 2026';

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return SimpleInfoScreen(
      title: 'Privacy Policy',
      header: 'Privacy Policy',
      body: 'CricPro respects your privacy.',
      icon: Icons.shield_outlined,
      children: [
        PremiumCard(
          padding: const EdgeInsets.all(18),
          child: Text(
            _content,
            style: TextStyle(
              color: c.text,
              fontSize: 14,
              height: 1.55,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
