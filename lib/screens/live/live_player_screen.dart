import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

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
  const LivePlayerScreen({
    super.key,
    this.matchId = '',
    this.skipInitialPreRoll = false,
  });

  final String matchId;

  /// When true, the central Watch Live launcher already showed the entry
  /// pre-roll ad, so the player must NOT show another pre-roll for the first
  /// (auto-selected) non-premium stream. Premium locked streams still require
  /// their per-stream reward unlock.
  final bool skipInitialPreRoll;

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

  /// True once the in-player pre-roll has been skipped for the first
  /// auto-selected stream because the central Watch Live launcher already
  /// showed the entry ad (prevents two ads per Watch Live tap).
  bool _initialPreRollConsumed = false;

  /// True while the screen is holding the wakelock (screen kept awake during
  /// playback). Mirrors the controller's play state.
  bool _wakelockOn = false;

  // Last-seen controller values, used to skip rebuilds when nothing the UI
  // shows has changed. Position/duration are tracked at whole-second
  // granularity so the progress/time UI updates ~1x/sec instead of on every
  // controller notification (several per second).
  bool _lastInitialized = false;
  bool _lastIsPlaying = false;
  bool _lastBuffering = false;
  bool _lastHasError = false;
  int _lastPositionSec = -1;
  int _lastDurationSec = -1;

  bool get _hasMatchId => widget.matchId.isNotEmpty;

  /// Live viewer-count label sourced from real backend data (detail/live-line).
  /// Returns null when the backend does not provide a count, so the player
  /// never shows a fabricated number.
  String? get _viewersLabel {
    for (final map in [_detailData, _liveLineData]) {
      if (map == null) continue;
      final raw = map['viewers'] ??
          map['viewer_count'] ??
          map['viewerCount'] ??
          map['liveViewers'] ??
          map['watching'];
      final n = apiInt(raw);
      if (n != null && n > 0) return _compactCount(n);
    }
    return null;
  }

  static String _compactCount(int n) {
    if (n >= 1000000) {
      final v = (n / 1000000);
      return '${v.toStringAsFixed(v >= 10 ? 0 : 1)}M';
    }
    if (n >= 1000) {
      final v = (n / 1000);
      return '${v.toStringAsFixed(v >= 10 ? 0 : 1)}K';
    }
    return '$n';
  }

  /// Enables/disables the screen wakelock, but only when the state actually
  /// changes, so we don't spam the platform channel on every tick.
  void _syncWakelock(bool enable) {
    if (enable == _wakelockOn) return;
    _wakelockOn = enable;
    WakelockPlus.toggle(enable: enable);
  }

  /// Controller listener that drives wakelock and rebuilds. It rebuilds only
  /// when a user-visible field changes (init/play/buffering/error or the
  /// whole-second position/duration), instead of on every notification — which
  /// previously rebuilt the entire player subtree several times per second.
  void _onControllerUpdate() {
    final controller = _videoController;
    if (controller == null || !mounted) return;
    final value = controller.value;

    // Keep the screen awake only while actually playing initialized video.
    _syncWakelock(value.isInitialized && value.isPlaying);

    final positionSec = value.position.inSeconds;
    final durationSec = value.duration.inSeconds;
    final changed = value.isInitialized != _lastInitialized ||
        value.isPlaying != _lastIsPlaying ||
        value.isBuffering != _lastBuffering ||
        value.hasError != _lastHasError ||
        positionSec != _lastPositionSec ||
        durationSec != _lastDurationSec;
    if (!changed) return;

    _lastInitialized = value.isInitialized;
    _lastIsPlaying = value.isPlaying;
    _lastBuffering = value.isBuffering;
    _lastHasError = value.hasError;
    _lastPositionSec = positionSec;
    _lastDurationSec = durationSec;
    setState(() {});
  }

  /// Resets the cached controller-value diff so the next controller produces a
  /// fresh first rebuild.
  void _resetControllerDiff() {
    _lastInitialized = false;
    _lastIsPlaying = false;
    _lastBuffering = false;
    _lastHasError = false;
    _lastPositionSec = -1;
    _lastDurationSec = -1;
  }

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
    _videoController?.removeListener(_onControllerUpdate);
    // Release the wakelock so the screen can sleep normally after leaving.
    _syncWakelock(false);
    _videoController?.dispose();
    // Clear the global video flag so interstitial/app-open ads are allowed
    // again after leaving the player.
    AdsManager.instance.videoPlaying = false;
    super.dispose();
  }

  Future<ApiEnvelope<Map<String, dynamic>>> _loadMatchDetail({
    bool forceRefresh = false,
  }) async {
    final response = await _repository.matchDetail(widget.matchId,
        forceRefresh: forceRefresh);
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
    setState(
        () => _availableStreams = List<StreamSource>.unmodifiable(streams));
  }

  /// Resolves the single pre-roll ad type to show before [stream], honoring the
  /// admin config and whether the stream was already unlocked this session.
  StreamPreRollAdType _resolvePreRoll(StreamSource stream) {
    final required = stream.isPremium && stream.requiresRewardAd;
    if (required && _rewardUnlockedStreamIds.contains(_rewardKey(stream))) {
      return StreamPreRollAdType.none;
    }
    // The central Watch Live launcher already showed the entry pre-roll. Skip
    // the in-player pre-roll for the FIRST (auto-selected) non-premium stream
    // so one Watch Live tap never shows two ads. Premium locked streams still
    // require their reward unlock here.
    if (widget.skipInitialPreRoll && !_initialPreRollConsumed && !required) {
      _initialPreRollConsumed = true;
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
        content: Text('Ad is not available right now. Please try again.'),
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
    oldController?.removeListener(_onControllerUpdate);
    _resetControllerDiff();
    _syncWakelock(false);
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

    // Per-stream request headers (User-Agent / Referer / Origin / custom),
    // configured in the admin panel and delivered via /app/config. Required for
    // hotlink-protected HLS sources, which 403 without them.
    final headers = _stringHeaders(stream.headers);
    if (kDebugMode) {
      debugPrint(
          '[Player] stream headers present=${headers.isNotEmpty} count=${headers.length}');
    }

    // TODO: Add a player backend that supports DASH/MPD and DRM. The current
    // video_player path handles HLS playback and request headers.
    // Parse HLS qualities if this is an HLS stream and no quality selected yet
    if (stream.isHls && quality == null && _hlsQualities.isEmpty) {
      await _parseHlsQualities(stream.url, headers: headers);
    }

    // Determine the URL to play. When an explicit quality is requested, use it.
    // Otherwise, if parsing produced a preferred default variant, play that so
    // the player opens on the best concrete quality instead of the master.
    String playUrl = stream.url;
    if (quality != null && quality.url.isNotEmpty) {
      playUrl = quality.url;
    } else if (quality == null &&
        _selectedQuality != null &&
        _selectedQuality!.url.isNotEmpty) {
      playUrl = _selectedQuality!.url;
    }

    final controller = VideoPlayerController.networkUrl(
      Uri.parse(playUrl),
      httpHeaders: headers,
    );
    controller.addListener(_onControllerUpdate);
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
      controller.removeListener(_onControllerUpdate);
      _syncWakelock(false);
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

  /// Normalizes admin-configured headers (which arrive as a dynamic-valued
  /// map) into the `Map<String, String>` the player/HTTP client require.
  /// Drops null/empty entries. Values are never logged.
  Map<String, String> _stringHeaders(Map<String, dynamic> raw) {
    final result = <String, String>{};
    raw.forEach((key, value) {
      if (value == null) return;
      final k = key.trim();
      final v = value.toString().trim();
      if (k.isEmpty || v.isEmpty) return;
      result[k] = v;
    });
    return result;
  }

  Future<void> _parseHlsQualities(
    String masterUrl, {
    Map<String, String> headers = const {},
  }) async {
    try {
      final response = await http
          .get(Uri.parse(masterUrl), headers: headers.isEmpty ? null : headers)
          .timeout(
            const Duration(seconds: 5),
          );
      if (kDebugMode) {
        debugPrint(
            '[Player] HLS master fetch status=${response.statusCode} headers=${headers.length}');
      }
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
          currentBandwidth =
              bandMatch != null ? int.parse(bandMatch.group(1)!) : null;

          // Find the variant URL on the next non-comment line.
          String? variantUrl;
          if (i + 1 < lines.length) {
            final variantLine = lines[i + 1].trim();
            if (variantLine.isNotEmpty && !variantLine.startsWith('#')) {
              variantUrl = _resolveUrl(masterUrl, variantLine);
            }
          }
          if (variantUrl == null) continue;

          HlsQuality? quality;
          if (resMatch != null) {
            final width = int.parse(resMatch.group(1)!);
            final height = int.parse(resMatch.group(2)!);
            currentResolution = '${width}x$height';
            quality = _createQualityFromResolution(
              currentResolution,
              variantUrl,
              currentBandwidth,
            );
          } else if (currentBandwidth != null) {
            // No RESOLUTION — bucket by bitrate as a fallback.
            quality = _createQualityFromBandwidth(currentBandwidth, variantUrl);
          }
          if (quality != null) qualities.add(quality);
        }
      }

      if (qualities.isNotEmpty) {
        // Keep only the best variant per bucket (highest bandwidth / height),
        // so each of FHD/HD/SD maps to a single concrete URL.
        final bestByCode = <String, HlsQuality>{};
        for (final q in qualities) {
          final existing = bestByCode[q.code];
          if (existing == null) {
            bestByCode[q.code] = q;
          } else {
            final better = (q.bandwidth ?? 0) > (existing.bandwidth ?? 0);
            if (better) bestByCode[q.code] = q;
          }
        }
        final deduped = bestByCode.values.toList()
          ..sort((a, b) => a.rank.compareTo(b.rank));
        qualities
          ..clear()
          ..addAll(deduped);

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

        // Default selected quality: best concrete variant (Full HD → HD → SD),
        // falling back to Auto/master when no concrete variant is present.
        HlsQuality byCode(String code) => qualities
            .firstWhere((q) => q.code == code, orElse: () => qualities.first);
        final hasFhd = qualities.any((q) => q.code == 'FHD');
        final hasHd = qualities.any((q) => q.code == 'HD');
        final hasSd = qualities.any((q) => q.code == 'SD');
        final defaultQuality = hasFhd
            ? byCode('FHD')
            : hasHd
                ? byCode('HD')
                : hasSd
                    ? byCode('SD')
                    : qualities.first;

        if (mounted) {
          setState(() {
            _hlsQualities = qualities;
            _selectedQuality = defaultQuality;
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

    // Quality bucket mapping per product spec:
    //   720p and higher → Full HD (FHD)
    //   480p            → HD
    //   240p / 360p     → SD
    // The resolution label always reflects the real variant height so we never
    // claim 1080p when the playlist only contains 720p.
    if (height >= 720) {
      return HlsQuality(
        label: 'Full HD',
        code: 'FHD',
        resolution: '${height}p',
        url: url,
        rank: 1,
        bandwidth: bandwidth,
      );
    } else if (height >= 480) {
      return HlsQuality(
        label: 'HD',
        code: 'HD',
        resolution: '${height}p',
        url: url,
        rank: 2,
        bandwidth: bandwidth,
      );
    } else {
      // 240p / 360p (and anything below 480p) → SD.
      return HlsQuality(
        label: 'SD',
        code: 'SD',
        resolution: '${height}p',
        url: url,
        rank: 3,
        bandwidth: bandwidth,
      );
    }
  }

  /// Buckets a variant that only advertises BANDWIDTH (no RESOLUTION) into a
  /// quality tier using rough bitrate thresholds.
  HlsQuality _createQualityFromBandwidth(int bandwidth, String url) {
    if (bandwidth >= 2500000) {
      return HlsQuality(
        label: 'Full HD',
        code: 'FHD',
        resolution: 'HD',
        url: url,
        rank: 1,
        bandwidth: bandwidth,
      );
    } else if (bandwidth >= 1200000) {
      return HlsQuality(
        label: 'HD',
        code: 'HD',
        resolution: 'SD',
        url: url,
        rank: 2,
        bandwidth: bandwidth,
      );
    }
    return HlsQuality(
      label: 'SD',
      code: 'SD',
      resolution: 'Low',
      url: url,
      rank: 3,
      bandwidth: bandwidth,
    );
  }

  String _resolveUrl(String baseUrl, String relativePath) {
    if (relativePath.startsWith('http://') ||
        relativePath.startsWith('https://')) {
      return relativePath;
    }

    final baseUri = Uri.parse(baseUrl);
    final basePath =
        baseUri.path.substring(0, baseUri.path.lastIndexOf('/') + 1);
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
          isMuted: _isMuted,
          onQualitySelected: (quality) {
            if (_selectedStream != null) {
              _loadStream(_selectedStream!, quality: quality);
            }
          },
          onFitChanged: (fit) => setState(() => _videoFit = fit),
          onGoLive: _goLive,
          onToggleMute: _toggleMute,
          onSeekBackward: _seekBackward,
          onSeekForward: _seekForward,
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

  /// Quality options for the currently-selected stream (empty when no stream
  /// is selected). Drives the premium Full HD / HD / SD cards.
  List<HlsQuality> get _currentQualityOptions {
    final stream = _selectedStream;
    if (stream == null) return const [];
    return _qualityOptionsFor(stream);
  }

  /// Switches to a specific quality variant and reinitializes the player while
  /// keeping the match UI. Safe to call from the premium quality cards.
  Future<void> _selectQuality(HlsQuality quality) async {
    final stream = _selectedStream;
    if (stream == null) return;
    if (_selectedQuality != null &&
        _selectedQuality!.code == quality.code &&
        _selectedQuality!.url == quality.url) {
      return;
    }
    await _loadStream(stream, quality: quality);
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
          resolution:
              _resolutionForCode(stream.qualityCode, stream.qualityLabel),
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
        resolution:
            _resolutionForCode(selected.qualityCode, selected.qualityLabel),
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

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: context.cric.card,
      ),
    );
  }

  /// Seek backward 10s. Works for both VOD and live HLS playlists that expose
  /// a seekable window.
  Future<void> _seekBackward() async {
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.duration == Duration.zero) {
      _snack('Rewind is not available for this live stream.');
      return;
    }
    final target = controller.value.position - const Duration(seconds: 10);
    await controller.seekTo(target < Duration.zero ? Duration.zero : target);
  }

  /// Seek forward 10s. For a true live stream with no seekable duration this
  /// jumps to the live edge instead.
  Future<void> _seekForward() async {
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) return;
    final duration = controller.value.duration;
    if (duration == Duration.zero) {
      _snack('Already at the live edge.');
      return;
    }
    final target = controller.value.position + const Duration(seconds: 10);
    await controller.seekTo(target > duration ? duration : target);
  }

  void _shareStream() {
    final stream = _selectedStream;
    final link = stream?.url ?? '';
    final text = link.isEmpty
        ? 'Watch live cricket on CricPro.'
        : 'Watch live cricket on CricPro: $link';
    Clipboard.setData(ClipboardData(text: text));
    _snack('Stream link copied to clipboard.');
  }

  void _showComments() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const _InfoSheet(
        icon: Icons.chat_bubble_outline_rounded,
        title: 'Live Commentary',
        message: 'Live comments coming soon.',
      ),
    );
  }

  void _showStats() {
    final detail = _detailData ?? const {};
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _StatsSheet(detail: detail, liveLine: _liveLineData),
    );
  }

  Future<void> _refresh() async {
    if (!_hasMatchId) return;
    setState(() {
      _detailFuture = _loadMatchDetail(forceRefresh: true);
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
        child: Stack(
          children: [
            // Premium dark stadium backdrop + cyan radial glow behind the top.
            Positioned.fill(
              child: IgnorePointer(
                child: Image.asset(
                  'assets/images/live_stream/backgrounds/live_screen_dark_background.png',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
            Positioned(
              top: -60,
              left: 0,
              right: 0,
              height: 360,
              child: IgnorePointer(
                child: Image.asset(
                  'assets/images/live_stream/overlays/cyan_radial_glow.png',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
            SafeArea(
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
                    _LivePlayerHeader(
                      matchId: widget.matchId,
                      onShare: _shareStream,
                    ),
                    const SizedBox(height: 16),
                    _MatchInfoSection(
                      matchId: widget.matchId,
                      detailFuture: _detailFuture,
                      liveLineFuture: _liveLineFuture,
                    ),
                    const SizedBox(height: 16),
                    _PlayerSurface(
                      stream: _selectedStream,
                      controller: _videoController,
                      initFuture: _videoInitFuture,
                      error: _playerError,
                      selectedQuality: _selectedQuality,
                      isMuted: _isMuted,
                      isLiveContent: _isLiveContent,
                      videoFit: _videoFit,
                      viewers: _viewersLabel,
                      onRetry: _selectedStream == null
                          ? null
                          : () => _loadStream(_selectedStream!),
                      onFullscreen: _openFullscreen,
                      onSettings: _openSettings,
                      onToggleMute: _toggleMute,
                      onShare: _shareStream,
                      onComments: _showComments,
                      onStats: _showStats,
                      onSeekBackward: _seekBackward,
                      onSeekForward: _seekForward,
                    ),
                    const SizedBox(height: 18),
                    _StreamsSection(
                      matchId: widget.matchId,
                      streamsFuture: _streamsFuture,
                      appConfigFuture: _appConfigFuture,
                      selectedId: _selectedStream?.id,
                      onAutoSelect: _autoSelectStream,
                      onStreamsLoaded: _setAvailableStreams,
                      qualityOptions: _currentQualityOptions,
                      selectedQuality: _selectedQuality,
                      onSelectQuality: _selectQuality,
                    ),
                    const SizedBox(height: 16),
                    const BannerAdWidget(placement: AdPlacement.livePlayer),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LivePlayerHeader extends StatelessWidget {
  const _LivePlayerHeader({required this.matchId, this.onShare});

  final String matchId;
  final VoidCallback? onShare;

  void _showCastNotAvailable(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Cast support is coming soon'),
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
          svgAsset: 'assets/images/live_stream/icons/ic_back_white.svg',
          fallback: Icons.arrow_back_rounded,
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
          svgAsset: 'assets/images/live_stream/icons/ic_cast_white.svg',
          fallback: Icons.cast_rounded,
          onTap: () => _showCastNotAvailable(context),
        ),
        const SizedBox(width: 8),
        _HeaderActionButton(
          svgAsset: 'assets/images/live_stream/icons/ic_share_white.svg',
          fallback: Icons.share_rounded,
          onTap: onShare,
        ),
        const SizedBox(width: 8),
        _HeaderActionButton(
          svgAsset:
              'assets/images/live_stream/icons/ic_more_vertical_white.svg',
          fallback: Icons.more_vert_rounded,
          onTap: () => _showMoreOptions(context),
        ),
      ],
    );
  }
}

class _HeaderActionButton extends StatelessWidget {
  const _HeaderActionButton(
      {required this.fallback, this.svgAsset, this.onTap});

  final IconData fallback;
  final String? svgAsset;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.card.withValues(alpha: .55),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: c.cyan.withValues(alpha: .3)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .25),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: svgAsset != null
            ? SvgPicture.asset(
                svgAsset!,
                width: 22,
                height: 22,
                colorFilter: ColorFilter.mode(c.text, BlendMode.srcIn),
                placeholderBuilder: (_) =>
                    Icon(fallback, color: c.text, size: 22),
              )
            : Icon(fallback, color: c.text, size: 22),
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

    // Build a per-innings "runs/wickets" string. For Test / multi-innings
    // matches we join both innings with " & " (e.g. "226 & 145/3") and show
    // overs only for the latest innings so the card stays compact.
    String inningScore(Map<String, dynamic> inn) {
      final runs = apiInt(inn['runs']);
      if (runs == null) return '';
      final wickets = apiInt(inn['wickets']);
      // A fully bowled-out innings (10 wickets) is conventionally shown as the
      // run total only in the combined Test view, but we keep runs/wkts to stay
      // faithful to the backend; callers decide compactness.
      return wickets == null ? '$runs' : '$runs/$wickets';
    }

    final parts = <String>[];
    for (final raw in innings) {
      final s = inningScore(apiMap(raw));
      if (s.isNotEmpty) parts.add(s);
    }
    if (parts.isEmpty) return const _ScoreLine();

    final latest = apiMap(innings.last);
    final overs = apiString(latest['overs']);
    return _ScoreLine(score: parts.join(' & '), overs: overs);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final narrow = context.w < 390;
    final team1 = apiMap(detail['team1']);
    final team2 = apiMap(detail['team2']);
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

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: narrow ? 14 : 16,
        vertical: narrow ? 12 : 14,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
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
            color: c.cyan.withValues(alpha: .10),
            blurRadius: 22,
            spreadRadius: -6,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: .30),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(
                color: c.card.withValues(alpha: .5),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: badgeColor.withValues(alpha: .7)),
              ),
              child: Text(
                isLive ? 'LIVE CRICKET' : badge,
                style: TextStyle(
                  color: badgeColor,
                  fontWeight: FontWeight.w900,
                  fontSize: 11,
                  letterSpacing: .5,
                ),
              ),
            ),
          ),
          SizedBox(height: narrow ? 12 : 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: _TeamRow(
                  name: t1Name,
                  fullName: t1Full,
                  score: t1Score,
                  logoUrl: resolveCricbuzzImageUrl(team1),
                  isStriker:
                      apiString(liveLine['battingTeam']?.toString()) == t1Name,
                  logoLeading: true,
                ),
              ),
              _VsMedallion(narrow: narrow),
              Expanded(
                child: _TeamRow(
                  name: t2Name,
                  fullName: t2Full,
                  score: t2Score,
                  logoUrl: resolveCricbuzzImageUrl(team2),
                  isStriker:
                      apiString(liveLine['battingTeam']?.toString()) == t2Name,
                  logoLeading: false,
                ),
              ),
            ],
          ),
          SizedBox(height: narrow ? 10 : 12),
          Text(
            contextText,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: c.cyan,
              fontWeight: FontWeight.w800,
              fontSize: narrow ? 12 : 13,
              height: 1.25,
            ),
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

class _LiveBadge extends StatefulWidget {
  const _LiveBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  State<_LiveBadge> createState() => _LiveBadgeState();
}

class _LiveBadgeState extends State<_LiveBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  bool get _isLive => widget.label.toUpperCase() == 'LIVE';

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: widget.color,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: widget.color.withValues(alpha: .32),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isLive) ...[
            AnimatedBuilder(
              animation: _pulse,
              builder: (context, _) => Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color:
                      Colors.white.withValues(alpha: .65 + .35 * _pulse.value),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            widget.label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 11.5,
              letterSpacing: .4,
            ),
          ),
        ],
      ),
    );
  }
}

