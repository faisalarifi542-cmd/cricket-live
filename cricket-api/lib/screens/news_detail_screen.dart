import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../models/news_model.dart';
import '../widgets/custom_header.dart';
import '../widgets/glass_card.dart';

class NewsDetailScreen extends StatelessWidget {
  final NewsModel news;

  const NewsDetailScreen({super.key, required this.news});

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
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Hero image area
                      Container(
                        width: double.infinity,
                        height: 200,
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              const Color(0xFF1A3A5C).withOpacity(0.8),
                              const Color(0xFF0D2247),
                            ],
                          ),
                        ),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: news.imageUrl != null && news.imageUrl!.isNotEmpty
                                    ? Image.network(
                                        news.imageUrl!,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => CustomPaint(painter: _NewsBgPainter(news.category)),
                                      )
                                    : CustomPaint(painter: _NewsBgPainter(news.category)),
                              ),
                            ),
                            Positioned(
                              left: 16,
                              bottom: 16,
                              right: 16,
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: _categoryColor().withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: _categoryColor().withOpacity(0.5)),
                                    ),
                                    child: Text(
                                      news.category,
                                      style: TextStyle(
                                        color: _categoryColor(),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                  if (news.context.isNotEmpty) ...[
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        news.context,
                                        style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 11),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Title
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          news.title,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            height: 1.3,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Meta info
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            Icon(Icons.access_time, color: AppColors.textMuted, size: 14),
                            const SizedBox(width: 4),
                            Text(
                              '${news.timeAgo} \u2022 ${news.readTime}',
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                            ),
                            const Spacer(),
                            _buildActionIcon(Icons.bookmark_outline),
                            const SizedBox(width: 12),
                            _buildActionIcon(Icons.share_outlined),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Divider(color: AppColors.borderColor.withOpacity(0.3), indent: 16, endIndent: 16),
                      const SizedBox(height: 16),
                      // Article body (intro — full body not available from Cricbuzz JSON API)
                      if (news.intro.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            news.intro,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 14,
                              height: 1.7,
                            ),
                          ),
                        ),
                      if (news.content != null && news.content!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            news.content!,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 14,
                              height: 1.7,
                            ),
                          ),
                        ),
                      if (news.intro.isEmpty && (news.content == null || news.content!.isEmpty))
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: const Text(
                            'Full article content is not available.',
                            style: TextStyle(color: AppColors.textMuted, fontSize: 13, fontStyle: FontStyle.italic),
                          ),
                        ),
                      const SizedBox(height: 24),
                      // Related articles
                      if (news.relatedStories.isNotEmpty) ...[  
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: const Text(
                            'Related Articles',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        ...news.relatedStories.map((related) =>
                          GestureDetector(
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => NewsDetailScreen(news: related)),
                              );
                            },
                            child: _buildRelatedCard(related.headline, related.category, related.publishedTime, related.imageUrl),
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _categoryColor() {
    switch (news.category) {
      case 'MATCH REPORT':
        return AppColors.red;
      case 'ANALYSIS':
        return AppColors.cyan;
      case 'NEWS':
        return AppColors.blue;
      case 'FEATURE':
        return AppColors.purple;
      default:
        return AppColors.cyan;
    }
  }

  Widget _buildActionIcon(IconData icon) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderColor.withOpacity(0.4)),
      ),
      child: Icon(icon, color: AppColors.textSecondary, size: 18),
    );
  }

  Widget _buildRelatedCard(String title, String category, String time, [String? imageUrl]) {
    return GlassCard(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      padding: const EdgeInsets.all(12),
      borderRadius: 12,
      child: Row(
        children: [
          Container(
            width: 60,
            height: 50,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: AppColors.cardBg2,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: imageUrl != null && imageUrl.isNotEmpty
                  ? Image.network(imageUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Icon(Icons.article, color: AppColors.textMuted.withOpacity(0.5), size: 20))
                  : Icon(Icons.article, color: AppColors.textMuted.withOpacity(0.5), size: 20),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(category, style: TextStyle(color: AppColors.cyan, fontSize: 9, fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 3),
                Text(time, style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
              ],
            ),
          ),
        ],
      ),
    );
  }

}

class _NewsBgPainter extends CustomPainter {
  final String category;
  _NewsBgPainter(this.category);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final color = category == 'MATCH REPORT'
        ? const Color(0xFF2A5E3B)
        : category == 'ANALYSIS'
            ? const Color(0xFF5A3A1A)
            : const Color(0xFF1A3A5C);

    paint.color = color.withOpacity(0.3);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(size.width * 0.7, size.height * 0.3), width: size.width * 0.5, height: size.height * 0.5),
      paint,
    );
    paint.color = color.withOpacity(0.15);
    canvas.drawOval(
      Rect.fromCenter(center: Offset(size.width * 0.3, size.height * 0.6), width: size.width * 0.6, height: size.height * 0.4),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
