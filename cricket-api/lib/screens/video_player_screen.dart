import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../models/video_model.dart';
import '../data/mock_data.dart';
import '../widgets/custom_header.dart';
import '../widgets/glass_card.dart';

class VideoPlayerScreen extends StatelessWidget {
  final VideoModel video;

  const VideoPlayerScreen({super.key, required this.video});

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
                      // Video player area
                      Container(
                        width: double.infinity,
                        height: 220,
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              const Color(0xFF1A3A5C).withOpacity(0.6),
                              const Color(0xFF0A1E3D),
                            ],
                          ),
                          border: Border.all(color: AppColors.borderColor.withOpacity(0.3)),
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Play button
                            Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.blue.withOpacity(0.8),
                                boxShadow: [
                                  BoxShadow(color: AppColors.blue.withOpacity(0.4), blurRadius: 20),
                                ],
                              ),
                              child: const Icon(Icons.play_arrow, color: Colors.white, size: 36),
                            ),
                            // Duration badge
                            Positioned(
                              bottom: 12,
                              right: 12,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.7),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  video.duration,
                                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ),
                            // Progress bar mock
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: Container(
                                height: 3,
                                decoration: BoxDecoration(
                                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                                  color: AppColors.textMuted.withOpacity(0.2),
                                ),
                                child: FractionallySizedBox(
                                  alignment: Alignment.centerLeft,
                                  widthFactor: 0.0,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: AppColors.red,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Video info
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          video.title,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          video.subtitle,
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Action buttons
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            _buildActionButton(Icons.thumb_up_outlined, 'Like'),
                            const SizedBox(width: 16),
                            _buildActionButton(Icons.share_outlined, 'Share'),
                            const SizedBox(width: 16),
                            _buildActionButton(Icons.download_outlined, 'Save'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Divider(color: AppColors.borderColor.withOpacity(0.3), indent: 16, endIndent: 16),
                      const SizedBox(height: 12),
                      // Related videos
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: const Text(
                          'Related Videos',
                          style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(height: 10),
                      ...MockData.videos.where((v) => v.id != video.id).map((v) => _buildRelatedVideo(context, v)),
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

  Widget _buildActionButton(IconData icon, String label) {
    return Column(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.cardBg,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.borderColor.withOpacity(0.4)),
          ),
          child: Icon(icon, color: AppColors.textSecondary, size: 20),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
      ],
    );
  }

  Widget _buildRelatedVideo(BuildContext context, VideoModel v) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => VideoPlayerScreen(video: v)),
        );
      },
      child: GlassCard(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        padding: const EdgeInsets.all(10),
        borderRadius: 12,
        child: Row(
          children: [
            Stack(
              children: [
                Container(
                  width: 100,
                  height: 62,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: const Color(0xFF1A3A5C),
                  ),
                  child: Center(
                    child: Icon(Icons.play_circle_outline, color: Colors.white.withOpacity(0.5), size: 28),
                  ),
                ),
                Positioned(
                  bottom: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(v.duration, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(v.title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 12, fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(v.subtitle, style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
