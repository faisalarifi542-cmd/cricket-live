import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../models/api/api_match_detail_model.dart';
import '../../models/api/api_scorecard_model.dart';
import '../../widgets/glass_card.dart';
import '../../core/utils/cricket_helpers.dart';

class ScorecardTab extends StatefulWidget {
  final ApiScorecard? scorecard;
  final ApiMatchDetail? matchDetail;

  const ScorecardTab({super.key, this.scorecard, this.matchDetail});

  @override
  State<ScorecardTab> createState() => _ScorecardTabState();
}

class _ScorecardTabState extends State<ScorecardTab> {
  int _selectedInnings = 0;
  bool _fowExpanded = false;
  bool _partnershipExpanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.scorecard == null || widget.scorecard!.innings.isEmpty) {
      // Show innings summary fallback from match detail if available
      if (widget.matchDetail != null && widget.matchDetail!.innings.isNotEmpty) {
        return _buildSummaryFallback(widget.matchDetail!);
      }
      // Premium empty state based on match status
      final isUpcoming = widget.matchDetail?.status == 'upcoming' || (widget.matchDetail?.innings.isEmpty ?? true);
      return _buildScorecardEmptyState(isUpcoming);
    }
    final innings = widget.scorecard!.innings;
    final current = innings[_selectedInnings.clamp(0, innings.length - 1)];

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 105),
      child: Column(
        children: [
          const SizedBox(height: 8),
          _buildScoreHeader(innings),
          const SizedBox(height: 8),
          _buildInningsSwitch(innings),
          const SizedBox(height: 6),
          _buildBattingTable(current),
          const SizedBox(height: 4),
          _buildExtras(current),
          const SizedBox(height: 8),
          _buildBowlingTable(current),
          const SizedBox(height: 6),
          _buildCollapsibleSection('Fall of Wickets', _fowExpanded, () => setState(() => _fowExpanded = !_fowExpanded), current),
          const SizedBox(height: 6),
          _buildCollapsibleSection('Partnerships', _partnershipExpanded, () => setState(() => _partnershipExpanded = !_partnershipExpanded), current),
        ],
      ),
    );
  }

  Widget _buildScorecardEmptyState(bool isUpcoming) {
    return Center(
      child: GlassCard(
        margin: const EdgeInsets.symmetric(horizontal: 32, vertical: 60),
        padding: const EdgeInsets.all(24),
        borderRadius: 16,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isUpcoming ? Icons.schedule : Icons.scoreboard_outlined,
              color: AppColors.cyan.withOpacity(0.5),
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              isUpcoming ? 'Scorecard will be available\nafter the match starts' : 'Scorecard not available\nfor this match',
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600, height: 1.4),
              textAlign: TextAlign.center,
            ),
            if (widget.matchDetail != null && widget.matchDetail!.startTime != null && isUpcoming) ...[
              const SizedBox(height: 10),
              Text(
                'Match starts at ${formatMatchTime(widget.matchDetail!.startTime)}',
                style: const TextStyle(color: AppColors.cyan, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildScoreHeader(List<ApiScorecardInnings> innings) {
    return GlassCard(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      borderRadius: 14,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: innings.map((inn) => _buildTeamScore(inn.battingTeam, '${inn.total.runs}/${inn.total.wickets}', '(${formatCricketOvers(inn.total.overs)})')).toList(),
          ),
          if (widget.matchDetail?.statusText.isNotEmpty == true) ...[
            const SizedBox(height: 6),
            Text(
              widget.matchDetail!.statusText,
              style: const TextStyle(color: AppColors.green, fontSize: 12, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTeamScore(String team, String score, String overs) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(team, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(width: 4),
        Text(score, style: const TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(width: 3),
        Text(overs, style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
      ],
    );
  }

  Widget _buildInningsSwitch(List<ApiScorecardInnings> innings) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderColor.withOpacity(0.4)),
      ),
      child: Row(
        children: innings.asMap().entries.map((entry) {
          return _buildInningsTab('${entry.value.battingTeam} Innings', entry.key);
        }).toList(),
      ),
    );
  }

  Widget _buildInningsTab(String label, int index) {
    final isActive = _selectedInnings == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() { _selectedInnings = index; _fowExpanded = false; _partnershipExpanded = false; }),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: isActive ? AppColors.blue.withOpacity(0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: isActive ? Border.all(color: AppColors.blue.withOpacity(0.4)) : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isActive ? AppColors.textPrimary : AppColors.textMuted,
              fontSize: 12,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }

  Widget _buildBattingTable(ApiScorecardInnings inn) {
    final batters = inn.batting.where((b) => b.didBat).toList();
    return GlassCard(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(10),
      borderRadius: 12,
      child: Column(
        children: [
          Row(
            children: const [
              Expanded(flex: 4, child: Text('Batter', style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w600))),
              Expanded(child: Text('R', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w600))),
              Expanded(child: Text('B', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w600))),
              Expanded(child: Text('4s', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w600))),
              Expanded(child: Text('6s', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w600))),
              Expanded(child: Text('SR', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w600))),
            ],
          ),
          const Divider(color: AppColors.borderColor, height: 8),
          ...batters.map((b) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(flex: 4, child: Text(b.name, style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
                    Expanded(child: Text('${b.runs}', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w700))),
                    Expanded(child: Text('${b.balls}', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted, fontSize: 11))),
                    Expanded(child: Text('${b.fours}', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted, fontSize: 11))),
                    Expanded(child: Text('${b.sixes}', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted, fontSize: 11))),
                    Expanded(child: Text(b.strikeRate.toStringAsFixed(1), textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted, fontSize: 10))),
                  ],
                ),
                if (b.dismissal.isNotEmpty && b.dismissal != 'not out')
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(b.dismissal, style: const TextStyle(color: AppColors.textMuted, fontSize: 9), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
              ],
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildExtras(ApiScorecardInnings inn) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Extras: ${inn.extras.breakdown}', style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
          Text('Total: ${inn.total.text}', style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _buildBowlingTable(ApiScorecardInnings inn) {
    return GlassCard(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(10),
      borderRadius: 12,
      child: Column(
        children: [
          Row(
            children: const [
              Expanded(flex: 4, child: Text('Bowler', style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w600))),
              Expanded(child: Text('O', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w600))),
              Expanded(child: Text('M', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w600))),
              Expanded(child: Text('R', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w600))),
              Expanded(child: Text('W', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w600))),
              Expanded(child: Text('ER', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w600))),
            ],
          ),
          const Divider(color: AppColors.borderColor, height: 8),
          ...inn.bowling.map((b) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Expanded(flex: 4, child: Text(b.name, style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
                Expanded(child: Text('${b.overs}', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted, fontSize: 11))),
                Expanded(child: Text('${b.maidens}', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted, fontSize: 11))),
                Expanded(child: Text('${b.runs}', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w600))),
                Expanded(child: Text('${b.wickets}', textAlign: TextAlign.center, style: TextStyle(color: b.wickets > 0 ? AppColors.green : AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w700))),
                Expanded(child: Text(b.economy.toStringAsFixed(1), textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted, fontSize: 10))),
              ],
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildCollapsibleSection(String title, bool expanded, VoidCallback onTap, ApiScorecardInnings inn) {
    final hasFow = inn.fallOfWickets.isNotEmpty;
    final hasPartnership = inn.partnerships.isNotEmpty;
    final hasData = title == 'Fall of Wickets' ? hasFow : hasPartnership;

    return GestureDetector(
      onTap: hasData ? onTap : null,
      child: GlassCard(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        borderRadius: 12,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
                Icon(
                  !hasData ? Icons.block : (expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down),
                  color: AppColors.textMuted, size: 18,
                ),
              ],
            ),
            if (!hasData)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('Data not available from API', style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
              ),
            if (expanded && hasData) ...[
              const SizedBox(height: 8),
              Divider(color: AppColors.borderColor.withOpacity(0.3), height: 1),
              const SizedBox(height: 8),
              if (title == 'Fall of Wickets')
                ...inn.fallOfWickets.map((fow) => _buildFowRow(
                  '${fow.wicketNumber}',
                  '${fow.runs}/${fow.wicketNumber}',
                  '${fow.overs} ov',
                  fow.player,
                ))
              else
                ...inn.partnerships.asMap().entries.map((e) {
                  final p = e.value;
                  final batters = [p.bat1?.name ?? '', p.bat2?.name ?? ''].where((s) => s.isNotEmpty).join(' & ');
                  return _buildPartnershipRow(
                    'Wkt ${e.key + 1}',
                    '${p.runs} (${p.balls})',
                    batters,
                  );
                }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFowRow(String wicket, String score, String over, [String? player]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(width: 25, child: Text(wicket, style: const TextStyle(color: AppColors.textMuted, fontSize: 11))),
          Expanded(child: Text(score, style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w600))),
          if (player != null && player.isNotEmpty)
            Expanded(child: Text(player, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10), overflow: TextOverflow.ellipsis)),
          Text(over, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildSummaryFallback(ApiMatchDetail md) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 105),
      child: Column(
        children: [
          const SizedBox(height: 16),
          GlassCard(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.all(14),
            borderRadius: 14,
            child: Column(
              children: [
                const Text('Match Summary', style: TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                ...md.innings.map((inn) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(child: Text(inn.battingTeam, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600))),
                      Text('${inn.runs}/${inn.wickets}', style: const TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w800)),
                      const SizedBox(width: 6),
                      Text('(${formatCricketOvers(inn.overs)} ov)', style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                    ],
                  ),
                )),
                if (md.statusText.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(md.statusText, style: const TextStyle(color: AppColors.green, fontSize: 12, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.blue.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.blue.withOpacity(0.2)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: AppColors.blue, size: 16),
                  SizedBox(width: 8),
                  Expanded(child: Text('Detailed scorecard will be available shortly', style: TextStyle(color: AppColors.textSecondary, fontSize: 11))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPartnershipRow(String wicket, String runs, String batters) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text(wicket, style: const TextStyle(color: AppColors.textMuted, fontSize: 11))),
          Expanded(flex: 2, child: Text(runs, style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w600))),
          Expanded(flex: 3, child: Text(batters, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11))),
        ],
      ),
    );
  }
}
