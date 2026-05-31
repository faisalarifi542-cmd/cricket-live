import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../components.dart';
import '../../models.dart';

class SearchScreen extends StatelessWidget {
  const SearchScreen({super.key});

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
              Row(
                children: [
                  IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.arrow_back_rounded, color: c.text)),
                  Expanded(
                    child: Container(
                      height: 52,
                      decoration: BoxDecoration(
                        color: c.card.withValues(alpha: .92),
                        borderRadius: BorderRadius.circular(26),
                        border: Border.all(color: c.border),
                      ),
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: Row(
                        children: [
                          Icon(Icons.search_rounded, color: c.muted),
                          const SizedBox(width: 10),
                          Text('Search teams, players, series...',
                              style: TextStyle(color: c.muted)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 26),
              const SectionHeader('Recent Searches', icon: Icons.history_rounded),
              const SizedBox(height: 12),
              Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children:
                      AppData.searchTopics.map((e) => PillChip(e)).toList()),
              const SizedBox(height: 26),
              const SectionHeader('Trending Topics', icon: Icons.trending_up_rounded),
              const SizedBox(height: 12),
              for (final topic in AppData.searchTopics)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading:
                      const Icon(Icons.search_rounded, color: Colors.white),
                  title: Text(topic),
                  trailing: const Icon(Icons.north_west_rounded),
                ),
              const SizedBox(height: 18),
              const SectionHeader('Popular Players',
                  icon: Icons.person_outline_rounded),
              const SizedBox(height: 12),
              for (final player in AppData.trendingPlayers)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: PremiumCard(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        const CircleAvatar(
                            radius: 22,
                            backgroundColor: Color(0xff0a2748),
                            child: Icon(Icons.person, color: Colors.white)),
                        const SizedBox(width: 14),
                        Expanded(
                            child: Text(player,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700))),
                        const Icon(Icons.chevron_right_rounded),
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
