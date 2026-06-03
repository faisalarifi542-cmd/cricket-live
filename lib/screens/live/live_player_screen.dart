import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';

import 'package:cricpro_flutter/app_theme.dart';
import 'package:cricpro_flutter/api_models.dart';
import 'package:cricpro_flutter/components.dart';
import 'package:cricpro_flutter/models/ad_config.dart';
import 'package:cricpro_flutter/models/api_response.dart';
import 'package:cricpro_flutter/repositories/cricket_repository.dart';
import 'package:cricpro_flutter/services/ad_service.dart';
import 'package:cricpro_flutter/widgets/ads/banner_ad_widget.dart';
import 'package:cricpro_flutter/widgets/ads/rewarded_ad_manager.dart';

/// Fixed quality model. The player only ever exposes SD / HD / FHD.
class StreamQuality {
  const StreamQuality({
    required this.code,
    required this.label,
    required this.resolution,
    required this.url,
  });

  final String code; // SD | HD | FHD
  final String label; // SD | HD | FHD
  final String resolution; // 480p | 720p | 1080p
  final String url; // resolved playback url (falls back to the master url)

  bool get hasUrl => url.isNotEmpty;
}

/// Snapshot of the active playback shared with the fullscreen route so it can
/// follow controller swaps (e.g. quality changes) without holding a disposed
/// controller reference.
class _Playback {
  const _Playback({this.controller, required this.qualityCode});

