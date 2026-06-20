import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/cricket_helpers.dart';
import '../models/api/api_match_model.dart';
import 'team_logo.dart';
import 'glass_card.dart';

class ApiMatchCard extends StatelessWidget {
  final ApiMatch match;
  final VoidCallback? onTap;

  const ApiMatchCard({super.key, required this.match, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: GlassCard(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        padding: const EdgeInsets.all(12),
        borderRadius: 14,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTopRow(),
            const SizedBox(height: 10),
            _buildTeamRow(match.team1, match.score?.team1 ?? []),
            const SizedBox(height: 8),
            _buildTeamRow(match.team2, match.score?.team2 ?? []),
            if (match.statusText.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                match.statusText,
                style: TextStyle(
                  color: match.isLive ? AppColors.red : AppColors.green,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ] else if (match.isUpcoming && match.matchDesc.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                match.matchDesc,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTopRow() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.blue.withOpacity(0.2),
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: AppColors.blue.withOpacity(0.4)),
          ),
          child: Text(
            match.formatLabel,
            style: const TextStyle(color: AppColors.blue, fontSize: 9, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            match.seriesName.isNotEmpty ? match.seriesName : match.title,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 4),
        if (match.isLive) ...[
          Container(
            width: 7, height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.red,
              boxShadow: [BoxShadow(color: AppColors.red.withOpacity(0.6), blurRadius: 3)],
            ),
          ),
          const SizedBox(width: 3),
          const Text('LIVE', style: TextStyle(color: AppColors.red, fontSize: 10, fontWeight: FontWeight.w700)),
        ] else ...[
          Container(
            width: 7, height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: match.isCompleted ? AppColors.green : AppColors.textMuted,
            ),
          ),
          const SizedBox(width: 3),
          Text(
            match.isCompleted
                ? 'Completed'
                : match.isUpcoming && match.startTime != null
                    ? formatMatchTime(match.startTime)
                    : 'Upcoming',
            style: TextStyle(
              color: match.isCompleted ? AppColors.green : AppColors.textMuted,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTeamRow(ApiTeam team, List<ApiInningsScore> innings) {
    return Row(
      children: [
        TeamLogo(teamCode: team.shortName, logoUrl: team.logoUrl, size: 26),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            team.name,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (innings.isNotEmpty)
          Text(
            innings.map((i) => i.fullText).join(' & '),
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w700),
          ),
      ],
    );
  }
}
