import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/network/network_result.dart';
import '../data/repositories/cricket_repository.dart';
import '../models/api/api_match_model.dart';
import '../models/api/api_series_stats_model.dart';
import '../models/news_model.dart';
import 'news_detail_screen.dart';
import '../widgets/custom_header.dart';
import '../widgets/glass_card.dart';
import '../widgets/api_match_card.dart';
import '../widgets/api_state_widgets.dart';
import '../widgets/team_logo.dart';
import 'match_detail/match_detail_screen.dart';

class SeriesDetailScreen extends StatefulWidget {
  final String seriesId;
  final String seriesName;

  const SeriesDetailScreen({super.key, required this.seriesId, required this.seriesName});

  @override
  State<SeriesDetailScreen> createState() => _SeriesDetailScreenState();
}

class _SeriesDetailScreenState extends State<SeriesDetailScreen> {
  final _repo = CricketRepository.instance;
  List<ApiMatch> _matches = [];
  List<ApiSeriesStatType> _statTypes = [];
  ApiSeriesStatsTable? _selectedStatsTable;
  String? _selectedStatType;
  bool _isLoading = true;
  bool _isLoadingStats = false;
  String? _errorMessage;
  List<NewsModel> _seriesNews = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    final results = await Future.wait([
      _repo.getSeriesMatches(widget.seriesId),
      _repo.getSeriesStatsTypes(widget.seriesId),
      _repo.getSeriesNews(widget.seriesId),
    ]);
    if (mounted) {
      setState(() {
        _isLoading = false;
        final matchResult = results[0] as NetworkResult<List<ApiMatch>>;
        final statsResult = results[1] as NetworkResult<ApiSeriesStatsTypes>;
        if (matchResult is NetworkSuccess<List<ApiMatch>>) {
          // STRICT safety filter: only show matches whose seriesId matches this series
          // Never trust backend blindly — verify each match belongs here
          _matches = matchResult.data.where((m) {
            final matchSeriesId = m.seriesId;
            if (matchSeriesId.isEmpty) {
              // No series ID — cannot verify, exclude it
              debugPrint('[SeriesDetail] Filtered out match ${m.matchId} (${m.title}): empty seriesId');
              return false;
            }
            if (matchSeriesId != widget.seriesId) {
              debugPrint('[SeriesDetail] Filtered out match ${m.matchId} (${m.title}): seriesId $matchSeriesId != ${widget.seriesId}');
              return false;
            }
            return true;
          }).toList();
          debugPrint('[SeriesDetail] Series ${widget.seriesId}: ${matchResult.data.length} fetched, ${_matches.length} after filter');
        } else if (matchResult is NetworkError<List<ApiMatch>>) {
          _errorMessage = matchResult.exception.message;
        }
        if (statsResult is NetworkSuccess<ApiSeriesStatsTypes>) {
          _statTypes = statsResult.data.types;
          if (_statTypes.isNotEmpty && _selectedStatType == null) {
            _selectedStatType = _statTypes.first.value;
            _loadStatsTable(_selectedStatType!);
          }
        }
        final newsResult = results[2] as NetworkResult<NewsListResponse>;
        if (newsResult is NetworkSuccess<NewsListResponse>) {
          _seriesNews = newsResult.data.stories;
        }
      });
    }
  }

  Future<void> _loadStatsTable(String statType) async {
    setState(() { _isLoadingStats = true; _selectedStatType = statType; });
    final result = await _repo.getSeriesStatsTable(widget.seriesId, statType);
    if (mounted) {
      setState(() {
        _isLoadingStats = false;
        if (result is NetworkSuccess<ApiSeriesStatsTable>) {
          _selectedStatsTable = result.data;
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
              Expanded(
                child: _isLoading
                    ? Column(
                        children: [
                          _buildBanner(),
                          const Expanded(child: LoadingWidget(message: 'Loading series...')),
                        ],
                      )
                    : _errorMessage != null
                        ? Column(
                            children: [
                              _buildBanner(),
                              Expanded(child: ErrorRetryWidget(message: _errorMessage!, onRetry: _loadData)),
                            ],
                          )
                        : RefreshIndicator(
                            color: AppColors.cyan,
                            backgroundColor: AppColors.cardBg,
                            onRefresh: _loadData,
                            child: SingleChildScrollView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildBanner(),
                                  const SizedBox(height: 16),
                                  _buildMatchesSection(),
                                  const SizedBox(height: 16),
                                  _buildSeriesStats(),
                                  const SizedBox(height: 16),
                                  _buildTeams(),
                                  const SizedBox(height: 16),
                                  _buildPointsTable(),
                                  const SizedBox(height: 16),
                                  _buildSeriesNewsSection(),
                                  const SizedBox(height: 24),
                                ],
                              ),
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBanner() {
    return Container(
      width: double.infinity,
      height: 120,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1A3A6C),
            Color(0xFF0D2247),
            Color(0xFF081838),
          ],
        ),
        border: Border.all(color: AppColors.borderColor.withOpacity(0.5)),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(17),
              child: CustomPaint(painter: _SeriesBannerPainter()),
            ),
          ),
          Positioned(
            left: 20,
            bottom: 16,
            right: 20,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.seriesName,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w800),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  '${_matches.length} matches',
                  style: const TextStyle(color: AppColors.cyan, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMatchesSection() {
    if (_matches.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: EmptyStateWidget(message: 'No matches found in this series'),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('Matches', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 10),
        ..._matches.map((match) => ApiMatchCard(
              match: match,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => MatchDetailScreen(matchId: match.matchId)),
                );
              },
            )),
      ],
    );
  }

  Widget _buildTeams() {
    // Collect unique teams with their logo URLs
    final teamMap = <String, ApiTeam>{};
    for (final m in _matches) {
      if (m.team1.name.isNotEmpty) {
        final key = m.team1.shortName.isNotEmpty ? m.team1.shortName : m.team1.name;
        teamMap.putIfAbsent(key, () => m.team1);
      }
      if (m.team2.name.isNotEmpty) {
        final key = m.team2.shortName.isNotEmpty ? m.team2.shortName : m.team2.name;
        teamMap.putIfAbsent(key, () => m.team2);
      }
    }

    if (teamMap.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('Teams', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 10),
          const FallbackBanner(message: 'Team data not available from API'),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('Teams', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 80,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: teamMap.entries.map((entry) {
              final teamName = entry.key;
              final team = entry.value;
              return Container(
                width: 75,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  color: AppColors.cardBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.borderColor.withOpacity(0.4)),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TeamLogo(teamCode: team.shortName, logoUrl: team.logoUrl, size: 36),
                    const SizedBox(height: 4),
                    Text(
                      teamName.length > 5 ? teamName.substring(0, 5) : teamName,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 10, fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildPointsTable() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('Points Table', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 10),
        const FallbackBanner(message: 'Points table not available from API'),
        const SizedBox(height: 6),
        GlassCard(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(14),
          borderRadius: 14,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Expanded(flex: 3, child: Text('Team', style: TextStyle(color: AppColors.textMuted, fontSize: 11))),
                  SizedBox(width: 30, child: Text('M', style: TextStyle(color: AppColors.textMuted, fontSize: 11), textAlign: TextAlign.center)),
                  SizedBox(width: 30, child: Text('W', style: TextStyle(color: AppColors.textMuted, fontSize: 11), textAlign: TextAlign.center)),
                  SizedBox(width: 30, child: Text('L', style: TextStyle(color: AppColors.textMuted, fontSize: 11), textAlign: TextAlign.center)),
                  SizedBox(width: 30, child: Text('Pts', style: TextStyle(color: AppColors.textMuted, fontSize: 11), textAlign: TextAlign.center)),
                ],
              ),
              const SizedBox(height: 6),
              ...[
                ['Team A', '5', '4', '1', '8'],
                ['Team B', '5', '3', '2', '6'],
                ['Team C', '5', '2', '3', '4'],
                ['Team D', '5', '1', '4', '2'],
              ].map((row) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        Expanded(flex: 3, child: Text(row[0], style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600))),
                        SizedBox(width: 30, child: Text(row[1], style: const TextStyle(color: AppColors.textSecondary, fontSize: 12), textAlign: TextAlign.center)),
                        SizedBox(width: 30, child: Text(row[2], style: const TextStyle(color: AppColors.green, fontSize: 12, fontWeight: FontWeight.w600), textAlign: TextAlign.center)),
                        SizedBox(width: 30, child: Text(row[3], style: const TextStyle(color: AppColors.red, fontSize: 12), textAlign: TextAlign.center)),
                        SizedBox(width: 30, child: Text(row[4], style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w700), textAlign: TextAlign.center)),
                      ],
                    ),
                  )),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSeriesStats() {
    if (_statTypes.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('Series Stats', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
          ),
          SizedBox(height: 10),
          FallbackBanner(message: 'Stats not available for this series'),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('Series Stats', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 10),
        // Stat type chips
        SizedBox(
          height: 34,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _statTypes.length,
            itemBuilder: (context, index) {
              final st = _statTypes[index];
              final isActive = st.value == _selectedStatType;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => _loadStatsTable(st.value),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: isActive ? AppColors.blue : AppColors.cardBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: isActive ? AppColors.blue : AppColors.borderColor.withOpacity(0.4)),
                    ),
                    child: Text(
                      st.header,
                      style: TextStyle(
                        color: isActive ? Colors.white : AppColors.textSecondary,
                        fontSize: 11,
                        fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        // Stats table
        if (_isLoadingStats)
          const SizedBox(height: 100, child: LoadingWidget(message: 'Loading stats...'))
        else if (_selectedStatsTable != null && _selectedStatsTable!.players.isNotEmpty)
          _buildStatsTable(_selectedStatsTable!)
        else
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: EmptyStateWidget(message: 'No stats data for this category'),
          ),
      ],
    );
  }

  Widget _buildStatsTable(ApiSeriesStatsTable table) {
    final headers = table.headers;
    if (headers.isEmpty || table.players.isEmpty) {
      return const SizedBox.shrink();
    }

    return GlassCard(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      borderRadius: 14,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 14,
          horizontalMargin: 8,
          headingRowHeight: 32,
          dataRowMinHeight: 36,
          dataRowMaxHeight: 42,
          headingTextStyle: const TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w600),
          dataTextStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
          columns: [
            const DataColumn(label: Text('#', style: TextStyle(color: AppColors.textMuted, fontSize: 10))),
            ...headers.map((h) => DataColumn(label: Text(h, style: const TextStyle(color: AppColors.textMuted, fontSize: 10, fontWeight: FontWeight.w600)))),
          ],
          rows: table.players.asMap().entries.map((entry) {
            final idx = entry.key;
            final player = entry.value;
            return DataRow(cells: [
              DataCell(Text('${idx + 1}', style: const TextStyle(color: AppColors.textMuted, fontSize: 10))),
              // PLAYER column (first header)
              DataCell(
                Text(
                  player.playerName,
                  style: TextStyle(
                    color: idx < 3 ? AppColors.cyan : AppColors.textPrimary,
                    fontSize: 11,
                    fontWeight: idx < 3 ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              // Remaining stat columns
              ...headers.skip(1).map((h) {
                final val = player.stats[h] ?? '-';
                return DataCell(Text(val, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)));
              }),
            ]);
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildSeriesNewsSection() {
    if (_seriesNews.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text('Series News', style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 140,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _seriesNews.length,
            itemBuilder: (context, index) {
              final news = _seriesNews[index];
              return GestureDetector(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => NewsDetailScreen(news: news),
                )),
                child: Container(
                  width: 220,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    color: AppColors.cardBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.borderColor.withOpacity(0.3)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: AppColors.cyan.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
                          child: Text(news.storyType.isNotEmpty ? news.storyType : 'News', style: const TextStyle(color: AppColors.cyan, fontSize: 9, fontWeight: FontWeight.w600)),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: Text(
                            news.title,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600, height: 1.3),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          news.timeAgo,
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _SeriesBannerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    paint.color = AppColors.blue.withOpacity(0.08);
    canvas.drawOval(Rect.fromCenter(center: Offset(size.width * 0.8, size.height * 0.3), width: size.width * 0.5, height: size.height * 0.6), paint);
    paint.color = AppColors.cyan.withOpacity(0.06);
    canvas.drawOval(Rect.fromCenter(center: Offset(size.width * 0.2, size.height * 0.7), width: size.width * 0.4, height: size.height * 0.4), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