class _VsMedallion extends StatefulWidget {
  const _VsMedallion({required this.narrow});

  final bool narrow;

  @override
  State<_VsMedallion> createState() => _VsMedallionState();
}

class _VsMedallionState extends State<_VsMedallion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final narrow = widget.narrow;
    final size = narrow ? 40.0 : 46.0;
    return SizedBox(
      width: narrow ? 50 : 60,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Subtle vertical divider behind the medallion.
          Container(
            width: 1,
            height: 58,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  c.cyan.withValues(alpha: .35),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          // Pulsing cyan glow ring + dark premium center.
          AnimatedBuilder(
            animation: _pulse,
            builder: (context, _) {
              final t = _pulse.value; // 0..1
              return Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xff0b2238), Color(0xff071528)],
                  ),
                  border: Border.all(
                    color: c.cyan.withValues(alpha: .55 + .35 * t),
                    width: 1.6,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: c.cyan.withValues(alpha: .22 + .22 * t),
                      blurRadius: 12 + 8 * t,
                      spreadRadius: 1 + t,
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  'VS',
                  style: TextStyle(
                    color: c.cyan,
                    fontWeight: FontWeight.w900,
                    fontSize: narrow ? 12 : 13,
                    letterSpacing: .5,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _TeamRow extends StatelessWidget {
  const _TeamRow({
    required this.name,
    required this.fullName,
    required this.score,
    required this.logoUrl,
    required this.isStriker,
    required this.logoLeading,
  });

  final String name;
  final String fullName;
  final _ScoreLine score;
  final String? logoUrl;
  final bool isStriker;

  /// When true the logo sits on the left (team 1); when false on the right
  /// (team 2) so both teams mirror outward from the center VS, like the target.
  final bool logoLeading;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final hasScore = apiString(score.score).isNotEmpty;
    final overs = apiString(score.overs);

    final logo = TeamLogoWidget(
      logoUrl: logoUrl,
      teamName: fullName,
      abbreviation: name,
      color: isStriker ? c.cyan : const Color(0xfff59e0b),
      size: 46,
      borderColor: isStriker ? c.cyan : c.border.withValues(alpha: .6),
    );

    final info = Column(
      crossAxisAlignment:
          logoLeading ? CrossAxisAlignment.start : CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
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
        const SizedBox(height: 2),
        if (hasScore) ...[
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment:
                logoLeading ? Alignment.centerLeft : Alignment.centerRight,
            child: Text(
              apiString(score.score),
              maxLines: 1,
              style: TextStyle(
                color: isStriker ? c.cyan : Colors.white.withValues(alpha: .95),
                fontWeight: FontWeight.w900,
                fontSize: 19,
              ),
            ),
          ),
          if (overs.isNotEmpty)
            Text(
              '($overs)',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.muted,
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
            ),
        ] else
          Container(
            margin: const EdgeInsets.only(top: 4),
            width: 14,
            height: 4,
            decoration: BoxDecoration(
              color: c.border,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
      ],
    );

    final children = logoLeading
        ? [logo, const SizedBox(width: 10), Flexible(child: info)]
        : [Flexible(child: info), const SizedBox(width: 10), logo];

    return Row(
      mainAxisAlignment:
          logoLeading ? MainAxisAlignment.start : MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: children,
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
    required this.videoFit,
    required this.viewers,
    required this.onRetry,
    required this.onFullscreen,
    required this.onSettings,
    required this.onToggleMute,
    required this.onShare,
    required this.onComments,
    required this.onStats,
    required this.onSeekBackward,
    required this.onSeekForward,
  });

  final StreamSource? stream;
  final VideoPlayerController? controller;
  final Future<void>? initFuture;
  final String? error;
  final HlsQuality? selectedQuality;
  final bool isMuted;
  final bool isLiveContent;
  final BoxFit videoFit;
  final String? viewers;
  final VoidCallback? onRetry;
  final VoidCallback onFullscreen;
  final VoidCallback onSettings;
  final VoidCallback onToggleMute;
  final VoidCallback onShare;
  final VoidCallback onComments;
  final VoidCallback onStats;
  final VoidCallback onSeekBackward;
  final VoidCallback onSeekForward;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final hasStream = stream != null && stream!.url.isNotEmpty;
    final initialized = controller?.value.isInitialized == true;
    final playing = controller?.value.isPlaying == true;
    return PremiumCard(
      padding: EdgeInsets.zero,
      radius: 18,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (initialized)
                _VideoContent(controller: controller!, fit: videoFit)
              else
                Image.asset(
                  'assets/images/live_stream/backgrounds/stadium_player_background_clean_16x9.png',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Image.asset(
                    'assets/images/stadium_live.png',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        Container(color: Colors.black),
                  ),
                ),
              // Cinematic vignette over the poster/video.
              Positioned.fill(
                child: IgnorePointer(
                  child: Image.asset(
                    'assets/images/live_stream/overlays/video_vignette_overlay_16x9.png',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: initialized ? .28 : .35),
                      Colors.black.withValues(alpha: initialized ? .12 : .45),
                      Colors.black.withValues(alpha: initialized ? .5 : .78),
                    ],
                    stops: const [0.0, 0.45, 1.0],
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
                  child: SizedBox(
                    width: 92,
                    height: 92,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Image.asset(
                          'assets/images/live_stream/overlays/neon_play_button.png',
                          width: 92,
                          height: 92,
                          errorBuilder: (_, __, ___) => Container(
                            width: 84,
                            height: 84,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black.withValues(alpha: .42),
                              border: Border.all(
                                  color: c.cyan.withValues(alpha: .7),
                                  width: 1.6),
                              boxShadow: [
                                BoxShadow(
                                  color: c.cyan.withValues(alpha: .35),
                                  blurRadius: 24,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                          ),
                        ),
                        hasStream
                            ? SvgPicture.asset(
                                'assets/images/live_stream/icons/ic_play_cyan.svg',
                                width: 34,
                                height: 34,
                                colorFilter:
                                    ColorFilter.mode(c.cyan, BlendMode.srcIn),
                                placeholderBuilder: (_) => Icon(
                                    Icons.play_arrow_rounded,
                                    color: c.cyan,
                                    size: 38),
                              )
                            : Icon(Icons.live_tv_rounded,
                                color: Colors.white.withValues(alpha: .65),
                                size: 34),
                      ],
                    ),
                  ),
                ),
              if (error != null) _PlayerErrorOverlay(onRetry: onRetry),
              // Top-left: CricPro branding + LIVE pill (target layout).
              Positioned(
                left: 14,
                top: 12,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.play_circle_fill_rounded,
                            color: c.cyan, size: 20),
                        const SizedBox(width: 6),
                        const CricLogo(size: 16),
                      ],
                    ),
                    if (isLiveContent) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 5),
                        decoration: BoxDecoration(
                          color: c.live,
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: [
                            BoxShadow(
                              color: c.live.withValues(alpha: .45),
                              blurRadius: 12,
                              spreadRadius: -2,
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 6,
                              height: 6,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                            SizedBox(width: 5),
                            Text(
                              'LIVE',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 10.5,
                                letterSpacing: .4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Top-right: viewers pill (when available) + quality pill.
              Positioned(
                right: 12,
                top: 10,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (viewers != null && viewers!.isNotEmpty) ...[
                      _PlayerPill(
                        label: viewers!,
                        color: c.card2.withValues(alpha: .72),
                        svgIcon:
                            'assets/images/live_stream/icons/ic_eye_white.svg',
                      ),
                      const SizedBox(width: 8),
                    ],
                    _PlayerPill(
                      label: selectedQuality?.code.toUpperCase() ??
                          (stream?.qualityCode.toUpperCase() ?? 'HD'),
                      color: c.card2.withValues(alpha: .72),
                      svgIcon:
                          'assets/images/live_stream/icons/ic_signal_cyan.svg',
                    ),
                  ],
                ),
              ),
              if (initialized && !playing)
                Positioned.fill(
                  child: Center(
                    child: GestureDetector(
                      onTap: controller!.play,
                      child: SizedBox(
                        width: 88,
                        height: 88,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Image.asset(
                              'assets/images/live_stream/overlays/neon_play_button.png',
                              width: 88,
                              height: 88,
                              errorBuilder: (_, __, ___) => Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.black.withValues(alpha: .42),
                                  border: Border.all(
                                      color: c.cyan.withValues(alpha: .6),
                                      width: 1.6),
                                  boxShadow: [
                                    BoxShadow(
                                      color: c.cyan.withValues(alpha: .35),
                                      blurRadius: 22,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            SvgPicture.asset(
                              'assets/images/live_stream/icons/ic_play_cyan.svg',
                              width: 30,
                              height: 30,
                              colorFilter:
                                  ColorFilter.mode(c.cyan, BlendMode.srcIn),
                              placeholderBuilder: (_) => Icon(
                                  Icons.play_arrow_rounded,
                                  color: c.cyan,
                                  size: 36),
                            ),
                          ],
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
                    isMuted: isMuted,
                    onToggleMute: onToggleMute,
                    onSettings: onSettings,
                    onFullscreen: onFullscreen,
                    onSeekBackward: onSeekBackward,
                    onSeekForward: onSeekForward,
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
    this.icon,
    this.svgIcon,
  });

  final String label;
  final Color color;
  final IconData? icon;
  final String? svgIcon;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.cyan.withValues(alpha: .3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (svgIcon != null)
            SvgPicture.asset(
              svgIcon!,
              width: 12,
              height: 12,
              colorFilter: ColorFilter.mode(c.cyan, BlendMode.srcIn),
              placeholderBuilder: (_) => Icon(Icons.signal_cellular_alt_rounded,
                  color: c.cyan, size: 11),
            )
          else if (icon != null)
            Icon(icon, color: Colors.white, size: 10),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
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

class _PortraitPlayerControls extends StatelessWidget {
  const _PortraitPlayerControls({
    required this.controller,
    required this.playing,
    required this.isLiveContent,
    required this.isMuted,
    required this.onToggleMute,
    required this.onSettings,
    required this.onFullscreen,
    required this.onSeekBackward,
    required this.onSeekForward,
    this.fullscreenIcon = Icons.fullscreen_rounded,
  });

  final VideoPlayerController controller;
  final bool playing;
  final bool isLiveContent;
  final bool isMuted;
  final VoidCallback onToggleMute;
  final VoidCallback onSettings;
  final VoidCallback onFullscreen;
  final VoidCallback onSeekBackward;
  final VoidCallback onSeekForward;
  final IconData fullscreenIcon;

  static String _fmtTime(Duration d) {
    final s = d.inSeconds;
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = sec.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    const base = 'assets/images/live_stream/icons';
    final c = context.cric;
    final pos = controller.value.position;
    final dur = controller.value.duration;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Progress line + time labels.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: VideoProgressIndicator(
                  controller,
                  allowScrubbing: !isLiveContent,
                  padding: EdgeInsets.zero,
                  colors: VideoProgressColors(
                    playedColor: c.cyan,
                    bufferedColor: Colors.white24,
                    backgroundColor: Colors.white.withValues(alpha: .14),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(
                    _fmtTime(pos),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .9),
                      fontWeight: FontWeight.w700,
                      fontSize: 11.5,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    dur == Duration.zero ? 'LIVE' : _fmtTime(dur),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .9),
                      fontWeight: FontWeight.w700,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        // Long glass control bar.
        Container(
          height: 50,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .58),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: .1)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .3),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              _ctrl(
                context,
                svg: playing ? '$base/ic_pause_white.svg' : null,
                fallback:
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                onTap: () => playing ? controller.pause() : controller.play(),
              ),
              _divider(c),
              _ctrl(
                context,
                svg: '$base/ic_rewind_white.svg',
                fallback: Icons.replay_10_rounded,
                onTap: onSeekBackward,
              ),
              _divider(c),
              _ctrl(
                context,
                svg: '$base/ic_forward_white.svg',
                fallback: Icons.forward_10_rounded,
                onTap: onSeekForward,
              ),
              _divider(c),
              _ctrl(
                context,
                svg: '$base/ic_volume_white.svg',
                fallback: isMuted
                    ? Icons.volume_off_rounded
                    : Icons.volume_up_rounded,
                onTap: onToggleMute,
              ),
              _divider(c),
              _ctrl(
                context,
                svg: '$base/ic_settings_white.svg',
                fallback: Icons.settings_rounded,
                onTap: onSettings,
              ),
              _divider(c),
              _ctrl(
                context,
                svg: '$base/ic_fullscreen_white.svg',
                fallback: fullscreenIcon,
                onTap: onFullscreen,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _divider(CricColors c) => Container(
        width: 1,
        height: 22,
        color: Colors.white.withValues(alpha: .12),
      );

  Widget _ctrl(
    BuildContext context, {
    String? svg,
    required IconData fallback,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 50,
          child: Center(
            child: svg != null
                ? SvgPicture.asset(
                    svg,
                    width: 20,
                    height: 20,
                    colorFilter:
                        const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                    placeholderBuilder: (_) =>
                        Icon(fallback, color: Colors.white, size: 20),
                  )
                : Icon(fallback, color: Colors.white, size: 22),
          ),
        ),
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
    required this.onAutoSelect,
    required this.onStreamsLoaded,
    required this.qualityOptions,
    required this.selectedQuality,
    required this.onSelectQuality,
  });

  final String matchId;
  final Future<ApiEnvelope<Map<String, dynamic>>>? streamsFuture;
  final Future<ApiEnvelope<Map<String, dynamic>>>? appConfigFuture;
  final String? selectedId;
  final ValueChanged<StreamSource> onAutoSelect;
  final ValueChanged<List<StreamSource>> onStreamsLoaded;
  final List<HlsQuality> qualityOptions;
  final HlsQuality? selectedQuality;
  final ValueChanged<HlsQuality> onSelectQuality;

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

        // Auto-select highest priority stream once available
        if (selectedId == null) {
          WidgetsBinding.instance
              .addPostFrameCallback((_) => onAutoSelect(selected));
        }

        // Build the three fixed quality tiers (Full HD / HD / SD).
        final tiers = _buildQualityTiers(qualityOptions);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.card.withValues(alpha: .55),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: c.cyan.withValues(alpha: .35)),
                  ),
                  child: SvgPicture.asset(
                    'assets/images/live_stream/icons/ic_bars_cyan.svg',
                    width: 16,
                    height: 16,
                    colorFilter: ColorFilter.mode(c.cyan, BlendMode.srcIn),
                    placeholderBuilder: (_) =>
                        Icon(Icons.bar_chart_rounded, color: c.cyan, size: 16),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Stream Quality',
                  style: TextStyle(
                    color: c.text,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    letterSpacing: .2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final spacing = constraints.maxWidth < 360 ? 8.0 : 12.0;
                final cardWidth = (constraints.maxWidth - spacing * 2) / 3;
                // Below ~96px per card the 3-up row is too cramped; fall back
                // to a horizontal scroller with a sensible minimum card width.
                final useScroll = cardWidth < 96;

                Widget card(int i) => _QualityTierCard(
                      tier: tiers[i],
                      selected: _isTierSelected(tiers[i], selectedQuality),
                      onTap: tiers[i].quality == null
                          ? null
                          : () => onSelectQuality(tiers[i].quality!),
                    );

                if (useScroll) {
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var i = 0; i < tiers.length; i++) ...[
                            SizedBox(width: 120, child: card(i)),
                            if (i != tiers.length - 1) SizedBox(width: spacing),
                          ],
                        ],
                      ),
                    ),
                  );
                }

                // IntrinsicHeight bounds the Row's cross axis so the cards
                // stretch to equal height instead of collapsing inside the
                // unbounded ListView.
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < tiers.length; i++) ...[
                        Expanded(child: card(i)),
                        if (i != tiers.length - 1) SizedBox(width: spacing),
                      ],
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 18),
            const _CompactStreamStatus(),
          ],
        );
      },
    );
  }

  /// Maps available variants into the three fixed display tiers. Each tier maps
  /// directly to its own bucket; a tier with no matching variant renders
  /// disabled/unavailable so the premium 3-card layout is always preserved.
  ///
  /// Variant codes (from the parsed playlist): FHD(720p+), HD(480p),
  /// SD(240p/360p), AUTO(adaptive).
  ///   Full HD ← FHD (e.g. 720p)
  ///   HD      ← HD  (480p)
  ///   SD      ← SD  (240p / 360p)
  static List<_QualityTier> _buildQualityTiers(List<HlsQuality> options) {
    HlsQuality? byCode(String code) =>
        options.where((q) => q.code == code).firstOrNull;

    final fhd = byCode('FHD');
    final hd = byCode('HD');
    final sd = byCode('SD');

    return [
      _QualityTier(
        title: 'Full HD',
        badge: 'FHD',
        resolution: fhd?.resolution ?? '720p',
        subtitle: 'Best Experience',
        quality: fhd,
      ),
      _QualityTier(
        title: 'HD',
        badge: 'HD',
        resolution: hd?.resolution ?? '480p',
        subtitle: 'Good Quality',
        quality: hd,
      ),
      _QualityTier(
        title: 'SD',
        badge: 'SD',
        resolution: sd?.resolution ?? '360p',
        subtitle: 'Data Saver',
        quality: sd,
      ),
    ];
  }

  static bool _isTierSelected(_QualityTier tier, HlsQuality? selected) {
    final q = tier.quality;
    if (q == null || selected == null) return false;
    return q.url == selected.url && q.code == selected.code;
  }
}

