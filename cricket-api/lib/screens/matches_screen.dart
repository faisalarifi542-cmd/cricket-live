import 'dart:async';
import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/network/network_result.dart';
import '../core/utils/cricket_helpers.dart';
import '../data/repositories/cricket_repository.dart';
import '../models/api/api_match_model.dart';
import '../models/api/api_schedule_model.dart';
import '../widgets/custom_header.dart';
import '../widgets/pill_chip.dart';
import '../widgets/api_match_card.dart';
import '../widgets/api_state_widgets.dart';
import '../widgets/glass_card.dart';
import '../widgets/team_logo.dart';
import 'match_detail/match_detail_screen.dart';

class MatchesScreen extends StatefulWidget {
  const MatchesScreen({super.key});

  @override
  State<MatchesScreen> createState() => _MatchesScreenState();
}

class _MatchesScreenState extends State<MatchesScreen> {
  int _activeTab = 1;
  int _activeFilter = 0;
  Timer? _refreshTimer;

  final _tabs = ['Live', 'Upcoming', 'Results'];
  final _filters = ['All', 'T20', 'ODI', 'Test'];
  final _scheduleTypes = ['All', 'International', 'League', 'Domestic', 'Women'];
  final _scheduleTypeKeys = ['all', 'international', 'league', 'domestic', 'women'];
  final _repo = CricketRepository.instance;

