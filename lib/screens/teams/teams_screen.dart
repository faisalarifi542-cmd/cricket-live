import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../components.dart';
import '../../models.dart';
import 'team_detail_screen.dart';

class TeamsScreen extends StatelessWidget {
  const TeamsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final teams = [
      AppData.india,
      AppData.australia,
      AppData.england,
      AppData.newZealand,
      AppData.pakistan,
      AppData.southAfrica,
      AppData.sriLanka,
      AppData.bangladesh,
      AppData.westIndies,
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
                title: 'Teams',
              ),
              const SizedBox(height: 18),
              SegmentedTabs(
                  items: const [('International', null), ('Franchise', null)],
                  selected: 0,
                  onChanged: (_) {}),
              const SizedBox(height: 18),
              for (final team in teams)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: PremiumCard(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => TeamDetailScreen(teamId: team.code),
                      ),
                    ),
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        TeamBadge(team, size: 42),
                        const SizedBox(width: 14),
                        Expanded(
                            child: Text(team.name,
                                style: TextStyle(
                                    color: c.text,
                                    fontWeight: FontWeight.w700))),
                        Icon(Icons.chevron_right_rounded, color: c.muted),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
