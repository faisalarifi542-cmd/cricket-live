import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../core/theme/app_colors.dart';
import '../models/series_model.dart';

class SeriesCard extends StatelessWidget {
  final SeriesModel series;
  final double width;
  final double height;

  const SeriesCard({
    super.key,
    required this.series,
    this.width = 140,
    this.height = 150,
  });

  static const List<List<Color>> _gradients = [
    [Color(0xFF1A3A6C), Color(0xFF102A52), Color(0xFF081830)],
    [Color(0xFF3D1B7A), Color(0xFF2D1569), Color(0xFF1A0D3D)],
    [Color(0xFF1B5E3A), Color(0xFF14472B), Color(0xFF0D2818)],
    [Color(0xFF4A2020), Color(0xFF3D1B1B), Color(0xFF2D0D0D)],
  ];

  static const List<Color> _accents = [
    Color(0xFF4A90D9),
    Color(0xFF9B5CFF),
    Color(0xFF2ECC71),
    Color(0xFFE74C3C),
  ];

  @override
  Widget build(BuildContext context) {
    final idx = series.gradientIndex % _gradients.length;
    final colors = _gradients[idx];
    final accent = _accents[idx];
    return Container(
      width: width,
      height: height,
      margin: const EdgeInsets.only(right: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
        border: Border.all(
          color: accent.withOpacity(0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: colors[0].withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Stack(
          children: [
            _buildIllustration(idx, accent),
            // Bottom text overlay
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(8, 20, 8, 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withOpacity(0.85),
                    ],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      series.title,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      series.dateRange,
                      style: TextStyle(
                        color: AppColors.textMuted.withOpacity(0.8),
                        fontSize: 8.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIllustration(int idx, Color accent) {
    return Positioned.fill(
      child: CustomPaint(
        painter: _SeriesIllustrationPainter(idx, accent),
      ),
    );
  }
}

class _SeriesIllustrationPainter extends CustomPainter {
  final int index;
  final Color accent;
  _SeriesIllustrationPainter(this.index, this.accent);

  @override
  void paint(Canvas canvas, Size size) {
    switch (index) {
      case 0:
        _drawLeagueBadge(canvas, size);
        break;
      case 1:
        _drawTrophyCup(canvas, size);
        break;
      case 2:
        _drawCricketField(canvas, size);
        break;
      case 3:
        _drawFlagCross(canvas, size);
        break;
    }
  }

  void _drawLeagueBadge(Canvas canvas, Size size) {
    final paint = Paint()..color = accent.withOpacity(0.08);
    canvas.drawCircle(Offset(size.width * 0.5, size.height * 0.35), size.width * 0.35, paint);

    paint.color = accent.withOpacity(0.12);
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 2;
    canvas.drawCircle(Offset(size.width * 0.5, size.height * 0.35), size.width * 0.25, paint);
    canvas.drawCircle(Offset(size.width * 0.5, size.height * 0.35), size.width * 0.38, paint);

    paint.color = accent.withOpacity(0.15);
    paint.strokeWidth = 1.5;
    for (int i = 0; i < 6; i++) {
      final angle = (i * math.pi) / 3;
      final cx = size.width * 0.5 + size.width * 0.25 * math.cos(angle);
      final cy = size.height * 0.35 + size.width * 0.25 * math.sin(angle);
      canvas.drawCircle(Offset(cx, cy), 3, paint..style = PaintingStyle.fill);
    }

    final textPaint = Paint()
      ..color = accent.withOpacity(0.2)
      ..style = PaintingStyle.fill;
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(size.width * 0.5, size.height * 0.35), width: size.width * 0.4, height: 14),
      const Radius.circular(4),
    );
    canvas.drawRRect(rect, textPaint);
  }

  void _drawTrophyCup(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = accent.withOpacity(0.12)
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(size.width * 0.3, size.height * 0.15);
    path.lineTo(size.width * 0.7, size.height * 0.15);
    path.lineTo(size.width * 0.65, size.height * 0.4);
    path.quadraticBezierTo(size.width * 0.5, size.height * 0.52, size.width * 0.35, size.height * 0.4);
    path.close();
    canvas.drawPath(path, paint);

    paint.color = accent.withOpacity(0.15);
    canvas.drawRect(Rect.fromCenter(center: Offset(size.width * 0.5, size.height * 0.48), width: 8, height: 12), paint);
    canvas.drawRect(Rect.fromCenter(center: Offset(size.width * 0.5, size.height * 0.55), width: 24, height: 6), paint);

    paint.color = accent.withOpacity(0.08);
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 1.5;
    final handleL = Path();
    handleL.moveTo(size.width * 0.28, size.height * 0.18);
    handleL.quadraticBezierTo(size.width * 0.15, size.height * 0.25, size.width * 0.28, size.height * 0.35);
    canvas.drawPath(handleL, paint);
    final handleR = Path();
    handleR.moveTo(size.width * 0.72, size.height * 0.18);
    handleR.quadraticBezierTo(size.width * 0.85, size.height * 0.25, size.width * 0.72, size.height * 0.35);
    canvas.drawPath(handleR, paint);

    paint.color = accent.withOpacity(0.06);
    for (int i = 0; i < 3; i++) {
      canvas.drawCircle(Offset(size.width * 0.5, size.height * 0.35), size.width * (0.3 + i * 0.08), paint);
    }
  }

  void _drawCricketField(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = accent.withOpacity(0.06)
      ..style = PaintingStyle.fill;
    canvas.drawOval(Rect.fromCenter(center: Offset(size.width * 0.5, size.height * 0.35), width: size.width * 0.7, height: size.width * 0.5), paint);

    paint.color = accent.withOpacity(0.1);
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 1;
    canvas.drawOval(Rect.fromCenter(center: Offset(size.width * 0.5, size.height * 0.35), width: size.width * 0.35, height: size.width * 0.25), paint);

    paint.color = accent.withOpacity(0.12);
    paint.strokeWidth = 2;
    canvas.drawLine(Offset(size.width * 0.45, size.height * 0.28), Offset(size.width * 0.55, size.height * 0.28), paint);
    canvas.drawLine(Offset(size.width * 0.45, size.height * 0.42), Offset(size.width * 0.55, size.height * 0.42), paint);

    paint.color = accent.withOpacity(0.08);
    paint.strokeWidth = 1;
    for (int i = 0; i < 4; i++) {
      final y = size.height * (0.18 + i * 0.06);
      canvas.drawLine(Offset(size.width * 0.2, y), Offset(size.width * 0.8, y), paint);
    }
  }

  void _drawFlagCross(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = accent.withOpacity(0.1)
      ..style = PaintingStyle.fill;

    final flagPath1 = Path();
    flagPath1.moveTo(size.width * 0.35, size.height * 0.12);
    flagPath1.lineTo(size.width * 0.35, size.height * 0.45);
    flagPath1.lineTo(size.width * 0.55, size.height * 0.35);
    flagPath1.lineTo(size.width * 0.35, size.height * 0.25);
    canvas.drawPath(flagPath1, paint);

    paint.color = accent.withOpacity(0.07);
    final flagPath2 = Path();
    flagPath2.moveTo(size.width * 0.55, size.height * 0.12);
    flagPath2.lineTo(size.width * 0.55, size.height * 0.45);
    flagPath2.lineTo(size.width * 0.75, size.height * 0.35);
    flagPath2.lineTo(size.width * 0.55, size.height * 0.25);
    canvas.drawPath(flagPath2, paint);

    paint.color = accent.withOpacity(0.12);
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 1.5;
    canvas.drawLine(Offset(size.width * 0.35, size.height * 0.1), Offset(size.width * 0.35, size.height * 0.5), paint);
    canvas.drawLine(Offset(size.width * 0.55, size.height * 0.1), Offset(size.width * 0.55, size.height * 0.5), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
