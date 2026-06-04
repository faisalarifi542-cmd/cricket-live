import 'dart:async';
import 'dart:convert';

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
import 'package:cricpro_flutter/services/ads/ads_manager.dart';
import 'package:cricpro_flutter/widgets/ads/banner_ad_widget.dart';

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
  Map<String, dynamic>? _detailData;
  Map<String, dynamic>? _liveLineData;
  bool _livePolling = false;
  StreamSource? _selectedStream;
  VideoPlayerController? _videoController;
  Future<void>? _videoInitFuture;
  String? _playerError;
  List<HlsQuality> _hlsQualities = [];
  HlsQuality? _selectedQuality;
  bool _isMuted = false;
  bool _isLiveContent = true;
  BoxFit _videoFit = BoxFit.contain;
  List<StreamSource> _availableStreams = const [];
  final Set<String> _rewardUnlockedStreamIds = <String>{};

  bool get _hasMatchId => widget.matchId.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _appConfigFuture = _repository.appConfig();
    if (_hasMatchId) {
      _detailFuture = _loadMatchDetail();
      _liveLineFuture = _repository.matchLiveLine(widget.matchId);
      _liveLineFuture!.then((response) => _liveLineData = response.data);
      _streamsFuture = _repository.matchStreams(widget.matchId);
    }
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    _videoController?.dispose();
    // Clear the global video flag so interstitial/app-open ads are allowed
    // again after leaving the player.
    AdsManager.instance.videoPlaying = false;
    super.dispose();
  }

  Future<ApiEnvelope<Map<String, dynamic>>> _loadMatchDetail({
    bool forceRefresh = false,
  }) async {
    final response =
        await _repository.matchDetail(widget.matchId, forceRefresh: forceRefresh);
    _detailData = response.data;
    _configureLivePolling();
    return response;
  }

  void _configureLivePolling() {
    final live = _isLiveMatchData(_detailData);
    if (!live) {
      _liveTimer?.cancel();
      _liveTimer = null;
      return;
    }
    if (_liveTimer != null) return;
    _liveTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _silentPollLiveLine(),
    );
  }

  Future<void> _silentPollLiveLine() async {
    if (_livePolling || !mounted || !_hasMatchId) return;
    if (!_isLiveMatchData(_detailData)) {
      _liveTimer?.cancel();
      _liveTimer = null;
      return;
    }
    _livePolling = true;
    try {
      final detail =
          await _repository.matchDetail(widget.matchId, forceRefresh: true);
      final line =
          await _repository.matchLiveLine(widget.matchId, forceRefresh: true);
      if (!mounted) return;
      final detailChanged = _jsonChanged(_detailData, detail.data);
      final lineChanged = _jsonChanged(_liveLineData, line.data);
      _detailData = detail.data;
      _liveLineData = line.data;
      if (!_isLiveMatchData(detail.data)) {
        _liveTimer?.cancel();
        _liveTimer = null;
      }
      if (detailChanged || lineChanged) {
        setState(() {
          _detailFuture = Future.value(detail);
          _liveLineFuture = Future.value(line);
        });
      }
    } finally {
      _livePolling = false;
    }
  }

  bool _jsonChanged(Map<String, dynamic>? oldData, Map<String, dynamic> next) {
    if (oldData == null) return true;
    return jsonEncode(oldData) != jsonEncode(next);
  }

  bool _isLiveMatchData(Map<String, dynamic>? data) {
    if (data == null || data.isEmpty) return false;
    final status = apiString(data['status'] ?? data['state']).toLowerCase();
    return status == 'live' ||
        status == 'inprogress' ||
        status == 'in_progress' ||
        status == 'progress';
  }

  /// Guards against duplicate pre-roll ad attempts. The stream picker can
  /// re-fire its auto-select (e.g. when live polling rebuilds it) while we are
  /// awaiting an ad; this flag ensures one Watch Live tap = one ad attempt.
  bool _streamAdInProgress = false;

  /// True once the initial auto-select has been attempted, so live-poll
  /// rebuilds never re-trigger the pre-roll ad / prompt again.
  bool _autoSelectAttempted = false;

  /// Called by the picker exactly to auto-select the default stream. Runs only
  /// once per screen so a failed/cancelled pre-roll is not retried on every
  /// live-poll rebuild.
  Future<void> _autoSelectStream(StreamSource stream) async {
    if (_autoSelectAttempted) return;
    _autoSelectAttempted = true;
    await _selectStream(stream);
  }

  Future<void> _selectStream(StreamSource stream) async {
    // Already playing this exact stream — nothing to do (prevents re-trigger
    // from auto-select rebuilds during live polling).
    if (_selectedStream?.id == stream.id) return;
    if (_streamAdInProgress) return;

    final gate = _resolvePreRoll(stream);
    if (gate != StreamPreRollAdType.none) {
      _streamAdInProgress = true;
      try {
        final required = stream.isPremium && stream.requiresRewardAd;
        // For rewarded types, show a short honest "Watch ad to continue" notice
        // first so the user understands an ad unlocks the stream (policy-safe).
        if (gate == StreamPreRollAdType.rewardedVideo ||
            gate == StreamPreRollAdType.rewardedInterstitial) {
          final proceed = await _confirmWatchAd();
          if (proceed != true) return;
        }
        _showLoadingAdDialog();
        final result = await AdsManager.instance.showStreamPreRoll(
          type: gate,
          isRequiredForPremium: required,
        );
        _dismissLoadingAdDialog();
        if (result != StreamAdResult.allowed) {
          if (required) {
            _showAdRetryMessage();
            return; // Do NOT open a required premium stream without the ad.
          }
          // Optional free-stream pre-roll failed — continue normally.
        } else if (required) {
          _rewardUnlockedStreamIds.add(_rewardKey(stream));
        }
      } finally {
        _streamAdInProgress = false;
      }
    }

    // A stream is about to play — suppress interstitial/app-open ads while the
    // user is watching video.
    AdsManager.instance.videoPlaying = true;
    setState(() {
      _selectedStream = stream;
      _playerError = null;
      _hlsQualities = [];
      _selectedQuality = null;
      _isLiveContent = true;
    });
    await _loadStream(stream);
  }

  void _setAvailableStreams(List<StreamSource> streams) {
    final ids = streams.map((stream) => stream.id).join('|');
    final currentIds = _availableStreams.map((stream) => stream.id).join('|');
    if (ids == currentIds) return;
    setState(() => _availableStreams = List<StreamSource>.unmodifiable(streams));
  }

  /// Resolves the single pre-roll ad type to show before [stream], honoring the
  /// admin config and whether the stream was already unlocked this session.
  StreamPreRollAdType _resolvePreRoll(StreamSource stream) {
    final required = stream.isPremium && stream.requiresRewardAd;
    if (required && _rewardUnlockedStreamIds.contains(_rewardKey(stream))) {
      return StreamPreRollAdType.none;
    }
    return AdService.instance.config.resolveStreamPreRoll(
      isPremium: stream.isPremium,
      requiresRewardAd: stream.requiresRewardAd,
    );
  }

  String _rewardKey(StreamSource stream) => '${widget.matchId}:${stream.id}';

  /// Short, non-deceptive confirmation that an ad unlocks the stream.
  Future<bool?> _confirmWatchAd() {
    final c = context.cric;
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: c.card,
        title: Text('Watch ad to continue', style: TextStyle(color: c.text)),
        content: Text(
          'Watch a short ad to unlock this stream for the current match session.',
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
  }

  void _showAdRetryMessage() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content:
            Text('Ad is not available right now. Please try again.'),
      ),
    );
  }

  bool _loadingAdDialogOpen = false;

  /// Shows a short, non-deceptive "Loading ad…" dialog while the rewarded ad is
  /// prepared. Auto-dismissed by [_dismissLoadingAdDialog].
  void _showLoadingAdDialog() {
    if (!mounted || _loadingAdDialogOpen) return;
    final c = context.cric;
    _loadingAdDialogOpen = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: c.card,
        content: Row(
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                'Loading ad to unlock stream…',
                style: TextStyle(color: c.text, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _dismissLoadingAdDialog() {
    if (!_loadingAdDialogOpen) return;
    _loadingAdDialogOpen = false;
    if (mounted) Navigator.of(context, rootNavigator: true).pop();
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

    // TODO: Add a player backend that supports DASH/MPD, DRM, and request
    // headers. The current video_player path keeps HLS playback stable.
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
      final isLive = !content.contains('#EXT-X-ENDLIST');
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
            _isLiveContent = isLive;
          });
        }
      } else if (mounted) {
        setState(() => _isLiveContent = isLive);
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
    _showQualitySelector(context);
  }

  void _openFullscreen() {
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _FullscreenVideoPage(
          controller: controller,
          stream: _selectedStream!,
          qualities: _qualityOptionsFor(_selectedStream!),
          selectedQuality: _selectedQuality,
          videoFit: _videoFit,
          isLiveContent: _isLiveContent,
          onQualitySelected: (quality) {
            if (_selectedStream != null) {
              _loadStream(_selectedStream!, quality: quality);
            }
          },
          onFitChanged: (fit) => setState(() => _videoFit = fit),
          onGoLive: _goLive,
        ),
      ),
    );
  }

  List<HlsQuality> _qualityOptionsFor(StreamSource stream) {
    if (_hlsQualities.isNotEmpty) return _hlsQualities;
    final admin = _adminQualityOptions(_availableStreams, stream);
    if (admin.isNotEmpty) return admin;
    return [
      HlsQuality(
        label: stream.qualityLabel,
        code: stream.qualityCode,
        resolution: stream.qualityLabel,
        url: stream.url,
        rank: stream.qualityRank,
        source: 'admin',
      ),
    ];
  }

  List<HlsQuality> _adminQualityOptions(
    List<StreamSource> streams,
    StreamSource selected,
  ) {
    final byKey = <String, HlsQuality>{};
    for (final stream in streams.where((stream) => stream.url.isNotEmpty)) {
      final key = stream.qualityCode;
      byKey.putIfAbsent(
        key,
        () => HlsQuality(
          label: stream.qualityLabel,
          code: stream.qualityCode,
          resolution: _resolutionForCode(stream.qualityCode, stream.qualityLabel),
          url: stream.url,
          rank: stream.qualityRank,
          source: 'admin',
        ),
      );
    }
    byKey.putIfAbsent(
      selected.qualityCode,
      () => HlsQuality(
        label: selected.qualityLabel,
        code: selected.qualityCode,
        resolution: _resolutionForCode(selected.qualityCode, selected.qualityLabel),
        url: selected.url,
        rank: selected.qualityRank,
        source: 'admin',
      ),
    );
    final values = byKey.values.toList()
      ..sort((a, b) => a.rank.compareTo(b.rank));
    return values;
  }

  static String _resolutionForCode(String code, String label) {
    return switch (code.toUpperCase()) {
      'AUTO' => 'Adaptive',
      'FHD' => '1080p',
      'HD' => '720p',
      'SD' => '480p',
      'LOW' => '240p',
      _ => label,
    };
  }

  void _showQualitySelector(BuildContext context) {
    final stream = _selectedStream;
    if (stream == null) return;
    final qualities = _qualityOptionsFor(stream);
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    void select(HlsQuality quality) {
      Navigator.pop(context);
      _loadStream(stream, quality: quality);
    }

    if (landscape) {
      showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(20),
          child: _QualitySelectorPanel(
            selectedStream: stream,
            qualities: qualities,
            selectedQuality: _selectedQuality,
            landscape: true,
            onQualitySelected: select,
          ),
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _QualitySelectorPanel(
        selectedStream: stream,
        qualities: qualities,
        selectedQuality: _selectedQuality,
        landscape: false,
        onQualitySelected: select,
      ),
    );
  }

  bool get _isBehindLive {
    final value = _videoController?.value;
    if (!_isLiveContent || value == null || !value.isInitialized) return false;
    if (value.duration == Duration.zero) return false;
    final behind = value.duration - value.position;
    return behind.inSeconds > 12;
  }

  Future<void> _goLive() async {
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) return;
    final duration = controller.value.duration;
    if (duration != Duration.zero) {
      final target = duration - const Duration(seconds: 2);
      if (!target.isNegative) {
        await controller.seekTo(target);
        await controller.play();
        return;
      }
    }
    final stream = _selectedStream;
    if (stream != null) {
      await _loadStream(stream, quality: _selectedQuality);
    }
  }

  void _toggleMute() {
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) return;
    setState(() {
      _isMuted = !_isMuted;
      controller.setVolume(_isMuted ? 0.0 : 1.0);
    });
  }

  Future<void> _refresh() async {
    if (!_hasMatchId) return;
    setState(() {
      _detailFuture =
          _loadMatchDetail(forceRefresh: true);
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
                  isLiveContent: _isLiveContent,
                  isBehindLive: _isBehindLive,
                  videoFit: _videoFit,
                  onRetry: _selectedStream == null
                      ? null
                      : () => _loadStream(_selectedStream!),
                  onGoLive: _goLive,
                  onFullscreen: _openFullscreen,
                  onSettings: _openSettings,
                  onToggleMute: _toggleMute,
                ),
                const SizedBox(height: 24),
                _StreamsSection(
                  matchId: widget.matchId,
                  streamsFuture: _streamsFuture,
                  appConfigFuture: _appConfigFuture,
                  selectedId: _selectedStream?.id,
                  onSelect: _selectStream,
                  onAutoSelect: _autoSelectStream,
                  onStreamsLoaded: _setAvailableStreams,
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
        TeamLogoWidget(
          logoUrl: logoUrl,
          teamName: fullName,
          abbreviation: name,
          color: isStriker ? c.cyan : const Color(0xfff59e0b),
          size: 72,
          borderColor: isStriker ? c.cyan : c.border.withValues(alpha: .6),
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
    required this.isLiveContent,
    required this.isBehindLive,
    required this.videoFit,
    required this.onRetry,
    required this.onGoLive,
    required this.onFullscreen,
    required this.onSettings,
    required this.onToggleMute,
  });

  final StreamSource? stream;
  final VideoPlayerController? controller;
  final Future<void>? initFuture;
  final String? error;
  final HlsQuality? selectedQuality;
  final bool isMuted;
  final bool isLiveContent;
  final bool isBehindLive;
  final BoxFit videoFit;
  final VoidCallback? onRetry;
  final VoidCallback onGoLive;
  final VoidCallback onFullscreen;
  final VoidCallback onSettings;
  final VoidCallback onToggleMute;

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
                _VideoContent(controller: controller!, fit: videoFit)
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
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: hasStream ? c.primaryGradient : null,
                      color: hasStream ? null : c.card2,
                      boxShadow: hasStream
                          ? [
                              BoxShadow(
                                color: c.cyan.withValues(alpha: .38),
                                blurRadius: 22,
                                spreadRadius: 2,
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
                      size: 38,
                    ),
                  ),
                ),
              if (error != null)
                _PlayerErrorOverlay(onRetry: onRetry),
              Positioned(
                left: 14,
                top: 14,
                child: _PlayerPill(
                  label: isLiveContent ? 'LIVE' : (playing ? 'PLAYING' : 'STANDBY'),
                  color: playing ? c.live : c.card2,
                  icon: Icons.circle,
                ),
              ),
              if (stream != null)
                Positioned(
                  right: 14,
                  top: 14,
                  child: _PlayerPill(
                    label: selectedQuality?.code ?? stream!.qualityLabel,
                    color: Colors.black.withValues(alpha: .55),
                    textColor: c.cyan,
                    icon: Icons.hd_rounded,
                  ),
                ),
              if (initialized && !playing)
                Positioned.fill(
                  child: Center(
                    child: GestureDetector(
                      onTap: controller!.play,
                      child: Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black.withValues(alpha: .42),
                          border: Border.all(
                            color: c.cyan.withValues(alpha: .55),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: c.cyan.withValues(alpha: .25),
                              blurRadius: 18,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 34,
                        ),
                      ),
                    ),
                  ),
                ),
              if (initialized)
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 10,
                  child: _PortraitPlayerControls(
                    controller: controller!,
                    playing: playing,
                    isLiveContent: isLiveContent,
                    isBehindLive: isBehindLive,
                    isMuted: isMuted,
                    onGoLive: onGoLive,
                    onToggleMute: onToggleMute,
                    onSettings: onSettings,
                    onFullscreen: onFullscreen,
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

IconData _fitIcon(BoxFit fit) {
  return switch (fit) {
    BoxFit.cover => Icons.crop_free_rounded,
    BoxFit.fill => Icons.open_in_full_rounded,
    _ => Icons.fit_screen_rounded,
  };
}

class _VideoContent extends StatelessWidget {
  const _VideoContent({required this.controller, required this.fit});

  final VideoPlayerController controller;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final aspect = controller.value.aspectRatio == 0
        ? 16 / 9
        : controller.value.aspectRatio;
    if (fit == BoxFit.fill) {
      return SizedBox.expand(child: VideoPlayer(controller));
    }
    return FittedBox(
      fit: fit,
      child: SizedBox(
        width: aspect * 1000,
        height: 1000,
        child: VideoPlayer(controller),
      ),
    );
  }
}