/// A single resolved quality tier for the Full HD / HD / SD cards. [quality]
/// is null when no matching variant exists (card renders disabled).
class _QualityTier {
  const _QualityTier({
    required this.title,
    required this.badge,
    required this.resolution,
    required this.subtitle,
    required this.quality,
  });

  final String title;
  final String badge;
  final String resolution;
  final String subtitle;
  final HlsQuality? quality;

  bool get available => quality != null;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class _QualityTierCard extends StatelessWidget {
  const _QualityTierCard({
    required this.tier,
    required this.selected,
    required this.onTap,
  });

  final _QualityTier tier;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final available = tier.available;
    final disabled = !available;

    final borderColor = selected
        ? c.cyan
        : disabled
            ? c.border.withValues(alpha: .35)
            : c.border.withValues(alpha: .7);

    return Opacity(
      opacity: disabled ? .55 : 1,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: selected
                  ? [
                      c.cyan.withValues(alpha: .12),
                      const Color(0xff0b2b4a).withValues(alpha: .85),
                    ]
                  : [
                      c.card2.withValues(alpha: .55),
                      c.card.withValues(alpha: .9),
                    ],
            ),
            border: Border.all(color: borderColor, width: selected ? 1.6 : 1.1),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: c.cyan.withValues(alpha: .22),
                      blurRadius: 16,
                      spreadRadius: -6,
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: selected ? c.cyan : c.card2,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color:
                            selected ? c.cyan : c.border.withValues(alpha: .8),
                      ),
                    ),
                    child: Text(
                      tier.badge,
                      style: TextStyle(
                        color: selected ? Colors.black : c.text,
                        fontWeight: FontWeight.w900,
                        fontSize: 9,
                        letterSpacing: .2,
                      ),
                    ),
                  ),
                  const Spacer(),
                  selected
                      ? SvgPicture.asset(
                          'assets/images/live_stream/icons/ic_check_circle_cyan.svg',
                          width: 16,
                          height: 16,
                          colorFilter:
                              ColorFilter.mode(c.cyan, BlendMode.srcIn),
                          placeholderBuilder: (_) => Icon(
                              Icons.check_circle_rounded,
                              color: c.cyan,
                              size: 15),
                        )
                      : SvgPicture.asset(
                          'assets/images/live_stream/icons/ic_radio_circle_cyan.svg',
                          width: 16,
                          height: 16,
                          colorFilter: ColorFilter.mode(
                              c.muted.withValues(alpha: .7), BlendMode.srcIn),
                          placeholderBuilder: (_) => Icon(
                              Icons.radio_button_unchecked_rounded,
                              color: c.muted.withValues(alpha: .7),
                              size: 15),
                        ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                tier.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: c.text,
                  fontWeight: FontWeight.w900,
                  fontSize: 13.5,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                disabled ? 'N/A' : tier.resolution,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? c.cyan : c.muted,
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: disabled
                        ? Icon(Icons.block_rounded, color: c.muted, size: 11)
                        : SvgPicture.asset(
                            'assets/images/live_stream/icons/ic_diamond_outline.svg',
                            width: 11,
                            height: 11,
                            colorFilter: ColorFilter.mode(
                                selected ? c.cyan : c.muted, BlendMode.srcIn),
                            placeholderBuilder: (_) => Icon(
                                Icons.diamond_outlined,
                                color: selected ? c.cyan : c.muted,
                                size: 11),
                          ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      disabled ? 'Unavailable' : tier.subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.muted,
                        fontWeight: FontWeight.w600,
                        fontSize: 9.5,
                        height: 1.15,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Premium trust strip used below the real quality/server controls.
class _CompactStreamStatus extends StatelessWidget {
  const _CompactStreamStatus();

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    const base = 'assets/images/live_stream';
    const items = [
      _FeatureItemData(
        svg: '$base/icons/ic_lightning_cyan.svg',
        title: 'Low Latency',
        subtitle: 'Live at real speed',
      ),
      _FeatureItemData(
        svg: '$base/icons/ic_signal_cyan.svg',
        title: 'Adaptive Streaming',
        subtitle: 'Smooth on any network',
      ),
      _FeatureItemData(
        svg: '$base/icons/ic_lock_cyan.svg',
        title: 'Secure Stream',
        subtitle: 'Protected & Encrypted',
      ),
      _FeatureItemData(
        svg: '$base/icons/ic_monitor_pulse_cyan.svg',
        title: 'Stable Playback',
        subtitle: 'No buffering experience',
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Feature strip — 4 equal items + dividers over the glass overlay.
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: c.card2.withValues(alpha: .4),
            border: Border.all(color: c.cyan.withValues(alpha: .2)),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: Image.asset(
                  '$base/overlays/feature_strip_glass.png',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    for (var i = 0; i < items.length; i++) ...[
                      Expanded(child: _StreamFeatureChip(data: items[i])),
                      if (i != items.length - 1)
                        Container(
                          width: 1,
                          height: 38,
                          color: c.cyan.withValues(alpha: .18),
                        ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Secure & encrypted info card.
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: c.card.withValues(alpha: .55),
            border: Border.all(color: c.cyan.withValues(alpha: .24)),
            boxShadow: [
              BoxShadow(
                color: c.cyan.withValues(alpha: .08),
                blurRadius: 18,
                spreadRadius: -8,
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: Image.asset(
                  '$base/overlays/secure_info_card_glass.png',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    SizedBox(
                      width: 44,
                      height: 44,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Image.asset(
                            '$base/overlays/blue_icon_badge_glow.png',
                            width: 44,
                            height: 44,
                            errorBuilder: (_, __, ___) => Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: c.primaryGradient,
                              ),
                            ),
                          ),
                          SvgPicture.asset(
                            '$base/icons/ic_shield_lock_cyan.svg',
                            width: 22,
                            height: 22,
                            colorFilter:
                                ColorFilter.mode(c.cyan, BlendMode.srcIn),
                            placeholderBuilder: (_) => const Icon(
                                Icons.lock_rounded,
                                color: Colors.white,
                                size: 20),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'This is a secure & encrypted stream',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: c.text,
                              fontWeight: FontWeight.w900,
                              fontSize: 13.5,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Your privacy and data are protected.',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: c.muted,
                              fontWeight: FontWeight.w600,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    SvgPicture.asset(
                      '$base/icons/ic_chevron_right.svg',
                      width: 18,
                      height: 18,
                      colorFilter: ColorFilter.mode(
                          c.muted.withValues(alpha: .9), BlendMode.srcIn),
                      placeholderBuilder: (_) => Icon(
                          Icons.chevron_right_rounded,
                          color: c.muted,
                          size: 20),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FeatureItemData {
  const _FeatureItemData({
    required this.svg,
    required this.title,
    required this.subtitle,
  });

  final String svg;
  final String title;
  final String subtitle;
}

class _StreamFeatureChip extends StatelessWidget {
  const _StreamFeatureChip({required this.data});

  final _FeatureItemData data;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SvgPicture.asset(
            data.svg,
            width: 19,
            height: 19,
            colorFilter: ColorFilter.mode(c.cyan, BlendMode.srcIn),
            placeholderBuilder: (_) =>
                Icon(Icons.bolt_rounded, color: c.cyan, size: 18),
          ),
          const SizedBox(height: 6),
          Text(
            data.title,
            maxLines: 2,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: c.text,
              fontWeight: FontWeight.w800,
              fontSize: 10,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            data.subtitle,
            maxLines: 2,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: c.muted,
              fontWeight: FontWeight.w600,
              fontSize: 9,
              height: 1.1,
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
    required this.isMuted,
    required this.onQualitySelected,
    required this.onFitChanged,
    required this.onGoLive,
    required this.onToggleMute,
    required this.onSeekBackward,
    required this.onSeekForward,
  });

  final VideoPlayerController controller;
  final StreamSource stream;
  final List<HlsQuality> qualities;
  final HlsQuality? selectedQuality;
  final BoxFit videoFit;
  final bool isLiveContent;
  final bool isMuted;
  final ValueChanged<HlsQuality> onQualitySelected;
  final ValueChanged<BoxFit> onFitChanged;
  final VoidCallback onGoLive;
  final VoidCallback onToggleMute;
  final VoidCallback onSeekBackward;
  final VoidCallback onSeekForward;

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
                    child:
                        _VideoContent(controller: widget.controller, fit: _fit),
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
                                  child: _FullscreenIconButton(
                                    icon: _fitIcon(_fit),
                                    onTap: _cycleFit,
                                  ),
                                ),
                                // Center play/pause with cyan glow (same style
                                // as the portrait player).
                                Center(
                                  child: GestureDetector(
                                    onTap: () {
                                      value.isPlaying
                                          ? widget.controller.pause()
                                          : widget.controller.play();
                                      _scheduleHideControls();
                                    },
                                    child: Container(
                                      width: 66,
                                      height: 66,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color:
                                            Colors.black.withValues(alpha: .42),
                                        border: Border.all(
                                          color: c.cyan.withValues(alpha: .55),
                                          width: 1.5,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color:
                                                c.cyan.withValues(alpha: .25),
                                            blurRadius: 18,
                                            spreadRadius: 1,
                                          ),
                                        ],
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
                                // Bottom-left LIVE badge.
                                if (widget.isLiveContent)
                                  Positioned(
                                    left: 16,
                                    bottom: 84,
                                    child: _PlayerPill(
                                      label: 'LIVE',
                                      color: value.isPlaying ? c.live : c.card2,
                                      icon: Icons.circle,
                                    ),
                                  ),
                                // Bottom glass control bar — same design as
                                // the portrait player, adapted to landscape.
                                Positioned(
                                  left: 16,
                                  right: 16,
                                  bottom: 14,
                                  child: _PortraitPlayerControls(
                                    controller: widget.controller,
                                    playing: value.isPlaying,
                                    isLiveContent: widget.isLiveContent,
                                    isMuted: widget.isMuted,
                                    onToggleMute: widget.onToggleMute,
                                    onSettings: _openQuality,
                                    onFullscreen: _exit,
                                    onSeekBackward: widget.onSeekBackward,
                                    onSeekForward: widget.onSeekForward,
                                    fullscreenIcon:
                                        Icons.fullscreen_exit_rounded,
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

/// Simple info bottom sheet used for "Live Commentary" (coming soon) and other
/// short messages. Keeps the premium dark/cyan style with no overflow.
class _InfoSheet extends StatelessWidget {
  const _InfoSheet({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xff0a1929).withValues(alpha: .98),
              const Color(0xff0f2744).withValues(alpha: .98),
            ],
          ),
          border: Border.all(color: c.cyan.withValues(alpha: .35)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: c.primaryGradient,
                boxShadow: [
                  BoxShadow(
                    color: c.cyan.withValues(alpha: .34),
                    blurRadius: 18,
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 26),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: c.text,
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: c.muted,
                fontWeight: FontWeight.w600,
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Live match stats bottom sheet. Surfaces the score/status data already
/// fetched for the match. Falls back gracefully when fields are missing.
class _StatsSheet extends StatelessWidget {
  const _StatsSheet({required this.detail, required this.liveLine});

  final Map<String, dynamic> detail;
  final Map<String, dynamic>? liveLine;

  String _teamLabel(Map<String, dynamic> team) {
    return apiString(
      team['short_name'] ?? team['shortName'] ?? team['name'],
      'TBD',
    );
  }

  String _teamScore(Map<String, dynamic> team) {
    final innings = apiList(team['innings']);
    if (innings.isEmpty) return '—';
    final first = apiMap(innings.first);
    final runs = apiInt(first['runs']);
    if (runs == null) return '—';
    final wickets = apiInt(first['wickets']);
    final overs = apiString(first['overs']);
    final score = wickets == null ? '$runs' : '$runs/$wickets';
    return overs.isEmpty ? score : '$score ($overs)';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final team1 = apiMap(detail['team1']);
    final team2 = apiMap(detail['team2']);
    final status = apiString(
      detail['status_text'] ??
          liveLine?['statusText'] ??
          liveLine?['status'] ??
          detail['status'],
      'Match details will update shortly.',
    );
    final rows = <List<String>>[
      [_teamLabel(team1), _teamScore(team1)],
      [_teamLabel(team2), _teamScore(team2)],
    ];

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(16),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .7,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xff0a1929).withValues(alpha: .98),
              const Color(0xff0f2744).withValues(alpha: .98),
            ],
          ),
          border: Border.all(color: c.cyan.withValues(alpha: .35)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
              child: Row(
                children: [
                  Icon(Icons.bar_chart_rounded, color: c.cyan, size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Match Stats',
                      style: TextStyle(
                        color: c.text,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
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
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final row in rows) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: c.card2.withValues(alpha: .42),
                          borderRadius: BorderRadius.circular(14),
                          border:
                              Border.all(color: c.border.withValues(alpha: .3)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                row[0],
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: c.text,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              row[1],
                              style: TextStyle(
                                color: c.cyan,
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      status,
                      style: TextStyle(
                        color: c.muted,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
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
    // Compact sheet — never covers most of the screen.
    final maxHeight = screen.height * (landscape ? .8 : .55);
    final maxWidth = landscape ? screen.width * .5 : double.infinity;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: maxHeight,
          maxWidth: maxWidth,
          minWidth: landscape ? 320 : 0,
        ),
        child: Container(
          margin: EdgeInsets.all(landscape ? 0 : 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xff0a1929).withValues(alpha: .99),
                const Color(0xff0f2744).withValues(alpha: .99),
              ],
            ),
            border: Border.all(color: c.cyan.withValues(alpha: .3)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .55),
                blurRadius: 28,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Compact header: icon + "Quality" + close.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 10),
                child: Row(
                  children: [
                    Icon(Icons.settings_rounded, color: c.cyan, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Quality',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.text,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () => Navigator.pop(context),
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child:
                            Icon(Icons.close_rounded, color: c.muted, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
              Divider(color: c.border.withValues(alpha: .3), height: 1),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                  itemCount: qualities.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final quality = qualities[index];
                    return _QualityOption(
                      quality: quality,
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
  });

  final HlsQuality quality;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? c.cyan.withValues(alpha: .1) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? c.cyan.withValues(alpha: .7) : Colors.transparent,
            width: 1.2,
          ),
        ),
        child: Row(
          children: [
            // Small badge pill (AUTO/FHD/HD/SD).
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: selected ? c.cyan : c.card2,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                quality.code,
                style: TextStyle(
                  color: selected ? Colors.black : c.muted,
                  fontWeight: FontWeight.w900,
                  fontSize: 9,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Row(
                children: [
                  Text(
                    quality.label,
                    style: TextStyle(
                      color: c.text,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    quality.resolution,
                    style: TextStyle(
                      color: selected ? c.cyan : c.muted,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected ? c.cyan : c.muted.withValues(alpha: .6),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}
