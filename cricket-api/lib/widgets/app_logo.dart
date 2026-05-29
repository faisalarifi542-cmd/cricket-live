import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme/app_colors.dart';

class AppLogo extends StatelessWidget {
  final double height;
  final bool compact;

  const AppLogo({super.key, this.height = 36, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final iconSize = compact ? 30.0 : height;
    final fontSize = compact ? 18.0 : height * 0.55;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildBallIcon(iconSize),
        const SizedBox(width: 6),
        RichText(
          text: TextSpan(
            style: GoogleFonts.poppins(
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              fontStyle: FontStyle.italic,
            ),
            children: const [
              TextSpan(
                text: 'Cricket',
                style: TextStyle(color: AppColors.textPrimary),
              ),
              TextSpan(
                text: 'Zone',
                style: TextStyle(color: AppColors.cyan),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBallIcon(double s) {
    return SizedBox(
      width: s,
      height: s,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: s * 0.1,
            child: Container(
              width: s * 0.38,
              height: 1.5,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(1),
                gradient: LinearGradient(
                  colors: [
                    AppColors.cyan.withOpacity(0),
                    AppColors.cyan.withOpacity(0.9),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: s * 0.35,
            child: Container(
              width: s * 0.28,
              height: 1.5,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(1),
                gradient: LinearGradient(
                  colors: [
                    AppColors.blue.withOpacity(0),
                    AppColors.blue.withOpacity(0.7),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: s * 0.58,
            child: Container(
              width: s * 0.34,
              height: 1.5,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(1),
                gradient: LinearGradient(
                  colors: [
                    AppColors.cyan.withOpacity(0),
                    AppColors.cyan.withOpacity(0.8),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: s * 0.8,
            child: Container(
              width: s * 0.22,
              height: 1.5,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(1),
                gradient: LinearGradient(
                  colors: [
                    AppColors.blue.withOpacity(0),
                    AppColors.blue.withOpacity(0.6),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            right: 0,
            top: s * 0.05,
            child: Container(
              width: s * 0.72,
              height: s * 0.72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const RadialGradient(
                  center: Alignment(-0.2, -0.3),
                  radius: 0.85,
                  colors: [
                    Color(0xFFFAFAFA),
                    Color(0xFFE8E8E8),
                    Color(0xFFCCCCCC),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.cyan.withOpacity(0.35),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                  BoxShadow(
                    color: Colors.white.withOpacity(0.15),
                    blurRadius: 3,
                  ),
                ],
              ),
              child: Center(
                child: CustomPaint(
                  size: Size(s * 0.45, s * 0.45),
                  painter: _SeamPainter(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SeamPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFCC3333).withOpacity(0.55)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    final path = Path();
    path.moveTo(size.width * 0.15, size.height * 0.05);
    path.cubicTo(
      size.width * 0.65, size.height * 0.25,
      size.width * 0.35, size.height * 0.75,
      size.width * 0.85, size.height * 0.95,
    );
    canvas.drawPath(path, paint);

    final path2 = Path();
    path2.moveTo(size.width * 0.22, size.height * 0.0);
    path2.cubicTo(
      size.width * 0.72, size.height * 0.2,
      size.width * 0.42, size.height * 0.7,
      size.width * 0.92, size.height * 0.9,
    );
    paint.color = const Color(0xFFCC3333).withOpacity(0.3);
    paint.strokeWidth = 0.8;
    canvas.drawPath(path2, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
