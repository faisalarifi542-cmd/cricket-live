import 'dart:async';
import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/network/network_result.dart';
import '../data/repositories/cricket_repository.dart';
import '../models/api/api_match_model.dart';
import '../models/api/api_series_model.dart';
import '../models/news_model.dart';
import '../widgets/custom_header.dart';
import '../widgets/pill_chip.dart';
import '../widgets/section_header.dart';
import '../widgets/story_card.dart';
import '../widgets/api_hero_card.dart';
import '../widgets/api_state_widgets.dart';
import 'match_detail/match_detail_screen.dart';
import 'series_screen.dart';
import 'series_detail_screen.dart';
import 'news_screen.dart';
import 'news_detail_screen.dart';
import 'premium_screen.dart';
import 'schedule_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentTab = 0;
  int _carouselPage = 0;
  late PageController _pageController;
  Timer? _refreshTimer;

  final _tabs = ['Home', 'Live', 'Upcoming', 'Results'];
  final _repo = CricketRepository.instance;

  List<ApiMatch> _heroMatches = [];
  List<ApiMatch> _liveMatches = [];
  List<ApiMatch> _upcomingMatches = [];
  List<ApiMatch> _recentMatches = [];
  List<ApiSeries> _seriesList = [];
  List<NewsModel> _topStories = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.88, initialPage: 0);
    _loadData();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) => _loadData(silent: true));
  }

  @override
  void dispose() {
    _pageController.dispose();
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
        _repo.getSeries(),
        _repo.getNews(limit: 5),
      ]);

      final liveResult = results[0] as NetworkResult<List<ApiMatch>>;
      final upcomingResult = results[1] as NetworkResult<List<ApiMatch>>;
      final recentResult = results[2] as NetworkResult<List<ApiMatch>>;
      final seriesResult = results[3] as NetworkResult<List<ApiSeries>>;
      final newsResult = results[4] as NetworkResult<NewsListResponse>;

      if (mounted) {
        setState(() {
          _liveMatches = liveResult is NetworkSuccess<List<ApiMatch>> ? liveResult.data : [];
          _upcomingMatches = upcomingResult is NetworkSuccess<List<ApiMatch>> ? upcomingResult.data : [];
          _recentMatches = recentResult is NetworkSuccess<List<ApiMatch>> ? recentResult.data : [];
          _seriesList = seriesResult is NetworkSuccess<List<ApiSeries>> ? seriesResult.data : [];
          _topStories = newsResult is NetworkSuccess<NewsListResponse> ? newsResult.data.stories : [];

          // Hero: prioritize live > recent > upcoming
          _heroMatches = [
            ..._liveMatches.where((m) => m.isLive),
            ..._recentMatches.take(3),
            ..._upcomingMatches.take(2),
          ];
          if (_heroMatches.isEmpty) _heroMatches = [..._liveMatches.take(5)];

          _isLoading = false;
          _errorMessage = null;
        });
      }
    } catch (e) {
      if (mounted && !silent) {
        setState(() { _isLoading = false; _errorMessage = e.toString(); });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
      child: Column(
        children: [
          const CustomHeader(showPremiumButton: true),
          _buildTopTabs(),
          Expanded(
            child: _isLoading
                ? const LoadingWidget(message: 'Loading matches...')
                : _errorMessage != null
                    ? ErrorRetryWidget(message: _errorMessage!, onRetry: _loadData)
                    : RefreshIndicator(
                        color: AppColors.cyan,
                        backgroundColor: AppColors.cardBg,
                        onRefresh: _loadData,
                        child: SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 6),
                              _buildHeroCarousel(),
                              const SizedBox(height: 6),
                              _buildCarouselDots(),
                              const SizedBox(height: 8),
                              _buildQuickChips(),
                              const SizedBox(height: 10),
                              _buildFeaturedSeries(),
                              const SizedBox(height: 10),
                              _buildTopStories(),
                              const SizedBox(height: 8),
                              _buildAdBanner(),
                              const SizedBox(height: 90),
                            ],
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopTabs() {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AppColors.borderColor.withOpacity(0.3),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: _tabs.asMap().entries.map((entry) {
          final isActive = entry.key == _currentTab;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _currentTab = entry.key),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
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

  Widget _buildHeroCarousel() {
    if (_heroMatches.isEmpty) {
      return const SizedBox(height: 100, child: EmptyStateWidget(message: 'No matches available'));
    }
    return SizedBox(
      height: 195,
      child: PageView.builder(
        controller: _pageController,
        itemCount: _heroMatches.length.clamp(0, 5),
        onPageChanged: (i) => setState(() => _carouselPage = i),
        itemBuilder: (context, index) {
          final match = _heroMatches[index];
          return ApiHeroCard(
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
        },
      ),
    );
  }

  Widget _buildCarouselDots() {
    final count = _heroMatches.length.clamp(0, 5);
    if (count <= 1) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        count,
        (i) => Container(
          width: i == _carouselPage ? 10 : 6,
          height: 6,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            color: i == _carouselPage ? AppColors.blue : AppColors.textMuted.withOpacity(0.3),
          ),
        ),
      ),
    );
  }

  void _onChipTap(int index) {
    switch (index) {
      case 0: // IPL 26
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SeriesScreen()));
        break;
      case 1: // Hot Takes
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NewsScreen()));
        break;
      case 2: // Buzz
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NewsScreen()));
        break;
      case 3: // Scorecard
        if (_heroMatches.isNotEmpty) {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => MatchDetailScreen(matchId: _heroMatches[0].matchId, initialTab: 1),
          ));
        }
        break;
      case 4: // Fantasy
        if (_heroMatches.isNotEmpty) {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => MatchDetailScreen(matchId: _heroMatches[0].matchId, initialTab: 4),
          ));
        }
        break;
      case 6: // Schedule
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ScheduleScreen()));
        break;
      default:
        break;
    }
  }

  Widget _buildQuickChips() {
    final chips = [
      {'emoji': '\u{1F3C6}', 'label': 'IPL 26'},
      {'emoji': '\u{1F525}', 'label': 'Hot Takes'},
      {'emoji': '\u{26A1}', 'label': 'Buzz'},
      {'emoji': '\u{1F4CB}', 'label': 'Scorecard'},
      {'emoji': '\u{1F455}', 'label': 'Fantasy'},
      {'emoji': '\u{25B6}', 'label': 'Videos'},
      {'emoji': '\u{1F4C5}', 'label': 'Schedule'},
    ];
    return SizedBox(
      height: 36,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: chips.length,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: PillChip(
              label: chips[index]['label']!,
              emoji: chips[index]['emoji'],
              onTap: () => _onChipTap(index),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFeaturedSeries() {
    if (_seriesList.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        SectionHeader(
          title: 'Featured Series',
          onViewAll: () {
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SeriesScreen()));
          },
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 90,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _seriesList.length,
            itemBuilder: (context, index) {
              final series = _seriesList[index];
              return GestureDetector(
                onTap: () {
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => SeriesDetailScreen(seriesId: series.seriesId, seriesName: series.cleanName),
                  ));
                },
                child: _buildApiSeriesCard(series, index),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildApiSeriesCard(ApiSeries series, int index) {
    final gradients = [
      [const Color(0xFF0A2463), const Color(0xFF1E3A5F)],
      [const Color(0xFF1A4341), const Color(0xFF0D2B2A)],
      [const Color(0xFF3B0764), const Color(0xFF1E1B4B)],
      [const Color(0xFF7C2D12), const Color(0xFF431407)],
    ];
    final colors = gradients[index % gradients.length];
    return Container(
      width: 180,
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
        border: Border.all(color: colors[0].withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            series.cleanName,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w700, height: 1.2),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            series.season.isNotEmpty ? series.season : 'View Matches',
            style: TextStyle(color: AppColors.textMuted.withOpacity(0.8), fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _buildTopStories() {
    if (_topStories.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        SectionHeader(
          title: 'Top Stories',
          onViewAll: () {
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NewsScreen()));
          },
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 175,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _topStories.length.clamp(0, 5),
            itemBuilder: (context, index) {
              final news = _topStories[index];
              return Padding(
                padding: const EdgeInsets.only(right: 10),
                child: GestureDetector(
                  onTap: () {
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => NewsDetailScreen(news: news),
                    ));
                  },
                  child: StoryCard(
                    news: news,
                    width: MediaQuery.of(context).size.width * 0.44,
                    height: 175,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAdBanner() {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PremiumScreen()));
      },
      child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          colors: [
            Color(0xFF6B21A8),
            Color(0xFF3B0764),
            Color(0xFF1E1B4B),
          ],
        ),
        border: Border.all(
          color: AppColors.purple.withOpacity(0.3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Text(
                        'STRIDE',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'PERFORMANCE GEAR',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 8,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Next-Gen Performance For Next-Gen Players.',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.cyan, width: 1),
                color: AppColors.cyan.withOpacity(0.1),
              ),
              child: const Text(
                'Shop Now',
                style: TextStyle(
                  color: AppColors.cyan,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }
}