  final VideoPlayerController? controller;
  final String qualityCode;
}

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

  VideoPlayerController? _videoController;
  Future<void>? _videoInitFuture;
  String? _playerError;
  bool _isMuted = false;
  bool _switchingQuality = false;

  StreamSource? _primaryStream;
  List<StreamQuality> _qualities = const [];
  StreamQuality? _selectedQuality;
  String? _currentUrl;
  String _matchTitle = 'Live Stream';

  final ValueNotifier<_Playback> _playback =
      ValueNotifier<_Playback>(const _Playback(qualityCode: 'HD'));
  final Set<String> _rewardUnlockedStreamIds = <String>{};

  bool get _hasMatchId => widget.matchId.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _appConfigFuture = _repository.appConfig();
    if (_hasMatchId) {
      _detailFuture = _repository.matchDetail(widget.matchId);
      _liveLineFuture = _repository.matchLiveLine(widget.matchId);
      _streamsFuture = _repository.matchStreams(widget.matchId);
      _detailFuture!.then(_onDetailLoaded).catchError((_) {});
      _streamsFuture!.then(_onStreamsLoaded).catchError((_) {});
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
    _playback.dispose();
    // Defensive restore so the app never gets stuck in landscape / immersive
    // after leaving the player screen.
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _publishPlayback() {
    _playback.value = _Playback(
      controller: _videoController,
      qualityCode: _selectedQuality?.code ?? 'HD',
    );
  }

  void _onDetailLoaded(ApiEnvelope<Map<String, dynamic>> env) {
    if (!mounted) return;
    final detail = apiMap(env.data);
    final team1 = apiMap(detail['team1']);
    final team2 = apiMap(detail['team2']);
    String teamName(Map<String, dynamic> team) => apiString(
          team['short_name'] ?? team['shortName'] ?? team['name'],
          '',
        );
    final t1 = teamName(team1);
    final t2 = teamName(team2);
    final title = (t1.isNotEmpty && t2.isNotEmpty) ? '$t1 vs $t2' : 'Live Stream';
    if (title != _matchTitle) {
      setState(() => _matchTitle = title);
    }
  }

  // ---------------------------------------------------------------------------
  // Stream loading + quality mapping
  // ---------------------------------------------------------------------------

  void _onStreamsLoaded(ApiEnvelope<Map<String, dynamic>> env) {
    if (!mounted) return;
    final data = apiMap(env.data);
    final streams = apiList(data['streams'])
        .map(StreamSource.fromJson)
        .where((s) => s.isPlayable && s.url.isNotEmpty)
        .toList();
    streams.sort((a, b) {
      final priority = (a.priority ?? 100).compareTo(b.priority ?? 100);
      if (priority != 0) return priority;
      return a.qualityRank.compareTo(b.qualityRank);
    });

    if (streams.isEmpty) {
      setState(() {
        _primaryStream = null;
        _qualities = const [];
        _selectedQuality = null;
      });
      _publishPlayback();
      return;
    }

    final primary = streams.first;
    final qualities = _buildQualities(streams, primary, const {});
    final keepCode = _selectedQuality?.code;
    StreamQuality pickDefault() => qualities.firstWhere(
          (q) => q.code == 'HD' && q.hasUrl,
          orElse: () => qualities.firstWhere(
            (q) => q.hasUrl,
            orElse: () => qualities.first,
          ),
        );
    final selected = keepCode == null
        ? pickDefault()
        : qualities.firstWhere(
            (q) => q.code == keepCode && q.hasUrl,
            orElse: pickDefault,
          );

    setState(() {
      _primaryStream = primary;
      _qualities = qualities;
      _selectedQuality = selected;
    });

    if (selected.url != _currentUrl) {
      _initialLoad(primary, selected);
    } else {
      _publishPlayback();
    }

    if (primary.isHls) {
      _refineQualitiesFromHls(primary, streams);
    }
  }

  Future<void> _initialLoad(StreamSource primary, StreamQuality quality) async {
    if (await _requiresRewardedUnlock(primary)) {
      final allowed = await _showRewardedUnlock(primary);
      if (!allowed) return;
    }
    await _loadUrl(quality.url);
  }

  /// Builds the fixed SD / HD / FHD list. For each quality we look for, in
  /// order: a backend stream tagged with that quality code, a parsed HLS
  /// variant, then finally the primary (master) url so playback never breaks
  /// even when the backend only exposes a single HLS url.
  List<StreamQuality> _buildQualities(
    List<StreamSource> streams,
    StreamSource primary,
    Map<String, String> hlsVariants,
  ) {
    String resolve(String code) {
      final tagged = streams.where(
        (s) => s.qualityCode == code && s.url.isNotEmpty,
      );
      if (tagged.isNotEmpty) return tagged.first.url;
      final variant = hlsVariants[code];
      if (variant != null && variant.isNotEmpty) return variant;
      return primary.url;
    }

    return [
      StreamQuality(
          code: 'SD', label: 'SD', resolution: '480p', url: resolve('SD')),
      StreamQuality(
          code: 'HD', label: 'HD', resolution: '720p', url: resolve('HD')),
      StreamQuality(
          code: 'FHD', label: 'FHD', resolution: '1080p', url: resolve('FHD')),
    ];
  }

  Future<void> _refineQualitiesFromHls(
    StreamSource primary,
    List<StreamSource> streams,
  ) async {
    final variants = await _parseHlsVariants(primary.url);
    if (!mounted || variants.isEmpty) return;
    final refined = _buildQualities(streams, primary, variants);
    setState(() {
      _qualities = refined;
      if (_selectedQuality != null) {
        _selectedQuality = refined.firstWhere(
          (q) => q.code == _selectedQuality!.code,
          orElse: () => _selectedQuality!,
        );
      }
    });
  }

  Future<Map<String, String>> _parseHlsVariants(String masterUrl) async {
    try {
      final response = await http
          .get(Uri.parse(masterUrl))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return const {};
      final lines = response.body.split('\n');
      final urls = <String, String>{};
      final heights = <String, int>{};
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        if (!line.startsWith('#EXT-X-STREAM-INF:')) continue;
        final resMatch = RegExp(r'RESOLUTION=(\d+)x(\d+)').firstMatch(line);
        if (resMatch == null) continue;
        final height = int.tryParse(resMatch.group(2)!) ?? 0;
        String? code;
        if (height >= 1080) {
          code = 'FHD';
        } else if (height >= 720) {
          code = 'HD';
        } else if (height >= 480) {
          code = 'SD';
        }
        if (code == null || i + 1 >= lines.length) continue;
        final variantLine = lines[i + 1].trim();
        if (variantLine.isEmpty || variantLine.startsWith('#')) continue;
        final abs = _resolveUrl(masterUrl, variantLine);
        if (!heights.containsKey(code) || height > heights[code]!) {
          heights[code] = height;
          urls[code] = abs;
        }
      }
      return urls;
    } catch (e) {
      debugPrint('HLS parsing failed: $e');
      return const {};
    }
  }

  String _resolveUrl(String baseUrl, String relativePath) {
    if (relativePath.startsWith('http://') ||
        relativePath.startsWith('https://')) {
      return relativePath;
    }
    final baseUri = Uri.parse(baseUrl);
    final basePath =
        baseUri.path.substring(0, baseUri.path.lastIndexOf('/') + 1);
    return Uri(
      scheme: baseUri.scheme,
      host: baseUri.host,
      port: baseUri.port,
      path: basePath + relativePath,
    ).toString();
  }

  Future<void> _loadUrl(String url) async {
    final oldController = _videoController;
    _videoController = null;
    _videoInitFuture = null;
    if (mounted) {
      setState(() {
        _switchingQuality = true;
        _playerError = null;
      });
    }
    _publishPlayback();
    await oldController?.dispose();

    if (url.isEmpty) {
      if (mounted) {
        setState(() {
          _switchingQuality = false;
          _playerError = 'This stream URL is missing. Please try again.';
        });
      }
      return;
    }

    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    controller.addListener(_onControllerUpdate);
    final initFuture = controller.initialize().then((_) {
      controller.setLooping(false);
      controller.setVolume(_isMuted ? 0.0 : 1.0);
      controller.play();
    });

    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() {
      _videoController = controller;
      _videoInitFuture = initFuture;
      _currentUrl = url;
    });
    _publishPlayback();

    try {
      await initFuture;
      if (mounted) setState(() => _switchingQuality = false);
      _publishPlayback();
    } catch (_) {
      await controller.dispose();
      if (mounted) {
        setState(() {
          _videoController = null;
          _videoInitFuture = null;
          _switchingQuality = false;
          _playerError =
              'Unable to play this stream. Please retry or refresh.';
        });
      }
      _publishPlayback();
    }
  }

  void _onControllerUpdate() {
    if (mounted) setState(() {});
  }

  // ---------------------------------------------------------------------------
  // Rewarded unlock (premium streams) – unchanged behaviour
  // ---------------------------------------------------------------------------

  Future<bool> _requiresRewardedUnlock(StreamSource stream) async {
    if (!stream.isPremium || !stream.requiresRewardAd) return false;
    if (_rewardUnlockedStreamIds.contains(_rewardKey(stream))) return false;
    return AdService.instance.config.rewardedRequiredForPremiumStreams ||
        AdService.instance.config.canShowRewarded;
  }

  String _rewardKey(StreamSource stream) => '${widget.matchId}:${stream.id}';

  Future<bool> _showRewardedUnlock(StreamSource stream) async {
    final c = context.cric;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: c.card,
        title: Text('Unlock premium stream', style: TextStyle(color: c.text)),
        content: Text(
          'Watch a rewarded ad to unlock this stream for the current match session.',
          style: TextStyle(color: c.muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Watch ad'),
          ),
        ],
      ),
    );
    if (accepted != true) return false;
    final earned = await RewardedAdManager.instance.showForUnlock();
    if (earned) {
      _rewardUnlockedStreamIds.add(_rewardKey(stream));
      return true;
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Rewarded ad was not completed. Please try again.'),
        ),
      );
    }
    return false;
  }

  // ---------------------------------------------------------------------------
  // Player controls
  // ---------------------------------------------------------------------------

  Future<void> _selectQuality(StreamQuality quality) async {
    if (_selectedQuality?.code == quality.code && _playerError == null) {
      setState(() => _selectedQuality = quality);
      _publishPlayback();
      return;
    }
    setState(() {
      _selectedQuality = quality;
      _playerError = null;
    });
    _publishPlayback();
    if (!quality.hasUrl) {
      setState(() =>
          _playerError = 'This quality is not available. Please try another.');
      return;
    }
    if (quality.url == _currentUrl &&
        _videoController?.value.isInitialized == true) {
      return; // same source – just update the UI selection.
    }
    await _loadUrl(quality.url);
  }

  void _toggleMute() {
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) return;
    setState(() {
      _isMuted = !_isMuted;
      controller.setVolume(_isMuted ? 0.0 : 1.0);
    });
  }

  void _retry() {
    final url = _selectedQuality?.url ?? _primaryStream?.url;
    if (url != null && url.isNotEmpty) {
      _loadUrl(url);
    }
  }

  void _openSettings() {
    if (_qualities.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => _QualitySheet(
        qualities: _qualities,
        selectedCode: _selectedQuality?.code,
        onSelected: (quality) {
          Navigator.pop(sheetContext);
          _selectQuality(quality);
        },
      ),
    );
  }

  Future<void> _openFullscreen() async {
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _FullscreenPlayerPage(
          playback: _playback,
          matchTitle: _matchTitle,
          onToggleMute: _toggleMute,
          onOpenSettings: _openSettings,
        ),
      ),
    );
    // Ensure portrait + system UI is restored on return.
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (mounted) setState(() {});
  }

  Future<void> _shareStream() async {
    final title = _matchTitle == 'Live Stream' ? 'Live cricket' : _matchTitle;
    final link = _currentUrl ?? _primaryStream?.url ?? '';
    final payload = link.isEmpty ? title : '$title\n$link';
    await Clipboard.setData(ClipboardData(text: payload));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Match link copied to clipboard'),
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
    _detailFuture!.then(_onDetailLoaded).catchError((_) {});
    _streamsFuture!.then(_onStreamsLoaded).catchError((_) {});
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
                14,
                context.horizontalPadding,
                context.detailBottomPadding,
              ),
              children: [
                _LivePlayerHeader(
                  onShare: _shareStream,
                  onRefresh: _refresh,
                ),
                const SizedBox(height: 16),
                _MatchInfoSection(
                  matchId: widget.matchId,
                  detailFuture: _detailFuture,
                  liveLineFuture: _liveLineFuture,
                ),
                const SizedBox(height: 16),
                _PlayerSurface(
                  controller: _videoController,
                  initFuture: _videoInitFuture,
                  error: _playerError,
                  switching: _switchingQuality,
                  hasStream: _primaryStream != null,
                  qualityCode: _selectedQuality?.code ?? 'HD',
                  matchTitle: _matchTitle,
                  onRetry: _retry,
                  onToggleMute: _toggleMute,
                  onSettings: _openSettings,
                  onFullscreen: _openFullscreen,
                ),
                const SizedBox(height: 22),
                _StreamQualitySection(
                  matchId: widget.matchId,
                  streamsFuture: _streamsFuture,
                  appConfigFuture: _appConfigFuture,
                  qualities: _qualities,
                  selectedCode: _selectedQuality?.code,
                  onSelect: _selectQuality,
                ),
                const SizedBox(height: 16),
                const BannerAdWidget(placement: AdPlacement.livePlayer),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Header
// =============================================================================

class _LivePlayerHeader extends StatelessWidget {
  const _LivePlayerHeader({required this.onShare, required this.onRefresh});

  final VoidCallback onShare;
  final Future<void> Function() onRefresh;

  void _showCastNotAvailable(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Casting is not available yet'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: context.cric.card,
      ),
    );
  }

  void _showMoreOptions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _MoreOptionsSheet(
        onRefresh: () {
          Navigator.pop(sheetContext);
          onRefresh();
        },
        onShare: () {
          Navigator.pop(sheetContext);
          onShare();
        },
      ),
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
                  color: c.live,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: c.live.withValues(alpha: .7),
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
                  fontSize: context.sp(20),
                ),
              ),
            ],
          ),
        ),
        // Cast is not implemented yet – shown as a disabled state so the UI
        // stays consistent without crashing.
        _HeaderActionButton(
          icon: Icons.cast_rounded,
          enabled: false,
          onTap: () => _showCastNotAvailable(context),
        ),
        const SizedBox(width: 8),
        _HeaderActionButton(
          icon: Icons.share_rounded,
          onTap: onShare,
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
  const _HeaderActionButton({
    required this.icon,
    this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final bool enabled;

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
          color: c.card.withValues(alpha: enabled ? .7 : .35),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: c.border.withValues(alpha: enabled ? .75 : .35),
          ),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: .22),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Icon(
          icon,
          color: enabled ? c.text : c.muted.withValues(alpha: .6),
          size: 22,
        ),
      ),
    );
  }
}

