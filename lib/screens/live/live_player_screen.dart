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
import 'package:cricpro_flutter/models/cricket_match.dart';
import 'package:cricpro_flutter/widgets/remote_or_local_image.dart';
import 'package:cricpro_flutter/models/ad_config.dart';
import 'package:cricpro_flutter/models/api_response.dart';
import 'package:cricpro_flutter/repositories/cricket_repository.dart';
import 'package:cricpro_flutter/services/analytics_service.dart';
import 'package:cricpro_flutter/services/ad_service.dart';
import 'package:cricpro_flutter/services/ads/ads_manager.dart';
import 'package:cricpro_flutter/services/ads/pre_roll_gate.dart';
import 'package:cricpro_flutter/widgets/ads/banner_ad_widget.dart';

part 'widgets/live_player_info.dart';
part 'widgets/live_player_surface.dart';
part 'widgets/live_player_streams.dart';
part 'widgets/live_player_sheets.dart';

class LivePlayerScreen extends StatefulWidget {
  const LivePlayerScreen({
    super.key,
    this.matchId = '',
    this.openingId,
  });

  final String matchId;

  /// Identifies the single logical "opening" (one Watch Live tap or one deep
  /// link) this player belongs to. The central launcher registers it with
  /// [PreRollGate] and may run the entry pre-roll; the player asks the gate
  /// whether the initial pre-roll for this opening was already attempted, so a
  /// second pre-roll is NEVER shown for the same opening. Null when the player
  /// was opened by a path that did not register an opening (the player then
  /// owns the initial pre-roll itself).
  final int? openingId;

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
  List<HlsQuality> _hlsAllVariants = []; // all raw variants, pre-dedup
  HlsQuality? _selectedQuality;
  bool _isMuted = false;
  bool _isLiveContent = true;
  BoxFit _videoFit = BoxFit.contain;

  // Portrait player controls auto-hide. The controls overlay shows on tap and
  // hides after ~3s of inactivity, mirroring the fullscreen page behaviour.
  // `_portraitMenuOpen` pins the controls visible while a modal (quality
  // selector) is up so they don't vanish under an open menu.
  bool _portraitControlsVisible = true;
  bool _portraitMenuOpen = false;
  Timer? _portraitHideTimer;
  List<StreamSource> _availableStreams = const [];
  final Set<String> _rewardUnlockedStreamIds = <String>{};

  /// True once the in-player pre-roll has been skipped for the first
  /// auto-selected stream because the central Watch Live launcher already
  /// showed the entry ad (prevents two ads per Watch Live tap).
  bool _initialPreRollConsumed = false;

  /// One-shot guard for the gate-complete → video-start continuation. The path
  /// that opens the stream after the pre-roll gate finishes must run exactly
  /// once; duplicate ad callbacks, rebuilds, live-poll timers, or lifecycle
  /// resume must never trigger a second video init or a second pre-roll.
  bool _hasContinuedToStream = false;

  /// The gate opening id this player belongs to. Uses the one passed from the
  /// launcher, or registers its own when opened by a path that did not (e.g. a
  /// deep link). Resolved lazily so it survives rebuilds.
  int? _openingId;
  int get _resolvedOpeningId =>
      _openingId ??= (widget.openingId ?? PreRollGate.instance.newOpening(widget.matchId));

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

    // When the video first becomes initialized the portrait controls appear;
    // arm the auto-hide so they fade after 3s without a tap. Also covers a
    // stream reload/quality change that re-initializes the controller.
    final justInitialized = value.isInitialized && !_lastInitialized;

    _lastInitialized = value.isInitialized;
    _lastIsPlaying = value.isPlaying;
    _lastBuffering = value.isBuffering;
    _lastHasError = value.hasError;
    _lastPositionSec = positionSec;
    _lastDurationSec = durationSec;
    setState(() {});
    if (justInitialized) {
      _portraitControlsVisible = true;
      _schedulePortraitHide();
    }
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

  // ── Portrait controls auto-hide ──────────────────────────────────────────

  /// (Re)starts the 3s inactivity timer that hides the portrait controls.
  /// Cancels any existing timer first so only one ever runs. While a menu
  /// (quality selector) is open the controls stay pinned, so no hide is armed.
  void _schedulePortraitHide() {
    _portraitHideTimer?.cancel();
    _portraitHideTimer = null;
    if (_portraitMenuOpen) return;
    _portraitHideTimer = Timer(const Duration(seconds: 3), () {
      _portraitHideTimer = null;
      if (!mounted || _portraitMenuOpen) return;
      setState(() => _portraitControlsVisible = false);
    });
  }

