import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../components.dart';
import 'simple_info_screen.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  static const _content =
      'Welcome to CricPro. By using this app, you agree to these Terms & Conditions.\n\n'
      'CricPro provides cricket scores, match information, series details, schedules, notifications, and live stream access where available. The app is intended for personal and informational use.\n\n'
      'You agree not to misuse the app, attempt to access restricted systems, copy or redistribute protected content, interfere with app services, or use the app for illegal activity.\n\n'
      'Match data, scores, fixtures, teams, player information, and statistics may be provided by third-party sources. CricPro does its best to keep information accurate and updated, but we cannot guarantee that all data will always be complete, real-time, or error-free.\n\n'
      'Live streaming availability may depend on match rights, admin configuration, stream availability, location, network quality, and device support. CricPro may change or remove stream access at any time.\n\n'
      'The app may show advertisements, including banner, native, interstitial, and rewarded ads. Rewarded ads may be used to unlock premium stream access or app features when enabled.\n\n'
      'Notifications may be sent for match updates, live streams, reminders, news, and app announcements. Users can disable notifications from their device settings.\n\n'
      'CricPro may update, suspend, or discontinue parts of the app at any time. We are not responsible for losses caused by service interruptions, incorrect data, or third-party service issues.\n\n'
      'By continuing to use CricPro, you agree to follow these terms. If you do not agree, please stop using the app.\n\n'
      'Last updated: 6 June 2026';

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return SimpleInfoScreen(
      title: 'Terms & Conditions',
      header: 'Terms & Conditions',
      body: 'Please read these terms before using CricPro.',
      icon: Icons.description_outlined,
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