// =============================================================================
// Match info (compact) – preserved layout
// =============================================================================

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
      padding: EdgeInsets.all(narrow ? 14 : 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
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
                borderRadius: BorderRadius.circular(22),
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
                            color: c.text.withValues(alpha: .86), size: 16),
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
              SizedBox(height: narrow ? 12 : 16),
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
              const SizedBox(height: 12),
              Text(
                contextText,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: c.cyan,
                  fontWeight: FontWeight.w900,
                  fontSize: narrow ? 12 : 14,
                  height: 1.3,
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
      width: narrow ? 52 : 66,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 1,
            height: 80,
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
            width: narrow ? 44 : 50,
            height: narrow ? 44 : 50,
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
                fontSize: 16,
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
          width: 60,
          height: 60,
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
        const SizedBox(height: 8),
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 16,
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
              fontSize: 20,
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
          fontSize: 22,
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

// =============================================================================
// Player surface (portrait, 16:9)
// =============================================================================

class _PlayerSurface extends StatelessWidget {
  const _PlayerSurface({
    required this.controller,
    required this.initFuture,
    required this.error,
    required this.switching,
    required this.hasStream,
    required this.qualityCode,
    required this.matchTitle,
    required this.onRetry,
    required this.onToggleMute,
    required this.onSettings,
    required this.onFullscreen,
  });

  final VideoPlayerController? controller;
  final Future<void>? initFuture;
  final String? error;
  final bool switching;
  final bool hasStream;
  final String qualityCode;
  final String matchTitle;
  final VoidCallback onRetry;
  final VoidCallback onToggleMute;
  final VoidCallback onSettings;
  final VoidCallback onFullscreen;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final initialized = controller?.value.isInitialized == true;

    Widget content;
    if (error != null) {
      content = _PlayerMessage(
        icon: Icons.error_outline_rounded,
        color: c.warning,
        message: error!,
        onRetry: onRetry,
      );
    } else if (initialized && controller != null) {
      content = _VideoStage(
        controller: controller!,
        fullscreen: false,
        qualityCode: qualityCode,
        matchTitle: matchTitle,
        onToggleMute: onToggleMute,
        onSettings: onSettings,
        onFullscreen: onFullscreen,
        onExitFullscreen: () {},
      );
    } else {
      content = _PlayerLoading(
        hasStream: hasStream,
        showSpinner: switching || (initFuture != null && hasStream),
      );
    }

    return PremiumCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: ColoredBox(
            color: Colors.black,
            child: content,
          ),
        ),
      ),
    );
  }
}

