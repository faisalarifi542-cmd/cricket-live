import 'package:flutter/material.dart';
import '../../app_theme.dart';
import '../../components.dart';
import '../../models/api_models.dart';
import '../../models/api_response.dart';
import '../../repositories/cricket_repository.dart';

class LivePlayerScreen extends StatefulWidget {
  const LivePlayerScreen({super.key, this.matchId = ''});

  final String matchId;

  @override
  State<LivePlayerScreen> createState() => _LivePlayerScreenState();
}

class _LivePlayerScreenState extends State<LivePlayerScreen> {
  String selectedQuality = 'Full HD';
  final CricketRepository _repository = CricketRepository();
  Future<ApiEnvelope<Map<String, dynamic>>>? _streams;

  @override
  void initState() {
    super.initState();
    if (widget.matchId.isNotEmpty) {
      _streams = _repository.matchStreams(widget.matchId);
    }
  }

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
                          'Live Match',
                          style: TextStyle(
                            color: c.text,
                            fontWeight: FontWeight.w900,
                            fontSize: context.sp(24),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: c.live,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: c.live.withValues(alpha: .5),
                                    blurRadius: 8,
                                    spreadRadius: 2,
                                  )
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'LIVE NOW',
                              style: TextStyle(
                                color: c.live,
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  GlowIconButton(icon: Icons.cast_rounded),
                  const SizedBox(width: 8),
                  GlowIconButton(icon: Icons.more_vert_rounded),
                ],
              ),
              const SizedBox(height: 24),

              // Match Info Card
              PremiumCard(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    Text(
                      'ICC MEN\'S ODI SERIES',
                      style: TextStyle(
                        color: c.cyan,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Column(
                          children: [
                            Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: c.card2,
                                border: Border.all(color: c.border, width: 2),
                              ),
                              alignment: Alignment.center,
                              child: const Text('🇮🇳',
                                  style: TextStyle(fontSize: 32)),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'IND',
                              style: TextStyle(
                                color: c.text,
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              '321/4',
                              style: TextStyle(
                                color: c.cyan,
                                fontWeight: FontWeight.w800,
                                fontSize: 20,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 24),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            gradient: c.primaryGradient,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'VS',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                            ),
                          ),
                        ),
                        const SizedBox(width: 24),
                        Column(
                          children: [
                            Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: c.card2,
                                border: Border.all(color: c.border, width: 2),
                              ),
                              alignment: Alignment.center,
                              child: const Text('🇦🇺',
                                  style: TextStyle(fontSize: 32)),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'AUS',
                              style: TextStyle(
                                color: c.text,
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              '315/9',
                              style: TextStyle(
                                color: c.muted,
                                fontWeight: FontWeight.w800,
                                fontSize: 20,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'India need 6 runs to win',
                      style: TextStyle(
                        color: c.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
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
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(26)),
                        color: Colors.black,
                      ),
                      child: Stack(
                        children: [
                          // Stadium Background
                          Positioned.fill(
                            child: Image.asset(
                              'assets/images/stadium_live.png',
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  Container(color: Colors.black),
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
                                    Colors.black.withValues(alpha: .3),
                                    Colors.black.withValues(alpha: .7),
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
                          // Fullscreen Button
                          Positioned(
                            right: 16,
                            bottom: 16,
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: .6),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.fullscreen_rounded,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                          ),
                          // Live Badge
                          Positioned(
                            left: 16,
                            top: 16,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: c.live,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: c.live.withValues(alpha: .5),
                                    blurRadius: 12,
                                  )
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: const BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Text(
                                    'LIVE',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Controls
                    Padding(
                      padding: const EdgeInsets.all(18),
                      child: Row(
                        children: [
                          Icon(Icons.volume_up_rounded,
                              color: c.text, size: 24),
                          const SizedBox(width: 16),
                          Expanded(
                            child: SliderTheme(
                              data: SliderThemeData(
                                activeTrackColor: c.cyan,
                                inactiveTrackColor: c.border,
                                thumbColor: c.cyan,
                                overlayColor: c.cyan.withValues(alpha: .2),
                              ),
                              child: Slider(
                                value: 0.7,
                                onChanged: (v) {},
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Icon(Icons.settings_rounded, color: c.text, size: 24),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              if (_streams != null) ...[
                FutureBuilder<ApiEnvelope<Map<String, dynamic>>>(
                  future: _streams,
                  builder: (context, snapshot) {
                    final streams = apiList(snapshot.data?.data['streams'] ?? snapshot.data?.data['data'])
                        .map(StreamSource.fromJson)
                        .where((stream) => stream.url.isNotEmpty)
                        .toList();
                    if (snapshot.connectionState == ConnectionState.waiting && streams.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 18),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (streams.isEmpty) {
                      return PremiumCard(
                        padding: const EdgeInsets.all(18),
                        child: Row(
                          children: [
                            Icon(Icons.live_tv_rounded, color: c.cyan, size: 30),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Text(
                                'Stream will be available before match starts.',
                                style: TextStyle(color: c.text, fontWeight: FontWeight.w800, height: 1.35),
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Available Servers',
                          style: TextStyle(color: c.text, fontWeight: FontWeight.w900, fontSize: 20),
                        ),
                        const SizedBox(height: 14),
                        for (final stream in streams)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _QualityOption(
                              label: stream.name,
                              subtitle: stream.quality ?? 'Public stream',
                              selected: selectedQuality == stream.id,
                              onTap: () => setState(() => selectedQuality = stream.id),
                            ),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 24),
              ],

              // Quality Selection
              Text(
                'Stream Quality',
                style: TextStyle(
                  color: c.text,
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                ),
              ),
              const SizedBox(height: 14),
              _QualityOption(
                label: 'Full HD',
                subtitle: '1080p • Best quality',
                selected: selectedQuality == 'Full HD',
                onTap: () => setState(() => selectedQuality = 'Full HD'),
              ),
              const SizedBox(height: 12),
              _QualityOption(
                label: 'HD',
                subtitle: '720p • Recommended',
                selected: selectedQuality == 'HD',
                onTap: () => setState(() => selectedQuality = 'HD'),
              ),
              const SizedBox(height: 12),
              _QualityOption(
                label: 'SD',
                subtitle: '480p • Save data',
                selected: selectedQuality == 'SD',
                onTap: () => setState(() => selectedQuality = 'SD'),
              ),
              const SizedBox(height: 24),

              // Server Info
              PremiumCard(
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: .15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check_circle_rounded,
                          color: Colors.green, size: 28),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Stable Connection',
                            style: TextStyle(
                              color: c.text,
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Server: Asia-Pacific • Latency: 24ms',
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QualityOption extends StatelessWidget {
  const _QualityOption({
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      onTap: onTap,
      padding: const EdgeInsets.all(18),
      borderColor: selected ? c.cyan : null,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: c.text,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: c.muted,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          if (selected)
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                gradient: c.primaryGradient,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_rounded,
                  color: Colors.white, size: 18),
            )
          else
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: c.border, width: 2),
              ),
            ),
        ],
      ),
    );
  }
}
