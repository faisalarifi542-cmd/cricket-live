import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../components.dart';
import 'simple_info_screen.dart';

class ContactUsScreen extends StatelessWidget {
  const ContactUsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final options = [
      ('Email Support', 'support@cricpro.app', Icons.mail_outline_rounded),
      ('Website', 'cricpro.app', Icons.language_rounded),
      ('Report a Problem', 'Tell us what is not working', Icons.report_outlined),
    ];
    return SimpleInfoScreen(
      title: 'Contact Us',
      header: "We're here to help!",
      body: 'Feel free to reach out to us for any queries or support.',
      icon: Icons.headset_mic_rounded,
      children: [
        for (final item in options)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: PremiumCard(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  CircleAvatar(
                      radius: 20,
                      backgroundColor: c.card2,
                      child: Icon(item.$3, color: c.cyan, size: 20)),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.$1,
                            style: TextStyle(
                                color: c.text, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(item.$2,
                            style: TextStyle(color: c.muted, fontSize: 13)),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: c.muted),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
