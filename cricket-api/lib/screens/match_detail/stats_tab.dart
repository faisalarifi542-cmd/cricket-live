import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/cricket_helpers.dart';
import '../../models/api/api_match_detail_model.dart';
import '../../models/api/api_scorecard_model.dart';
import '../../widgets/glass_card.dart';

class StatsTab extends StatelessWidget {
  final ApiMatchDetail? matchDetail;
  final ApiScorecard? scorecard;

  const StatsTab({super.key, this.matchDetail, this.scorecard});

  bool get _hasData => scorecard != null && scorecard!.innings.isNotEmpty;
  String get _team1Name => _hasData ? scorecard!.innings[0].battingTeam : (matchDetail?.team1.shortName ?? 'Team 1');
  String get _team2Name => _hasData && scorecard!.innings.length >= 2 ? scorecard!.innings[1].battingTeam : (matchDetail?.team2.shortName ?? 'Team 2');

  @override
  Widget build(BuildContext context) {
    if (!_hasData && (matchDetail == null || matchDetail!.innings.isEmpty)) {
      final isUpcoming = matchDetail?.status == 'upcoming';
      return Center(
        child: GlassCard(
          margin: const EdgeInsets.symmetric(horizontal: 32, vertical: 60),
          padding: const EdgeInsets.all(24),
          borderRadius: 16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isUpcoming ? Icons.bar_chart : Icons.analytics_outlined,
                color: AppColors.cyan.withOpacity(0.5),
                size: 48,
              ),
              const SizedBox(height: 12),
              Text(
                isUpcoming ? 'Stats will be available\nafter the match starts' : 'Stats not available\nfor this match',
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600, height: 1.4),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 105),
      child: Column(
        children: [
          const SizedBox(height: 12),
          _buildMatchSummary(),
          const SizedBox(height: 12),
          if (_hasData) ...[
            _buildBoundaries(),
            const SizedBox(height: 12),
            _buildRunRate(),
            const SizedBox(height: 12),
            _buildTopPerformers(),
          ],
        ],
      ),
    );
  }

  Widget _buildMatchSummary() {
    if (_hasData) {
      final i1 = scorecard!.innings[0];
      final i2 = scorecard!.innings.length >= 2 ? scorecard!.innings[1] : null;
      return GlassCard(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(12),
        borderRadius: 12,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Match Summary', style: TextStyle(color: AppColors.cyan, fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            _buildStatRow('Total Runs', '${i1.total.runs}', i2 != null ? '${i2.total.runs}' : '-'),
            _buildStatRow('Wickets', '${i1.total.wickets}', i2 != null ? '${i2.total.wickets}' : '-'),
            _buildStatRow('Overs', formatCricketOvers(i1.total.overs), i2 != null ? formatCricketOvers(i2.total.overs) : '-'),
            _buildStatRow('Run Rate', i1.runRate.toStringAsFixed(2), i2 != null ? i2.runRate.toStringAsFixed(2) : '-'),
            _buildStatRow('Extras', '${i1.extras.total}', i2 != null ? '${i2.extras.total}' : '-'),
          ],
        ),
      );
    }
    // Fallback from match detail
    final md = matchDetail!;
    return GlassCard(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      borderRadius: 12,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Match Summary', style: TextStyle(color: AppColors.cyan, fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          ...md.innings.map((inn) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(child: Text(inn.battingTeam, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600))),
                Text('${inn.runs}/${inn.wickets} (${formatCricketOvers(inn.overs)})', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildBoundaries() {
    final i1 = scorecard!.innings[0];
    final i2 = scorecard!.innings.length >= 2 ? scorecard!.innings[1] : null;
    int f1 = 0, s1 = 0, f2 = 0, s2 = 0;
    for (final b in i1.batting) { f1 += b.fours; s1 += b.sixes; }
    if (i2 != null) for (final b in i2.batting) { f2 += b.fours; s2 += b.sixes; }

    return GlassCard(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      borderRadius: 12,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Boundaries', style: TextStyle(color: AppColors.cyan, fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _buildBoundaryCard(_team1Name, '$f1', '$s1', AppColors.orange)),
              if (i2 != null) ...[
                const SizedBox(width: 10),
                Expanded(child: _buildBoundaryCard(_team2Name, '$f2', '$s2', AppColors.blue)),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBoundaryCard(String team, String fours, String sixes, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(team, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Column(children: [
                Text(fours, style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w800)),
                const Text('Fours', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
              ]),
              Column(children: [
                Text(sixes, style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w800)),
                const Text('Sixes', style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
              ]),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRunRate() {
    final i1 = scorecard!.innings[0];
    final i2 = scorecard!.innings.length >= 2 ? scorecard!.innings[1] : null;
    return GlassCard(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      borderRadius: 12,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Run Rate', style: TextStyle(color: AppColors.cyan, fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          _buildStatRow('Run Rate', i1.runRate.toStringAsFixed(2), i2 != null ? i2.runRate.toStringAsFixed(2) : '-'),
          if (matchDetail != null && matchDetail!.currentRunRate > 0)
            _buildStatRow('Current RR', matchDetail!.currentRunRate.toStringAsFixed(2), ''),
          if (matchDetail != null && matchDetail!.requiredRunRate > 0)
            _buildStatRow('Required RR', matchDetail!.requiredRunRate.toStringAsFixed(2), ''),
        ],
      ),
    );
  }

  Widget _buildTopPerformers() {
    final allBatting = <ApiBattingEntry>[];
    final allBowling = <ApiBowlingEntry>[];
    for (final inn in scorecard!.innings) {
      allBatting.addAll(inn.batting.where((b) => b.didBat));
      allBowling.addAll(inn.bowling);
    }
    allBatting.sort((a, b) => b.runs.compareTo(a.runs));
    allBowling.sort((a, b) {
      if (b.wickets != a.wickets) return b.wickets.compareTo(a.wickets);
      return a.runs.compareTo(b.runs);
    });

    final topBats = allBatting.take(3).toList();
    final topBowls = allBowling.take(3).toList();

    return GlassCard(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      borderRadius: 12,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Top Performers', style: TextStyle(color: AppColors.cyan, fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          if (topBats.isNotEmpty) ...[
            const Text('Best Batters', style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ...topBats.asMap().entries.map((e) {
              final b = e.value;
              final notOut = b.isNotOut ? '*' : '';
              return _buildPerformerRow(b.name, '${b.runs}$notOut (${b.balls})', e.key == 0 ? AppColors.green : AppColors.textPrimary);
            }),
          ],
          if (topBowls.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('Best Bowlers', style: TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ...topBowls.asMap().entries.map((e) {
              final b = e.value;
              return _buildPerformerRow(b.name, '${b.wickets}/${b.runs} (${b.overs})', e.key == 0 ? AppColors.green : AppColors.textPrimary);
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildPerformerRow(String name, String stat, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 32, height: 32,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.cardBg2),
            child: const Icon(Icons.person, color: AppColors.textMuted, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(name, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600))),
          Text(stat, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String val1, String val2) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(val1, style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
          Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          Text(val2, style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
