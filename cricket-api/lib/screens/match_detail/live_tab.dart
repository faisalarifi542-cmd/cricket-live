import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../models/api/api_match_detail_model.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/team_logo.dart';
import '../../widgets/api_state_widgets.dart';
import '../../core/utils/cricket_helpers.dart';

class LiveTab extends StatelessWidget {
  final ApiMatchDetail? matchDetail;

  const LiveTab({super.key, this.matchDetail});

  @override
  Widget build(BuildContext context) {
    if (matchDetail == null) {
      return const EmptyStateWidget(message: 'No match data available');
    }
    final md = matchDetail!;
    final isUpcoming = md.status == 'upcoming' && md.innings.isEmpty;
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 105),
      child: Column(
        children: [
          const SizedBox(height: 8),
          _buildMainScoreCard(md),
          if (!isUpcoming) ...[
            const SizedBox(height: 8),
            _buildBattingBowlingCards(md),
            const SizedBox(height: 8),
            if (md.recentOvers != null && md.recentOvers!.isNotEmpty)
              _buildRecentOvers(md),
          ],
          const SizedBox(height: 8),
          _buildMatchInfo(md),
          if (isUpcoming) ...[
            const SizedBox(height: 16),
            _buildUpcomingInfo(md),
          ],
        ],
      ),
    );
  }

  Widget _buildMainScoreCard(ApiMatchDetail md) {
    return GlassCard(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(10),
      borderRadius: 14,
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.blue.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.blue.withOpacity(0.4)),
                ),
                child: Text(md.matchFormat.toUpperCase(), style: const TextStyle(color: AppColors.blue, fontSize: 10, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  md.seriesName.isNotEmpty ? md.seriesName : md.title,
                  style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: md.isLive ? AppColors.red : AppColors.green,
                  boxShadow: [BoxShadow(color: (md.isLive ? AppColors.red : AppColors.green).withOpacity(0.6), blurRadius: 4)],
                ),
              ),
              const SizedBox(width: 4),
              Text(
                md.isLive ? 'LIVE' : md.status.toUpperCase(),
                style: TextStyle(color: md.isLive ? AppColors.red : AppColors.green, fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...md.innings.map((inn) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                TeamLogo(teamCode: inn.battingTeam, size: 32),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(inn.battingTeam, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                ),
                Text('${inn.runs}/${inn.wickets}', style: const TextStyle(color: AppColors.textPrimary, fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(width: 6),
                Text('(${formatCricketOvers(inn.overs)} ov)', style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
              ],
            ),
          )),
          if (md.statusText.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                md.statusText,
                style: const TextStyle(color: AppColors.green, fontSize: 12, fontWeight: FontWeight.w600),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBattingBowlingCards(ApiMatchDetail md) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: GlassCard(
              padding: const EdgeInsets.all(8),
              borderRadius: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.sports_cricket, color: AppColors.cyan, size: 12),
                      const SizedBox(width: 4),
                      const Text('Batting', style: TextStyle(color: AppColors.cyan, fontSize: 11, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const Divider(color: AppColors.borderColor, height: 10),
                  if (md.currentBatsmen.isNotEmpty)
                    ...md.currentBatsmen.map((b) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: _buildMiniRow(
                        '${b.name}${b.isStriker ? "*" : ""}',
                        '${b.runs}(${b.balls})',
                      ),
                    ))
                  else
                    const Text('No batting data', style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GlassCard(
              padding: const EdgeInsets.all(8),
              borderRadius: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.sports_baseball, color: AppColors.orange, size: 12),
                      const SizedBox(width: 4),
                      const Text('Bowling', style: TextStyle(color: AppColors.orange, fontSize: 11, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const Divider(color: AppColors.borderColor, height: 10),
                  if (md.currentBowler != null)
                    _buildMiniRow(md.currentBowler!.name, '${md.currentBowler!.wickets}/${md.currentBowler!.runs} (${md.currentBowler!.overs})')
                  else
                    const Text('No bowling data', style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniRow(String name, String stat) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(name, style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
        ),
        Text(stat, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildRecentOvers(ApiMatchDetail md) {
    final recentStr = md.recentOvers ?? '';
    final balls = recentStr.split(' ').where((s) => s.isNotEmpty).toList();

    return GlassCard(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      borderRadius: 12,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Recent Overs', style: TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: balls.map((b) {
                Color bgColor;
                if (b == '4') {
                  bgColor = AppColors.green;
                } else if (b == '6') {
                  bgColor = AppColors.purple;
                } else if (b == 'W') {
                  bgColor = AppColors.red;
                } else if (b == '0') {
                  bgColor = AppColors.textMuted.withOpacity(0.3);
                } else {
                  bgColor = AppColors.green.withOpacity(0.7);
                }
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Container(
                    width: 28, height: 28,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: bgColor),
                    child: Center(
                      child: Text(b, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMatchInfo(ApiMatchDetail md) {
    return GlassCard(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      borderRadius: 12,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Match Info', style: TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (md.toss != null && md.toss!.displayText.isNotEmpty)
            _buildInfoRow('Toss', md.toss!.displayText),
          if (md.venue.displayName.isNotEmpty)
            _buildInfoRow('Venue', md.venue.displayName),
          if (md.manOfMatch.isNotEmpty)
            _buildInfoRow('Player of Match', md.manOfMatch),
          if (md.partnership != null)
            _buildInfoRow('Partnership', '${md.partnership!.runs} (${md.partnership!.balls} balls)'),
          if (md.lastWicket != null && md.lastWicket!.isNotEmpty)
            _buildInfoRow('Last Wicket', md.lastWicket!),
          _buildInfoRow('Run Rate', md.currentRunRate.toStringAsFixed(2)),
          if (md.requiredRunRate > 0)
            _buildInfoRow('Required RR', md.requiredRunRate.toStringAsFixed(2)),
        ],
      ),
    );
  }

  Widget _buildUpcomingInfo(ApiMatchDetail md) {
    final t1Name = md.team1.shortName.isNotEmpty ? md.team1.shortName : md.team1.name;
    final t2Name = md.team2.shortName.isNotEmpty ? md.team2.shortName : md.team2.name;
    final hasTeams = t1Name.isNotEmpty && t2Name.isNotEmpty;
    final countdown = _countdownText(md.startTime);

    return GlassCard(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      borderRadius: 14,
      child: Column(
        children: [
          if (hasTeams) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Column(
                  children: [
                    TeamLogo(shortName: t1Name, logoUrl: md.team1.logoUrl, size: 48),
                    const SizedBox(height: 6),
                    Text(t1Name, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
                    if (md.team1.name.isNotEmpty && md.team1.name != t1Name)
                      Text(md.team1.name, style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
                  ],
                ),
                const SizedBox(width: 24),
                Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.cyan.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.cyan.withOpacity(0.3)),
                      ),
                      child: const Text('VS', style: TextStyle(color: AppColors.cyan, fontSize: 14, fontWeight: FontWeight.w800)),
                    ),
                  ],
                ),
                const SizedBox(width: 24),
                Column(
                  children: [
                    TeamLogo(shortName: t2Name, logoUrl: md.team2.logoUrl, size: 48),
                    const SizedBox(height: 6),
                    Text(t2Name, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
                    if (md.team2.name.isNotEmpty && md.team2.name != t2Name)
                      Text(md.team2.name, style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
          ],
          if (!hasTeams)
            const Icon(Icons.schedule, color: AppColors.cyan, size: 32),
          if (countdown.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.cyan.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.cyan.withOpacity(0.2)),
              ),
              child: Text(countdown, style: const TextStyle(color: AppColors.cyan, fontSize: 14, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 8),
          ] else ...[
            const SizedBox(height: 6),
            const Text('Match Not Started', style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
          ],
          if (md.statusText.isNotEmpty && md.statusText != 'Match details will be available closer to start time')
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(md.statusText, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11), textAlign: TextAlign.center),
            ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.notifications_outlined, size: 16),
            label: const Text('Set Match Alert', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.cyan.withOpacity(0.15),
              foregroundColor: AppColors.cyan,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  String _countdownText(DateTime? startTime) {
    if (startTime == null) return '';
    final now = DateTime.now();
    final diff = startTime.difference(now);
    if (diff.isNegative) return '';
    if (diff.inDays > 0) {
      return 'Starts in ${diff.inDays}d ${diff.inHours % 24}h';
    }
    if (diff.inHours > 0) {
      return 'Starts in ${diff.inHours}h ${diff.inMinutes % 60}m';
    }
    return 'Starts in ${diff.inMinutes}m';
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}