class _PlayerLoading extends StatelessWidget {
  const _PlayerLoading({required this.hasStream, required this.showSpinner});

  final bool hasStream;
  final bool showSpinner;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Stack(
      fit: StackFit.expand,
      children: [
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
                Colors.black.withValues(alpha: .25),
                Colors.black.withValues(alpha: .72),
              ],
            ),
          ),
        ),
        Center(
          child: showSpinner
              ? SizedBox(
                  width: 46,
                  height: 46,
                  child: CircularProgressIndicator(
                    color: c.cyan,
                    strokeWidth: 3,
                  ),
                )
              : Container(
                  width: 78,
                  height: 78,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.card2,
                  ),
                  child: Icon(
                    Icons.live_tv_rounded,
                    color: Colors.white.withValues(alpha: .65),
                    size: 44,
                  ),
                ),
        ),
      ],
    );
  }
}

class _PlayerMessage extends StatelessWidget {
  const _PlayerMessage({
    required this.icon,
    required this.color,
    required this.message,
    required this.onRetry,
  });

  final IconData icon;
  final Color color;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 34),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: c.text,
                fontWeight: FontWeight.w800,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 14),
            GradientButton(
              label: 'Retry',
              icon: Icons.refresh_rounded,
              onTap: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}

/// Renders the video + auto-hiding overlay controls. Shared between the inline
/// (portrait) player and the fullscreen route.
class _VideoStage extends StatefulWidget {
  const _VideoStage({
    super.key,
    required this.controller,
    required this.fullscreen,
    required this.qualityCode,
    required this.matchTitle,
    required this.onToggleMute,
    required this.onSettings,
    required this.onFullscreen,
    required this.onExitFullscreen,
  });

