import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/network/network_result.dart';
import '../../data/repositories/cricket_repository.dart';
import '../../models/api/api_match_detail_model.dart';
import '../../models/api/api_scorecard_model.dart';
import '../../models/api/api_commentary_model.dart';
import '../../widgets/custom_header.dart';
import '../../widgets/api_state_widgets.dart';
import 'live_tab.dart';
import 'scorecard_tab.dart';
import 'commentary_tab.dart';
import 'stats_tab.dart';
import 'fantasy_tab.dart';

class MatchDetailScreen extends StatefulWidget {
  final String matchId;
  final int initialTab;
  final String? matchTitle;
  final String? matchStatus;

  const MatchDetailScreen({
    super.key,
    required this.matchId,
    this.initialTab = 0,
    this.matchTitle,
    this.matchStatus,
  });

  @override
  State<MatchDetailScreen> createState() => _MatchDetailScreenState();
}

class _MatchDetailScreenState extends State<MatchDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _tabs = ['Live', 'Scorecard', 'Commentary', 'Stats', 'Fantasy'];
  final _repo = CricketRepository.instance;
  Timer? _refreshTimer;

  ApiMatchDetail? _matchDetail;
  ApiScorecard? _scorecard;
  List<ApiCommentaryEntry> _commentary = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: _tabs.length,
      vsync: this,
      initialIndex: widget.initialTab,
    );
    _loadData();
    _refreshTimer = Timer.periodic(const Duration(seconds: 20), (_) => _loadData(silent: true));
  }

  @override
  void dispose() {
    _tabController.dispose();
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadData({bool silent = false}) async {
    if (!silent) setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final results = await Future.wait([
        _repo.getMatchDetail(widget.matchId),
        _repo.getMatchScorecard(widget.matchId),
        _repo.getMatchCommentary(widget.matchId),
      ]);

      final detailResult = results[0] as NetworkResult<ApiMatchDetail>;
      final scorecardResult = results[1] as NetworkResult<ApiScorecard>;
      final commentaryResult = results[2] as NetworkResult<List<ApiCommentaryEntry>>;

      if (mounted) {
        setState(() {
          _matchDetail = detailResult is NetworkSuccess<ApiMatchDetail> ? detailResult.data : _matchDetail;
          _scorecard = scorecardResult is NetworkSuccess<ApiScorecard> ? scorecardResult.data : _scorecard;
          _commentary = commentaryResult is NetworkSuccess<List<ApiCommentaryEntry>> ? commentaryResult.data : _commentary;
          _isLoading = false;
          _errorMessage = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          if (!silent && _matchDetail == null) _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              const CustomHeader(showBackButton: true),
              _buildMatchHeader(),
              _buildTabBar(),
              Expanded(
                child: _isLoading
                    ? const LoadingWidget(message: 'Loading match...')
                    : _errorMessage != null && _matchDetail == null
                        ? ErrorRetryWidget(message: _errorMessage!, onRetry: _loadData)
                        : TabBarView(
                            controller: _tabController,
                            children: [
                              LiveTab(matchDetail: _matchDetail),
                              ScorecardTab(scorecard: _scorecard, matchDetail: _matchDetail),
                              CommentaryTab(
                                commentary: _commentary,
                                matchId: widget.matchId,
                                inningsId: _scorecard?.innings.isNotEmpty == true ? _scorecard!.innings.last.inningsNumber : null,
                              ),
                              StatsTab(matchDetail: _matchDetail, scorecard: _scorecard),
                              FantasyTab(matchDetail: _matchDetail, scorecard: _scorecard),
                            ],
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMatchHeader() {
    final md = _matchDetail;
    final title = md?.title ?? widget.matchTitle ?? 'Match Details';
    final isLive = md?.isLive ?? (widget.matchStatus == 'live');
    final status = md?.status ?? widget.matchStatus ?? '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (status.isNotEmpty) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: (isLive ? AppColors.red : AppColors.green).withOpacity(0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                isLive ? 'LIVE' : status.toUpperCase(),
                style: TextStyle(
                  color: isLive ? AppColors.red : AppColors.green,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AppColors.borderColor.withOpacity(0.3),
          ),
        ),
      ),
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        indicatorColor: AppColors.cyan,
        indicatorWeight: 2,
        labelColor: AppColors.textPrimary,
        unselectedLabelColor: AppColors.textMuted,
        labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
        labelPadding: const EdgeInsets.symmetric(horizontal: 12),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        tabs: _tabs.map((t) => Tab(text: t, height: 34)).toList(),
      ),
    );
  }
}
