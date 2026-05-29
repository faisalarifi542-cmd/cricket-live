import 'package:flutter/material.dart';

import '../../components.dart';
import 'simple_info_screen.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SimpleInfoScreen(
      title: 'Terms & Conditions',
      header: 'Last updated: 20 Nov 2024',
      body:
          'Please read these terms and conditions carefully before using CricPro.',
      children: [
        for (final item in [
          '1. Acceptance of Terms',
          '2. Use of the App',
          '3. User Accounts',
          '4. Intellectual Property',
          '5. Limitation of Liability',
          '6. Termination',
          '7. Governing Law',
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
