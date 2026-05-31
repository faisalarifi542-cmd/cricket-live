import 'package:flutter/material.dart';

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
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: c.border)),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned.fill(
              child: _NewsImage(
                source: article.asset,
                fallbackLabel: 'Featured',
              ),
            ),
            Positioned.fill(
                child: DecoratedBox(
                    decoration: BoxDecoration(
                        gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                  Colors.black.withValues(alpha: .12),
                  Colors.black.withValues(alpha: .74)
                ])))),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    StatusBadge(
                        label: article.breaking ? 'BREAKING' : 'FEATURED',
                        color: article.breaking ? c.live : c.cyan,
                        filled: true,
                        icon: article.breaking
                            ? Icons.bolt_rounded
                            : Icons.star_rounded),
                    const Spacer(),
                    if (article.timeAgo != null)
                      Text(article.timeAgo!,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 16)),
                  ],
                ),
                const SizedBox(height: 160),
                Text(article.title,
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: context.sp(26),
                        fontWeight: FontWeight.w900,
                        height: 1.15)),
                const SizedBox(height: 12),
                Text(article.subtitle,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: .84),
                        fontSize: 16,
                        height: 1.45)),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Text(article.source,
                        style: TextStyle(
                            color: c.cyan,
                            fontWeight: FontWeight.w700,
                            fontSize: 16)),
                    const SizedBox(width: 12),
                    Text('•',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: .75))),
                    const SizedBox(width: 12),
                    Text(article.date,
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: .75),
                            fontSize: 16)),
                    const SizedBox(width: 12),
                    Text('•',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: .75))),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: .22),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: c.border)),
                      child: Text(article.tag,
                          style: TextStyle(
                              color: c.cyan, fontWeight: FontWeight.w700)),
                    ),
                    const Spacer(),
                    GradientButton(
                        label: 'Read More',
                        outlined: true,
                        onTap: onTap,
                        height: 48),
                  ],
                )
              ],
            )
          ],
        ),
      ),
    );
  }
}

class NewsListCard extends StatelessWidget {
  const NewsListCard(
      {super.key, required this.article, this.onTap, this.compact = false});

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
                Text(article.title,
                    maxLines: compact ? 2 : 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: c.text,
                        fontWeight: FontWeight.w800,
                        fontSize: compact ? 16 : 17.5,
                        height: 1.25)),
                const SizedBox(height: 8),
                Text(article.subtitle,
                    maxLines: compact ? 2 : 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.muted, height: 1.45)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(article.source,
                        style: TextStyle(
                            color: c.cyan, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 12),
                    Text('•', style: TextStyle(color: c.muted)),
                    const SizedBox(width: 12),
                    Text(article.date, style: TextStyle(color: c.muted)),
                    const SizedBox(width: 12),
                    Text('•', style: TextStyle(color: c.muted)),
                    const SizedBox(width: 12),
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
      errorBuilder: (_, __, ___) => EmptyOrErrorImage(label: fallbackLabel),
    );
  }
}
