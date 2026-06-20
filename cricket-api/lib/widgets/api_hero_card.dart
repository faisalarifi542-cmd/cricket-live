import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/cricket_helpers.dart';
import '../models/api/api_match_model.dart';
import 'team_logo.dart';

class ApiHeroCard extends StatelessWidget {
  final ApiMatch match;
  final VoidCallback? onTap;

  const ApiHeroCard({super.key, required this.match, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: AppColors.cardGradient,
          border: Border.all(color: AppColors.borderColor.withOpacity(0.3)),
          boxShadow: AppColors.glowShadow,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              CustomPaint(painter: _StadiumBgPainter(), size: const Size(double.infinity, 195)),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildTopRow(),
                    const SizedBox(height: 10),
                    _buildScoresRow(),
                    const SizedBox(height: 8),
                    if (match.statusText.isNotEmpty)
                      Text(
                        match.statusText,
                        style: TextStyle(
                          color: match.isLive ? AppColors.red : AppColors.green,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
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

  Widget _buildTopRow() {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.blue.withOpacity(0.2),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.blue.withOpacity(0.4)),
          ),
          child: Text(
            match.formatLabel,
            style: const TextStyle(color: AppColors.blue, fontSize: 10, fontWeight: FontWeight.w700),
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
        Container(
          width: 7, height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: match.isLive ? AppColors.red : AppColors.green,
            boxShadow: [BoxShadow(color: (match.isLive ? AppColors.red : AppColors.green).withOpacity(0.6), blurRadius: 3)],
          ),
        ),
        const SizedBox(width: 3),
        Text(
          match.isLive
              ? 'LIVE'
              : match.isCompleted
                  ? 'Completed'
                  : match.startTime != null
                      ? formatMatchTime(match.startTime)
                      : 'Upcoming',
          style: TextStyle(
            color: match.isLive ? AppColors.red : AppColors.green,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildScoresRow() {
    final t1Scores = match.score?.team1 ?? [];
    final t2Scores = match.score?.team2 ?? [];
    return Column(
      children: [
        _buildTeamScore(match.team1, t1Scores),
        const SizedBox(height: 6),
        _buildTeamScore(match.team2, t2Scores),
      ],
    );
  }

  Widget _buildTeamScore(ApiTeam team, List<ApiInningsScore> innings) {
    return Row(
      children: [
        TeamLogo(teamCode: team.shortName, logoUrl: team.logoUrl, size: 32),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            team.name,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (innings.isNotEmpty)
          Text(
            innings.map((i) => '${i.runs}/${i.wickets}').join(' & '),
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w800),
          ),
        if (innings.isNotEmpty) ...[
          const SizedBox(width: 6),
          Text(
            innings.last.oversText,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
          ),
        ],
      ],
    );
  }
}

class _StadiumBgPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final arcPaint = Paint()
      ..color = AppColors.cyan.withOpacity(0.04)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (int i = 0; i < 5; i++) {
      final rect = Rect.fromCenter(
        center: Offset(size.width / 2, size.height + 40 + i * 30),
        width: size.width * (0.8 + i * 0.15),
        height: 80 + i * 20,
      );
      canvas.drawArc(rect, 3.14, 3.14, false, arcPaint);
    }

    final lightPaint = Paint()
      ..color = AppColors.cyan.withOpacity(0.03)
      ..strokeWidth = 0.5;
    canvas.drawLine(Offset(size.width * 0.15, 0), Offset(size.width * 0.35, size.height), lightPaint);
    canvas.drawLine(Offset(size.width * 0.85, 0), Offset(size.width * 0.65, size.height), lightPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
