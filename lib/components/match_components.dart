import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../components.dart';
import '../models.dart';

class UpcomingMatchCard extends StatelessWidget {
  const UpcomingMatchCard(
      {super.key, required this.match, this.onTap, this.onReminder});

  final CompactFixture match;
  final VoidCallback? onTap;
  final VoidCallback? onReminder;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      onTap: onTap,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child: Text(match.series,
                      style: TextStyle(
                          color: c.cyan,
                          fontWeight: FontWeight.w800,
                          fontSize: 15))),
              Text(match.subtitle,
                  style: TextStyle(color: c.cyan, fontWeight: FontWeight.w700)),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded, color: c.muted),
            ],
          ),
          const SizedBox(height: 18),
          Builder(builder: (ctx) {
            final w = ctx.w;
            final narrow = w <= 400;
            final vsSize = narrow ? 46.0 : 64.0;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: _matchTeamBlock(context, match.left)),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(match.date.split('•').first.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: c.text,
                            fontWeight: FontWeight.w700,
                            fontSize: context.sp(14)),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 6),
                    Text(match.date.split('•').last.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: c.cyan,
                            fontWeight: FontWeight.w700,
                            fontSize: context.sp(15))),
                    const SizedBox(height: 10),
                    Container(
                      width: vsSize,
                      height: vsSize,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: c.card2,
                          border: Border.all(color: c.border)),
                      alignment: Alignment.center,
                      child: Text('VS',
                          style: TextStyle(
                              color: c.text,
                              fontWeight: FontWeight.w900,
                              fontSize: narrow ? 18 : 24)),
                    ),
                  ],
                ),
                Expanded(child: _matchTeamBlock(context, match.right)),
              ],
            );
          }),
          const SizedBox(height: 18),
          Row(
            children: [
              Icon(Icons.location_on_outlined, color: c.muted),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(match.venue,
                      style: TextStyle(color: c.muted, height: 1.45))),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              StatusBadge(label: match.status, color: c.muted),
              const Spacer(),
              InkWell(
                onTap: onReminder,
                child: Row(
                  children: [
                    Icon(Icons.notifications_none_rounded, color: c.cyan),
                    const SizedBox(width: 8),
                    Text(match.action,
                        style: TextStyle(
                            color: c.cyan,
                            fontWeight: FontWeight.w700,
                            fontSize: 16)),
                  ],
                ),
              )
            ],
          )
        ],
      ),
    );
  }

  Widget _matchTeamBlock(BuildContext context, TeamInfo team) {
    final c = context.cric;
    final w = context.w;
    final size = w <= 400 ? 64.0 : (w <= 480 ? 84.0 : 104.0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TeamBadge(team, size: size),
        const SizedBox(height: 12),
        Text(team.shortName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: c.text,
                fontWeight: FontWeight.w800,
                fontSize: context.sp(15)),
            textAlign: TextAlign.center),
      ],
    );
  }
}

class FinishedMatchCard extends StatelessWidget {
  const FinishedMatchCard({super.key, required this.match, this.onTap});

  final CompactFixture match;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      onTap: onTap,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child: Text(match.series,
                      style: TextStyle(
                          color: c.cyan,
                          fontWeight: FontWeight.w800,
                          fontSize: 15))),
              StatusBadge(label: match.status, color: c.cyan),
            ],
          ),
          const SizedBox(height: 18),
          Builder(builder: (ctx) {
            final narrow = ctx.w <= 400;
            final vsSize = narrow ? 46.0 : 64.0;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                    child: _finishedTeamBlock(context, match.left,
                        match.date.split('•').first.trim())),
                Container(
                  width: vsSize,
                  height: vsSize,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: c.card2,
                      border: Border.all(color: c.border)),
                  alignment: Alignment.center,
                  child: Text('VS',
                      style: TextStyle(
                          color: c.text,
                          fontWeight: FontWeight.w900,
                          fontSize: narrow ? 18 : 24)),
                ),
                Expanded(
                    child: _finishedTeamBlock(context, match.right,
                        match.date.split('•').last.trim())),
              ],
            );
          }),
          const SizedBox(height: 16),
          Center(
              child: Text(match.venue,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: c.success,
                      fontWeight: FontWeight.w800,
                      fontSize: context.sp(16)))),
          const SizedBox(height: 18),
          PremiumCard(
            padding: const EdgeInsets.all(14),
            gradient: LinearGradient(colors: [c.card2, c.card]),
            child: Builder(builder: (ctx) {
              final narrow = ctx.w <= 400;
              final action = GradientButton(
                label: match.action,
                icon: match.action == 'Highlights'
                    ? Icons.play_circle_outline_rounded
                    : Icons.receipt_long_rounded,
                outlined: true,
                height: 44,
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const CircleAvatar(
                          radius: 24,
                          backgroundColor: Color(0xff0a2748),
                          child: Icon(Icons.person, color: Colors.white)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Player of the Match',
                                style: TextStyle(
                                    color: c.cyan,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12)),
                            const SizedBox(height: 4),
                            Text(match.playerOfMatch ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: c.text,
                                    fontWeight: FontWeight.w800,
                                    fontSize: context.sp(15))),
                            Text(match.playerStat ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: c.muted, fontSize: 12)),
                          ],
                        ),
                      ),
                      if (!narrow) action,
                    ],
                  ),
                  if (narrow) ...[
                    const SizedBox(height: 12),
                    SizedBox(width: double.infinity, child: action),
                  ],
                ],
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _finishedTeamBlock(BuildContext context, TeamInfo team, String score) {
    final c = context.cric;
    final w = context.w;
    final size = w <= 400 ? 64.0 : (w <= 480 ? 84.0 : 102.0);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TeamBadge(team, size: size),
        const SizedBox(height: 10),
        Text(team.shortName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: c.text,
                fontWeight: FontWeight.w800,
                fontSize: context.sp(14)),
            textAlign: TextAlign.center),
        const SizedBox(height: 6),
        Text(score,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: context.sp(16)),
            textAlign: TextAlign.center),
      ],
    );
  }
}
