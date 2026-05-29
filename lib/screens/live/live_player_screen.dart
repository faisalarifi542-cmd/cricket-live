import 'dart:async';

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
  final CricketRepository _repository = CricketRepository();
  Future<ApiEnvelope<Map<String, dynamic>>>? _streamsFuture;
  Future<ApiEnvelope<Map<String, dynamic>>>? _detailFuture;
  Future<ApiEnvelope<Map<String, dynamic>>>? _liveLineFuture;
  Future<ApiEnvelope<Map<String, dynamic>>>? _appConfigFuture;
  Timer? _liveTimer;
  StreamSource? _selectedStream;

  bool get _hasMatchId => widget.matchId.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _appConfigFuture = _repository.appConfig();
    if (_hasMatchId) {
      _detailFuture = _repository.matchDetail(widget.matchId);
      _liveLineFuture = _repository.matchLiveLine(widget.matchId);
      _streamsFuture = _repository.matchStreams(widget.matchId);
      _liveTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (mounted) {
          setState(() {
            _liveLineFuture =
                _repository.matchLiveLine(widget.matchId, forceRefresh: true);
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!_hasMatchId) return;
    setState(() {
      _detailFuture =
          _repository.matchDetail(widget.matchId, forceRefresh: true);
      _liveLineFuture =
          _repository.matchLiveLine(widget.matchId, forceRefresh: true);
      _streamsFuture =
          _repository.matchStreams(widget.matchId, forceRefresh: true);
    });
    await Future.wait<dynamic>([
      _detailFuture!,
      _liveLineFuture!,
      _streamsFuture!,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: c.bgGradient),
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                context.horizontalPadding,
                18,
                context.horizontalPadding,
                context.detailBottomPadding,
              ),
              children: [
                _LivePlayerHeader(matchId: widget.matchId),
                const SizedBox(height: 24),
                _MatchInfoSection(
                  matchId: widget.matchId,
                  detailFuture: _detailFuture,
                  liveLineFuture: _liveLineFuture,
                ),
                const SizedBox(height: 20),
                _PlayerSurface(stream: _selectedStream),
                const SizedBox(height: 24),
                _StreamsSection(
                  matchId: widget.matchId,
                  streamsFuture: _streamsFuture,
                  appConfigFuture: _appConfigFuture,
                  selectedId: _selectedStream?.id,
                  onSelect: (s) => setState(() => _selectedStream = s),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LivePlayerHeader extends StatelessWidget {
  const _LivePlayerHeader({required this.matchId});

  final String matchId;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Row(
      children: [
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(Icons.arrow_back_rounded, color: c.text, size: 28),
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
                        ),
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
                  if (matchId.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(
                      '#$matchId',
                      style: TextStyle(
                        color: c.muted,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        const GlowIconButton(icon: Icons.cast_rounded),
        const SizedBox(width: 8),
        const GlowIconButton(icon: Icons.more_vert_rounded),
      ],
    );
  }
}

class _MatchInfoSection extends StatelessWidget {
  const _MatchInfoSection({
    required this.matchId,
    required this.detailFuture,
    required this.liveLineFuture,
  });

  final String matchId;
  final Future<ApiEnvelope<Map<String, dynamic>>>? detailFuture;
  final Future<ApiEnvelope<Map<String, dynamic>>>? liveLineFuture;

  @override
  Widget build(BuildContext context) {
    if (matchId.isEmpty) {
      return const _MatchInfoUnavailable();
    }
    return FutureBuilder<ApiEnvelope<Map<String, dynamic>>>(
      future: detailFuture,
      builder: (context, detailSnapshot) {
        return FutureBuilder<ApiEnvelope<Map<String, dynamic>>>(
          future: liveLineFuture,
          builder: (context, lineSnapshot) {
            final loading = detailSnapshot.connectionState ==
                    ConnectionState.waiting &&
                !detailSnapshot.hasData;
            if (loading) {
              return const _MatchInfoSkeleton();
            }
            final detail = apiMap(detailSnapshot.data?.data);
            final liveLine = apiMap(lineSnapshot.data?.data);
            return _MatchInfoCard(detail: detail, liveLine: liveLine);
          },
        );
      },
    );
  }
}

class _MatchInfoCard extends StatelessWidget {
  const _MatchInfoCard({required this.detail, required this.liveLine});

  final Map<String, dynamic> detail;
  final Map<String, dynamic> liveLine;

  String _firstNonEmpty(List<String?> values, String fallback) {
    for (final value in values) {
      final v = apiString(value);
      if (v.isNotEmpty) return v;
    }
    return fallback;
  }

  String _formatScore(dynamic team) {
    final t = apiMap(team);
    final innings = apiList(t['innings']);
    if (innings.isEmpty) return '—';
    final first = apiMap(innings.first);
    final runs = apiInt(first['runs']);
    final wickets = apiInt(first['wickets']);
    final overs = apiString(first['overs']);
    if (runs == null) return '—';
    final scoreLine = wickets == null ? '$runs' : '$runs/$wickets';
    return overs.isEmpty ? scoreLine : '$scoreLine ($overs)';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final team1 = apiMap(detail['team1']);
    final team2 = apiMap(detail['team2']);
    final series = _firstNonEmpty(
      [
        detail['series_name']?.toString(),
        detail['seriesName']?.toString(),
        detail['match_desc']?.toString(),
      ],
      'Live cricket',
    );
    final t1Name = _firstNonEmpty(
      [
        team1['short_name']?.toString(),
        team1['shortName']?.toString(),
        team1['name']?.toString(),
      ],
      'TBD',
    );
    final t2Name = _firstNonEmpty(
      [
        team2['short_name']?.toString(),
        team2['shortName']?.toString(),
        team2['name']?.toString(),
      ],
      'TBD',
    );
    final t1Score = _formatScore(team1);
    final t2Score = _formatScore(team2);
    final statusText = _firstNonEmpty(
      [
        detail['status_text']?.toString(),
        liveLine['statusText']?.toString(),
        liveLine['status']?.toString(),
      ],
      'Match in progress',
    );

    return PremiumCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          Text(
            series.toUpperCase(),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: c.cyan,
              fontWeight: FontWeight.w800,
              fontSize: 12,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Expanded(
                child: _TeamColumn(
                  name: t1Name,
                  score: t1Score,
                  logoUrl: team1['logo_url']?.toString(),
                  isStriker:
                      apiString(liveLine['battingTeam']?.toString()) == t1Name,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
              Expanded(
                child: _TeamColumn(
                  name: t2Name,
                  score: t2Score,
                  logoUrl: team2['logo_url']?.toString(),
                  isStriker:
                      apiString(liveLine['battingTeam']?.toString()) == t2Name,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            statusText,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: c.text,
              fontWeight: FontWeight.w700,
              fontSize: 14,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _TeamColumn extends StatelessWidget {
  const _TeamColumn({
    required this.name,
    required this.score,
    required this.logoUrl,
    required this.isStriker,
  });

  final String name;
  final String score;
  final String? logoUrl;
  final bool isStriker;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Column(
      children: [
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: c.card2,
            border: Border.all(
              color: isStriker ? c.cyan : c.border,
              width: 2,
            ),
          ),
          alignment: Alignment.center,
          clipBehavior: Clip.antiAlias,
          child: logoUrl != null && logoUrl!.isNotEmpty
              ? Image.network(
                  logoUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _TeamInitial(name: name),
                )
              : _TeamInitial(name: name),
        ),
        const SizedBox(height: 8),
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: c.text,
            fontWeight: FontWeight.w900,
            fontSize: 16,
          ),
        ),
        Text(
          score,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: isStriker ? c.cyan : c.muted,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
      ],
    );
  }
}

class _TeamInitial extends StatelessWidget {
  const _TeamInitial({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final initial = name.isEmpty ? '?' : name.substring(0, 1).toUpperCase();
    return Text(
      initial,
      style: TextStyle(
        color: c.text,
        fontWeight: FontWeight.w900,
        fontSize: 22,
      ),
    );
  }
}

class _MatchInfoSkeleton extends StatelessWidget {
  const _MatchInfoSkeleton();

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          Container(
            width: 140,
            height: 12,
            decoration: BoxDecoration(
              color: c.card2,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(
              3,
              (_) => Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: c.card2,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: 200,
            height: 12,
            decoration: BoxDecoration(
              color: c.card2,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ],
      ),
    );
  }
}

class _MatchInfoUnavailable extends StatelessWidget {
  const _MatchInfoUnavailable();

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: c.cyan, size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              'Open Live Player from a live match card to see streams.',
              style: TextStyle(
                color: c.text,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayerSurface extends StatelessWidget {
  const _PlayerSurface({required this.stream});

  final StreamSource? stream;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final hasStream = stream != null && stream!.url.isNotEmpty;
    return PremiumCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Container(
            height: 240,
            decoration: const BoxDecoration(
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(26)),
              color: Colors.black,
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Image.asset(
                    'assets/images/stadium_live.png',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        Container(color: Colors.black),
                  ),
                ),
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: .3),
                          Colors.black.withValues(alpha: .75),
                        ],
                      ),
                    ),
                  ),
                ),
                Center(
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: hasStream
                          ? c.primaryGradient
                          : LinearGradient(colors: [c.card2, c.card2]),
                      boxShadow: hasStream
                          ? [
                              BoxShadow(
                                color: c.cyan.withValues(alpha: .4),
                                blurRadius: 24,
                                spreadRadius: 4,
                              ),
                            ]
                          : null,
                    ),
                    child: Icon(
                      hasStream
                          ? Icons.play_arrow_rounded
                          : Icons.live_tv_rounded,
                      color: Colors.white.withValues(
                          alpha: hasStream ? 1.0 : 0.65),
                      size: 48,
                    ),
                  ),
                ),
                if (hasStream)
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
                Positioned(
                  left: 16,
                  top: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: hasStream ? c.live : c.card2,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: hasStream
                          ? [
                              BoxShadow(
                                color: c.live.withValues(alpha: .5),
                                blurRadius: 12,
                              ),
                            ]
                          : null,
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
                        Text(
                          hasStream ? 'LIVE' : 'STANDBY',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (hasStream)
                  Positioned(
                    right: 16,
                    top: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: .6),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        stream!.qualityLabel,
                        style: TextStyle(
                          color: c.cyan,
                          fontWeight: FontWeight.w900,
                          fontSize: 11,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Icon(Icons.volume_up_rounded, color: c.text, size: 24),
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
                      onChanged: hasStream ? (_) {} : null,
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
    );
  }
}

class _StreamsSection extends StatelessWidget {
  const _StreamsSection({
    required this.matchId,
    required this.streamsFuture,
    required this.appConfigFuture,
    required this.selectedId,
    required this.onSelect,
  });

  final String matchId;
  final Future<ApiEnvelope<Map<String, dynamic>>>? streamsFuture;
  final Future<ApiEnvelope<Map<String, dynamic>>>? appConfigFuture;
  final String? selectedId;
  final ValueChanged<StreamSource> onSelect;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    if (matchId.isEmpty) {
      return PremiumCard(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Icon(Icons.live_tv_rounded, color: c.cyan, size: 30),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                'No match selected. Tap Watch Live on a live or upcoming match.',
                style: TextStyle(
                    color: c.text,
                    fontWeight: FontWeight.w800,
                    height: 1.35),
              ),
            ),
          ],
        ),
      );
    }

    return FutureBuilder<ApiEnvelope<Map<String, dynamic>>>(
      future: streamsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const _StreamsSkeleton();
        }
        final data = apiMap(snapshot.data?.data);
        final streams = apiList(data['streams'])
            .map(StreamSource.fromJson)
            .where((stream) => stream.url.isNotEmpty)
            .toList();
        if (streams.isEmpty) {
          return _StreamsUnavailable(appConfigFuture: appConfigFuture);
        }
        // Auto-select highest priority stream once available
        if (selectedId == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) => onSelect(streams.first));
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Available Servers',
              style: TextStyle(
                color: c.text,
                fontWeight: FontWeight.w900,
                fontSize: 20,
              ),
            ),
            const SizedBox(height: 14),
            for (final stream in streams) ...[
              _StreamOption(
                stream: stream,
                selected: stream.id == selectedId,
                onTap: () => onSelect(stream),
              ),
              const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }
}

