import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/network/network_result.dart';
import '../data/repositories/cricket_repository.dart';
import '../models/api/api_schedule_model.dart';
import '../widgets/custom_header.dart';
import '../widgets/pill_chip.dart';
import '../widgets/api_state_widgets.dart';
import '../core/utils/cricket_helpers.dart';
import 'match_detail/match_detail_screen.dart';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  final _repo = CricketRepository.instance;
  final _types = ['all', 'international', 'league', 'domestic', 'women'];
  final _labels = ['All', 'International', 'League', 'Domestic', 'Women'];
  int _activeType = 0;
  ApiSchedule? _schedule;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadSchedule();
  }

  Future<void> _loadSchedule() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    final result = await _repo.getUpcomingSchedule(type: _types[_activeType]);
    if (mounted) {
      setState(() {
        _isLoading = false;
        if (result is NetworkSuccess<ApiSchedule>) {
          _schedule = result.data;
        } else if (result is NetworkError<ApiSchedule>) {
          _errorMessage = result.exception.message;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
        child: SafeArea(
          child: Column(
            children: [
              const CustomHeader(showBackButton: true),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: const [
                    Icon(Icons.calendar_month, color: AppColors.cyan, size: 20),
                    SizedBox(width: 8),
                    Text('Match Schedule', style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w800)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              _buildTypeChips(),
              const SizedBox(height: 8),
              Expanded(
                child: _isLoading
                    ? const LoadingWidget(message: 'Loading schedule...')
                    : _errorMessage != null
                        ? ErrorRetryWidget(message: _errorMessage!, onRetry: _loadSchedule)
                        : _schedule == null || _schedule!.days.isEmpty
                            ? const EmptyStateWidget(message: 'No upcoming matches found')
                            : RefreshIndicator(
                                color: AppColors.cyan,
                                backgroundColor: AppColors.cardBg,
                                onRefresh: _loadSchedule,
                                child: ListView.builder(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                  itemCount: _schedule!.days.length,
                                  itemBuilder: (context, index) => _buildDaySection(_schedule!.days[index]),
                                ),
                              ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTypeChips() {
    return SizedBox(
      height: 34,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _labels.length,
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: PillChip(
            label: _labels[index],
            isActive: index == _activeType,
            activeColor: AppColors.cyan,
            onTap: () {
              if (index != _activeType) {
                setState(() => _activeType = index);
                _loadSchedule();
              }
            },
          ),
        ),
      ),
    );
  }

  Widget _buildDaySection(ApiScheduleDay day) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.cyan.withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            day.date,
            style: const TextStyle(color: AppColors.cyan, fontSize: 12, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 8),
        ...day.series.map((series) => _buildSeriesGroup(series)),
      ],
    );
  }

  Widget _buildSeriesGroup(ApiScheduleSeries series) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  series.seriesName,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (series.category.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(color: AppColors.purple.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
                  child: Text(series.category, style: const TextStyle(color: AppColors.purple, fontSize: 9, fontWeight: FontWeight.w600)),
                ),
            ],
          ),
        ),
        ...series.matches.map((match) => _buildMatchTile(match)),
        const SizedBox(height: 6),
      ],
    );
  }

  Widget _buildMatchTile(ApiScheduleMatch match) {
    final startDt = match.startDateTime;
    final timeStr = startDt != null ? formatMatchTime(startDt) : '';

    return GestureDetector(
      onTap: () {
        if (match.matchId.isNotEmpty) {
          final title = [match.team1?.name, match.team2?.name].where((n) => n != null && n.isNotEmpty).join(' vs ');
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => MatchDetailScreen(
              matchId: match.matchId,
              matchTitle: title.isNotEmpty ? title : match.matchDesc,
              matchStatus: 'upcoming',
            ),
          ));
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.borderColor.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    match.matchDesc,
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (match.team1 != null)
                        Expanded(
                          child: Text(
                            match.team1!.shortName.isNotEmpty ? match.team1!.shortName : match.team1!.name,
                            style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      const Text(' vs ', style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
                      if (match.team2 != null)
                        Expanded(
                          child: Text(
                            match.team2!.shortName.isNotEmpty ? match.team2!.shortName : match.team2!.name,
                            style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                  if (match.venue != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      '${match.venue!.name}, ${match.venue!.city}',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 9),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(color: AppColors.green.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
                  child: Text(match.matchFormat, style: const TextStyle(color: AppColors.green, fontSize: 9, fontWeight: FontWeight.w600)),
                ),
                if (timeStr.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(timeStr, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
