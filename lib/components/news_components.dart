import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../app_theme.dart';
import '../components.dart';
import '../models.dart';

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
                          colors: [
                            Colors.transparent,
                            Color(0xCC000000),
                          ],
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
                Text('�',
                    style: TextStyle(color: Colors.white.withValues(alpha: .6))),
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
                    Text('�', style: TextStyle(color: c.muted)),
                    Text(article.date, style: TextStyle(color: c.muted)),
                    Text('�', style: TextStyle(color: c.muted)),
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
    // The article headline/subtitle always sit next to this thumbnail, so the
    // image is redundant for a screen reader — it stays silent rather than
    // announcing an unnamed "image" before every headline. The loading/error
    // placeholders below are real Text, hence the outer ExcludeSemantics.
    if (src.startsWith('http://') || src.startsWith('https://')) {
      return ExcludeSemantics(
        child: CachedNetworkImage(
          imageUrl: src,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
          fadeInDuration: Duration.zero,
          placeholder: (context, _) =>
              const EmptyOrErrorImage(label: 'Loading'),
          errorWidget: (_, __, ___) => EmptyOrErrorImage(label: fallbackLabel),
        ),
      );
    }
    return ExcludeSemantics(
      child: Image.asset(
        src.isEmpty ? 'assets/images/stadium_live.webp' : src,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, __, ___) => EmptyOrErrorImage(label: fallbackLabel),
      ),
    );
  }
}

