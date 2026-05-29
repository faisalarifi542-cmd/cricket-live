import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../components.dart';
import '../models.dart';

class LiveMatchMiniCard extends StatelessWidget {
  const LiveMatchMiniCard({
    super.key,
    required this.onWatch,
    required this.onOpen,
    this.series = 'WEST INDIES TOUR OF NEW ZEALAND',
    this.title = 'NZ vs WI',
    this.meta = '1st Test • Day 1 • 158/3 (38.4 OV)',
    this.accent = AppData.newZealand,
    this.accent2 = AppData.westIndies,
  });

  final VoidCallback onWatch;
  final VoidCallback onOpen;
  final String series;
  final String title;
  final String meta;
  final TeamInfo accent;
  final TeamInfo accent2;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      onTap: onOpen,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusBadge(label: 'LIVE', color: c.live, filled: true),
              const SizedBox(width: 10),
              Expanded(
                child: Text(series,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: c.cyan,
                        fontWeight: FontWeight.w800,
                        fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              TeamBadge(accent, size: 40),
              const SizedBox(width: 6),
              TeamBadge(accent2, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            color: c.text,
                            fontWeight: FontWeight.w900,
                            fontSize: context.sp(20))),
                    const SizedBox(height: 4),
                    Text(meta,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: c.muted, fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: GradientButton(
              label: 'Watch Live',
              icon: Icons.play_circle_fill_rounded,
              height: 46,
              onTap: onWatch,
            ),
          ),
        ],
      ),
    );
  }
}
