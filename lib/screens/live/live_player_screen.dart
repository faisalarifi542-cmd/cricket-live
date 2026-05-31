import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';

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
  VideoPlayerController? _videoController;
  Future<void>? _videoInitFuture;
  String? _playerError;
  List<HlsQuality> _hlsQualities = [];
  HlsQuality? _selectedQuality;
  bool _isMuted = false;

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
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _selectStream(StreamSource stream) async {
    setState(() {
      _selectedStream = stream;
      _playerError = null;
      _hlsQualities = [];
      _selectedQuality = null;
    });
    await _loadStream(stream);
  }

  Future<void> _loadStream(StreamSource stream, {HlsQuality? quality}) async {
    final oldController = _videoController;
    _videoController = null;
    _videoInitFuture = null;
    await oldController?.dispose();

    if (stream.url.isEmpty) {
      if (mounted) {
        setState(() => _playerError =
            'This stream URL is missing. Please try another server.');
      }
      return;
    }
    if (stream.isDash || stream.isExternal) {
      if (mounted) {
        setState(() {
          _playerError =
              'This stream type is not supported on this device. Please try another server.';
        });
      }
      return;
    }

    // Parse HLS qualities if this is an HLS stream and no quality selected yet
    if (stream.isHls && quality == null && _hlsQualities.isEmpty) {
      await _parseHlsQualities(stream.url);
    }

    // Determine the URL to play
    String playUrl = stream.url;
    if (quality != null && quality.url.isNotEmpty) {
      playUrl = quality.url;
    }

    final controller = VideoPlayerController.networkUrl(Uri.parse(playUrl));
    controller.addListener(() {
      if (mounted) setState(() {});
    });
    final initFuture = controller.initialize().then((_) {
      controller.play();
      controller.setLooping(false);
    });
    if (mounted) {
      setState(() {
        _videoController = controller;
        _videoInitFuture = initFuture;
        if (quality != null) {
          _selectedQuality = quality;
        }
      });
    }
    try {
      await initFuture;
      if (mounted) setState(() {});
    } catch (_) {
      await controller.dispose();
      if (mounted) {
        setState(() {
          _videoController = null;
          _videoInitFuture = null;
          _playerError =
              'Unable to play this stream. Please retry or choose another server.';
        });
      }
    }
  }

  Future<void> _parseHlsQualities(String masterUrl) async {
    try {
      final response = await http.get(Uri.parse(masterUrl)).timeout(
        const Duration(seconds: 5),
      );
      if (response.statusCode != 200) return;

      final content = response.body;
      final lines = content.split('\n');
      final qualities = <HlsQuality>[];
      
      String? currentResolution;
      int? currentBandwidth;
      
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        
        if (line.startsWith('#EXT-X-STREAM-INF:')) {
          // Parse resolution and bandwidth
          final resMatch = RegExp(r'RESOLUTION=(\d+)x(\d+)').firstMatch(line);
          final bandMatch = RegExp(r'BANDWIDTH=(\d+)').firstMatch(line);
          
          if (resMatch != null) {
            final width = int.parse(resMatch.group(1)!);
            final height = int.parse(resMatch.group(2)!);
            currentResolution = '${width}x$height';
            currentBandwidth = bandMatch != null ? int.parse(bandMatch.group(1)!) : null;
            
            // Get the variant URL from next line
            if (i + 1 < lines.length) {
              final variantLine = lines[i + 1].trim();
              if (variantLine.isNotEmpty && !variantLine.startsWith('#')) {
                final variantUrl = _resolveUrl(masterUrl, variantLine);
                final quality = _createQualityFromResolution(
                  currentResolution,
                  variantUrl,
                  currentBandwidth,
                );
                if (quality != null) {
                  qualities.add(quality);
                }
              }
            }
          }
        }
      }

      if (qualities.isNotEmpty) {
        // Sort by quality rank
        qualities.sort((a, b) => a.rank.compareTo(b.rank));
        
        // Add AUTO option at the beginning
        qualities.insert(
          0,
          HlsQuality(
            label: 'Auto',
            code: 'AUTO',
            resolution: 'Adaptive',
            url: masterUrl,
            rank: 0,
          ),
        );

        if (mounted) {
          setState(() {
            _hlsQualities = qualities;
            _selectedQuality = qualities.first; // Auto by default
          });
        }
      }
    } catch (e) {
      // Silently fail - we'll use fallback quality buttons
      debugPrint('HLS parsing failed: $e');
    }
  }

  HlsQuality? _createQualityFromResolution(
    String resolution,
    String url,
    int? bandwidth,
  ) {
    final parts = resolution.split('x');
    if (parts.length != 2) return null;
    
    final height = int.tryParse(parts[1]);
    if (height == null) return null;

    if (height >= 1080) {
      return HlsQuality(
        label: 'Full HD',
        code: 'FHD',
        resolution: '1080p',
        url: url,
        rank: 1,
        bandwidth: bandwidth,
      );
    } else if (height >= 720) {
      return HlsQuality(
        label: 'HD',
        code: 'HD',
        resolution: '720p',
        url: url,
        rank: 2,
        bandwidth: bandwidth,
      );
    } else if (height >= 480) {
      return HlsQuality(
        label: 'SD',
        code: 'SD',
        resolution: '480p',
        url: url,
        rank: 3,
        bandwidth: bandwidth,
      );
    } else if (height >= 240) {
      return HlsQuality(
        label: 'Low',
        code: 'LOW',
        resolution: '240p',
        url: url,
        rank: 4,
        bandwidth: bandwidth,
      );
    } else {
      return HlsQuality(
        label: 'Low',
        code: 'LOW',
        resolution: '${height}p',
        url: url,
        rank: 5,
        bandwidth: bandwidth,
      );
    }
  }

  String _resolveUrl(String baseUrl, String relativePath) {
    if (relativePath.startsWith('http://') || relativePath.startsWith('https://')) {
      return relativePath;
    }
    
    final baseUri = Uri.parse(baseUrl);
    final basePath = baseUri.path.substring(0, baseUri.path.lastIndexOf('/') + 1);
    final resolvedPath = basePath + relativePath;
    
    return Uri(
      scheme: baseUri.scheme,
      host: baseUri.host,
      port: baseUri.port,
      path: resolvedPath,
    ).toString();
  }

  void _openSettings() {
    if (_selectedStream == null) return;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _SettingsBottomSheet(
        selectedStream: _selectedStream!,
        hlsQualities: _hlsQualities,
        selectedQuality: _selectedQuality,
        onQualitySelected: (quality) {
          Navigator.pop(context);
          if (_selectedStream != null) {
            _loadStream(_selectedStream!, quality: quality);
          }
        },
      ),
    );
  }

  void _openFullscreen() {
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _FullscreenVideoPage(controller: controller),
      ),
    );
  }

  void _toggleMute() {
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) return;
    setState(() {
      _isMuted = !_isMuted;
      controller.setVolume(_isMuted ? 0.0 : 1.0);
    });
  }

  void _showCommentNotAvailable() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Live chat is coming soon'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showStatsNotAvailable() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Stats will be available here soon'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _shareStream() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Share match ${widget.matchId}'),
        behavior: SnackBarBehavior.floating,
      ),
    );
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
                _PlayerSurface(
                  stream: _selectedStream,
                  controller: _videoController,
                  initFuture: _videoInitFuture,
                  error: _playerError,
                  selectedQuality: _selectedQuality,
                  isMuted: _isMuted,
                  onRetry: _selectedStream == null
                      ? null
                      : () => _loadStream(_selectedStream!),
                  onFullscreen: _openFullscreen,
                  onSettings: _openSettings,
                  onToggleMute: _toggleMute,
                  onComment: _showCommentNotAvailable,
                  onStats: _showStatsNotAvailable,
                  onShare: _shareStream,
                ),
                const SizedBox(height: 24),
                _StreamsSection(
                  matchId: widget.matchId,
                  streamsFuture: _streamsFuture,
                  appConfigFuture: _appConfigFuture,
                  selectedId: _selectedStream?.id,
                  onSelect: _selectStream,
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

  void _showCastNotAvailable(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Cast support is coming soon'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: context.cric.card,
      ),
    );
  }

  void _shareMatch(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Share match $matchId'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: context.cric.card,
      ),
    );
  }

  void _showMoreOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _MoreOptionsSheet(matchId: matchId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Row(
      children: [
        _HeaderActionButton(
          icon: Icons.arrow_back_rounded,
          onTap: () => Navigator.pop(context),
        ),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: c.cyan,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: c.cyan.withValues(alpha: .7),
                      blurRadius: 12,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Live Stream',
                style: TextStyle(
                  color: c.text,
                  fontWeight: FontWeight.w900,
                  fontSize: context.sp(22),
                ),
              ),
            ],
          ),
        ),
        _HeaderActionButton(
          icon: Icons.cast_rounded,
          onTap: () => _showCastNotAvailable(context),
        ),
        const SizedBox(width: 8),
        _HeaderActionButton(
          icon: Icons.share_rounded,
          onTap: () => _shareMatch(context),
        ),
        const SizedBox(width: 8),
        _HeaderActionButton(
          icon: Icons.more_vert_rounded,
          onTap: () => _showMoreOptions(context),
        ),
      ],
    );
  }
}

