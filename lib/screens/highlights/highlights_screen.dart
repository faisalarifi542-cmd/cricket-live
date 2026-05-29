import 'package:flutter/material.dart';
import '../../app_theme.dart';
import '../../components.dart';
import '../../models.dart';

class HighlightsScreen extends StatefulWidget {
  const HighlightsScreen({
    super.key,
    required this.onOpenVideo,
    required this.onOpenSearch,
    required this.onOpenNotifications,
  });

  final VoidCallback onOpenVideo;
  final VoidCallback onOpenSearch;
  final VoidCallback onOpenNotifications;

  @override
  State<HighlightsScreen> createState() => _HighlightsScreenState();
}

class _HighlightsScreenState extends State<HighlightsScreen> {
  int tab = 0;
  int category = 0;

  final categories = [
    'All',
    'T20I',
    'ODI',
    'Test',
    'Batting',
    'Bowling',
    'Fielding'
  ];

  final topMoments = const [
    VideoHighlight(
      title:
          'Rohit Sharma\'s blazing 121* powers India to series-clinching win',
      match: 'India vs Australia • ODI',
      duration: '05:42',
      views: '1.2M views',
      tag: 'Featured',
      asset: 'assets/images/player_rohit_sharma.png',
      featured: true,
    ),
    VideoHighlight(
      title: 'Bumrah rips through Australia with dream spell',
      match: 'India vs Australia • ODI',
      duration: '02:14',
      views: '740K views',
      tag: 'Bowling',
      asset: 'assets/images/player_rohit_sharma.png',
    ),
    VideoHighlight(
      title: 'Mitchell Santner\'s impossible one-handed catch',
      match: 'NZ vs WI • Test',
      duration: '01:08',
      views: '510K views',
      tag: 'Fielding',
      asset: 'assets/images/player_daryl_mitchell.png',
    ),
    VideoHighlight(
      title: 'Virat Kohli ends the chase with trademark cover drive',
      match: 'India vs England • ODI',
      duration: '00:48',
      views: '1.8M views',
      tag: 'Batting',
      asset: 'assets/images/player_rohit_sharma.png',
    ),
    VideoHighlight(
      title: 'Jasprit Bumrah\'s unplayable yorker to dismiss Smith',
      match: 'India vs Australia • Test',
      duration: '00:32',
      views: '890K views',
      tag: 'Bowling',
      asset: 'assets/images/player_rohit_sharma.png',
    ),
    VideoHighlight(
      title: 'Kane Williamson\'s masterclass century in tough conditions',
      match: 'New Zealand vs England • Test',
      duration: '04:18',
      views: '620K views',
      tag: 'Batting',
      asset: 'assets/images/player_kane_williamson.png',
    ),
  ];

  final shorts = const [
    VideoHighlight(
      title: 'Rohit upper-cut for six',
      match: 'IND vs AUS',
      duration: '0:21',
      views: '230K',
      tag: 'Short',
      asset: 'assets/images/player_rohit_sharma.png',
    ),
    VideoHighlight(
      title: 'Bumrah yorker angle',
      match: 'IND vs AUS',
      duration: '0:18',
      views: '180K',
      tag: 'Short',
      asset: 'assets/images/player_daryl_mitchell.png',
    ),
    VideoHighlight(
      title: 'Gill lofted drive',
      match: 'IND vs ENG',
      duration: '0:15',
      views: '260K',
      tag: 'Short',
      asset: 'assets/images/player_yashasvi_jaiswal.png',
    ),
    VideoHighlight(
      title: 'Pant reverse sweep',
      match: 'IND vs AUS',
      duration: '0:19',
      views: '210K',
      tag: 'Short',
      asset: 'assets/images/player_rohit_sharma.png',
    ),
    VideoHighlight(
      title: 'Rahul diving take',
      match: 'IND vs AUS',
      duration: '0:17',
      views: '196K',
      tag: 'Short',
      asset: 'assets/images/player_steven_smith.png',
    ),
    VideoHighlight(
      title: 'Starc inswinger',
      match: 'AUS vs IND',
      duration: '0:16',
      views: '242K',
      tag: 'Short',
      asset: 'assets/images/player_steven_smith.png',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Highlights',
                          style: TextStyle(
                            color: c.text,
                            fontWeight: FontWeight.w900,
                            fontSize: context.sp(28),
                          ),
                        ),
                        Text(
                          'Relive the best cricket moments',
                          style: TextStyle(
                            color: c.muted,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  GlowIconButton(
                      icon: Icons.search_rounded, onTap: widget.onOpenSearch),
                  const SizedBox(width: 8),
                  GlowIconButton(
                      icon: Icons.notifications_none_rounded,
                      onTap: widget.onOpenNotifications),
                ],
              ),
              const SizedBox(height: 22),

              // Tabs
              SegmentedTabs(
                items: const [
                  ('Top Moments', null),
                  ('Shorts', null),
                ],
                selected: tab,
                onChanged: (v) => setState(() => tab = v),
              ),
              const SizedBox(height: 18),

              // Category Chips
              SizedBox(
                height: 46,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: categories.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (_, i) => PillChip(
                    categories[i],
                    selected: category == i,
                    onTap: () => setState(() => category = i),
                  ),
                ),
              ),
              const SizedBox(height: 22),

