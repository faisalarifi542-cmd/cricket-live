import 'package:flutter/material.dart';

import '../../components.dart';
import 'simple_info_screen.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SimpleInfoScreen(
      title: 'Privacy Policy',
      header: 'Last updated: 20 Nov 2024',
      body:
          'At CricPro, we value your privacy and are committed to protecting your personal data.',
      children: [
        for (final item in [
          '1. Information We Collect',
          '2. How We Use Information',
          '3. Data Sharing',
          '4. Data Security',
          '5. Your Rights',
          '6. Cookies & Tracking',
          '7. Changes To This Policy',
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: PremiumCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              child: Row(
                children: [
                  Expanded(
                      child: Text(item,
                          style: const TextStyle(fontWeight: FontWeight.w700))),
                  const Icon(Icons.chevron_right_rounded)
                ],
              ),
            ),
          ),
      ],
    );
  }
}
