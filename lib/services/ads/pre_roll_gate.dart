import 'package:flutter/foundation.dart';

/// Single authority for the **initial** stream pre-roll (the one ad allowed
/// between a Watch Live tap / deep link and the stream playing).
///
/// Why this exists: the full-screen mutex in [AdsManager] only prevents two
/// ads being on screen at the same millisecond. It does NOT stop a second
/// pre-roll from starting *after* the first one is dismissed. A Watch Live tap
/// has TWO potential pre-roll owners — the launcher in `main.dart` and the
/// auto-select flow in the live player — so without a shared, attempt-based
/// record they can each fire one ad for the same stream opening.
///
/// The gate fixes that by tracking, per logical "opening" (one tap / one deep
/// link), whether the initial pre-roll has already been **attempted**.
/// "Attempted" means decided in any way: shown, failed, timed out, no-fill,
/// skipped by a cap, or disabled by admin. Once an opening is marked handled,
/// every later initial-pre-roll request for that opening continues straight to
/// the stream with NO ad — regardless of rebuilds, rotation, resume, auto
/// select, or quality load.
class PreRollGate {
  PreRollGate._();

  static final PreRollGate instance = PreRollGate._();

  int _counter = 0;

  /// Opening ids whose initial pre-roll has been attempted (terminal outcome).
  final Set<int> _initialHandled = <int>{};

  /// Insertion order of opening ids, for bounded in-memory cleanup.
  final List<int> _openingOrder = <int>[];

  /// Pre-rolls that ACTUALLY showed, keyed by matchId (per-match cap source).
  final Map<String, int> _shownPerMatch = <String, int>{};

  /// True while a pre-roll attempt is running anywhere (entry OR player). A
  /// sequential lock — released only when the whole attempt finishes — so a
  /// second attempt cannot begin even after the first ad is dismissed.
  bool _attemptActive = false;

  DateTime? _lastShownAt;

  bool get isAttemptActive => _attemptActive;
  DateTime? get lastPreRollShownAt => _lastShownAt;

  /// Registers a new logical opening (one Watch Live tap or one deep-link
  /// open) and returns its id. Pass this id to the live player so it can ask
  /// the gate whether the initial pre-roll was already handled by the launcher.
  int newOpening(String matchId) {
    final id = ++_counter;
    _openingOrder.add(id);
    // Keep memory bounded: retain only the most recent openings.
    while (_openingOrder.length > 50) {
      final old = _openingOrder.removeAt(0);
      _initialHandled.remove(old);
    }
    return id;
  }

  /// Whether the initial pre-roll for [openingId] has already been attempted.
  bool isInitialHandled(int? openingId) =>
      openingId != null && _initialHandled.contains(openingId);

  /// Marks the initial pre-roll for [openingId] as attempted (any outcome).
  /// Safe to call more than once.
  void markInitialHandled(int? openingId) {
    if (openingId == null) return;
    _initialHandled.add(openingId);
  }

  /// Pre-rolls that have actually shown for [matchId] this session.
  int shownForMatch(String matchId) => _shownPerMatch[matchId] ?? 0;

  /// Attempts to take the global pre-roll lock. Returns false when an attempt
  /// is already in flight, so the caller must NOT start its own.
  bool beginAttempt() {
    if (_attemptActive) return false;
    _attemptActive = true;
    return true;
  }

  /// Releases the global pre-roll lock. Always call from a `finally`.
  void endAttempt() {
    _attemptActive = false;
  }

  /// Records that a pre-roll actually showed for [matchId] (drives the
  /// per-match cap and `lastPreRollShownAt`).
  void recordShown(String matchId) {
    _shownPerMatch[matchId] = (_shownPerMatch[matchId] ?? 0) + 1;
    _lastShownAt = DateTime.now();
  }

  /// Structured, debug-only pre-roll event log. One line per event with the
  /// stable fields needed to prove only one initial pre-roll runs per tap.
  void log(
    String event, {
    String matchId = '',
    String streamKey = '',
    int? attemptId,
    String source = '',
    int sessionCount = -1,
    int perMatchCount = -1,
    bool? videoInit,
    bool? isPlaying,
  }) {
    if (!kDebugMode) return;
    debugPrint('PRE_ROLL_GATE $event '
        'match=$matchId stream=$streamKey attemptId=${attemptId ?? '-'} '
        'source=$source sessionCount=$sessionCount perMatch=$perMatchCount '
        'videoInit=${videoInit ?? '-'} isPlaying=${isPlaying ?? '-'} '
        'attemptActive=$_attemptActive');
  }
}
