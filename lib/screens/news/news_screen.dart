import 'package:flutter/material.dart';
import '../../app_theme.dart';
import '../../components.dart';
import '../../components/news_components.dart';
import '../../models/api_models.dart';
import '../../models/api_response.dart';
import '../../models.dart';
import '../../repositories/cricket_repository.dart';

class NewsScreen extends StatefulWidget {
  const NewsScreen({
    super.key,
    required this.onOpenFilters,
    required this.onOpenArticle,
  });

  final VoidCallback onOpenFilters;
  final ValueChanged<NewsArticle> onOpenArticle;

  @override
  State<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends State<NewsScreen> {
  int tab = 0;
  final CricketRepository _repository = CricketRepository();
  late Future<ApiEnvelope<List<NewsStory>>> _news;

  @override
  void initState() {
    super.initState();
    _news = _repository.newsStories(limit: 20);
  }

  Future<void> _refresh() async {
    setState(
        () => _news = _repository.newsStories(limit: 20, forceRefresh: true));
    await _news;
  }

  NewsArticle _articleFromStory(NewsStory story) {
    final tag = (story.context?.isNotEmpty ?? false)
        ? story.context!
        : ((story.storyType?.isNotEmpty ?? false)
            ? story.storyType!
            : 'Cricket');
    return NewsArticle(
      title: story.title,
      subtitle: story.summary ?? 'Story details are available from Cricbuzz.',
      source: 'Cricbuzz',
      date: story.publishedLabel ?? 'Latest',
      tag: tag,
      asset: story.image,
      timeAgo: story.publishedLabel,
    );
  }

  List<NewsStory> _storiesForTab(List<NewsStory> stories) {
    if (tab == 0 || tab == 3) return stories;
    const leagueTerms = [
      'ipl',
      'psl',
      'bbl',
      'cpl',
      'blast',
      'league',
      'hundred',
      'sa20',
      'ilt20'
    ];
    bool isLeague(NewsStory story) {
      final text = '${story.context ?? ''} ${story.title}'.toLowerCase();
      return leagueTerms.any(text.contains);
    }

    if (tab == 2) return stories.where(isLeague).toList();
    return stories.where((story) => !isLeague(story)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
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
                  final filtered = _storiesForTab(stories);
                  final rendered = filtered.map(_articleFromStory).toList();

                  if (snapshot.connectionState == ConnectionState.waiting &&
                      stories.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 28),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snapshot.hasError) {
                    return _NewsStateCard(
                        onRetry: () => setState(() => _news = _repository
                            .newsStories(limit: 20, forceRefresh: true)));
                  }
                  if (rendered.isEmpty) {
                    return _NewsStateCard(
                      title: stories.isEmpty
                          ? 'No news available'
                          : 'No news in this category',
                      message: stories.isEmpty
                          ? 'Please refresh shortly for the latest cricket updates.'
                          : 'Try another filter or refresh for new stories.',
                      onRetry: () => setState(() => _news = _repository
                          .newsStories(limit: 20, forceRefresh: true)),
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FeaturedNewsCard(
                        article: rendered.first,
                        onTap: () => widget.onOpenArticle(rendered.first),
                      ),
                      const SizedBox(height: 14),
                      for (final article in rendered.skip(1))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: NewsListCard(
                            article: article,
                            onTap: () => widget.onOpenArticle(article),
                          ),
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
          Text(title,
              style: TextStyle(
                  color: c.text, fontWeight: FontWeight.w900, fontSize: 18)),
          const SizedBox(height: 8),
          Text(message,
              textAlign: TextAlign.center,
              style: TextStyle(color: c.muted, height: 1.4)),
          const SizedBox(height: 16),
          GradientButton(
              label: 'Retry', icon: Icons.refresh_rounded, onTap: onRetry),
        ],
      ),
    );
  }
}