class _HeaderActionButton extends StatelessWidget {
  const _HeaderActionButton({required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: c.card.withValues(alpha: .7),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.border.withValues(alpha: .75)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .22),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Icon(icon, color: c.text, size: 24),
      ),
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
            final loading =
                detailSnapshot.connectionState == ConnectionState.waiting &&
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

  _ScoreLine _formatScore(dynamic team) {
    final t = apiMap(team);
    final innings = apiList(t['innings']);
    if (innings.isEmpty) return const _ScoreLine();
    final first = apiMap(innings.first);
    final runs = apiInt(first['runs']);
    final wickets = apiInt(first['wickets']);
    final overs = apiString(first['overs']);
    if (runs == null) return const _ScoreLine();
    final scoreLine = wickets == null ? '$runs' : '$runs/$wickets';
    return _ScoreLine(score: scoreLine, overs: overs);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final narrow = context.w < 390;
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
    final matchDesc = _firstNonEmpty(
      [detail['match_desc']?.toString(), detail['matchDesc']?.toString()],
      '',
    );
    final status = apiString(detail['status']).toLowerCase();
    final isLive = status == 'live' || status == 'inprogress';
    final isCompleted = status == 'completed' || status == 'finished';
    final badge = isLive
        ? 'LIVE'
        : isCompleted
            ? 'RESULT'
            : 'UPCOMING';
    final badgeColor = isLive
        ? c.live
        : isCompleted
            ? c.success
            : c.cyan;
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
    final t1Full = apiString(team1['name'], t1Name);
    final t2Full = apiString(team2['name'], t2Name);
    final t1Score = _formatScore(team1);
    final t2Score = _formatScore(team2);
    final statusText = _firstNonEmpty(
      [
        detail['status_text']?.toString(),
        liveLine['statusText']?.toString(),
        liveLine['status']?.toString(),
      ],
      'Match details will update shortly.',
    );
    final start = apiDate(detail['start_time'] ?? detail['startTime']);
    final contextText = start != null && !isLive && !isCompleted
        ? 'Match starts at ${_formatStart(start)}'
        : statusText;
    final titleParts = <String>[
      series.toUpperCase(),
      if (matchDesc.isNotEmpty) matchDesc,
    ];

    return Container(
      padding: EdgeInsets.all(narrow ? 16 : 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xff071528),
            c.card.withValues(alpha: .98),
            const Color(0xff0b2b4a),
          ],
        ),
        border: Border.all(color: c.cyan.withValues(alpha: .28)),
        boxShadow: [
          BoxShadow(
            color: c.cyan.withValues(alpha: .12),
            blurRadius: 28,
            spreadRadius: -4,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: .34),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                gradient: RadialGradient(
                  center: Alignment.topCenter,
                  radius: 1.1,
                  colors: [c.cyan.withValues(alpha: .14), Colors.transparent],
                ),
              ),
            ),
          ),
          Column(
            children: [
              Row(
                children: [
                  _LiveBadge(label: badge, color: badgeColor),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      titleParts.join('  -  '),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.cyan,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                        letterSpacing: .35,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (isLive)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.visibility_rounded,
                            color: c.text.withValues(alpha: .86), size: 17),
                        const SizedBox(width: 4),
                        Text(
                          'Live',
                          style: TextStyle(
                            color: c.text.withValues(alpha: .9),
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    )
                  else
                    const SizedBox(width: 42),
                ],
              ),
              SizedBox(height: narrow ? 18 : 24),
              Row(
                children: [
                  Expanded(
                    child: _TeamColumn(
                      name: t1Name,
                      fullName: t1Full,
                      score: t1Score,
                      logoUrl: resolveCricbuzzImageUrl(team1),
                      isStriker:
                          apiString(liveLine['battingTeam']?.toString()) ==
                              t1Name,
                    ),
                  ),
                  _VsMedallion(narrow: narrow),
                  Expanded(
                    child: _TeamColumn(
                      name: t2Name,
                      fullName: t2Full,
                      score: t2Score,
                      logoUrl: resolveCricbuzzImageUrl(team2),
                      isStriker:
                          apiString(liveLine['battingTeam']?.toString()) ==
                              t2Name,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                contextText,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: c.cyan,
                  fontWeight: FontWeight.w900,
                  fontSize: narrow ? 13 : 15,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _formatStart(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final utc = date.toUtc();
    final hour = utc.hour.toString().padLeft(2, '0');
    final minute = utc.minute.toString().padLeft(2, '0');
    return '${utc.day} ${months[utc.month - 1]}, $hour:$minute GMT';
  }
}

class _ScoreLine {
  const _ScoreLine({this.score, this.overs});

  final String? score;
  final String? overs;
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: .32),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 12,
          letterSpacing: .4,
        ),
      ),
    );
  }
}