class _LiveEdgeBadge extends StatelessWidget {
  const _LiveEdgeBadge({required this.isBehindLive, required this.onGoLive});

  final bool isBehindLive;
  final VoidCallback onGoLive;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    if (isBehindLive) {
      return InkWell(
        onTap: onGoLive,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: c.cyan.withValues(alpha: .18),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: c.cyan.withValues(alpha: .72)),
          ),
          child: Text(
            'Go Live',
            style: TextStyle(
              color: c.cyan,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 7, height: 7, decoration: BoxDecoration(color: c.live, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(
          'LIVE',
          style: TextStyle(
            color: c.text,
            fontWeight: FontWeight.w900,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}

class _PlayerErrorOverlay extends StatelessWidget {
  const _PlayerErrorOverlay({required this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxHeight < 190;
          return Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 14 : 18,
                vertical: compact ? 8 : 14,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: c.warning,
                    size: compact ? 28 : 36,
                  ),
                  SizedBox(height: compact ? 6 : 10),
                  Text(
                    'Unable to play this stream. Please retry or refresh.',
                    textAlign: TextAlign.center,
                    maxLines: compact ? 2 : 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.text,
                      fontWeight: FontWeight.w900,
                      height: 1.25,
                      fontSize: compact ? 13 : 15,
                    ),
                  ),
                  if (onRetry != null) ...[
                    SizedBox(height: compact ? 8 : 14),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 170),
                      child: GradientButton(
                        label: 'Retry',
                        icon: Icons.refresh_rounded,
                        height: compact ? 38 : 44,
                        onTap: onRetry,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PlayerMiniIcon extends StatelessWidget {
  const _PlayerMiniIcon({required this.icon, required this.onTap, this.size = 38});

  final IconData icon;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: .08)),
        ),
        child: Icon(icon, color: Colors.white, size: size <= 34 ? 18 : 20),
      ),
    );
  }
}

class _PortraitPlayerControls extends StatelessWidget {
  const _PortraitPlayerControls({
    required this.controller,
    required this.playing,
    required this.isLiveContent,
    required this.isBehindLive,
    required this.isMuted,
    required this.onGoLive,
    required this.onToggleMute,
    required this.onSettings,
    required this.onFullscreen,
  });

