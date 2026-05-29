import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../components.dart';
import '../../models.dart';

class PlayerDetailScreen extends StatelessWidget {
  const PlayerDetailScreen({super.key, this.player});

  final PlayerInfo? player;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final p = player ?? AppData.indiaSquadTop.first;
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
                title: p.name,
              ),
              const SizedBox(height: 18),
              PremiumCard(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    PlayerAvatar(player: p, size: 110, borderColor: c.cyan),
                    const SizedBox(height: 16),
                    Text(p.name,
                        style: TextStyle(
                            color: c.text,
                            fontSize: 28,
                            fontWeight: FontWeight.w900)),
                    const SizedBox(height: 6),
                    Text('${p.team.name} • ${p.role}',
                        style: TextStyle(
                            color: c.cyan, fontWeight: FontWeight.w700)),
                    if (p.subtitle != null) ...[
                      const SizedBox(height: 6),
                      Text(p.subtitle!, style: TextStyle(color: c.muted)),
                    ],
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                            child: _StatValue(title: 'Matches', value: '92')),
                        Expanded(
                            child: _StatValue(title: 'Runs', value: '4,128')),
                        Expanded(
                            child: _StatValue(title: 'SR', value: '134.2')),
                      ],
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

class _StatValue extends StatelessWidget {
  const _StatValue({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value,
            style: TextStyle(
                color: c.text, fontWeight: FontWeight.w900, fontSize: 28)),
        const SizedBox(height: 4),
        Text(title, style: TextStyle(color: c.muted)),
      ],
    );
  }
}
