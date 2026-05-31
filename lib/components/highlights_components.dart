import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../components.dart';
import '../models.dart';

class FeaturedVideoCard extends StatelessWidget {
  const FeaturedVideoCard(
      {super.key, required this.video, this.onTap, this.largeOnly = false});

  final VideoHighlight video;
  final VoidCallback? onTap;
  final bool largeOnly;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        height: largeOnly ? 320 : 360,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: c.border)),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned.fill(
              child: Image.asset(
                video.asset ?? 'assets/images/stadium_live.png',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    const EmptyOrErrorImage(label: 'Video'),
              ),
            ),
            Positioned.fill(
                child: DecoratedBox(
                    decoration: BoxDecoration(
                        gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                  Colors.black.withValues(alpha: .10),
                  Colors.black.withValues(alpha: .74)
                ])))),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    StatusBadge(
                        label: video.featured ? 'FEATURED' : video.tag,
                        color: c.cyan,
                        filled: true),
                    const Spacer(),
                    StatusBadge(
                        label: video.duration,
                        color: Colors.white,
                        filled: true,
                        icon: Icons.play_arrow_rounded),
                  ],
                ),
                const Spacer(),
                Row(
                  children: [
                    Container(
                      width: 66,
                      height: 66,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: c.cyan.withValues(alpha: .18),
                          border:
                              Border.all(color: c.cyan.withValues(alpha: .7))),
                      child: Icon(Icons.play_arrow_rounded,
                          color: c.cyan, size: 36),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(video.title,
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: context.sp(24),
                                  height: 1.15)),
                          const SizedBox(height: 8),
                          Text('${video.match} • ${video.views}',
                              style: TextStyle(
                                  color: Colors.white.withValues(alpha: .82))),
                        ],
                      ),
                    ),
                    const GlowIconButton(icon: Icons.more_horiz_rounded),
                  ],
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}

class VideoListCard extends StatelessWidget {
  const VideoListCard({super.key, required this.video, this.onTap});

  final VideoHighlight video;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: SizedBox(
                  width: 144,
                  height: 96,
                  child: Image.asset(
                    video.asset ?? 'assets/images/stadium_live.png',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        const EmptyOrErrorImage(label: 'Clip'),
                  ),
                ),
              ),
              Positioned(
                bottom: 8,
                left: 8,
                child: StatusBadge(
                    label: video.duration, color: Colors.white, filled: true),
              )
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(video.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: c.text,
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                        height: 1.25)),
                const SizedBox(height: 8),
                Text(video.match, style: TextStyle(color: c.muted)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(video.views,
                        style: TextStyle(
                            color: c.cyan, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 12),
                    StatusBadge(label: video.tag, color: c.cyan),
                  ],
                )
              ],
            ),
          ),
          const GlowIconButton(icon: Icons.more_horiz_rounded),
        ],
      ),
    );
  }
}

class ShortCard extends StatelessWidget {
  const ShortCard({super.key, required this.video, this.onTap});

  final VideoHighlight video;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: SizedBox.expand(
                    child: Image.asset(
                      video.asset ?? 'assets/images/stadium_live.png',
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const EmptyOrErrorImage(label: 'Short'),
                    ),
                  ),
                ),
                Positioned(
                  left: 10,
                  top: 10,
                  child: StatusBadge(
                      label: video.duration, color: Colors.white, filled: true),
                ),
                const Positioned(
                  right: 10,
                  top: 10,
                  child: GlowIconButton(icon: Icons.more_horiz_rounded),
                ),
                Positioned(
                  left: 10,
                  bottom: 10,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: c.cyan.withValues(alpha: .18),
                        border:
                            Border.all(color: c.cyan.withValues(alpha: .8))),
                    child:
                        Icon(Icons.play_arrow_rounded, color: c.cyan, size: 30),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(video.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: c.text,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  height: 1.25)),
          const SizedBox(height: 6),
          Text('${video.match} • ${video.views}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: c.muted, height: 1.35)),
        ],
      ),
    );
  }
}