  List<ApiMatch> _liveMatches = [];
  List<ApiMatch> _upcomingMatches = [];
  List<ApiMatch> _recentMatches = [];
  ApiSchedule? _schedule;
  int _activeScheduleType = 2; // Default to League
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadData();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) => _loadData(silent: true));
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData({bool silent = false}) async {
    if (!silent) setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final results = await Future.wait([
        _repo.getLiveMatches(),
        _repo.getUpcomingMatches(),
        _repo.getRecentMatches(),
        _repo.getUpcomingSchedule(type: _scheduleTypeKeys[_activeScheduleType]),
      ]);
      if (mounted) {
        setState(() {
          _liveMatches = results[0] is NetworkSuccess<List<ApiMatch>> ? (results[0] as NetworkSuccess<List<ApiMatch>>).data : [];
          _upcomingMatches = results[1] is NetworkSuccess<List<ApiMatch>> ? (results[1] as NetworkSuccess<List<ApiMatch>>).data : [];
          _recentMatches = results[2] is NetworkSuccess<List<ApiMatch>> ? (results[2] as NetworkSuccess<List<ApiMatch>>).data : [];
          _schedule = results[3] is NetworkSuccess<ApiSchedule> ? (results[3] as NetworkSuccess<ApiSchedule>).data : null;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted && !silent) setState(() { _isLoading = false; _errorMessage = e.toString(); });
    }
  }

  List<ApiMatch> get _currentMatches {
    List<ApiMatch> list;
    switch (_activeTab) {
      case 0: list = _liveMatches; break;
      case 2: list = _recentMatches; break;
      default: list = [];
    }
    if (_activeFilter == 0) return list;
    final format = _filters[_activeFilter].toLowerCase();
    return list.where((m) => m.matchFormat.toLowerCase() == format).toList();
  }

  void _switchScheduleType(int index) {
    if (_activeScheduleType == index) return;
    setState(() => _activeScheduleType = index);
    _loadScheduleOnly();
  }

  Future<void> _loadScheduleOnly() async {
    final result = await _repo.getUpcomingSchedule(type: _scheduleTypeKeys[_activeScheduleType]);
    if (mounted) {
      setState(() {
        _schedule = result is NetworkSuccess<ApiSchedule> ? result.data : null;
      });
    }
  }

  /// Check if we should use the schedule-based view for Upcoming tab
  bool get _useScheduleView {
    if (_activeTab != 1) return false;
    if (_schedule != null && _schedule!.days.isNotEmpty) return true;
    return false;
  }

  /// Get schedule days (already filtered by type via API call)
  List<ApiScheduleDay> get _filteredScheduleDays {
    if (_schedule == null) return [];
    return _schedule!.days;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
      child: Column(
        children: [
          const CustomHeader(),
          _buildTabs(),
          const SizedBox(height: 8),
          _buildFilters(),
          const SizedBox(height: 10),
          Expanded(
            child: _isLoading
                ? const LoadingWidget(message: 'Loading matches...')
                : _errorMessage != null
                    ? ErrorRetryWidget(message: _errorMessage!, onRetry: _loadData)
                    : RefreshIndicator(
                        color: AppColors.cyan,
                        backgroundColor: AppColors.cardBg,
                        onRefresh: _loadData,
                        child: _useScheduleView
                            ? _buildUpcomingScheduleList()
                            : _buildMatchList(),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildMatchList() {
    final matches = _currentMatches;
    if (matches.isEmpty) {
      // If on upcoming tab but schedule is empty too, show fallback
      if (_activeTab == 1 && _upcomingMatches.isNotEmpty) {
        final filtered = _activeFilter == 0
            ? _upcomingMatches
            : _upcomingMatches.where((m) => m.matchFormat.toLowerCase() == _filters[_activeFilter].toLowerCase()).toList();
        if (filtered.isNotEmpty) {
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 90),
            itemCount: filtered.length,
            itemBuilder: (context, index) => _buildApiMatchCardWithNav(filtered[index]),
          );
        }
      }
      return ListView(
        children: const [SizedBox(height: 100), EmptyStateWidget(message: 'No matches found')],
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 90),
      itemCount: matches.length,
      itemBuilder: (context, index) => _buildApiMatchCardWithNav(matches[index]),
    );
  }

  Widget _buildApiMatchCardWithNav(ApiMatch match) {
    return ApiMatchCard(
      match: match,
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MatchDetailScreen(
              matchId: match.matchId,
              matchTitle: match.title,
              matchStatus: match.status,
            ),
          ),
        );
      },
    );
  }

  /// Build the Upcoming tab with grouped day cards from schedule API
  Widget _buildUpcomingScheduleList() {
    final days = _filteredScheduleDays;
    if (days.isEmpty) {
      // Fallback to normal upcoming match list
      if (_upcomingMatches.isNotEmpty) {
        final filtered = _activeFilter == 0
            ? _upcomingMatches
            : _upcomingMatches.where((m) => m.matchFormat.toLowerCase() == _filters[_activeFilter].toLowerCase()).toList();
        if (filtered.isNotEmpty) {
          return ListView.builder(
            padding: const EdgeInsets.only(bottom: 90),
            itemCount: filtered.length,
            itemBuilder: (context, index) => _buildApiMatchCardWithNav(filtered[index]),
          );
        }
      }
      return ListView(
        children: const [SizedBox(height: 100), EmptyStateWidget(message: 'No upcoming matches')],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 90),
      itemCount: days.length,
      itemBuilder: (context, dayIndex) {
        final day = days[dayIndex];
        return _buildDayGroup(day);
      },
    );
  }

  Widget _buildDayGroup(ApiScheduleDay day) {
    // Parse the day's date for "Today" / "Tomorrow" formatting
    final dateLabel = _formatDayLabel(day.date);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Text(
            dateLabel,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
        ...day.series.expand((series) => series.matches.map((match) => _buildScheduleMatchCard(match, series.seriesName))),
      ],
    );
  }

  String _formatDayLabel(String dateStr) {
    // dateStr is like "FRI, MAY 22 2026"
    try {
      // Parse "FRI, MAY 22 2026" -> remove day prefix
      final cleaned = dateStr.contains(',') ? dateStr.substring(dateStr.indexOf(',') + 1).trim() : dateStr;
      final parts = cleaned.split(' ');
      if (parts.length >= 3) {
        final monthStr = parts[0];
        final dayNum = parts[1];
        final yearStr = parts[2];
        final months = {'JAN': '01', 'FEB': '02', 'MAR': '03', 'APR': '04', 'MAY': '05', 'JUN': '06', 'JUL': '07', 'AUG': '08', 'SEP': '09', 'OCT': '10', 'NOV': '11', 'DEC': '12'};
        final month = months[monthStr.toUpperCase()] ?? '01';
        final dt = DateTime.tryParse('$yearStr-$month-${dayNum.padLeft(2, '0')}');
        if (dt != null) return formatDateGroup(dt);
      }
    } catch (_) {}
    return dateStr;
  }

  Widget _buildScheduleMatchCard(ApiScheduleMatch match, String seriesName) {
    final startDt = match.startDateTime;
    final timeStr = startDt != null ? formatMatchTime(startDt) : '';
    final team1Name = match.team1?.shortName ?? match.team1?.name ?? 'TBA';
    final team2Name = match.team2?.shortName ?? match.team2?.name ?? 'TBA';
    final venueLine = match.venue != null
        ? [match.venue!.name, match.venue!.city].where((s) => s.isNotEmpty).join(', ')
        : '';

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => MatchDetailScreen(
            matchId: match.matchId,
            matchTitle: '$team1Name vs $team2Name',
            matchStatus: 'upcoming',
          ),
        ));
      },
      child: GlassCard(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        padding: const EdgeInsets.all(14),
        borderRadius: 14,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: format + series name + time
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.cyan.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    match.matchFormat.toUpperCase(),
                    style: const TextStyle(color: AppColors.cyan, fontSize: 9, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${match.matchDesc} \u2022 $seriesName',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (timeStr.isNotEmpty)
                  Text(timeStr, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 12),
            // Row 2: Team 1 VS Team 2
            Row(
              children: [
                TeamLogo(
                  shortName: team1Name,
                  logoUrl: match.team1?.logoUrl,
                  size: 32,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(match.team1?.name ?? team1Name, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                const Text('VS', style: TextStyle(color: AppColors.textMuted, fontSize: 11, fontWeight: FontWeight.w700)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(match.team2?.name ?? team2Name, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                TeamLogo(
                  shortName: team2Name,
                  logoUrl: match.team2?.logoUrl,
                  size: 32,
                ),
              ],
            ),
            // Row 3: Venue
            if (venueLine.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.location_on_outlined, size: 12, color: AppColors.textMuted),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(venueLine, style: const TextStyle(color: AppColors.textMuted, fontSize: 10), overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.notifications_none, size: 16, color: AppColors.textMuted),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AppColors.borderColor.withOpacity(0.3),
          ),
        ),
      ),
      child: Row(
        children: _tabs.asMap().entries.map((entry) {
          final isActive = entry.key == _activeTab;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _activeTab = entry.key),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: isActive ? AppColors.cyan : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                child: Text(
                  entry.value,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isActive ? AppColors.textPrimary : AppColors.textMuted,
                    fontSize: 14,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildFilters() {
    // When on Upcoming tab, show schedule type filters instead of format filters
    if (_activeTab == 1) {
      return SizedBox(
        height: 36,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: _scheduleTypes.length,
          itemBuilder: (context, index) {
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: PillChip(
                label: _scheduleTypes[index],
                isActive: index == _activeScheduleType,
                activeColor: AppColors.cyan,
                onTap: () => _switchScheduleType(index),
              ),
            );
          },
        ),
      );
    }

    return SizedBox(
      height: 36,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _filters.length + 1,
        itemBuilder: (context, index) {
          if (index == _filters.length) {
            return Padding(
              padding: const EdgeInsets.only(left: 8),
              child: GestureDetector(
                onTap: _showDatePicker,
                child: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: AppColors.cardBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.borderColor.withOpacity(0.5)),
                  ),
                  child: const Icon(Icons.calendar_today, color: AppColors.textMuted, size: 15),
                ),
              ),
            );
          }
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

  void _showDatePicker() async {
    await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime(2027),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(primary: AppColors.cyan, surface: AppColors.cardBg),
          ),
          child: child!,
        );
      },
    );
  }
}