class _VsMedallion extends StatelessWidget {
  const _VsMedallion({required this.narrow});

  final bool narrow;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return SizedBox(
      width: narrow ? 58 : 76,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 1,
            height: 96,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  c.cyan.withValues(alpha: .55),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          Container(
            width: narrow ? 50 : 58,
            height: narrow ? 50 : 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: c.primaryGradient,
              boxShadow: [
                BoxShadow(
                  color: c.cyan.withValues(alpha: .35),
                  blurRadius: 20,
                  spreadRadius: 1,
                ),
              ],
            ),
            alignment: Alignment.center,
            child: const Text(
              'VS',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 17,
              ),
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
    required this.fullName,
    required this.score,
    required this.logoUrl,
    required this.isStriker,
  });

  final String name;
  final String fullName;
  final _ScoreLine score;
  final String? logoUrl;
  final bool isStriker;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final hasScore = apiString(score.score).isNotEmpty;
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xff102341),
            border: Border.all(
              color: isStriker ? c.cyan : c.border.withValues(alpha: .6),
              width: 2.4,
            ),
            boxShadow: [
              BoxShadow(
                color: isStriker
                    ? c.cyan.withValues(alpha: .24)
                    : Colors.black.withValues(alpha: .14),
                blurRadius: 20,
                spreadRadius: -2,
              ),
            ],
          ),
          alignment: Alignment.center,
          clipBehavior: Clip.antiAlias,
          child: logoUrl != null && logoUrl!.isNotEmpty
              ? Image.network(
                  logoUrl!,
                  fit: BoxFit.cover,
                  webHtmlElementStrategy: WebHtmlElementStrategy.prefer,
                  errorBuilder: (_, __, ___) => _TeamInitial(name: name),
                )
              : _TeamInitial(name: name),
        ),
        const SizedBox(height: 10),
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
        Text(
          fullName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: c.muted,
            fontWeight: FontWeight.w700,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 4),
        if (hasScore)
          Text(
            apiString(score.score),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isStriker ? c.cyan : Colors.white.withValues(alpha: .92),
              fontWeight: FontWeight.w900,
              fontSize: 22,
            ),
          )
        else
          Container(
            margin: const EdgeInsets.only(top: 3),
            width: 16,
            height: 4,
            decoration: BoxDecoration(
              color: c.border,
              borderRadius: BorderRadius.circular(99),
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
    final safeName = apiString(name, 'TBD').trim();
    final initial =
        safeName.isEmpty ? 'T' : safeName.substring(0, 1).toUpperCase();
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            c.cyan.withValues(alpha: .28),
            const Color(0xff102341),
          ],
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 24,
        ),
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
  const _PlayerSurface({
    required this.stream,
    required this.controller,
    required this.initFuture,
    required this.error,
    required this.selectedQuality,
    required this.isMuted,
    required this.onRetry,
    required this.onFullscreen,
    required this.onSettings,
    required this.onToggleMute,
    required this.onComment,
    required this.onStats,
    required this.onShare,
  });

  final StreamSource? stream;
  final VideoPlayerController? controller;
  final Future<void>? initFuture;
  final String? error;
  final HlsQuality? selectedQuality;
  final bool isMuted;
  final VoidCallback? onRetry;
  final VoidCallback onFullscreen;
  final VoidCallback onSettings;
  final VoidCallback onToggleMute;
  final VoidCallback onComment;
  final VoidCallback onStats;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final hasStream = stream != null && stream!.url.isNotEmpty;
    final initialized = controller?.value.isInitialized == true;
    final playing = controller?.value.isPlaying == true;
    return PremiumCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (initialized)
                VideoPlayer(controller!)
              else
                Image.asset(
                  'assets/images/stadium_live.png',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(color: Colors.black),
                ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: initialized ? .08 : .25),
                      Colors.black.withValues(alpha: initialized ? .25 : .72),
                    ],
                  ),
                ),
              ),
              if (initFuture != null && !initialized && error == null)
                FutureBuilder<void>(
                  future: initFuture,
                  builder: (context, snapshot) => Center(
                    child: snapshot.hasError
                        ? const SizedBox.shrink()
                        : SizedBox(
                            width: 46,
                            height: 46,
                            child: CircularProgressIndicator(
                              color: c.cyan,
                              strokeWidth: 3,
                            ),
                          ),
                  ),
                ),
              if (!initialized && error == null)
                Center(
                  child: Container(
                    width: 82,
                    height: 82,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: hasStream ? c.primaryGradient : null,
                      color: hasStream ? null : c.card2,
                      boxShadow: hasStream
                          ? [
                              BoxShadow(
                                color: c.cyan.withValues(alpha: .42),
                                blurRadius: 26,
                                spreadRadius: 4,
                              )
                            ]
                          : null,
                    ),
                    child: Icon(
                      hasStream
                          ? Icons.play_arrow_rounded
                          : Icons.live_tv_rounded,
                      color:
                          Colors.white.withValues(alpha: hasStream ? 1 : .65),
                      size: 50,
                    ),
                  ),
                ),
              if (error != null)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline_rounded,
                            color: c.warning, size: 34),
                        const SizedBox(height: 10),
                        Text(
                          error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: c.text,
                              fontWeight: FontWeight.w800,
                              height: 1.35),
                        ),
                        if (onRetry != null) ...[
                          const SizedBox(height: 14),
                          GradientButton(
                            label: 'Retry',
                            icon: Icons.refresh_rounded,
                            onTap: onRetry,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              Positioned(
                left: 14,
                top: 14,
                child: _PlayerPill(
                  label: playing ? 'LIVE' : 'STANDBY',
                  color: playing ? c.live : c.card2,
                  icon: Icons.circle,
                ),
              ),
              if (stream != null)
                Positioned(
                  right: 14,
                  top: 14,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _PlayerPill(
                        label: selectedQuality?.code ?? stream!.qualityLabel,
                        color: Colors.black.withValues(alpha: .55),
                        textColor: c.cyan,
                        icon: Icons.hd_rounded,
                      ),
                      const SizedBox(width: 8),
                      _PlayerMiniIcon(
                        icon: Icons.chat_bubble_outline_rounded,
                        onTap: onComment,
                      ),
                      const SizedBox(width: 8),
                      _PlayerMiniIcon(
                        icon: Icons.bar_chart_rounded,
                        onTap: onStats,
                      ),
                      const SizedBox(width: 8),
                      _PlayerMiniIcon(
                        icon: Icons.share_rounded,
                        onTap: onShare,
                      ),
                    ],
                  ),
                ),
              if (initialized && !playing)
                Positioned.fill(
                  child: Center(
                    child: GestureDetector(
                      onTap: controller!.play,
                      child: Container(
                        width: 92,
                        height: 92,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: c.primaryGradient,
                          boxShadow: [
                            BoxShadow(
                              color: c.cyan.withValues(alpha: .42),
                              blurRadius: 30,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 60,
                        ),
                      ),
                    ),
                  ),
                ),
              if (initialized)
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: .48),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: .08),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(99),
                          child: VideoProgressIndicator(
                            controller!,
                            allowScrubbing: true,
                            colors: VideoProgressColors(
                              playedColor: c.cyan,
                              bufferedColor: Colors.white24,
                              backgroundColor:
                                  Colors.white.withValues(alpha: .12),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _PlayerMiniIcon(
                              icon: playing
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              onTap: () {
                                playing
                                    ? controller!.pause()
                                    : controller!.play();
                              },
                            ),
                            const SizedBox(width: 8),
                            _PlayerMiniIcon(
                              icon: Icons.replay_10_rounded,
                              onTap: () {
                                if (controller!.value.duration == Duration.zero) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Seek is not available on this live stream'),
                                      behavior: SnackBarBehavior.floating,
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                  return;
                                }
                                final target = controller!.value.position -
                                    const Duration(seconds: 10);
                                controller!.seekTo(
                                  target.isNegative ? Duration.zero : target,
                                );
                              },
                            ),
                            const SizedBox(width: 8),
                            _PlayerMiniIcon(
                              icon: Icons.forward_10_rounded,
                              onTap: () {
                                if (controller!.value.duration == Duration.zero) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Seek is not available on this live stream'),
                                      behavior: SnackBarBehavior.floating,
                                      duration: Duration(seconds: 2),
                                    ),
                                  );
                                  return;
                                }
                                final target = controller!.value.position +
                                    const Duration(seconds: 10);
                                final duration = controller!.value.duration;
                                controller!.seekTo(
                                  target > duration ? duration : target,
                                );
                              },
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _timeLabel(controller!.value.position,
                                    controller!.value.duration),
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: c.text,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _PlayerMiniIcon(
                              icon: isMuted
                                  ? Icons.volume_off_rounded
                                  : Icons.volume_up_rounded,
                              onTap: onToggleMute,
                            ),
                            const SizedBox(width: 8),
                            _PlayerMiniIcon(
                              icon: Icons.settings_rounded,
                              onTap: onSettings,
                            ),
                            const SizedBox(width: 8),
                            _PlayerMiniIcon(
                              icon: Icons.fullscreen_rounded,
                              onTap: onFullscreen,
                            ),
                          ],
                        ),
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
}

