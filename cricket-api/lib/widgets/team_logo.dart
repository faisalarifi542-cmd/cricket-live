import 'package:flutter/material.dart';

class TeamLogo extends StatelessWidget {
  final String? shortName;
  final String? teamCode;
  final String? logoUrl;
  final String colorHex;
  final double size;

  const TeamLogo({
    super.key,
    this.shortName,
    this.teamCode,
    this.logoUrl,
    this.colorHex = '3B82F6',
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    final displayName = shortName ?? teamCode ?? '?';
    final color = Color(int.parse('0xFF$colorHex'));

    if (logoUrl != null && logoUrl!.isNotEmpty) {
      return ClipOval(
        child: SizedBox(
          width: size,
          height: size,
          child: Image.network(
            logoUrl!,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _buildFallback(displayName, color),
          ),
        ),
      );
    }

    return _buildFallback(displayName, color);
  }

  Widget _buildFallback(String displayName, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.2, -0.3),
          radius: 0.85,
          colors: [
            color,
            color.withOpacity(0.85),
            color.withOpacity(0.6),
          ],
        ),
        border: Border.all(
          color: Colors.white.withOpacity(0.45),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.45),
            blurRadius: 6,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withOpacity(0.15),
            width: 1,
          ),
        ),
        child: Center(
          child: Text(
            displayName.length > 3 ? displayName.substring(0, 3) : displayName,
            style: TextStyle(
              color: Colors.white,
              fontSize: size * 0.26,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.3,
              shadows: [
                Shadow(
                  color: Colors.black.withOpacity(0.6),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
