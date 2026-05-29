import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../models/news_model.dart';

class StoryCard extends StatelessWidget {
  final NewsModel news;
  final double width;
  final double height;

  const StoryCard({
    super.key,
    required this.news,
    this.width = 160,
    this.height = 170,
  });

  List<Color> _bgColorsForCategory() {
    switch (news.category) {
      case 'MATCH REPORT':
        return [const Color(0xFF2A5E3B), const Color(0xFF1A4A30), const Color(0xFF0D2818)];
      case 'ANALYSIS':
        return [const Color(0xFF5A3A1A), const Color(0xFF3D2815), const Color(0xFF1E140A)];
      default:
        return [const Color(0xFF1A3A5C), const Color(0xFF122D4A), const Color(0xFF0A1E3D)];
    }
  }

  @override
  Widget build(BuildContext context) {
    final bgColors = _bgColorsForCategory();
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: bgColors,
        ),
        border: Border.all(
          color: AppColors.borderColor.withOpacity(0.4),
          width: 1,
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (news.imageUrl != null && news.imageUrl!.isNotEmpty)
                    Image.network(
                      news.imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => CustomPaint(
                        painter: _StoryBgPainter(bgColors[0]),
                        child: const SizedBox.expand(),
                      ),
                    )
                  else
                    CustomPaint(
                      painter: _StoryBgPainter(bgColors[0]),
                      child: const SizedBox.expand(),
                    ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.0, 0.35, 1.0],
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.3),
                          Colors.black.withOpacity(0.9),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Top right icon
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.blue.withOpacity(0.3),
                border: Border.all(
                  color: AppColors.blue.withOpacity(0.5),
                ),
              ),
              child: Icon(
                news.category == 'MATCH REPORT' ? Icons.play_arrow : Icons.article,
                color: Colors.white,
                size: 14,
              ),
            ),
          ),
          // Bottom content
          Positioned(
            left: 10,
            right: 10,
            bottom: 10,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  news.category,
                  style: TextStyle(
                    color: news.category == 'MATCH REPORT' ? AppColors.red : AppColors.cyan,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  news.title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  '${news.timeAgo} \u2022 ${news.readTime}',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StoryBgPainter extends CustomPainter {
  final Color baseColor;
  _StoryBgPainter(this.baseColor);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    paint.color = baseColor.withOpacity(0.15);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.3, size.height * 0.25),
        width: size.width * 0.6,
        height: size.height * 0.35,
      ),
      paint,
    );

    paint.color = baseColor.withOpacity(0.1);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.75, size.height * 0.2),
        width: size.width * 0.45,
        height: size.height * 0.3,
      ),
      paint,
    );

    paint.style = PaintingStyle.stroke;
    paint.color = baseColor.withOpacity(0.08);
    paint.strokeWidth = 1;
    for (int i = 0; i < 3; i++) {
      final y = size.height * (0.12 + i * 0.08);
      canvas.drawLine(
        Offset(size.width * 0.1, y),
        Offset(size.width * 0.9, y + size.height * 0.04),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