class _PlayerPill extends StatelessWidget {
  const _PlayerPill({
    required this.label,
    required this.color,
    required this.icon,
    this.textColor = Colors.white,
  });

  final String label;
  final Color color;
  final IconData icon;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: textColor, size: 10),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: textColor,
              fontWeight: FontWeight.w900,
              fontSize: 11,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayerMiniIcon extends StatelessWidget {
  const _PlayerMiniIcon({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: .08)),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}

String _timeLabel(Duration position, Duration duration) {
  String format(Duration value) {
    final minutes = value.inMinutes.toString().padLeft(2, '0');
    final seconds = (value.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  if (duration == Duration.zero) {
    return format(position);
  }
  return '${format(position)} / ${format(duration)}';
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
                    color: c.text, fontWeight: FontWeight.w800, height: 1.35),
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
        streams.sort((a, b) {
          final priority = (a.priority ?? 100).compareTo(b.priority ?? 100);
          if (priority != 0) return priority;
          return a.qualityRank.compareTo(b.qualityRank);
        });
        if (streams.isEmpty) {
          return _StreamsUnavailable(appConfigFuture: appConfigFuture);
        }
        final selected = streams.where((s) => s.id == selectedId).firstOrNull ??
            streams.first;
        
        // Create all standard quality options
        final allQualities = <String, StreamSource>{
          'AUTO': StreamSource(
            id: 'auto',
            name: selected.name,
            url: selected.url,
            quality: 'AUTO',
            label: 'Auto',
            streamType: selected.streamType,
            isPremium: selected.isPremium,
            priority: 0,
          ),
          'FHD': StreamSource(
            id: 'fhd',
            name: selected.name,
            url: selected.url,
            quality: 'FHD',
            label: 'Full HD',
            streamType: selected.streamType,
            isPremium: selected.isPremium,
            priority: 1,
          ),
          'HD': StreamSource(
            id: 'hd',
            name: selected.name,
            url: selected.url,
            quality: 'HD',
            label: 'HD',
            streamType: selected.streamType,
            isPremium: selected.isPremium,
            priority: 2,
          ),
          'SD': StreamSource(
            id: 'sd',
            name: selected.name,
            url: selected.url,
            quality: 'SD',
            label: 'SD',
            streamType: selected.streamType,
            isPremium: selected.isPremium,
            priority: 3,
          ),
          'LOW': StreamSource(
            id: 'low',
            name: selected.name,
            url: selected.url,
            quality: 'LOW',
            label: 'Low',
            streamType: selected.streamType,
            isPremium: selected.isPremium,
            priority: 4,
          ),
        };
        
        // Override with actual streams if they exist
        for (final stream in streams) {
          final code = stream.qualityCode;
          if (allQualities.containsKey(code)) {
            allQualities[code] = stream;
          }
        }
        
        final selectedQuality = selected.qualityCode;
        final serverStreams =
            streams.where((s) => s.qualityCode == selectedQuality).toList();
        final hasMultipleServers = serverStreams.length > 1;
        
        // Auto-select highest priority stream once available
        if (selectedId == null) {
          WidgetsBinding.instance
              .addPostFrameCallback((_) => onSelect(selected));
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.wifi_tethering_rounded, color: c.cyan),
                const SizedBox(width: 8),
                Text(
                  'Stream Quality',
                  style: TextStyle(
                    color: c.text,
                    fontWeight: FontWeight.w900,
                    fontSize: 19,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 430;
                final cards = allQualities.values
                    .map((stream) => _QualityCard(
                          stream: stream,
                          selected: stream.qualityCode == selectedQuality,
                          onTap: () => onSelect(stream),
                        ))
                    .toList();
                if (narrow) {
                  return Column(
                    children: [
                      for (final card in cards) ...[
                        card,
                        const SizedBox(height: 10),
                      ],
                    ],
                  );
                }
                return Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  children: cards,
                );
              },
            ),
            if (hasMultipleServers) ...[
              const SizedBox(height: 22),
              Text(
                'Server',
                style: TextStyle(
                  color: c.text,
                  fontWeight: FontWeight.w900,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 14),
              for (final stream in serverStreams) ...[
                _StreamOption(
                  stream: stream,
                  selected: stream.id == selectedId,
                  onTap: () => onSelect(stream),
                ),
                const SizedBox(height: 12),
              ],
            ] else if (serverStreams.isNotEmpty) ...[
              const SizedBox(height: 16),
              _CompactServerCard(stream: serverStreams.first),
            ],
            const SizedBox(height: 10),
            const _StreamInfoRow(),
            const SizedBox(height: 16),
            const _SecureStreamCard(),
          ],
        );
      },
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class _QualityCard extends StatelessWidget {
  const _QualityCard({
    required this.stream,
    required this.selected,
    required this.onTap,
  });

  final StreamSource stream;
  final bool selected;
  final VoidCallback onTap;

  String get _headline => switch (stream.qualityCode) {
        'FHD' => 'Full HD',
        'HD' => 'HD',
        'SD' => 'SD',
        'LOW' => 'Low',
        _ => 'Auto',
      };

  String get _detail => switch (stream.qualityCode) {
        'FHD' => '1080p',
        'HD' => '720p',
        'SD' => '480p',
        'LOW' => '240p',
        _ => 'Adaptive',
      };

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      borderColor: selected ? c.cyan : null,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: selected ? c.cyan : c.card2,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: selected ? c.cyan : c.border),
            ),
            child: Text(
              stream.qualityCode,
              style: TextStyle(
                color: selected ? Colors.black : c.text,
                fontWeight: FontWeight.w900,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_headline,
                    style: TextStyle(
                        color: c.text,
                        fontWeight: FontWeight.w900,
                        fontSize: 16)),
                const SizedBox(height: 2),
                Text(_detail,
                    style: TextStyle(
                        color: selected ? c.cyan : c.muted,
                        fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          Icon(
            selected
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            color: selected ? c.cyan : c.muted,
          ),
        ],
      ),
    );
  }
}

