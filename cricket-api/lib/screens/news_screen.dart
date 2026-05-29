import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/network/network_result.dart';
import '../data/repositories/cricket_repository.dart';
import '../models/news_model.dart';
import '../widgets/custom_header.dart';
import '../widgets/glass_card.dart';
import '../widgets/api_state_widgets.dart';
import 'news_detail_screen.dart';

class NewsScreen extends StatefulWidget {
  const NewsScreen({super.key});

  @override
  State<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends State<NewsScreen> {
  String _activeFilter = 'All';
  final _filters = ['All', 'News', 'Match Features', 'Features', 'Previews', 'Pulse'];
  final _repo = CricketRepository.instance;
  final ScrollController _scrollController = ScrollController();

  List<NewsModel> _stories = [];
  String? _nextCursor;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadData();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadData() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    final storyType = _activeFilter == 'All' ? null : _activeFilter;
    final result = await _repo.getNews(limit: 20, storyType: storyType);
    if (mounted) {
      setState(() {
        _isLoading = false;
        if (result is NetworkSuccess<NewsListResponse>) {
          _stories = result.data.stories;
          _nextCursor = result.data.nextCursor;
        } else if (result is NetworkError<NewsListResponse>) {
          _errorMessage = result.exception.message;
        }
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || _nextCursor == null) return;
    setState(() => _isLoadingMore = true);
    final storyType = _activeFilter == 'All' ? null : _activeFilter;
    final result = await _repo.getNews(cursor: _nextCursor, limit: 20, storyType: storyType);
    if (mounted) {
      setState(() {
        _isLoadingMore = false;
        if (result is NetworkSuccess<NewsListResponse>) {
          _stories.addAll(result.data.stories);
          _nextCursor = result.data.nextCursor;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
      child: Column(
        children: [
          const CustomHeader(showPremiumButton: true),
          _buildFilterChips(),
          Expanded(
            child: _isLoading
                ? const LoadingWidget(message: 'Loading news...')
                : _errorMessage != null
                    ? ErrorRetryWidget(message: _errorMessage!, onRetry: _loadData)
                    : _stories.isEmpty
                        ? const EmptyStateWidget(message: 'No news stories available', icon: Icons.article_outlined)
                        : RefreshIndicator(
                            color: AppColors.cyan,
                            backgroundColor: AppColors.cardBg,
                            onRefresh: _loadData,
                            child: ListView.builder(
                              controller: _scrollController,
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              itemCount: _stories.length + (_isLoadingMore ? 1 : 0),
                              itemBuilder: (context, index) {
                                if (index == _stories.length) {
                                  return const Padding(
                                    padding: EdgeInsets.all(16),
                                    child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.cyan)),
                                  );
                                }
                                final news = _stories[index];
                                return GestureDetector(
                                  onTap: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => NewsDetailScreen(news: news),
                                      ),
                                    );
                                  },
                                  child: index == 0 ? _buildFeaturedCard(news) : _buildNewsCard(news),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    return Container(
      height: 42,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AppColors.borderColor.withOpacity(0.3),
            width: 1,
          ),
        ),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        itemCount: _filters.length,
        itemBuilder: (context, index) {
          final isActive = _filters[index] == _activeFilter;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () {
                setState(() => _activeFilter = _filters[index]);
                _loadData();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: isActive ? AppColors.blue : AppColors.cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isActive ? AppColors.blue : AppColors.borderColor.withOpacity(0.4),
                  ),
                ),
                child: Text(
                  _filters[index],
                  style: TextStyle(
                    color: isActive ? Colors.white : AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFeaturedCard(NewsModel news) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.zero,
      borderRadius: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
            child: SizedBox(
              height: 160,
              width: double.infinity,
              child: news.imageUrl != null && news.imageUrl!.isNotEmpty
                  ? Image.network(news.imageUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _buildImagePlaceholder(news.category))
                  : _buildImagePlaceholder(news.category),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _categoryAccentColor(news.category).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(news.category, style: TextStyle(color: _categoryAccentColor(news.category), fontSize: 9, fontWeight: FontWeight.w700)),
                    ),
                    if (news.context.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Flexible(child: Text(news.context, style: const TextStyle(color: AppColors.textMuted, fontSize: 9), overflow: TextOverflow.ellipsis)),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Text(news.title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w700, height: 1.3), maxLines: 3, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(news.timeAgo, style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
                    const SizedBox(width: 8),
                    Container(width: 3, height: 3, decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.textMuted)),
                    const SizedBox(width: 8),
                    Text(news.readTime, style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNewsCard(NewsModel news) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      borderRadius: 14,
      child: Row(
        children: [
          Container(
            width: 85,
            height: 70,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: LinearGradient(colors: _bgColorsForCategory(news.category)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: news.imageUrl != null && news.imageUrl!.isNotEmpty
                  ? Image.network(news.imageUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _buildImagePlaceholder(news.category))
                  : _buildImagePlaceholder(news.category),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: _categoryAccentColor(news.category).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(news.category, style: TextStyle(color: _categoryAccentColor(news.category), fontSize: 8, fontWeight: FontWeight.w700)),
                    ),
                    if (news.context.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Flexible(child: Text(news.context, style: const TextStyle(color: AppColors.textMuted, fontSize: 9), overflow: TextOverflow.ellipsis)),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(news.title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600, height: 1.3), maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(news.timeAgo, style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
                    const SizedBox(width: 8),
                    Container(width: 3, height: 3, decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.textMuted)),
                    const SizedBox(width: 8),
                    Text(news.readTime, style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
                    if (news.isPremium) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(color: AppColors.purple.withOpacity(0.2), borderRadius: BorderRadius.circular(3)),
                        child: const Text('PREMIUM', style: TextStyle(color: AppColors.purple, fontSize: 7, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImagePlaceholder(String category) {
    return Container(
      color: _bgColorsForCategory(category).first,
      child: Center(child: Icon(_iconForCategory(category), color: Colors.white.withOpacity(0.5), size: 28)),
    );
  }

  Color _categoryAccentColor(String category) {
    switch (category) {
      case 'MATCH REPORT':
      case 'MATCH FEATURES':
        return AppColors.red;
      case 'ANALYSIS':
        return AppColors.cyan;
      case 'FEATURES':
        return AppColors.purple;
      case 'PREVIEWS':
        return AppColors.blue;
      default:
        return AppColors.cyan;
    }
  }

  List<Color> _bgColorsForCategory(String category) {
    switch (category) {
      case 'MATCH REPORT':
      case 'MATCH FEATURES':
        return [const Color(0xFF2A5E3B), const Color(0xFF0D2818)];
      case 'ANALYSIS':
        return [const Color(0xFF5A3A1A), const Color(0xFF1E140A)];
      default:
        return [const Color(0xFF1A3A5C), const Color(0xFF0A1E3D)];
    }
  }

  IconData _iconForCategory(String category) {
    switch (category) {
      case 'MATCH REPORT':
      case 'MATCH FEATURES':
        return Icons.play_arrow;
      case 'ANALYSIS':
        return Icons.analytics;
      case 'FEATURES':
        return Icons.star;
      default:
        return Icons.article;
    }
  }
}