  final VideoPlayerController controller;
  final bool playing;
  final bool isLiveContent;
  final bool isBehindLive;
  final bool isMuted;
  final VoidCallback onGoLive;
  final VoidCallback onToggleMute;
  final VoidCallback onSettings;
  final VoidCallback onFullscreen;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 360;
        final iconSize = compact ? 34.0 : 38.0;
        return Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 10,
            vertical: compact ? 8 : 9,
          ),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .50),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: .08)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: VideoProgressIndicator(
                  controller,
                  allowScrubbing: !isLiveContent,
                  colors: VideoProgressColors(
                    playedColor: c.cyan,
                    bufferedColor: Colors.white24,
                    backgroundColor: Colors.white.withValues(alpha: .12),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _PlayerMiniIcon(
                    size: iconSize,
                    icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    onTap: () => playing ? controller.pause() : controller.play(),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Center(
                      child: isLiveContent
                          ? _LiveEdgeBadge(
                              isBehindLive: isBehindLive,
                              onGoLive: onGoLive,
                            )
                          : Text(
                              _timeLabel(
                                controller.value.position,
                                controller.value.duration,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: c.text,
                                fontWeight: FontWeight.w800,
                                fontSize: compact ? 11 : 12,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _PlayerMiniIcon(
                    size: iconSize,
                    icon: isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                    onTap: onToggleMute,
                  ),
                  const SizedBox(width: 6),
                  _PlayerMiniIcon(
                    size: iconSize,
                    icon: Icons.settings_rounded,
                    onTap: onSettings,
                  ),
                  const SizedBox(width: 6),
                  _PlayerMiniIcon(
                    size: iconSize,
                    icon: Icons.fullscreen_rounded,
                    onTap: onFullscreen,
                  ),
                ],
              ),
            ],
          ),
        );
      },
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
    required this.onAutoSelect,
    required this.onStreamsLoaded,
  });

  final String matchId;
  final Future<ApiEnvelope<Map<String, dynamic>>>? streamsFuture;
  final Future<ApiEnvelope<Map<String, dynamic>>>? appConfigFuture;
  final String? selectedId;
  final ValueChanged<StreamSource> onSelect;
  final ValueChanged<StreamSource> onAutoSelect;
  final ValueChanged<List<StreamSource>> onStreamsLoaded;

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
        WidgetsBinding.instance.addPostFrameCallback((_) {
          onStreamsLoaded(streams);
        });
        if (streams.isEmpty) {
          return _StreamsUnavailable(appConfigFuture: appConfigFuture);
        }
        final selected = streams.where((s) => s.id == selectedId).firstOrNull ??
            streams.first;
        final qualityStreams = <String, StreamSource>{};
        for (final stream in streams) {
          qualityStreams.putIfAbsent(stream.qualityCode, () => stream);
        }
        
        final selectedQuality = selected.qualityCode;
        final serverStreams =
            streams.where((s) => s.qualityCode == selectedQuality).toList();
        final hasMultipleServers = serverStreams.length > 1;
        
        // Auto-select highest priority stream once available
        if (selectedId == null) {
          WidgetsBinding.instance
              .addPostFrameCallback((_) => onAutoSelect(selected));
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
                final cards = qualityStreams.values
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
            const SizedBox(height: 14),
            const _CompactStreamStatus(),
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

/// Compact, single-line stream status replacing the heavy marketing cards
/// (Low Latency / Adaptive / Secure Stream). Keeps the screen focused on the
/// player + quality + server.
class _CompactStreamStatus extends StatelessWidget {
  const _CompactStreamStatus();

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: c.card2.withValues(alpha: .4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border.withValues(alpha: .3)),
      ),
      child: Row(
        children: [
          Icon(Icons.verified_user_rounded, color: c.cyan, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Secure, low-latency adaptive stream',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.muted,
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
          ),
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

class _FullscreenVideoPage extends StatefulWidget {
  const _FullscreenVideoPage({
    required this.controller,
    required this.stream,
    required this.qualities,
    required this.selectedQuality,
    required this.videoFit,
    required this.isLiveContent,
    required this.onQualitySelected,
    required this.onFitChanged,
    required this.onGoLive,
  });

  final VideoPlayerController controller;
  final StreamSource stream;
  final List<HlsQuality> qualities;
  final HlsQuality? selectedQuality;
  final BoxFit videoFit;
  final bool isLiveContent;
  final ValueChanged<HlsQuality> onQualitySelected;
  final ValueChanged<BoxFit> onFitChanged;
  final VoidCallback onGoLive;

  @override
  State<_FullscreenVideoPage> createState() => _FullscreenVideoPageState();
}

class _FullscreenVideoPageState extends State<_FullscreenVideoPage> {
  late BoxFit _fit = widget.videoFit;
  bool _controlsVisible = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    // True fullscreen: force landscape and hide the status/navigation bars
    // using immersive sticky mode so the phone chrome never shows over video.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _scheduleHideControls();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    // Restore portrait + system UI when leaving fullscreen.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    super.dispose();
  }

  void _scheduleHideControls() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) _scheduleHideControls();
  }

  Future<void> _exit() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    if (mounted) Navigator.pop(context);
  }

  bool get _isBehindLive {
    final value = widget.controller.value;
    if (!widget.isLiveContent || !value.isInitialized) return false;
    if (value.duration == Duration.zero) return false;
    return (value.duration - value.position).inSeconds > 12;
  }

  void _cycleFit() {
    final next = switch (_fit) {
      BoxFit.contain => BoxFit.cover,
      BoxFit.cover => BoxFit.fill,
      _ => BoxFit.contain,
    };
    setState(() => _fit = next);
    widget.onFitChanged(next);
    _scheduleHideControls();
    final label = switch (next) {
      BoxFit.cover => 'Fill',
      BoxFit.fill => 'Stretch',
      _ => 'Fit',
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(label),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 900),
      ),
    );
  }

  void _openQuality() {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: _QualitySelectorPanel(
          selectedStream: widget.stream,
          qualities: widget.qualities,
          selectedQuality: widget.selectedQuality,
          landscape: true,
          onQualitySelected: (quality) {
            Navigator.pop(context);
            widget.onQualitySelected(quality);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exit();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: ValueListenableBuilder<VideoPlayerValue>(
          valueListenable: widget.controller,
          builder: (context, value, _) {
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggleControls,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Center(
                    child: _VideoContent(
                        controller: widget.controller, fit: _fit),
                  ),
                  // Dim layer + controls only while visible.
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 220),
                    opacity: _controlsVisible ? 1 : 0,
                    child: IgnorePointer(
                      ignoring: !_controlsVisible,
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
                              ),
                            ),
                          ),
                          SafeArea(
                            child: Stack(
                              children: [
                                Positioned(
                                  left: 8,
                                  top: 8,
                                  child: _FullscreenIconButton(
                                    icon: Icons.close_rounded,
                                    onTap: _exit,
                                  ),
                                ),
                                Positioned(
                                  right: 8,
                                  top: 8,
                                  child: Row(
                                    children: [
                                      _FullscreenIconButton(
                                        icon: Icons.hd_rounded,
                                        onTap: _openQuality,
                                      ),
                                      const SizedBox(width: 8),
                                      _FullscreenIconButton(
                                        icon: _fitIcon(_fit),
                                        onTap: _cycleFit,
                                      ),
                                    ],
                                  ),
                                ),
                                // Compact center play/pause.
                                Center(
                                  child: GestureDetector(
                                    onTap: () {
                                      value.isPlaying
                                          ? widget.controller.pause()
                                          : widget.controller.play();
                                      _scheduleHideControls();
                                    },
                                    child: Container(
                                      width: 64,
                                      height: 64,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.black
                                            .withValues(alpha: .42),
                                        border: Border.all(
                                            color: Colors.white
                                                .withValues(alpha: .25)),
                                      ),
                                      child: Icon(
                                        value.isPlaying
                                            ? Icons.pause_rounded
                                            : Icons.play_arrow_rounded,
                                        color: Colors.white,
                                        size: 38,
                                      ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  left: 16,
                                  right: 16,
                                  bottom: 12,
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: VideoProgressIndicator(
                                          widget.controller,
                                          allowScrubbing:
                                              !widget.isLiveContent,
                                          colors: VideoProgressColors(
                                            playedColor: c.cyan,
                                            bufferedColor: Colors.white38,
                                            backgroundColor: Colors.white24,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      if (widget.isLiveContent)
                                        _LiveEdgeBadge(
                                          isBehindLive: _isBehindLive,
                                          onGoLive: widget.onGoLive,
                                        )
                                      else
                                        Text(
                                          _timeLabel(
                                              value.position, value.duration),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w800,
                                            fontSize: 12,
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
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _FullscreenIconButton extends StatelessWidget {
  const _FullscreenIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .45),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white24),
        ),
        child: Icon(icon, color: Colors.white, size: 22),
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
    this.source = 'hlsVariant',
  });

  final String label;
  final String code;
  final String resolution;
  final String url;
  final int rank;
  final int? bandwidth;
  final String source;
}

// Settings Bottom Sheet
class _QualitySelectorPanel extends StatelessWidget {
  const _QualitySelectorPanel({
    required this.selectedStream,
    required this.qualities,
    required this.selectedQuality,
    required this.landscape,
    required this.onQualitySelected,
  });

  final StreamSource selectedStream;
  final List<HlsQuality> qualities;
  final HlsQuality? selectedQuality;
  final bool landscape;
  final ValueChanged<HlsQuality> onQualitySelected;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final screen = MediaQuery.sizeOf(context);
    final maxHeight = screen.height * (landscape ? .68 : .70);
    final maxWidth = landscape ? screen.width * .58 : double.infinity;
    final rowCompact = landscape || screen.height < 620;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: maxHeight,
          maxWidth: maxWidth,
          minWidth: landscape ? 360 : 0,
        ),
        child: Container(
          margin: EdgeInsets.all(landscape ? 0 : 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
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
                blurRadius: 32,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  rowCompact ? 14 : 18,
                  rowCompact ? 12 : 16,
                  rowCompact ? 10 : 14,
                  rowCompact ? 10 : 14,
                ),
                child: Row(
                  children: [
                    Container(
                      width: rowCompact ? 34 : 40,
                      height: rowCompact ? 34 : 40,
                      decoration: BoxDecoration(
                        gradient: c.primaryGradient,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.hd_rounded,
                          color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Stream Quality',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.text,
                          fontWeight: FontWeight.w900,
                          fontSize: rowCompact ? 17 : 20,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.close_rounded, color: c.text),
                    ),
                  ],
                ),
              ),
              Divider(color: c.border.withValues(alpha: .35), height: 1),
              Flexible(
                child: ListView.separated(
                  padding: EdgeInsets.fromLTRB(
                    rowCompact ? 12 : 16,
                    rowCompact ? 10 : 14,
                    rowCompact ? 12 : 16,
                    rowCompact ? 14 : 18,
                  ),
                  itemCount: qualities.length + 1,
                  separatorBuilder: (_, __) => SizedBox(height: rowCompact ? 8 : 10),
                  itemBuilder: (context, index) {
                    if (index == qualities.length) {
                      return _CurrentServerTile(
                        selectedStream: selectedStream,
                        compact: rowCompact,
                      );
                    }
                    final quality = qualities[index];
                    return _QualityOption(
                      quality: quality,
                      compact: rowCompact,
                      selected: selectedQuality == null
                          ? index == 0
                          : selectedQuality!.url == quality.url &&
                              selectedQuality!.code == quality.code,
                      onTap: () => onQualitySelected(quality),
                    );
                  },
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
    required this.quality,
    required this.selected,
    required this.onTap,
    required this.compact,
  });

  final HlsQuality quality;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 12 : 16,
          vertical: compact ? 10 : 14,
        ),
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
              width: compact ? 36 : 44,
              height: compact ? 36 : 44,
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
                  fontSize: compact ? 10 : 12,
                ),
              ),
            ),
            SizedBox(width: compact ? 10 : 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    quality.label,
                    style: TextStyle(
                      color: c.text,
                      fontWeight: FontWeight.w900,
                      fontSize: compact ? 14 : 16,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    quality.resolution,
                    style: TextStyle(
                      color: selected ? c.cyan : c.muted,
                      fontWeight: FontWeight.w700,
                      fontSize: compact ? 11 : 13,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              selected ? Icons.check_circle_rounded : Icons.circle_outlined,
              color: selected ? c.cyan : c.muted,
              size: compact ? 21 : 24,
            ),
          ],
        ),
      ),
    );
  }
}

class _CurrentServerTile extends StatelessWidget {
  const _CurrentServerTile({required this.selectedStream, required this.compact});

  final StreamSource selectedStream;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      padding: EdgeInsets.all(compact ? 12 : 16),
      decoration: BoxDecoration(
        color: c.card2.withValues(alpha: .42),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border.withValues(alpha: .28)),
      ),
      child: Row(
        children: [
          Icon(Icons.dns_rounded, color: c.cyan, size: compact ? 18 : 20),
          SizedBox(width: compact ? 10 : 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Current server',
                  style: TextStyle(
                    color: c.muted,
                    fontSize: compact ? 10 : 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  selectedStream.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.text,
                    fontWeight: FontWeight.w900,
                    fontSize: compact ? 13 : 15,
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
