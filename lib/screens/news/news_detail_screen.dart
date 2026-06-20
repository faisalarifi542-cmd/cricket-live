import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:cricpro_flutter/app_theme.dart';
import 'package:cricpro_flutter/components.dart';
import 'package:cricpro_flutter/models.dart';
import 'package:cricpro_flutter/models/api_response.dart';
import 'package:cricpro_flutter/repositories/cricket_repository.dart';

class NewsDetailScreen extends StatefulWidget {
  const NewsDetailScreen({super.key, this.article});

  final NewsArticle? article;

  @override
  State<NewsDetailScreen> createState() => _NewsDetailScreenState();
}

class _NewsDetailScreenState extends State<NewsDetailScreen> {
  final CricketRepository _repository = CricketRepository();
  Future<ApiEnvelope<Map<String, dynamic>>>? _detail;

  @override
  void initState() {
    super.initState();
    final id = widget.article?.id.trim() ?? '';
    if (id.isNotEmpty) {
      _detail = _repository.newsDetail(id, forceRefresh: true);
    }
  }

  Future<void> _retry() async {
    final id = widget.article?.id.trim() ?? '';
    if (id.isEmpty) return;
    setState(() => _detail = _repository.newsDetail(id, forceRefresh: true));
    await _detail;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final article = widget.article;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: c.bgGradient),
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.fromLTRB(context.horizontalPadding, 18,
                context.horizontalPadding, context.detailBottomPadding),
            children: [
              AppHeader(
                leading: IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.arrow_back_rounded, color: c.text)),
                title: 'News Detail',
                trailing: const [GlowIconButton(icon: Icons.share_outlined)],
              ),
              const SizedBox(height: 16),
              if (article == null)
                const _EmptyNewsCard(
                    text: 'Select a news story to view details.',
                    onRetry: null)
              else
                FutureBuilder<ApiEnvelope<Map<String, dynamic>>>(
                  future: _detail,
                  builder: (context, snapshot) {
                    final data = snapshot.data?.data;
                    final headline = _storyHeadline(article, data);
                    final source = _storySource(article, data);
                    final date = _storyDate(article, data);
                    final imageSource = _storyImage(article, data);
                    final content = _storyContent(article, data);
                    final related = _relatedStories(data);
                    final message = data?['message']?.toString().trim() ?? '';
                    if (snapshot.connectionState == ConnectionState.waiting &&
                        data == null) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 28),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (snapshot.hasError && data == null) {
                      return _EmptyNewsCard(
                        text:
                            'Unable to load the full article right now. Pull to retry.',
                        onRetry: _retry,
                      );
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        PremiumCard(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(18),
                                child: SizedBox(
                                  height: 220,
                                  width: double.infinity,
                                  child: _ArticleImage(source: imageSource),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  StatusBadge(
                                    label: article.tag,
                                    color: c.cyan,
                                    filled: true,
                                    icon: Icons.newspaper_rounded,
                                  ),
                                  const Spacer(),
                                  if (article.timeAgo != null)
                                    Text(
                                      article.timeAgo!,
                                      style: TextStyle(
                                          color: c.muted,
                                          fontWeight: FontWeight.w800),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Text(
                                headline,
                                style: TextStyle(
                                  color: c.text,
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                                  height: 1.08,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  const CircleAvatar(
                                    radius: 18,
                                    backgroundColor: Color(0xff0a2748),
                                    child: Icon(Icons.edit, size: 18),
                                  ),
                                  const SizedBox(width: 12),
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(source,
                                          style: TextStyle(
                                              color: c.text,
                                              fontWeight: FontWeight.w700)),
                                      Text(date,
                                          style: TextStyle(
                                              color: c.muted, fontSize: 13)),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              if (message.isNotEmpty) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: c.card2.withValues(alpha: .6),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: c.border),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(Icons.info_outline_rounded,
                                          color: c.cyan, size: 18),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          message,
                                          style: TextStyle(
                                            color: c.muted,
                                            fontWeight: FontWeight.w600,
                                            height: 1.45,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                              ],
                              _StoryBody(text: content),
                              if (related.isNotEmpty) ...[
                                const SizedBox(height: 18),
                                Text(
                                  'Related stories',
                                  style: TextStyle(
                                    color: c.text,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    for (final story in related)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 8),
                                        decoration: BoxDecoration(
                                          color:
                                              Colors.white.withValues(alpha: .04),
                                          borderRadius:
                                              BorderRadius.circular(999),
                                          border:
                                              Border.all(color: c.border),
                                        ),
                                        child: Text(
                                          story['headline'] ?? '',
                                          style: TextStyle(
                                            color: c.text,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ],
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

  String _storyContent(
      NewsArticle article, Map<String, dynamic>? detailPayload) {
    final detail = detailPayload ?? const <String, dynamic>{};
    final paragraphs = <String>[];
    final detailParagraphs = detail['paragraphs'];
    if (detailParagraphs is List) {
      for (final paragraph in detailParagraphs) {
        final text = paragraph?.toString().trim() ?? '';
        if (text.isNotEmpty) paragraphs.add(text);
      }
    }
    final candidates = [
      detail['body'],
      detail['content'],
      detail['articleBody'],
      article.body,
      article.subtitle,
    ];
    for (final candidate in candidates) {
      final text = candidate?.toString().trim() ?? '';
      if (text.isNotEmpty) {
        paragraphs.add(text);
      }
    }
    if (paragraphs.isEmpty) {
      return 'Full article text is not available from the current CricPro feed.';
    }
    return paragraphs.join('\n\n');
  }

  String _storyHeadline(NewsArticle article, Map<String, dynamic>? detailPayload) {
    final detail = detailPayload ?? const <String, dynamic>{};
    return detail['headline']?.toString().trim().isNotEmpty == true
        ? detail['headline'].toString().trim()
        : article.title;
  }

  String _storySource(NewsArticle article, Map<String, dynamic>? detailPayload) {
    return 'CricPro';
  }

  String _storyDate(NewsArticle article, Map<String, dynamic>? detailPayload) {
    final detail = detailPayload ?? const <String, dynamic>{};
    final value = detail['publishedTime']?.toString().trim() ?? '';
    return value.isNotEmpty ? value : article.date;
  }

  String? _storyImage(NewsArticle article, Map<String, dynamic>? detailPayload) {
    final detail = detailPayload ?? const <String, dynamic>{};
    final value = detail['imageUrl']?.toString().trim() ?? '';
    if (value.isNotEmpty) return value;
    return article.asset;
  }

  List<Map<String, dynamic>> _relatedStories(Map<String, dynamic>? detail) {
    final related = <Map<String, dynamic>>[];
    final items = detail?['relatedStories'];
    if (items is List) {
      for (final item in items) {
        if (item is Map<String, dynamic>) related.add(item);
      }
    }
    return related;
  }
}

class _StoryBody extends StatelessWidget {
  const _StoryBody({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final paragraphs = text
        .split(RegExp(r'\n{2,}'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final p in paragraphs.isEmpty ? [text] : paragraphs) ...[
          Text(
            p,
            style: TextStyle(
              color: c.muted,
              fontSize: 16,
              height: 1.72,
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _EmptyNewsCard extends StatelessWidget {
  const _EmptyNewsCard({required this.text, this.onRetry});

  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        children: [
          Icon(Icons.article_outlined, color: c.cyan, size: 36),
          const SizedBox(height: 12),
          Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: c.text, fontWeight: FontWeight.w800, height: 1.4)),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            GradientButton(
                label: 'Retry', icon: Icons.refresh_rounded, onTap: onRetry!),
          ],
        ],
      ),
    );
  }
}

class _ArticleImage extends StatelessWidget {
  const _ArticleImage({this.source});

  final String? source;

  @override
  Widget build(BuildContext context) {
    final src = source?.trim() ?? '';
    if (src.startsWith('http://') || src.startsWith('https://')) {
      return CachedNetworkImage(
        imageUrl: src,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        fadeInDuration: Duration.zero,
        errorWidget: (_, __, ___) =>
            const EmptyOrErrorImage(label: 'Article image'),
      );
    }
    return Image.asset(
      src.isEmpty ? 'assets/images/stadium_live.webp' : src,
      fit: BoxFit.cover,
      filterQuality: FilterQuality.high,
      errorBuilder: (_, __, ___) =>
          const EmptyOrErrorImage(label: 'Article image'),
    );
  }
}
