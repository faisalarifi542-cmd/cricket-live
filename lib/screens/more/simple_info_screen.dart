import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../components.dart';

class SimpleInfoScreen extends StatelessWidget {
  const SimpleInfoScreen({
    super.key,
    required this.title,
    required this.header,
    required this.body,
    this.icon,
    this.children = const [],
  });

  final String title;
  final String header;
  final String body;
  final IconData? icon;
  final List<Widget> children;

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
                    tooltip: 'Back',
                    icon: Icon(Icons.arrow_back_rounded, color: c.text)),
                title: title,
              ),
              const SizedBox(height: 18),
              PremiumCard(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(header,
                              style: TextStyle(
                                  color: c.text,
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900)),
                          const SizedBox(height: 10),
                          Text(body,
                              style: TextStyle(
                                  color: c.muted, fontSize: 15, height: 1.6)),
                        ],
                      ),
                    ),
                    if (icon != null)
                      Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: c.primaryGradient),
                        child: Icon(icon, color: Colors.white, size: 34),
                      )
                  ],
                ),
              ),
              const SizedBox(height: 18),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}
