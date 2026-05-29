import 'package:flutter/material.dart';
import '../../app_theme.dart';
import '../../components.dart';
import '../../core/api/api_config.dart';
import '../../models/api_models.dart';
import '../../models/api_response.dart';
import '../../models.dart';
import '../../repositories/cricket_repository.dart';
import '../../screens.dart';

class NewsScreen extends StatefulWidget {
  const NewsScreen({
    super.key,
    required this.onOpenSearch,
    required this.onOpenFilters,
    required this.onOpenArticle,
  });

  final VoidCallback onOpenSearch;
  final VoidCallback onOpenFilters;
  final VoidCallback onOpenArticle;

  @override
  State<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends State<NewsScreen> {
  int tab = 0;
  final CricketRepository _repository = CricketRepository();
  late Future<ApiEnvelope<List<NewsStory>>> _news;

  List<NewsArticle> get articles => switch (tab) {
        0 => AppData.newsAll,
        1 => AppData.newsInternational,
        2 => AppData.newsLeagues,
        _ => AppData.newsLatest,
      };

  @override
  void initState() {
    super.initState();
    _news = _repository.newsStories(limit: 20);
  }

  Future<void> _refresh() async {
    setState(() => _news = _repository.newsStories(limit: 20, forceRefresh: true));
    await _news;
  }

  NewsArticle _articleFromStory(NewsStory story) {
    return NewsArticle(
      title: story.title,
      subtitle: story.summary ?? 'Full story details will appear when the provider includes article body data.',
      source: 'WebCricHD',
      date: story.publishedAt?.toLocal().toString() ?? 'Latest',
      tag: 'Cricket',
      asset: story.image,
      timeAgo: story.publishedAt == null ? null : 'Updated',
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final current = articles;
    return Container(
      decoration: BoxDecoration(gradient: c.bgGradient),
      child: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: EdgeInsets.fromLTRB(context.horizontalPadding, 18,
                context.horizontalPadding, context.mainBottomPadding),
            children: [
            AppHeader(
              showLogo: true,
              subtitle: 'NEWS',
              trailing: [
                GlowIconButton(
                    icon: Icons.search_rounded, onTap: widget.onOpenSearch),
                const SizedBox(width: 8),
                GlowIconButton(
                    icon: Icons.filter_alt_outlined,
                    onTap: widget.onOpenFilters),
              ],
            ),
            const SizedBox(height: 18),
            SegmentedTabs(
              items: const [
                ('All', null),
                ('International', null),
                ('Leagues', null),
                ('Latest', null),
              ],
              selected: tab,
              onChanged: (v) => setState(() => tab = v),
            ),
            const SizedBox(height: 18),
            FutureBuilder<ApiEnvelope<List<NewsStory>>>(
              future: _news,
              builder: (context, snapshot) {
                final stories = snapshot.data?.data ?? const <NewsStory>[];
                final useDemo = ApiConfig.allowDemoFallback && snapshot.hasError && stories.isEmpty;
                final rendered = useDemo ? current : stories.map(_articleFromStory).toList();

                if (snapshot.connectionState == ConnectionState.waiting && stories.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 28),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError && !useDemo) {
                  return _NewsStateCard(onRetry: () => setState(() => _news = _repository.newsStories(limit: 20, forceRefresh: true)));
                }
                if (rendered.isEmpty) {
                  return _NewsStateCard(
                    title: 'No news available',
                    message: 'Please refresh shortly for the latest cricket updates.',
                    onRetry: () => setState(() => _news = _repository.newsStories(limit: 20, forceRefresh: true)),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (useDemo)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          'Demo news shown because the API is unavailable in this debug build.',
                          style: TextStyle(color: c.warning, fontWeight: FontWeight.w800, fontSize: 12),
                        ),
                      ),
                    FeaturedNewsCard(article: rendered.first, onTap: widget.onOpenArticle),
                    const SizedBox(height: 14),
                    for (final article in rendered.skip(1))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: NewsListCard(article: article, onTap: widget.onOpenArticle),
                      ),
                  ],
                );
              },
            ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NewsStateCard extends StatelessWidget {
  const _NewsStateCard({
    this.title = 'Unable to load news',
    this.message = 'Please check your connection and try again.',
    required this.onRetry,
  });

  final String title;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        children: [
          Icon(Icons.newspaper_rounded, color: c.cyan, size: 38),
          const SizedBox(height: 12),
          Text(title, style: TextStyle(color: c.text, fontWeight: FontWeight.w900, fontSize: 18)),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center, style: TextStyle(color: c.muted, height: 1.4)),
          const SizedBox(height: 16),
          GradientButton(label: 'Retry', icon: Icons.refresh_rounded, onTap: onRetry),
        ],
      ),
    );
  }
}
