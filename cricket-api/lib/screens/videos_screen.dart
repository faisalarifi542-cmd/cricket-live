import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../data/mock_data.dart';
import '../widgets/custom_header.dart';
import '../widgets/section_header.dart';
import '../widgets/video_card.dart';
import 'video_player_screen.dart';

class VideosScreen extends StatelessWidget {
  const VideosScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final videos = MockData.videos;
    return Container(
      decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
      child: Column(
        children: [
          const CustomHeader(showBackButton: false),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionHeader(title: 'Highlights', onViewAll: () {}),
                  const SizedBox(height: 8),
                  // Featured video
                  GestureDetector(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => VideoPlayerScreen(video: videos[0]))),
                    child: VideoCard(video: videos[0], isLarge: true),
                  ),
                  const SizedBox(height: 16),
                  // More Videos section
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: const Text(
                      'More Videos',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...videos.skip(1).map((v) => GestureDetector(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => VideoPlayerScreen(video: v))),
                    child: VideoCard(video: v),
                  )),
                  const SizedBox(height: 90),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
