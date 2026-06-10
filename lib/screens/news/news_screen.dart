import 'package:flutter/material.dart';
import 'package:cricpro_flutter/app_theme.dart';
import 'package:cricpro_flutter/api_models.dart';
import 'package:cricpro_flutter/components.dart';
import 'package:cricpro_flutter/models/ad_config.dart';
import 'package:cricpro_flutter/models/api_response.dart';
import 'package:cricpro_flutter/models.dart';
import 'package:cricpro_flutter/repositories/cricket_repository.dart';
import 'package:cricpro_flutter/widgets/ads/banner_ad_widget.dart';
import 'package:cricpro_flutter/widgets/ads/native_ad_card.dart';

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
    _news = _repository.newsStories(limit: 20, forceRefresh: true);
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
      id: story.id,
      title: story.title,
      subtitle: story.summary ?? 'Story details are available from CricPro.',
      source: 'CricPro',
      date: story.publishedLabel ?? 'Latest',
      tag: tag,
      asset: story.image,
      timeAgo: story.publishedLabel,
      body: story.body,
      context: story.context,
      storyType: story.storyType,
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
              ScrollableSegmentedTabs(
                items: const [
                  'All',
                  'International',
                  'Leagues',
                  'Latest',
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
                      for (final entry in rendered.skip(1).indexed) ...[
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: NewsListCard(
                            article: entry.$2,
                            onTap: () => widget.onOpenArticle(entry.$2),
                          ),
                        ),
                        if ((entry.$1 + 2) % 4 == 0)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 12),
                            child: NativeAdCard(placement: AdPlacement.news),
                          ),
                      ],
                      const BannerAdWidget(placement: AdPlacement.news),
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

class FeaturedNewsCard extends StatelessWidget {
  const FeaturedNewsCard({super.key, required this.article, this.onTap});

  final NewsArticle article;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: c.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1.24,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _NewsImage(source: article.asset, fallbackLabel: 'Featured'),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Color(0xCC000000)],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              StatusBadge(
                                label: article.breaking
                                    ? 'BREAKING'
                                    : 'FEATURED',
                                color: article.breaking ? c.live : c.cyan,
                                filled: true,
                                icon: article.breaking
                                    ? Icons.bolt_rounded
                                    : Icons.star_rounded,
                              ),
                              const Spacer(),
                              if (article.timeAgo != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: c.isDark ? Colors.black.withValues(alpha: .22) : c.card.withValues(alpha: .55),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(color: c.border),
                                  ),
                                  child: Text(
                                    article.timeAgo!,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const Spacer(),
                          Text(
                            article.title,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: context.sp(21.5),
                              fontWeight: FontWeight.w900,
                              height: 1.08,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            article.subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: .88),
                              fontSize: 14.5,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'CricPro',
                  style: TextStyle(
                    color: c.cyan,
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                  ),
                ),
                Text('•',
                    style:
                        TextStyle(color: Colors.white.withValues(alpha: .6))),
                Text(
                  article.date,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: .75),
                    fontSize: 14,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: c.isDark ? Colors.black.withValues(alpha: .18) : c.card.withValues(alpha: .55),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: c.border),
                  ),
                  child: Text(
                    article.tag,
                    style: TextStyle(
                      color: c.cyan,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                GradientButton(
                  label: 'Read More',
                  outlined: true,
                  onTap: onTap,
                  height: 42,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class NewsListCard extends StatelessWidget {
  const NewsListCard({
    super.key,
    required this.article,
    this.onTap,
    this.compact = false,
  });

  final NewsArticle article;
  final VoidCallback? onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      radius: compact ? 18 : 22,
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              width: compact ? 94 : 132,
              height: compact ? 76 : 108,
              child: _NewsImage(source: article.asset, fallbackLabel: 'News'),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  article.title,
                  maxLines: compact ? 2 : 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.text,
                    fontWeight: FontWeight.w800,
                    fontSize: compact ? 16 : 17.5,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  article.subtitle,
                  maxLines: compact ? 2 : 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.muted, height: 1.45),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  children: [
                    Text('CricPro',
                        style: TextStyle(
                            color: c.cyan, fontWeight: FontWeight.w700)),
                    Text('•', style: TextStyle(color: c.muted)),
                    Text(article.date, style: TextStyle(color: c.muted)),
                    Text('•', style: TextStyle(color: c.muted)),
                    Text(article.tag, style: TextStyle(color: c.cyan)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Icon(Icons.chevron_right_rounded, color: c.muted),
        ],
      ),
    );
  }
}

class _NewsImage extends StatelessWidget {
  const _NewsImage({required this.source, required this.fallbackLabel});

  final String? source;
  final String fallbackLabel;

  @override
  Widget build(BuildContext context) {
    final src = source?.trim() ?? '';
    if (src.startsWith('http://') || src.startsWith('https://')) {
      return Image.network(
        src,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return const EmptyOrErrorImage(label: 'Loading');
        },
        errorBuilder: (_, __, ___) => EmptyOrErrorImage(label: fallbackLabel),
      );
    }
    return Image.asset(
      src.isEmpty ? 'assets/images/stadium_live.png' : src,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, __, ___) => EmptyOrErrorImage(label: fallbackLabel),
    );
  }
}
