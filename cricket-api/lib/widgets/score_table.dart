import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../models/match_model.dart';

class ScoreTable extends StatelessWidget {
  final List<BattingEntry>? batting;
  final List<BowlingEntry>? bowling;

  const ScoreTable({
    super.key,
    this.batting,
    this.bowling,
  });

  @override
  Widget build(BuildContext context) {
    if (batting != null) return _buildBattingTable();
    if (bowling != null) return _buildBowlingTable();
    return const SizedBox();
  }

  Widget _buildBattingTable() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.borderColor.withOpacity(0.4),
        ),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.cardBg2.withOpacity(0.5),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: const Row(
              children: [
                Expanded(flex: 4, child: Text('Batting', style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600))),
                SizedBox(width: 26, child: Text('R', style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600), textAlign: TextAlign.center)),
                SizedBox(width: 26, child: Text('B', style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600), textAlign: TextAlign.center)),
                SizedBox(width: 26, child: Text('4s', style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600), textAlign: TextAlign.center)),
                SizedBox(width: 26, child: Text('6s', style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600), textAlign: TextAlign.center)),
                SizedBox(width: 44, child: Text('SR', style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600), textAlign: TextAlign.center)),
              ],
            ),
          ),
          // Rows
          ...batting!.map((b) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: AppColors.borderColor.withOpacity(0.2),
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 4,
                  child: Text(
                    '${b.name}${b.isNotOut ? '' : ''}',
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SizedBox(width: 26, child: Text('${b.runs}${b.isNotOut ? '*' : ''}', style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w700), textAlign: TextAlign.center)),
                SizedBox(width: 26, child: Text('${b.balls}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11), textAlign: TextAlign.center)),
                SizedBox(width: 26, child: Text('${b.fours}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11), textAlign: TextAlign.center)),
                SizedBox(width: 26, child: Text('${b.sixes}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11), textAlign: TextAlign.center)),
                SizedBox(width: 44, child: Text(b.strikeRate.toStringAsFixed(1), style: const TextStyle(color: AppColors.textSecondary, fontSize: 11), textAlign: TextAlign.center)),
              ],
            ),
          )),
          // Extras
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppColors.borderColor.withOpacity(0.2)),
              ),
            ),
            child: const Row(
              children: [
                Expanded(child: Text('Extras', style: TextStyle(color: AppColors.textSecondary, fontSize: 11))),
                Text('4 (b 0, lb 1, w 3, nb 0)', style: TextStyle(color: AppColors.textSecondary, fontSize: 10)),
              ],
            ),
          ),
          // Total
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: const Row(
              children: [
                Expanded(child: Text('Total', style: TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w700))),
                Text('181/5 (19.0 Overs)', style: TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBowlingTable() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        gradient: AppColors.cardGradient,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.borderColor.withOpacity(0.4),
        ),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.cardBg2.withOpacity(0.5),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: const Row(
              children: [
                Expanded(flex: 4, child: Text('Bowling', style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600))),
                SizedBox(width: 26, child: Text('O', style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600), textAlign: TextAlign.center)),
                SizedBox(width: 26, child: Text('M', style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600), textAlign: TextAlign.center)),
                SizedBox(width: 26, child: Text('R', style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600), textAlign: TextAlign.center)),
                SizedBox(width: 26, child: Text('W', style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600), textAlign: TextAlign.center)),
                SizedBox(width: 44, child: Text('Econ', style: TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600), textAlign: TextAlign.center)),
              ],
            ),
          ),
          ...bowling!.map((b) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppColors.borderColor.withOpacity(0.2)),
              ),
            ),
            child: Row(
              children: [
                Expanded(flex: 4, child: Text(b.name, style: const TextStyle(color: AppColors.textPrimary, fontSize: 11, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
                SizedBox(width: 26, child: Text('${b.overs.toInt()}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11), textAlign: TextAlign.center)),
                SizedBox(width: 26, child: Text('${b.maidens}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11), textAlign: TextAlign.center)),
                SizedBox(width: 26, child: Text('${b.runs}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11), textAlign: TextAlign.center)),
                SizedBox(width: 26, child: Text('${b.wickets}', style: TextStyle(color: b.wickets > 0 ? AppColors.cyan : AppColors.textSecondary, fontSize: 11, fontWeight: b.wickets > 0 ? FontWeight.w700 : FontWeight.w400), textAlign: TextAlign.center)),
                SizedBox(width: 44, child: Text(b.economy.toStringAsFixed(2), style: const TextStyle(color: AppColors.textSecondary, fontSize: 11), textAlign: TextAlign.center)),
              ],
            ),
          )),
        ],
      ),
    );
  }
}
