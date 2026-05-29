import 'package:flutter/material.dart';
import '../../app_theme.dart';
import '../../components.dart';
import '../../models.dart';

class HighlightDetailScreen extends StatelessWidget {
  const HighlightDetailScreen({super.key, this.video});

  final VideoHighlight? video;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final v = video ??
        const VideoHighlight(
          title:
              'Rohit Sharma\'s blazing 121* powers India to series-clinching win',
          match: 'India vs Australia • ODI',
          duration: '05:42',
          views: '1.2M views',
          tag: 'Featured',
          asset: 'assets/images/player_rohit_sharma.png',
          featured: true,
        );

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: c.bgGradient),
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              context.horizontalPadding,
              18,
              context.horizontalPadding,
              context.detailBottomPadding,
            ),
            children: [
              // Header
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon:
                        Icon(Icons.arrow_back_rounded, color: c.text, size: 28),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Highlights',
                      style: TextStyle(
                        color: c.text,
                        fontWeight: FontWeight.w900,
                        fontSize: context.sp(24),
                      ),
                    ),
                  ),
                  const GlowIconButton(icon: Icons.share_outlined),
                  const SizedBox(width: 8),
                  const GlowIconButton(icon: Icons.more_vert_rounded),
                ],
              ),
              const SizedBox(height: 20),

              // Video Player Card
              PremiumCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    // Video Preview
                    Container(
                      height: 240,
                      decoration: const BoxDecoration(
                        borderRadius: BorderRadius.vertical(
                            top: Radius.circular(26)),
                        color: Colors.black,
                      ),
                      child: Stack(
                        children: [
                          // Thumbnail
                          Positioned.fill(
                            child: Image.asset(
                              v.asset ?? 'assets/images/stadium_live.png',
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color: c.card2,
                                child: Icon(Icons.play_circle_outline_rounded,
                                    color: c.muted, size: 64),
                              ),
                            ),
                          ),
                          // Overlay
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.black.withValues(alpha: .2),
                                    Colors.black.withValues(alpha: .6),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          // Play Button
                          Center(
                            child: Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: c.primaryGradient,
                                boxShadow: [
                                  BoxShadow(
                                    color: c.cyan.withValues(alpha: .4),
                                    blurRadius: 24,
                                    spreadRadius: 4,
                                  )
                                ],
                              ),
                              child: const Icon(
                                Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 48,
                              ),
                            ),
                          ),
                          // Duration Badge
                          Positioned(
                            right: 16,
                            bottom: 16,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: .8),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                v.duration,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                          // Featured Badge
                          if (v.featured)
                            Positioned(
                              left: 16,
                              top: 16,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: c.cyan,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const Text(
                                  'FEATURED',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    // Video Controls
                    Padding(
                      padding: const EdgeInsets.all(18),
                      child: Row(
                        children: [
                          Icon(Icons.replay_10_rounded,
                              color: c.text, size: 28),
                          const Spacer(),
                          Icon(Icons.play_arrow_rounded,
                              color: c.cyan, size: 36),
                          const Spacer(),
                          Icon(Icons.forward_10_rounded,
                              color: c.text, size: 28),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Video Title and Info
              Text(
                v.title,
                style: TextStyle(
                  color: c.text,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    v.match,
                    style: TextStyle(
                      color: c.cyan,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '•',
                    style: TextStyle(color: c.muted),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    v.views,
                    style: TextStyle(
                      color: c.muted,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.thumb_up_outlined,
                      label: 'Like',
                      onTap: () {},
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.bookmark_outline_rounded,
                      label: 'Save',
                      onTap: () {},
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ActionButton(
                      icon: Icons.share_outlined,
                      label: 'Share',
                      onTap: () {},
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Description
              PremiumCard(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'About this highlight',
                      style: TextStyle(
                        color: c.text,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Rohit Sharma played a captain\'s knock, scoring an unbeaten 121 off 98 balls to guide India to a commanding victory over Australia in the 3rd ODI. His innings included 12 fours and 4 sixes, showcasing his trademark pull shots and elegant drives.\n\nThis win sealed the series 2-1 for India, marking their first ODI series victory in Australia since 2019.',
                      style: TextStyle(
                        color: c.muted,
                        fontSize: 15,
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Related Highlights
              Row(
                children: [
                  Text(
                    'Related Highlights',
                    style: TextStyle(
                      color: c.text,
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () {},
                    child: Text(
                      'See All',
                      style: TextStyle(
                        color: c.cyan,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const _RelatedVideoCard(
                title: 'Bumrah rips through Australia with dream spell',
                match: 'India vs Australia • ODI',
                duration: '02:14',
                views: '740K views',
                asset: 'assets/images/player_rohit_sharma.png',
              ),
              const SizedBox(height: 12),
              const _RelatedVideoCard(
                title: 'Virat Kohli ends the chase with trademark cover drive',
                match: 'India vs England • ODI',
                duration: '00:48',
                views: '1.8M views',
                asset: 'assets/images/player_rohit_sharma.png',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Column(
        children: [
          Icon(icon, color: c.cyan, size: 26),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              color: c.text,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _RelatedVideoCard extends StatelessWidget {
  const _RelatedVideoCard({
    required this.title,
    required this.match,
    required this.duration,
    required this.views,
    required this.asset,
  });

  final String title;
  final String match;
  final String duration;
  final String views;
  final String asset;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      onTap: () {},
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          // Thumbnail
          Container(
            width: 120,
            height: 80,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: c.card2,
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Image.asset(
                    asset,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        Icon(Icons.play_circle_outline_rounded, color: c.muted),
                  ),
                ),
                Center(
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: .7),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.play_arrow_rounded,
                        color: Colors.white, size: 24),
                  ),
                ),
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: .8),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      duration,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: c.text,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  match,
                  style: TextStyle(
                    color: c.cyan,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  views,
                  style: TextStyle(
                    color: c.muted,
                    fontSize: 12,
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
