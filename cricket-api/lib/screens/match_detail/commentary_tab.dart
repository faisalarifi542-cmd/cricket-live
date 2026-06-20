import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/network/network_result.dart';
import '../../data/repositories/cricket_repository.dart';
import '../../models/api/api_commentary_model.dart';
import '../../widgets/pill_chip.dart';
import '../../widgets/api_state_widgets.dart';

class CommentaryTab extends StatefulWidget {
  final List<ApiCommentaryEntry> commentary;
  final String? matchId;
  final int? inningsId;

  const CommentaryTab({super.key, this.commentary = const [], this.matchId, this.inningsId});

  @override
  State<CommentaryTab> createState() => _CommentaryTabState();
}

class _CommentaryTabState extends State<CommentaryTab> {
  int _activeFilter = 0;
  final _filters = ['All', 'Wickets', 'Boundaries', '6s'];
  List<ApiCommentaryEntry> _fullCommentary = [];
  bool _isLoading = false;
  bool _loadedFull = false;

  @override
  void initState() {
    super.initState();
    _fullCommentary = List.from(widget.commentary);
    if (widget.matchId != null && widget.inningsId != null && widget.commentary.isEmpty) {
      _loadFullCommentary();
    }
  }

  Future<void> _loadFullCommentary() async {
    if (widget.matchId == null || widget.inningsId == null) return;
    setState(() => _isLoading = true);
    final result = await CricketRepository.instance.getFullCommentary(widget.matchId!, widget.inningsId!);
    if (mounted) {
      setState(() {
        _isLoading = false;
        _loadedFull = true;
        if (result is NetworkSuccess<ApiCommentary>) {
          _fullCommentary = result.data.entries;
        }
      });
    }
  }

  List<ApiCommentaryEntry> get _allEntries => _fullCommentary.isNotEmpty ? _fullCommentary : widget.commentary;

  /// Separate ball-by-ball entries from match notes/preview text
  List<ApiCommentaryEntry> get _ballByBallEntries => _allEntries.where((e) => e.isBallByBall).toList();
  List<ApiCommentaryEntry> get _matchNotes => _allEntries.where((e) => !e.isBallByBall && e.text.length > 20).toList();
  bool _notesExpanded = false;

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const LoadingWidget(message: 'Loading commentary...');
    }
    if (_allEntries.isEmpty) {
      return const EmptyStateWidget(message: 'No commentary available');
    }

    final ballEntries = _ballByBallEntries;
    final notes = _matchNotes;
    final hasBalls = ballEntries.isNotEmpty;

    return Column(
      children: [
        const SizedBox(height: 12),
        if (hasBalls) _buildFilterChips(),
        if (!_loadedFull && widget.matchId != null && widget.inningsId != null) ...[
          const SizedBox(height: 4),
          TextButton.icon(
            onPressed: _loadFullCommentary,
            icon: const Icon(Icons.refresh, size: 14, color: AppColors.cyan),
            label: const Text('Load full commentary', style: TextStyle(color: AppColors.cyan, fontSize: 11)),
          ),
        ],
        const SizedBox(height: 8),
        Expanded(
          child: Builder(
            builder: (context) {
              if (!hasBalls && notes.isNotEmpty) {
                // Only notes available (e.g. upcoming match preview)
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: notes.length,
                  itemBuilder: (context, index) => _buildNoteItem(notes[index]),
                );
              }

              final filtered = _getFiltered();
              if (filtered.isEmpty) {
                return const EmptyStateWidget(message: 'No entries for this filter');
              }

              // Build list: ball-by-ball + optional collapsed notes section at bottom
              final totalCount = filtered.length + (notes.isNotEmpty ? 1 : 0);
              return ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: totalCount,
                separatorBuilder: (_, __) => Divider(
                  color: AppColors.borderColor.withOpacity(0.2),
                  height: 1,
                ),
                itemBuilder: (context, index) {
                  if (index < filtered.length) {
                    return _buildCommentaryRow(filtered[index]);
                  }
                  // Match Notes collapsible section
                  return _buildMatchNotesSection(notes);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  List<ApiCommentaryEntry> _getFiltered() {
    final entries = _ballByBallEntries;
    switch (_activeFilter) {
      case 1:
        return entries.where((e) => e.isWicket).toList();
      case 2:
        return entries.where((e) => e.isFour || e.isSix || e.isBoundary).toList();
      case 3:
        return entries.where((e) => e.isSix).toList();
      default:
        return entries;
    }
  }

  Widget _buildFilterChips() {
    return SizedBox(
      height: 34,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _filters.length,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: PillChip(
              label: _filters[index],
              isActive: index == _activeFilter,
              activeColor: AppColors.cyan,
              onTap: () => setState(() => _activeFilter = index),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMatchNotesSection(List<ApiCommentaryEntry> notes) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => setState(() => _notesExpanded = !_notesExpanded),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.cardBg2,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.notes, size: 16, color: AppColors.textMuted),
                  const SizedBox(width: 8),
                  Text('Match Notes (${notes.length})', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Icon(_notesExpanded ? Icons.expand_less : Icons.expand_more, size: 18, color: AppColors.textMuted),
                ],
              ),
            ),
          ),
          if (_notesExpanded) ...notes.map((n) => _buildNoteItem(n)),
        ],
      ),
    );
  }

  Widget _buildNoteItem(ApiCommentaryEntry entry) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.cardBg2.withOpacity(0.5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.borderColor.withOpacity(0.2)),
        ),
        child: Text(
          entry.text,
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11, height: 1.5),
        ),
      ),
    );
  }

  Widget _buildCommentaryRow(ApiCommentaryEntry entry) {
    Color bubbleColor;
    if (entry.isWicket) {
      bubbleColor = AppColors.red;
    } else if (entry.isSix) {
      bubbleColor = AppColors.purple;
    } else if (entry.isFour) {
      bubbleColor = AppColors.green;
    } else if (entry.totalRuns == 0) {
      bubbleColor = AppColors.textMuted.withOpacity(0.3);
    } else {
      bubbleColor = AppColors.green.withOpacity(0.7);
    }

    final hasBallInfo = entry.isBallByBall;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasBallInfo)
            SizedBox(
              width: 44,
              child: Column(
                children: [
                  Text(
                    entry.overText,
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: 26, height: 26,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: bubbleColor),
                    child: Center(
                      child: Text(
                        entry.outcomeText,
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            const SizedBox(width: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (entry.bowlerName.isNotEmpty && entry.batsmanName.isNotEmpty && hasBallInfo)
                  Text(
                    '${entry.bowlerName} to ${entry.batsmanName}',
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                if (hasBallInfo) const SizedBox(height: 4),
                Text(
                  entry.text,
                  style: TextStyle(
                    color: hasBallInfo ? AppColors.textSecondary : AppColors.textPrimary,
                    fontSize: 11,
                    height: 1.4,
                    fontWeight: hasBallInfo ? FontWeight.w400 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