class _StreamInfoRow extends StatelessWidget {
  const _StreamInfoRow();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 380) {
          return const Column(
            children: [
              _InfoPill(
                icon: Icons.speed_rounded,
                title: 'Low Latency',
                subtitle: 'Live at real speed',
              ),
              SizedBox(height: 8),
              _InfoPill(
                icon: Icons.hd_rounded,
                title: 'Adaptive Streaming',
                subtitle: 'Smooth on any network',
              ),
              SizedBox(height: 8),
              _InfoPill(
                icon: Icons.lock_rounded,
                title: 'Secure Stream',
                subtitle: 'Protected and encrypted',
              ),
            ],
          );
        }
        return const Row(
          children: [
            Expanded(
                child: _InfoPill(
              icon: Icons.speed_rounded,
              title: 'Low Latency',
              subtitle: 'Live at real speed',
            )),
            SizedBox(width: 8),
            Expanded(
                child: _InfoPill(
              icon: Icons.hd_rounded,
              title: 'Adaptive Streaming',
              subtitle: 'Smooth on any network',
            )),
            SizedBox(width: 8),
            Expanded(
                child: _InfoPill(
              icon: Icons.lock_rounded,
              title: 'Secure Stream',
              subtitle: 'Protected and encrypted',
            )),
          ],
        );
      },
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill(
      {required this.icon, required this.title, required this.subtitle});

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Icon(icon, color: c.cyan, size: 22),
          const SizedBox(height: 8),
          Text(title,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: c.text, fontWeight: FontWeight.w900, fontSize: 12)),
          const SizedBox(height: 3),
          Text(subtitle,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: c.muted, fontSize: 10)),
        ],
      ),
    );
  }
}

