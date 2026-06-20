import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../models/match_model.dart';
import 'team_logo.dart';

class MatchScoreCard extends StatelessWidget {
  final MatchModel match;
  final VoidCallback? onTap;
  final VoidCallback? onHighlightsTap;
  final VoidCallback? onPlayerTap;

  const MatchScoreCard({
    super.key,
    required this.match,
    this.onTap,
    this.onHighlightsTap,
    this.onPlayerTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFF2A5B8F).withOpacity(0.5),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF00E5FF).withOpacity(0.06),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _StadiumBgPainter(),
                ),
              ),
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        const Color(0xFF0D2A4A).withOpacity(0.75),
                        const Color(0xFF081C36).withOpacity(0.92),
                        const Color(0xFF051428).withOpacity(0.97),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTopRow(),
                    const SizedBox(height: 8),
                    _buildMainContent(),
                    const SizedBox(height: 6),
                    if (match.result != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          match.result!,
                          style: const TextStyle(
                            color: AppColors.green,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    _buildBottomRow(),
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
            match.matchType,
            style: const TextStyle(color: AppColors.blue, fontSize: 10, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '${match.matchNumber} \u2022 ${match.tournament}',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
            maxLines: 1,
            overflow: TextOverflow.clip,
          ),
        ),
        const SizedBox(width: 4),
        Container(
          width: 7, height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: match.status == 'live' ? AppColors.red : AppColors.green,
            boxShadow: [
              BoxShadow(color: (match.status == 'live' ? AppColors.red : AppColors.green).withOpacity(0.6), blurRadius: 3),
            ],
          ),
        ),
        const SizedBox(width: 3),
        Text(
          match.statusText,
          style: TextStyle(
            color: match.status == 'live' ? AppColors.red : AppColors.green,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildMainContent() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          flex: 6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildTeamRow(match.team1),
              const SizedBox(height: 6),
              _buildTeamRow(match.team2),
            ],
          ),
        ),
        if (match.playerOfMatch != null) ...[
          const SizedBox(width: 8),
          Container(width: 1, height: 70, color: AppColors.borderColor.withOpacity(0.4)),
          const SizedBox(width: 8),
          SizedBox(
            width: 100,
            child: _buildPlayerOfMatch(),
          ),
        ],
      ],
    );
  }

  Widget _buildTeamRow(TeamScore team) {
    return Row(
      children: [
        TeamLogo(shortName: team.shortName, colorHex: team.logoColor, size: 28),
        const SizedBox(width: 6),
        SizedBox(
          width: 32,
          child: Text(
            team.shortName,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 4),
        if (team.score != null)
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    team.score!,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '(${team.overs})',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPlayerOfMatch() {
    final pom = match.playerOfMatch!;
    return GestureDetector(
      onTap: onPlayerTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'PLAYER OF THE MATCH',
            style: TextStyle(color: AppColors.green, fontSize: 7, fontWeight: FontWeight.w700, letterSpacing: 0.3),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.blue.withOpacity(0.5), AppColors.cyan.withOpacity(0.3)],
              ),
              border: Border.all(color: AppColors.cyan.withOpacity(0.6), width: 2),
              boxShadow: [
                BoxShadow(color: AppColors.cyan.withOpacity(0.2), blurRadius: 10),
              ],
            ),
            child: ClipOval(
              child: Stack(
                children: [
                  const Positioned.fill(
                    child: Icon(Icons.person, color: Colors.white70, size: 28),
                  ),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      height: 12,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, AppColors.blue.withOpacity(0.4)],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            pom.name,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            pom.score,
            style: const TextStyle(color: AppColors.cyan, fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomRow() {
    return GestureDetector(
      onTap: onHighlightsTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.blue.withOpacity(0.5), width: 1),
          color: AppColors.blue.withOpacity(0.1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.play_circle_fill, color: AppColors.blue, size: 14),
            const SizedBox(width: 4),
            const Text(
              'Match Highlights',
              style: TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _StadiumBgPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    // Stadium arc
    paint.color = const Color(0xFF1A3A5C).withOpacity(0.3);
    final path = Path();
    path.moveTo(0, size.height * 0.6);
    path.quadraticBezierTo(size.width * 0.5, size.height * 0.15, size.width, size.height * 0.6);
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();
    canvas.drawPath(path, paint);

    // Flood light circles
    paint.color = const Color(0xFF21E6E6).withOpacity(0.04);
    canvas.drawCircle(Offset(size.width * 0.15, size.height * 0.15), 20, paint);
    canvas.drawCircle(Offset(size.width * 0.85, size.height * 0.15), 20, paint);

    // Subtle light rays
    paint.color = const Color(0xFF21E6E6).withOpacity(0.02);
    for (int i = 0; i < 5; i++) {
      final x = size.width * (0.1 + i * 0.2);
      final rayPath = Path();
      rayPath.moveTo(x, 0);
      rayPath.lineTo(x - 15, size.height * 0.5);
      rayPath.lineTo(x + 15, size.height * 0.5);
      rayPath.close();
      canvas.drawPath(rayPath, paint);
    }

    // Stadium seating arcs
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 0.5;
    paint.color = const Color(0xFF2A5B8F).withOpacity(0.1);
    for (int i = 0; i < 3; i++) {
      final arcPath = Path();
      final y = size.height * (0.5 + i * 0.08);
      arcPath.moveTo(0, y);
      arcPath.quadraticBezierTo(size.width * 0.5, y - 20 + i * 5, size.width, y);
      canvas.drawPath(arcPath, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