  final VideoPlayerController controller;
  final bool fullscreen;
  final String qualityCode;
  final String matchTitle;
  final VoidCallback onToggleMute;
  final VoidCallback onSettings;
  final VoidCallback onFullscreen;
  final VoidCallback onExitFullscreen;

  @override
  State<_VideoStage> createState() => _VideoStageState();
}

class _VideoStageState extends State<_VideoStage> {
  bool _showControls = true;
  bool _lastPlaying = false;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onUpdate);
    _lastPlaying = widget.controller.value.isPlaying;
    WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleHide());
  }

  @override
  void didUpdateWidget(_VideoStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onUpdate);
      widget.controller.addListener(_onUpdate);
      _lastPlaying = widget.controller.value.isPlaying;
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    widget.controller.removeListener(_onUpdate);
    super.dispose();
  }

  void _onUpdate() {
    if (!mounted) return;
    final playing = widget.controller.value.isPlaying;
    if (playing != _lastPlaying) {
      _lastPlaying = playing;
      if (playing) {
        _scheduleHide();
      } else {
        _hideTimer?.cancel();
        if (!_showControls) {
          setState(() => _showControls = true);
          return;
        }
      }
    }
    setState(() {});
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (widget.controller.value.isPlaying) {
      _hideTimer = Timer(const Duration(seconds: 3), () {
        if (mounted && widget.controller.value.isPlaying) {
          setState(() => _showControls = false);
        }
      });
    }
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _scheduleHide();
  }

  void _bump(VoidCallback action) {
    action();
    setState(() => _showControls = true);
    _scheduleHide();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final aspect = controller.value.aspectRatio > 0
        ? controller.value.aspectRatio
        : 16 / 9;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleControls,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Colors.black),
          Center(
            child: AspectRatio(
              aspectRatio: aspect,
              child: VideoPlayer(controller),
            ),
          ),
          _ControlsOverlay(
            controller: controller,
            visible: _showControls,
            fullscreen: widget.fullscreen,
            qualityCode: widget.qualityCode,
            matchTitle: widget.matchTitle,
            onTogglePlay: () => _bump(() {
              controller.value.isPlaying
                  ? controller.pause()
                  : controller.play();
            }),
            onToggleMute: () => _bump(widget.onToggleMute),
            onSettings: () => _bump(widget.onSettings),
            onFullscreen: () => _bump(widget.onFullscreen),
            onExitFullscreen: () => _bump(widget.onExitFullscreen),
          ),
        ],
      ),
    );
  }
}