class _SecureStreamCard extends StatelessWidget {
  const _SecureStreamCard();

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      padding: const EdgeInsets.all(16),
      borderColor: c.cyan.withValues(alpha: .45),
      child: Row(
        children: [
          Icon(Icons.verified_user_rounded, color: c.cyan, size: 34),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Secure stream',
                    style: TextStyle(
                        color: c.text,
                        fontWeight: FontWeight.w900,
                        fontSize: 16)),
                const SizedBox(height: 4),
                Text('Your connection is protected while playback is active.',
                    style: TextStyle(color: c.muted, height: 1.35)),
              ],
            ),
          ),
          Icon(Icons.lock_rounded, color: c.cyan),
        ],
      ),
    );
  }
}

class _CompactServerCard extends StatelessWidget {
  const _CompactServerCard({required this.stream});

  final StreamSource stream;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: c.card2.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border.withValues(alpha: .3)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              gradient: c.primaryGradient,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.dns_rounded, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Server',
                  style: TextStyle(
                    color: c.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  stream.name,
                  style: TextStyle(
                    color: c.text,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.check_circle_rounded, color: c.cyan, size: 20),
        ],
      ),
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
                  subtitleParts.join(' - '),
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

class _FullscreenVideoPage extends StatelessWidget {
  const _FullscreenVideoPage({required this.controller});

  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: controller.value.aspectRatio == 0
                    ? 16 / 9
                    : controller.value.aspectRatio,
                child: VideoPlayer(controller),
              ),
            ),
            Positioned(
              left: 12,
              top: 12,
              child: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded,
                    color: Colors.white, size: 30),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Row(
                children: [
                  IconButton(
                    onPressed: () {
                      controller.value.isPlaying
                          ? controller.pause()
                          : controller.play();
                    },
                    icon: Icon(
                      controller.value.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 34,
                    ),
                  ),
                  Expanded(
                    child: VideoProgressIndicator(
                      controller,
                      allowScrubbing: true,
                      colors: const VideoProgressColors(
                        playedColor: Color(0xff22d3ee),
                        bufferedColor: Colors.white38,
                        backgroundColor: Colors.white24,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// More Options Bottom Sheet
class _MoreOptionsSheet extends StatelessWidget {
  const _MoreOptionsSheet({required this.matchId});

  final String matchId;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xff0a1929).withValues(alpha: .98),
            const Color(0xff0f2744).withValues(alpha: .98),
          ],
        ),
        border: Border.all(color: c.cyan.withValues(alpha: .35)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .6),
            blurRadius: 40,
            spreadRadius: 4,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: c.border.withValues(alpha: .4)),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: c.primaryGradient,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.more_horiz_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'More Options',
                    style: TextStyle(
                      color: c.text,
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                    ),
                  ),
                ),
                InkWell(
                  onTap: () => Navigator.pop(context),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: c.card2,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.close_rounded, color: c.text, size: 20),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _MoreOption(
                  icon: Icons.info_outline_rounded,
                  label: 'Stream Info',
                  onTap: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Stream info for match $matchId'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                _MoreOption(
                  icon: Icons.refresh_rounded,
                  label: 'Refresh Stream',
                  onTap: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Refreshing stream...'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                _MoreOption(
                  icon: Icons.report_outlined,
                  label: 'Report Issue',
                  onTap: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Report issue feature coming soon'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MoreOption extends StatelessWidget {
  const _MoreOption({
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: c.card2.withValues(alpha: .3),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.border.withValues(alpha: .25)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: c.cyan.withValues(alpha: .15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: c.cyan, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: c.text,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, color: c.muted, size: 18),
          ],
        ),
      ),
    );
  }
}