class _StreamOption extends StatelessWidget {
  const _StreamOption({
    required this.stream,
    required this.selected,
    required this.onTap,
  });

  final StreamSource stream;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final subtitleParts = <String>[
      stream.qualityLabel,
      if (apiString(stream.language).isNotEmpty) stream.language!,
      if (apiString(stream.streamType).isNotEmpty)
        stream.streamType!.toUpperCase(),
    ];
    return PremiumCard(
      onTap: onTap,
      padding: const EdgeInsets.all(18),
      borderColor: selected ? c.cyan : null,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: selected ? c.primaryGradient : null,
              color: selected ? null : c.card2,
              border: Border.all(color: c.border),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.dns_rounded,
              color: selected ? Colors.white : c.muted,
              size: 22,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        stream.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.text,
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    if (stream.isPremium) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: c.cyan.withValues(alpha: .15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'PRO',
                          style: TextStyle(
                            color: c.cyan,
                            fontWeight: FontWeight.w900,
                            fontSize: 10,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  subtitleParts.join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.muted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
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

class _StreamsSkeleton extends StatelessWidget {
  const _StreamsSkeleton();

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: 160,
          height: 18,
          decoration: BoxDecoration(
            color: c.card2,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        const SizedBox(height: 14),
        for (var i = 0; i < 3; i++) ...[
          Container(
            height: 76,
            decoration: BoxDecoration(
              color: c.card2,
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _StreamsUnavailable extends StatelessWidget {
  const _StreamsUnavailable({required this.appConfigFuture});

  final Future<ApiEnvelope<Map<String, dynamic>>>? appConfigFuture;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return FutureBuilder<ApiEnvelope<Map<String, dynamic>>>(
      future: appConfigFuture,
      builder: (context, snapshot) {
        final config = apiMap(snapshot.data?.data);
        final message = apiString(
          config['streamUnavailableMessage'],
          'Live stream will be available closer to match time.',
        );
        return PremiumCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: c.cyan.withValues(alpha: .12),
                    ),
                    alignment: Alignment.center,
                    child: Icon(Icons.schedule_rounded, color: c.cyan),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'Stream not live yet',
                      style: TextStyle(
                        color: c.text,
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                message,
                style: TextStyle(
                  color: c.muted,
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