class _ControlsOverlay extends StatelessWidget {
  const _ControlsOverlay({
    required this.controller,
    required this.visible,
    required this.fullscreen,
    required this.qualityCode,
    required this.matchTitle,
    required this.onTogglePlay,
    required this.onToggleMute,
    required this.onSettings,
    required this.onFullscreen,
    required this.onExitFullscreen,
  });

  final VideoPlayerController controller;
  final bool visible;
  final bool fullscreen;
  final String qualityCode;
  final String matchTitle;
  final VoidCallback onTogglePlay;
  final VoidCallback onToggleMute;
  final VoidCallback onSettings;
  final VoidCallback onFullscreen;
  final VoidCallback onExitFullscreen;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final value = controller.value;
    final playing = value.isPlaying;
    final muted = value.volume == 0;
    final pad = fullscreen ? 18.0 : 12.0;

    return AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: const Duration(milliseconds: 200),
      child: IgnorePointer(
        ignoring: !visible,
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: .45),
                    Colors.transparent,
                    Colors.black.withValues(alpha: .55),
                  ],
                  stops: const [0, .45, 1],
                ),
              ),
            ),
            // Top row
            Positioned(
              left: pad,
              right: pad,
              top: pad,
              child: Row(
                children: [
                  if (fullscreen) ...[
                    _PlayerMiniIcon(
                      icon: Icons.arrow_back_rounded,
                      onTap: onExitFullscreen,
                    ),
                    const SizedBox(width: 10),
                  ],
                  const _LivePill(),
                  if (fullscreen) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        matchTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ] else
                    const Spacer(),
                  const SizedBox(width: 8),
                  _PlayerPill(
                    label: qualityCode,
                    color: Colors.black.withValues(alpha: .55),
                    textColor: c.cyan,
                    icon: Icons.hd_rounded,
                  ),
                ],
              ),
            ),
            // Center play / pause
            Center(
              child: GestureDetector(
                onTap: onTogglePlay,
                child: Container(
                  width: fullscreen ? 84 : 72,
                  height: fullscreen ? 84 : 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: c.primaryGradient,
                    boxShadow: [
                      BoxShadow(
                        color: c.cyan.withValues(alpha: .42),
                        blurRadius: 26,
                        spreadRadius: 3,
                      ),
                    ],
                  ),
                  child: Icon(
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: fullscreen ? 50 : 42,
                  ),
                ),
              ),
            ),
            // Bottom row
            Positioned(
              left: pad,
              right: pad,
              bottom: pad,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: VideoProgressIndicator(
                      controller,
                      allowScrubbing: true,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      colors: VideoProgressColors(
                        playedColor: c.cyan,
                        bufferedColor: Colors.white24,
                        backgroundColor: Colors.white.withValues(alpha: .12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        _timeLabel(value.position, value.duration),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                      const Spacer(),
                      _PlayerMiniIcon(
                        icon: muted
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
                        icon: fullscreen
                            ? Icons.fullscreen_exit_rounded
                            : Icons.fullscreen_rounded,
                        onTap: fullscreen ? onExitFullscreen : onFullscreen,
                      ),
                    ],
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

class _LivePill extends StatelessWidget {
  const _LivePill();

  @override
  Widget build(BuildContext context) {
    return _PlayerPill(
      label: 'LIVE',
      color: context.cric.live,
      icon: Icons.circle,
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
          color: Colors.black.withValues(alpha: .4),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: .12)),
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

// =============================================================================
// Fullscreen route
// =============================================================================

class _FullscreenPlayerPage extends StatefulWidget {
  const _FullscreenPlayerPage({
    required this.playback,
    required this.matchTitle,
    required this.onToggleMute,
    required this.onOpenSettings,
  });

  final ValueListenable<_Playback> playback;
  final String matchTitle;
  final VoidCallback onToggleMute;
  final VoidCallback onOpenSettings;

  @override
  State<_FullscreenPlayerPage> createState() => _FullscreenPlayerPageState();
}

class _FullscreenPlayerPageState extends State<_FullscreenPlayerPage> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: ValueListenableBuilder<_Playback>(
        valueListenable: widget.playback,
        builder: (context, playback, _) {
          final controller = playback.controller;
          if (controller == null || !controller.value.isInitialized) {
            return const Center(
              child: SizedBox(
                width: 46,
                height: 46,
                child: CircularProgressIndicator(
                  color: Color(0xff22d3ee),
                  strokeWidth: 3,
                ),
              ),
            );
          }
          return _VideoStage(
            key: ValueKey<VideoPlayerController>(controller),
            controller: controller,
            fullscreen: true,
            qualityCode: playback.qualityCode,
            matchTitle: widget.matchTitle,
            onToggleMute: widget.onToggleMute,
            onSettings: widget.onOpenSettings,
            onFullscreen: () {},
            onExitFullscreen: () => Navigator.of(context).maybePop(),
          );
        },
      ),
    );
  }
}

// =============================================================================
// Quality selector (SD / HD / FHD only)
// =============================================================================

class _StreamQualitySection extends StatelessWidget {
  const _StreamQualitySection({
    required this.matchId,
    required this.streamsFuture,
    required this.appConfigFuture,
    required this.qualities,
    required this.selectedCode,
    required this.onSelect,
  });

  final String matchId;
  final Future<ApiEnvelope<Map<String, dynamic>>>? streamsFuture;
  final Future<ApiEnvelope<Map<String, dynamic>>>? appConfigFuture;
  final List<StreamQuality> qualities;
  final String? selectedCode;
  final ValueChanged<StreamQuality> onSelect;

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
        final hasPlayable = apiList(data['streams'])
            .map(StreamSource.fromJson)
            .any((s) => s.isPlayable && s.url.isNotEmpty);
        if (!hasPlayable) {
          return _StreamsUnavailable(appConfigFuture: appConfigFuture);
        }
        if (qualities.isEmpty) {
          return const _StreamsSkeleton();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.hd_rounded, color: c.cyan),
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
            for (final quality in qualities) ...[
              _QualityCard(
                quality: quality,
                selected: quality.code == selectedCode,
                onTap: () => onSelect(quality),
              ),
              const SizedBox(height: 10),
            ],
          ],
        );
      },
    );
  }
}