// HLS Quality Model
class HlsQuality {
  const HlsQuality({
    required this.label,
    required this.code,
    required this.resolution,
    required this.url,
    required this.rank,
    this.bandwidth,
  });

  final String label;
  final String code;
  final String resolution;
  final String url;
  final int rank;
  final int? bandwidth;
}

// Settings Bottom Sheet
class _SettingsBottomSheet extends StatelessWidget {
  const _SettingsBottomSheet({
    required this.selectedStream,
    required this.hlsQualities,
    required this.selectedQuality,
    required this.onQualitySelected,
  });

  final StreamSource selectedStream;
  final List<HlsQuality> hlsQualities;
  final HlsQuality? selectedQuality;
  final ValueChanged<HlsQuality> onQualitySelected;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    
    // Use HLS qualities if available, otherwise create fallback qualities
    final qualities = hlsQualities.isNotEmpty
        ? hlsQualities
        : _createFallbackQualities();

    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xff0a1929).withValues(alpha: .98),
            const Color(0xff0f2744).withValues(alpha: .98),
          ],
        ),
        border: Border.all(color: c.cyan.withValues(alpha: .35)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .6),
            blurRadius: 40,
            spreadRadius: 4,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: c.border.withValues(alpha: .4)),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: c.primaryGradient,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.settings_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    'Stream Settings',
                    style: TextStyle(
                      color: c.text,
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                    ),
                  ),
                ),
                InkWell(
                  onTap: () => Navigator.pop(context),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: c.card2,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.close_rounded, color: c.text, size: 20),
                  ),
                ),
              ],
            ),
          ),
          
          // Quality Options
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(20),
              children: [
                Row(
                  children: [
                    Icon(Icons.hd_rounded, color: c.cyan, size: 22),
                    const SizedBox(width: 8),
                    Text(
                      'Stream Quality',
                      style: TextStyle(
                        color: c.text,
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                for (final quality in qualities) ...[
                  _QualityOption(
                    quality: quality,
                    selected: selectedQuality?.code == quality.code,
                    onTap: () => onQualitySelected(quality),
                  ),
                  const SizedBox(height: 10),
                ],
                const SizedBox(height: 12),
                
                // Server Info
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: c.card2.withValues(alpha: .5),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: c.border.withValues(alpha: .3)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.dns_rounded, color: c.cyan, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Current Server',
                              style: TextStyle(
                                color: c.muted,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              selectedStream.name,
                              style: TextStyle(
                                color: c.text,
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.check_circle_rounded, color: c.cyan, size: 20),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<HlsQuality> _createFallbackQualities() {
    return [
      HlsQuality(
        label: 'Auto',
        code: 'AUTO',
        resolution: 'Adaptive',
        url: selectedStream.url,
        rank: 0,
      ),
      HlsQuality(
        label: 'Full HD',
        code: 'FHD',
        resolution: '1080p',
        url: selectedStream.url,
        rank: 1,
      ),
      HlsQuality(
        label: 'HD',
        code: 'HD',
        resolution: '720p',
        url: selectedStream.url,
        rank: 2,
      ),
      HlsQuality(
        label: 'SD',
        code: 'SD',
        resolution: '480p',
        url: selectedStream.url,
        rank: 3,
      ),
      HlsQuality(
        label: 'Low',
        code: 'LOW',
        resolution: '240p',
        url: selectedStream.url,
        rank: 4,
      ),
    ];
  }
}

class _QualityOption extends StatelessWidget {
  const _QualityOption({
    required this.quality,
    required this.selected,
    required this.onTap,
  });

  final HlsQuality quality;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: selected
              ? c.cyan.withValues(alpha: .12)
              : c.card2.withValues(alpha: .3),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? c.cyan : c.border.withValues(alpha: .25),
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: selected ? c.cyan : c.card2,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Text(
                quality.code,
                style: TextStyle(
                  color: selected ? Colors.black : c.text,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    quality.label,
                    style: TextStyle(
                      color: c.text,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    quality.resolution,
                    style: TextStyle(
                      color: selected ? c.cyan : c.muted,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              selected ? Icons.check_circle_rounded : Icons.circle_outlined,
              color: selected ? c.cyan : c.muted,
              size: 24,
            ),
          ],
        ),
      ),
    );
  }
}
