import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../components.dart';

/// Teams browse is still navigable from More -> Quick Access, but there is no
/// global `/teams` endpoint on the backend yet. We render a clean empty state
/// instead of the previous hardcoded list of nine international squads so
/// teams cannot disappear and reappear depending on Cricbuzz availability.
class TeamsScreen extends StatelessWidget {
  const TeamsScreen({super.key});

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
                title: 'Teams',
              ),
              const SizedBox(height: 40),
              PremiumCard(
                padding: const EdgeInsets.all(28),
                child: Column(
                  children: [
                    Icon(Icons.shield_outlined, color: c.cyan, size: 56),
                    const SizedBox(height: 14),
                    Text(
                      'Teams directory coming soon',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: c.text,
                        fontWeight: FontWeight.w900,
                        fontSize: context.sp(22),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Until the backend exposes a global teams feed, open any series and switch to the Squads tab to see real teams and players.',
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