class _QualityCard extends StatelessWidget {
  const _QualityCard({
    required this.quality,
    required this.selected,
    required this.onTap,
  });

  final StreamQuality quality;
  final bool selected;
  final VoidCallback onTap;

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
            width: 50,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? c.cyan : c.card2,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: selected ? c.cyan : c.border),
            ),
            child: Text(
              quality.code,
              style: TextStyle(
                color: selected ? Colors.black : c.text,
                fontWeight: FontWeight.w900,
                fontSize: 13,
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
            selected
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            color: selected ? c.cyan : c.muted,
            size: 24,
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
        final config = AppConfig.fromJson(snapshot.data?.data);
        final message = config.streamUnavailableMessage;
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

// =============================================================================
// Bottom sheets
// =============================================================================

class _MoreOptionsSheet extends StatelessWidget {
  const _MoreOptionsSheet({required this.onRefresh, required this.onShare});

  final VoidCallback onRefresh;
  final VoidCallback onShare;

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
          _SheetHeader(
            icon: Icons.more_horiz_rounded,
            title: 'More Options',
            onClose: () => Navigator.pop(context),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _MoreOption(
                  icon: Icons.refresh_rounded,
                  label: 'Refresh Stream',
                  onTap: onRefresh,
                ),
                const SizedBox(height: 12),
                _MoreOption(
                  icon: Icons.ios_share_rounded,
                  label: 'Share Match',
                  onTap: onShare,
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

class _QualitySheet extends StatelessWidget {
  const _QualitySheet({
    required this.qualities,
    required this.selectedCode,
    required this.onSelected,
  });

  final List<StreamQuality> qualities;
  final String? selectedCode;
  final ValueChanged<StreamQuality> onSelected;

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
          _SheetHeader(
            icon: Icons.hd_rounded,
            title: 'Stream Quality',
            onClose: () => Navigator.pop(context),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                for (final quality in qualities) ...[
                  _QualityCard(
                    quality: quality,
                    selected: quality.code == selectedCode,
                    onTap: () => onSelected(quality),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({
    required this.icon,
    required this.title,
    required this.onClose,
  });

  final IconData icon;
  final String title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
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
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: c.text,
                fontWeight: FontWeight.w900,
                fontSize: 20,
              ),
            ),
          ),
          InkWell(
            onTap: onClose,
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
    );
  }
}