  /// Tap on the video surface toggles the controls. Showing them re-arms the
  /// auto-hide; hiding them clears the timer.
  void _togglePortraitControls() {
    setState(() => _portraitControlsVisible = !_portraitControlsVisible);
    if (_portraitControlsVisible) {
      _schedulePortraitHide();
    } else {
      _portraitHideTimer?.cancel();
      _portraitHideTimer = null;
    }
  }

  /// Called after the user presses a control (play/pause, seek, mute, fit, …):
  /// keep the controls visible and restart the inactivity countdown.
  void _bumpPortraitControls() {
    if (!_portraitControlsVisible) {
      setState(() => _portraitControlsVisible = true);
    }
    _schedulePortraitHide();
  }

  @override
  void initState() {
    super.initState();
    _appConfigFuture = _repository.appConfig();
    if (_hasMatchId) {
      // Live player opened for a match. Fires once per screen open.
      PreRollGate.instance.log(
        'LIVE_PLAYER_CREATED',
        matchId: widget.matchId,
        attemptId: _resolvedOpeningId,
        source: 'live_player',
        sessionCount: AdsManager.instance.preRollShownThisSession,
        perMatchCount: PreRollGate.instance.shownForMatch(widget.matchId),
        videoInit: false,
        isPlaying: false,
      );
      AnalyticsService.instance.track('live_stream_open', {'match_id': widget.matchId});
      AnalyticsService.instance.screenView('live_player');
      _detailFuture = _loadMatchDetail();
      _liveLineFuture = _repository.matchLiveLine(widget.matchId);
      _liveLineFuture!.then((response) => _liveLineData = response.data);
      _streamsFuture = _repository.matchStreams(widget.matchId);
    }
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    _portraitHideTimer?.cancel();
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
    // One-shot continuation: the initial gate-complete → video-start path runs
    // exactly once. A duplicate auto-select from a rebuild/timer/resume that
    // slipped past `_autoSelectAttempted` must never run a second pre-roll or a
    // second video init.
    if (_hasContinuedToStream) {
      PreRollGate.instance.log(
        'DUPLICATE_PRE_ROLL_BLOCKED',
        matchId: widget.matchId,
        streamKey: _streamKey(stream),
        attemptId: _resolvedOpeningId,
        source: 'live_player',
        videoInit: _videoController?.value.isInitialized ?? false,
        isPlaying: _videoController?.value.isPlaying ?? false,
      );
      return;
    }

    final gate = _resolvePreRoll(stream);
    final required = stream.isPremium && stream.requiresRewardAd;
    if (gate != StreamPreRollAdType.none) {
      _streamAdInProgress = true;
      bool proceed;
      try {
        proceed = await _runPreRollGate(
          stream: stream,
          gate: gate,
          required: required,
          reason: 'initial',
        );
      } finally {
        _streamAdInProgress = false;
      }
      // Only a REQUIRED premium unlock can block playback. Every normal
      // pre-roll returns true regardless of ad outcome (fail-open).
      if (!proceed) return;
    }

    // The pre-roll gate is now final for this opening. Mark the continuation
    // consumed so nothing repeats it, then start the stream.
    _hasContinuedToStream = true;

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

  /// Runs the eligible pre-roll for [reason] and reports whether playback may
  /// proceed. Fail-open by contract:
  ///
  /// * Session-capped / min-interval not elapsed → skip ad, return true.
  /// * Ad load/show fails, no-fill, throws, or TIMES OUT → return true
  ///   (unless [required] premium unlock, which returns false so the stream
  ///   stays gated).
  /// * Ad shows and is dismissed/earned → return true (and records the premium
  ///   unlock when [required]).
  ///
  /// The single `_streamAdInProgress` guard owned by the callers serializes
  /// this, so one user action = one pre-roll attempt = one stream start.
  Future<bool> _runPreRollGate({
    required StreamSource stream,
    required StreamPreRollAdType gate,
    required bool required,
    required String reason,
  }) async {
    final isInitial = reason == 'initial';
    final streamKey = _streamKey(stream);
    // Take the global pre-roll lock. If an attempt is already running anywhere
    // (entry launcher OR another player path), do NOT start a second one — the
    // lock is held for the WHOLE attempt, so this also blocks a new attempt
    // that tries to begin right after a previous ad was dismissed.
    if (!PreRollGate.instance.beginAttempt()) {
      PreRollGate.instance.log(
        'LIVE_PLAYER_INITIAL_PRE_ROLL_BLOCKED_ALREADY_HANDLED',
        matchId: widget.matchId,
        streamKey: streamKey,
        attemptId: _resolvedOpeningId,
        source: reason == 'initial' ? 'live_player' : reason,
      );
      return true; // Never block the stream — just skip the duplicate ad.
    }
    try {
      // Mark the initial opening handled IMMEDIATELY on claim, so any rebuild /
      // resume / rotation that re-enters this path sees it as already handled
      // even while the ad is still resolving.
      if (isInitial) PreRollGate.instance.markInitialHandled(_resolvedOpeningId);

      PreRollGate.instance.log(
        'LIVE_PLAYER_INITIAL_PRE_ROLL_REQUESTED',
        matchId: widget.matchId,
        streamKey: streamKey,
        attemptId: _resolvedOpeningId,
        source: reason,
        sessionCount: AdsManager.instance.preRollShownThisSession,
        perMatchCount: PreRollGate.instance.shownForMatch(widget.matchId),
      );

      // Session capping (admin-managed). Never caps a required premium unlock.
      if (!required) {
        // Per-match cap: limit how many pre-rolls may show within one match
        // (across openings + quality/server switches). 0 = no limit.
        final perMatchCap = AdService.instance.config.preRollMaxPerMatch;
        final shownThisMatch = PreRollGate.instance.shownForMatch(widget.matchId);
        if (perMatchCap > 0 && shownThisMatch >= perMatchCap) {
          PreRollGate.instance.log(
            'WATCH_LIVE_PRE_ROLL_SKIPPED_CAP',
            matchId: widget.matchId,
            streamKey: streamKey,
            attemptId: _resolvedOpeningId,
            source: reason,
            perMatchCount: shownThisMatch,
          );
          return true; // Skip the ad, but never block the stream.
        }
        final decision = AdsManager.instance.preRollCapDecision();
        if (decision != PreRollCapDecision.allow) {
          PreRollGate.instance.log(
            'WATCH_LIVE_PRE_ROLL_SKIPPED_CAP',
            matchId: widget.matchId,
            streamKey: streamKey,
            attemptId: _resolvedOpeningId,
            source: reason,
            sessionCount: AdsManager.instance.preRollShownThisSession,
          );
          return true; // Skip the ad, but never block the stream.
        }
      }

      // Rewarded VIDEO needs an explicit app-side opt-in (the user chooses to
      // watch). Rewarded INTERSTITIAL shows its own SDK intro, so a second app
      // prompt is redundant. Cancelling the opt-in declines the ad: a required
      // premium stream stays locked; an optional pre-roll simply continues.
      if (gate == StreamPreRollAdType.rewardedVideo) {
        final accepted = await _confirmWatchAd();
        if (accepted != true) {
          if (kDebugMode) {
            debugPrint('CricProPreRoll: opt-in declined -> '
                '${required ? 'stream stays locked' : 'continue stream'}');
          }
          return !required;
        }
      }

      // No loading skeleton before pre-roll: a ready ad shows instantly, and a
      // slow/absent one is bounded by the LOAD timeout inside AdsManager
      // (fail-open). We do NOT time out here — once an ad is showing we wait for
      // its real dismiss/fail callback, so playback never starts behind a
      // still-visible ad.
      StreamAdResult result;
      try {
        result = await AdsManager.instance
            .showStreamPreRoll(type: gate, isRequiredForPremium: required);
      } catch (e) {
        result = StreamAdResult.failed;
        if (kDebugMode) {
          debugPrint('CricProPreRoll: exception -> continue stream');
        }
      }

      if (result != StreamAdResult.allowed) {
        PreRollGate.instance.log(
          'WATCH_LIVE_PRE_ROLL_RESULT_FAILED',
          matchId: widget.matchId,
          streamKey: streamKey,
          attemptId: _resolvedOpeningId,
          source: reason,
        );
        if (required) {
          _showAdRetryMessage();
          return false; // Do NOT open a required premium stream without the ad.
        }
        return true; // Optional pre-roll failed — fail open.
      }

      PreRollGate.instance.log(
        'WATCH_LIVE_PRE_ROLL_RESULT_SHOWN',
        matchId: widget.matchId,
        streamKey: streamKey,
        attemptId: _resolvedOpeningId,
        source: reason,
      );
      if (required) {
        _rewardUnlockedStreamIds.add(_rewardKey(stream));
        AnalyticsService.instance.track('rewarded_unlock', {
          'match_id': widget.matchId,
          'stream_id': stream.id,
        });
      } else {
        // An optional pre-roll actually showed — count it toward the per-match
        // cap so further switches on this match respect the admin limit.
        PreRollGate.instance.recordShown(widget.matchId);
      }
      PreRollGate.instance.log(
        'STREAM_OPEN_CONTINUE',
        matchId: widget.matchId,
        streamKey: streamKey,
        attemptId: _resolvedOpeningId,
        source: reason,
      );
      return true;
    } finally {
      PreRollGate.instance.endAttempt();
    }
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
    // CENTRAL AUTHORITY: the initial pre-roll for this opening is owned by the
    // gate. If the launcher already attempted it (shown, failed, timed out,
    // no-fill, capped, or disabled), the player must NOT start another one for
    // the first auto-selected stream. A required premium stream still runs its
    // own reward unlock here (that is a different user action, not the entry
    // pre-roll). This replaces the old success-only `skipInitialPreRoll` bool
    // that let a failed/un-earned entry ad fall through to a second pre-roll.
    if (!_initialPreRollConsumed && !required) {
      _initialPreRollConsumed = true;
      // Block when the opening's initial pre-roll was already attempted by the
      // launcher OR when ANY pre-roll attempt is currently in flight. The
      // active-attempt check is the safety net that does NOT depend on the
      // route-passed openingId/`skipInitialPreRoll` arg, so a missing/garbled
      // arg can never let the player start a second concurrent pre-roll.
      if (PreRollGate.instance.isInitialHandled(_resolvedOpeningId) ||
          PreRollGate.instance.isAttemptActive) {
        PreRollGate.instance.log(
          'LIVE_PLAYER_INITIAL_PRE_ROLL_BLOCKED_ALREADY_HANDLED',
          matchId: widget.matchId,
          streamKey: _streamKey(stream),
          attemptId: _resolvedOpeningId,
          source: 'live_player',
        );
        return StreamPreRollAdType.none;
      }
      // Not handled yet (e.g. deep link straight into the player). The player
      // owns the initial pre-roll; claim it so nothing else repeats it.
      PreRollGate.instance.log(
        'LIVE_PLAYER_INITIAL_PRE_ROLL_ALLOWED',
        matchId: widget.matchId,
        streamKey: _streamKey(stream),
        attemptId: _resolvedOpeningId,
        source: 'live_player',
      );
    }
    return AdService.instance.config.resolveStreamPreRoll(
      isPremium: stream.isPremium,
      requiresRewardAd: stream.requiresRewardAd,
    );
  }

  String _rewardKey(StreamSource stream) => '${widget.matchId}:${stream.id}';

  /// Stable per-opening stream key for logging/diagnostics.
  String _streamKey(StreamSource stream) =>
      '${stream.id}:${stream.url.hashCode}';

  /// Short, non-deceptive confirmation that an ad unlocks the stream.
  Future<bool?> _confirmWatchAd() {
    final c = context.cric;
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: c.card,
        title: Text('Watch an ad to continue', style: TextStyle(color: c.text)),
        content: Text(
          'Watch a short ad to continue to your stream.',
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

  /// Max time to wait for a single source to initialize before treating it as
  /// failed. A dead/hanging link would otherwise spin forever with no error.
  static const Duration _initTimeout = Duration(seconds: 12);

  Future<void> _loadStream(
    StreamSource stream, {
    HlsQuality? quality,
    bool isRetry = false,
  }) async {
    // Defense-in-depth: never initialize the video controller or call play()
    // while a pre-roll ad is showing or any pre-roll attempt is still in
    // flight. The normal flow already awaits the gate in `_selectStream`, but a
    // deep link, rebuild, resume, or route race could call here early — this
    // guarantees no video/audio ever starts behind an active ad.
    if (AdsManager.instance.isShowingAd ||
        PreRollGate.instance.isAttemptActive) {
      PreRollGate.instance.log(
        'LIVE_PLAYER_VIDEO_INIT_BLOCKED_WAITING_FOR_PRE_ROLL',
        matchId: widget.matchId,
        streamKey: _streamKey(stream),
        attemptId: _resolvedOpeningId,
        source: 'live_player',
        videoInit: _videoController?.value.isInitialized ?? false,
        isPlaying: _videoController?.value.isPlaying ?? false,
      );
      return;
    }

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
    // Reject only when the source is genuinely non-HLS. A URL whose path
    // contains `.m3u8` is treated as HLS even if the stored type is
    // missing/unknown/wrong (StreamSource.isDash/isExternal already honor this).
    if (stream.isDash || stream.isExternal) {
      if (kDebugMode) {
        final ext = (Uri.tryParse(stream.url)?.path ?? '').toLowerCase();
        final extOnly = ext.contains('.m3u8')
            ? '.m3u8'
            : ext.contains('.mpd')
                ? '.mpd'
                : (ext.contains('.') ? ext.substring(ext.lastIndexOf('.')) : 'none');
        debugPrint(
            '[Player] unsupported source match=${widget.matchId} '
            'stream=${stream.id} rawType=${stream.streamType} '
            'normalizedType=${stream.type} urlExt=$extOnly '
            'hasHeaders=${stream.headers.isNotEmpty}');
      }
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
    // Otherwise, if parsing produced a default variant (lowest/SD), play that so
    // the player opens on the data-saver quality instead of the master.
    String playUrl = stream.url;
    if (quality != null && quality.url.isNotEmpty) {
      playUrl = quality.url;
    } else if (quality == null &&
        _selectedQuality != null &&
        _selectedQuality!.url.isNotEmpty) {
      playUrl = _selectedQuality!.url;
    }

    // Candidate URLs tried in order: primary, then admin-configured backup.
    // The backup is only attempted when it differs from the primary play URL.
    final candidates = <String>[playUrl];
    final backup = stream.backupUrl;
    if (backup != null && backup.isNotEmpty && backup != playUrl) {
      candidates.add(backup);
    }

    Object? lastError;
    for (var i = 0; i < candidates.length; i++) {
      final url = candidates[i];
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(url),
        httpHeaders: headers,
      );
      controller.addListener(_onControllerUpdate);
      PreRollGate.instance.log(
        'LIVE_PLAYER_VIDEO_INIT_START',
        matchId: widget.matchId,
        streamKey: _streamKey(stream),
        attemptId: _resolvedOpeningId,
        source: isRetry ? 'rebuild' : 'live_player',
        videoInit: false,
        isPlaying: false,
      );
      final initFuture = controller.initialize().then((_) {
        PreRollGate.instance.log(
          'LIVE_PLAYER_PLAY_START',
          matchId: widget.matchId,
          streamKey: _streamKey(stream),
          attemptId: _resolvedOpeningId,
          source: isRetry ? 'rebuild' : 'live_player',
          videoInit: true,
          isPlaying: true,
        );
        controller.play();
        controller.setLooping(false);
      });
      if (mounted) {
        setState(() {
          _videoController = controller;
          _videoInitFuture = initFuture;
          _playerError = null;
          if (quality != null) {
            _selectedQuality = quality;
          }
        });
      }
      try {
        await initFuture.timeout(_initTimeout);
        if (mounted) setState(() {});
        return; // Playing — done.
      } catch (e) {
        lastError = e;
        if (kDebugMode) {
          final which = i == 0 ? 'primary' : 'backup';
          debugPrint(
              '[Player] $which source failed match=${widget.matchId} '
              'stream=${stream.id} retry=$isRetry err=$e');
        }
        controller.removeListener(_onControllerUpdate);
        _syncWakelock(false);
        await controller.dispose();
        if (_videoController == controller) _videoController = null;
        // Fall through to the next candidate (backup), if any.
      }
    }

    // Every candidate failed. Auto-retry the whole chain once after a short
    // delay before surfacing an error — covers transient network/token hiccups.
    if (!isRetry) {
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      if (!mounted || _selectedStream?.id != stream.id) return;
      return _loadStream(stream, quality: quality, isRetry: true);
    }

    if (mounted) {
      setState(() {
        _videoController = null;
        _videoInitFuture = null;
        _playerError = _classifyPlayerError(
          lastError,
          triedBackup: candidates.length > 1,
        );
      });
    }
  }

  /// Maps a low-level player/init failure to a short, user-safe message. Never
  /// exposes raw URLs, tokens, or header values. Best-effort: ExoPlayer error
  /// strings vary by device, so matching is heuristic and falls back to a
  /// generic retry message.
  String _classifyPlayerError(Object? error, {required bool triedBackup}) {
    final msg = error?.toString().toLowerCase() ?? '';
    if (error is TimeoutException ||
        msg.contains('timeout') ||
        msg.contains('timed out')) {
      return 'Stream is taking too long to respond. Check your connection and tap Retry.';
    }
    if (msg.contains('403') ||
        msg.contains('forbidden') ||
        msg.contains('401') ||
        msg.contains('unauthorized')) {
      return 'This stream link has expired or needs authorization. Please try another server.';
    }
    if (msg.contains('404') ||
        msg.contains('not found') ||
        msg.contains('410') ||
        msg.contains('gone')) {
      return 'This stream is no longer available. Please try another server.';
    }
    if (msg.contains('certificate') ||
        msg.contains('ssl') ||
        msg.contains('handshake')) {
      return 'Secure connection to this stream failed. Please try another server.';
    }
    if (msg.contains('format') ||
        msg.contains('codec') ||
        msg.contains('unsupported') ||
        msg.contains('parsing') ||
        msg.contains('malformed')) {
      return 'This stream format is not supported on this device. Please try another server.';
    }
    if (msg.contains('socket') ||
        msg.contains('network') ||
        msg.contains('connection') ||
        msg.contains('unreachable') ||
        msg.contains('host')) {
      return 'Network error while loading the stream. Tap Retry.';
    }
    if (triedBackup) {
      return 'Primary and backup streams both failed. Please retry or choose another server.';
    }
    return 'Unable to play this stream. Please retry or choose another server.';
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
      final allVariants = <HlsQuality>[];

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
            final height = int.parse(resMatch.group(2)!);
            currentResolution = '${resMatch.group(1)!}x${resMatch.group(2)!}';
            quality = _createQualityFromResolution(
              currentResolution,
              variantUrl,
              currentBandwidth,
            );
            // Store raw variant with real height for inline sheet.
            allVariants.add(HlsQuality(
              label: '${height}p',
              code: '${height}p',
              resolution: '${height}p',
              url: variantUrl,
              rank: 10000 - height, // lower height = higher rank number (sorted low→high)
              bandwidth: currentBandwidth,
              source: 'hlsVariant',
            ));
          } else if (currentBandwidth != null) {
            // No RESOLUTION — bucket by bitrate as a fallback.
            quality = _createQualityFromBandwidth(currentBandwidth, variantUrl);
            allVariants.add(quality);
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

        // Default selected quality: lowest concrete variant (SD → HD → Full HD)
        // to reduce buffering / data on startup. User can switch up manually.
        // Falls back to Auto/master when no concrete variant is present.
        HlsQuality byCode(String code) => qualities
            .firstWhere((q) => q.code == code, orElse: () => qualities.first);
        final hasFhd = qualities.any((q) => q.code == 'FHD');
        final hasHd = qualities.any((q) => q.code == 'HD');
        final hasSd = qualities.any((q) => q.code == 'SD');
        final defaultQuality = hasSd
            ? byCode('SD')
            : hasHd
                ? byCode('HD')
                : hasFhd
                    ? byCode('FHD')
                    : qualities.first;

        if (mounted) {
          // Build inline sheet list: dedup by resolution, sorted low→high, Auto on top.
          final variantByRes = <String, HlsQuality>{};
          for (final v in allVariants) {
            final existing = variantByRes[v.resolution];
            if (existing == null ||
                (v.bandwidth ?? 0) > (existing.bandwidth ?? 0)) {
              variantByRes[v.resolution] = v;
            }
          }
          final sortedVariants = variantByRes.values.toList()
            ..sort((a, b) => a.rank.compareTo(b.rank));
          sortedVariants.insert(
            0,
            HlsQuality(
              label: 'Auto',
              code: 'AUTO',
              resolution: 'Adaptive',
              url: masterUrl,
              rank: 0,
            ),
          );

          setState(() {
            _hlsQualities = qualities;
            _hlsAllVariants = sortedVariants;
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
    //   720p and higher → Full HD (FHD), display label capped at 720p
    //   480p            → HD, display 480p
    //   240p / 360p     → SD, display 288p
    // Display labels are fixed per spec regardless of actual stream height.
    // The real URL is preserved so playback is unaffected.
    if (height >= 720) {
      return HlsQuality(
        label: 'Full HD',
        code: 'FHD',
        resolution: '720p',
        url: url,
        rank: 1,
        bandwidth: bandwidth,
      );
    } else if (height >= 480) {
      return HlsQuality(
        label: 'HD',
        code: 'HD',
        resolution: '480p',
        url: url,
        rank: 2,
        bandwidth: bandwidth,
      );
    } else {
      return HlsQuality(
        label: 'SD',
        code: 'SD',
        resolution: '288p',
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

  /// Resolves a variant URL from an HLS master against the master URL, using
  /// RFC-3986 resolution. Handles absolute URLs, origin-absolute paths
  /// (e.g. `/Transcoding/x.m3u8`), and relative paths (`../x`, `x.m3u8`).
  /// A relative variant URL must never be passed to video_player directly.
  String _resolveUrl(String baseUrl, String relativePath) {
    if (relativePath.startsWith('http://') ||
        relativePath.startsWith('https://')) {
      return relativePath;
    }
    final base = Uri.tryParse(baseUrl);
    if (base == null) return relativePath;
    return base.resolve(relativePath).toString();
  }

  void _openSettings() {
    if (_selectedStream == null) return;
    // Pin the controls visible while the quality menu is open, then re-arm the
    // auto-hide once it closes.
    _portraitMenuOpen = true;
    _portraitHideTimer?.cancel();
    _portraitHideTimer = null;
    if (!_portraitControlsVisible) {
      setState(() => _portraitControlsVisible = true);
    }
    _showQualitySelector(context).whenComplete(() {
      _portraitMenuOpen = false;
      if (mounted) _schedulePortraitHide();
    });
  }

  void _openFullscreen() {
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _FullscreenVideoPage(
          controller: controller,
          stream: _selectedStream!,
          qualities: _hlsAllVariants.isNotEmpty
              ? _hlsAllVariants
              : _qualityOptionsFor(_selectedStream!),
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
    // User changed quality (past the same-quality guard above).
    AnalyticsService.instance.track('quality_selected', {
      'quality_code': quality.code,
      'quality_label': quality.label,
      'match_id': widget.matchId,
    });

    // A manual quality switch may also attempt the admin-selected pre-roll
    // (gated by config + session cap). It is ALWAYS fail-open: the new quality
    // loads regardless of the ad outcome, and never on internal retries/backup
    // fallback (those call _loadStream directly, not _selectQuality).
    if (AdService.instance.config.preRollApplyToQualitySwitch &&
        !_streamAdInProgress) {
      final gate = AdService.instance.config.resolveWatchLivePreRoll();
      if (gate != StreamPreRollAdType.none) {
        _streamAdInProgress = true;
        try {
          await _runPreRollGate(
            stream: stream,
            gate: gate,
            required: false, // already-playing stream — never a premium gate.
            reason: 'quality',
          );
        } finally {
          _streamAdInProgress = false;
        }
      }
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

  Future<void> _showQualitySelector(BuildContext context) {
    final stream = _selectedStream;
    if (stream == null) return Future<void>.value();
    // Sheet shows all real HLS variants when available; falls back to bucketed list.
    final qualities = _hlsAllVariants.isNotEmpty
        ? _hlsAllVariants
        : _qualityOptionsFor(stream);
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    void select(HlsQuality quality) {
      Navigator.pop(context);
      _loadStream(stream, quality: quality);
    }

    if (landscape) {
      return showDialog<void>(
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
    }

    final c = context.cric;
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: c.isDark
          ? Colors.black54
          : Colors.black.withValues(alpha: .25),
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
            // Premium dark stadium backdrop — dark mode only. Admin can swap
            // this via the App Assets panel (key: live_player_bg_dark); the
            // bundled PNG is the always-present fallback.
            if (c.isDark)
              Positioned.fill(
                child: IgnorePointer(
                  child: RemoteOrLocalImage(
                    assetKey: 'live_player_bg_dark',
                    fallbackAsset:
                        'assets/images/live_stream/backgrounds/live_screen_dark_background.webp',
                    isDark: c.isDark,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            Positioned(
              top: -60,
              left: 0,
              right: 0,
              height: 360,
              child: IgnorePointer(
                  child: Opacity(
                  opacity: c.isDark ? 1.0 : 0.3,
                  child: Image.asset(
                    'assets/images/live_stream/overlays/cyan_radial_glow.webp',
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
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
                      controlsVisible: _portraitControlsVisible,
                      onSurfaceTap: _togglePortraitControls,
                      onControlInteraction: _bumpPortraitControls,
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