              // Content based on tab
              if (tab == 0) ...[
                // Top Moments - Featured Video
                _FeaturedVideoCard(
                  video: topMoments.first,
                  onTap: widget.onOpenVideo,
                ),
                const SizedBox(height: 18),

                // Top Moments - List
                for (final video in topMoments.skip(1))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _VideoListCard(
                      video: video,
                      onTap: widget.onOpenVideo,
                    ),
                  ),
              ] else ...[
                // Shorts - Grid
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: shorts.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    childAspectRatio: 0.68,
                  ),
                  itemBuilder: (_, i) => _ShortCard(
                    video: shorts[i],
                    onTap: widget.onOpenVideo,
                  ),
                ),
                const SizedBox(height: 24),

                // Alert Card
                PremiumCard(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Never miss a moment',
                              style: TextStyle(
                                color: c.text,
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Enable alerts for wickets, milestones and clips from your favourite teams.',
                              style: TextStyle(
                                color: c.muted,
                                height: 1.5,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          gradient: c.primaryGradient,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.notifications_active_outlined,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FeaturedVideoCard extends StatelessWidget {
  const _FeaturedVideoCard({
    required this.video,
    required this.onTap,
  });

  final VideoHighlight video;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      onTap: onTap,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Thumbnail
          Container(
            height: 220,
            decoration: BoxDecoration(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(26)),
              color: c.card2,
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(26)),
                    child: Image.asset(
                      video.asset ?? 'assets/images/stadium_live.png',
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Icon(
                          Icons.play_circle_outline_rounded,
                          color: c.muted,
                          size: 64),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(26)),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: .1),
                          Colors.black.withValues(alpha: .5),
                        ],
                      ),
                    ),
                  ),
                ),
                Center(
                  child: Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      gradient: c.primaryGradient,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: c.cyan.withValues(alpha: .4),
                          blurRadius: 20,
                          spreadRadius: 3,
                        )
                      ],
                    ),
                    child: const Icon(Icons.play_arrow_rounded,
                        color: Colors.white, size: 42),
                  ),
                ),
                Positioned(
                  left: 14,
                  top: 14,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                Positioned(
                  right: 14,
                  bottom: 14,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: .8),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      video.duration,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Info
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  video.title,
                  style: TextStyle(
                    color: c.text,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      video.match,
                      style: TextStyle(
                        color: c.cyan,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text('•', style: TextStyle(color: c.muted)),
                    const SizedBox(width: 10),
                    Text(
                      video.views,
                      style: TextStyle(
                        color: c.muted,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoListCard extends StatelessWidget {
  const _VideoListCard({
    required this.video,
    required this.onTap,
  });

  final VideoHighlight video;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          // Thumbnail
          Container(
            width: 140,
            height: 90,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: c.card2,
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Image.asset(
                    video.asset ?? 'assets/images/stadium_live.png',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        Icon(Icons.play_circle_outline_rounded, color: c.muted),
                  ),
                ),
                Center(
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: .7),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.play_arrow_rounded,
                        color: Colors.white, size: 26),
                  ),
                ),
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: .8),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      video.duration,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
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
                  video.title,
                  style: TextStyle(
                    color: c.text,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Text(
                  video.match,
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
                  video.views,
                  style: TextStyle(
                    color: c.muted,
                    fontSize: 13,
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

class _ShortCard extends StatelessWidget {
  const _ShortCard({
    required this.video,
    required this.onTap,
  });

  final VideoHighlight video;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      onTap: onTap,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Thumbnail
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(26)),
                color: c.card2,
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(26)),
                      child: Image.asset(
                        video.asset ?? 'assets/images/stadium_live.png',
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Icon(
                            Icons.play_circle_outline_rounded,
                            color: c.muted),
                      ),
                    ),
                  ),
                  Center(
                    child: Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        gradient: c.primaryGradient,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.play_arrow_rounded,
                          color: Colors.white, size: 32),
                    ),
                  ),
                  Positioned(
                    right: 10,
                    bottom: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: .8),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        video.duration,
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
          ),
          // Info
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  video.title,
                  style: TextStyle(
                    color: c.text,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  video.views,
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
