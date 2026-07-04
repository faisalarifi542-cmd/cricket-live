import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:cricpro_flutter/app_theme.dart';
import 'package:cricpro_flutter/components.dart';
import 'package:cricpro_flutter/models/cricket_match.dart';
import 'package:cricpro_flutter/repositories/cricket_repository.dart';
import 'package:cricpro_flutter/utils/match_status.dart';
import 'package:cricpro_flutter/utils/team_format.dart';
import 'package:cricpro_flutter/widgets/team_score_view.dart';

/// Global state holder for the minimized (floating) live-score bar.
///
/// The app uses no state-management package; this follows the existing
/// `.instance` singleton + [ChangeNotifier] convention (matching
/// `RemoteAssetsService.instance`, and the `ValueNotifier` shell signals).
///
/// [activeMatch] == null means the bar is hidden. [show] minimizes a match and
/// starts a dedicated ~5s live poll keyed by matchId; [update] feeds fresh data
/// (also accepted from the Match Details poll while it is open); [clear] removes
/// the bar and stops polling. The poll pauses on app background and resumes on
/// foreground while the match is still live.
class MinimizedScoreController extends ChangeNotifier with WidgetsBindingObserver {
  MinimizedScoreController._();
  static final MinimizedScoreController instance = MinimizedScoreController._();

  final CricketRepository _repository = CricketRepository();

  CricketMatch? _activeMatch;
  CricketMatch? get activeMatch => _activeMatch;
  bool get isVisible => _activeMatch != null;

  String? get activeMatchId => _activeMatch?.id;

  Timer? _pollTimer;
  bool _polling = false;
  bool _observing = false;
  // Last time fresh data landed (from our own poll OR a Match Details push), so
  // our poll can skip a tick when the open detail screen already refreshed this
  // same match — avoids duplicate network calls.
  DateTime? _lastUpdated;
  static const Duration _interval = Duration(seconds: 5);

  /// Minimize [match] into the floating bar and begin live polling if live.
  void show(CricketMatch match) {
    _activeMatch = match;
    _lastUpdated = DateTime.now();
    if (match.isFinished && kDebugMode) {
      debugPrint('CricProMiniScore: completed -> stop polling, keep visible');
    }
    notifyListeners();
    _syncPolling();
  }

  /// Push fresh live data for the currently minimized match. No-op (ignored)
  /// when [match] is a different match than the one minimized, so a background
  /// poll for another screen can never hijack the bar. Merges score/status
  /// fields onto the existing instance to keep updates smooth (no blink).
  void update(CricketMatch match) {
    final current = _activeMatch;
    if (current == null || current.id != match.id) return;
    _lastUpdated = DateTime.now();
    final merged = current.mergeLiveScore(match);
    // Only repaint when something the bar shows actually changed (no blink).
    if (_scoreKey(merged) == _scoreKey(current)) {
      _activeMatch = merged;
      _syncPolling();
      return;
    }
    _activeMatch = merged;
    notifyListeners();
    _syncPolling();
  }

  /// Remove the bar (user tapped X, or match opened/ended) and stop polling.
  void clear() {
    if (_activeMatch == null) return;
    _activeMatch = null;
    _stopPolling();
    notifyListeners();
  }

  // ── Live polling ───────────────────────────────────────────────────────

  /// Starts the timer when the active match is live, stops it otherwise. Also
  /// registers/unregisters the app-lifecycle observer so we don't poll in the
  /// background.
  void _syncPolling() {
    final match = _activeMatch;
    final shouldPoll = match != null && match.isLive && !match.isFinished;
    if (shouldPoll) {
      if (!_observing) {
        WidgetsBinding.instance.addObserver(this);
        _observing = true;
      }
      _pollTimer ??= Timer.periodic(_interval, (_) => _tick());
    } else {
      _stopPolling();
    }
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    if (_observing) {
      WidgetsBinding.instance.removeObserver(this);
      _observing = false;
    }
  }

  Future<void> _tick() async {
    if (_polling) return;
    final match = _activeMatch;
    if (match == null || match.id.isEmpty || !match.isLive) {
      _syncPolling();
      return;
    }
    // Skip if a recent push (e.g. open Match Details poll) already refreshed
    // this match within the interval — reuse that data, no duplicate request.
    final last = _lastUpdated;
    if (last != null && DateTime.now().difference(last) < _interval) return;
    _polling = true;
    try {
      final res = await _repository.liveScores([match.id]);
      final current = _activeMatch;
      if (current == null || current.id != match.id) return; // changed mid-flight
      CricketMatch? fresh;
      for (final m in res.data) {
        if (m.id == current.id) {
          fresh = m;
          break;
        }
      }
      if (fresh == null) return; // not in feed — keep last good score.
      _lastUpdated = DateTime.now();
      final merged = current.mergeLiveScore(fresh);
      if (_scoreKey(merged) != _scoreKey(current)) {
        _activeMatch = merged;
        notifyListeners();
      } else {
        _activeMatch = merged;
      }
      // Match ended — stop polling but keep the final score on screen.
      if (merged.isFinished || !merged.isLive) {
        if (kDebugMode) {
          debugPrint('CricProMiniScore: completed -> stop polling, keep visible');
        }
        _syncPolling();
      }
    } catch (_) {
      // Fetch failed — keep last good score, no error UI. Try again next tick.
    } finally {
      _polling = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncPolling(); // resume if still live.
    } else {
      _pollTimer?.cancel();
      _pollTimer = null; // pause while backgrounded; observer stays registered.
    }
  }

  /// Fields the bar renders — used to decide whether a refresh is visible.
  String _scoreKey(CricketMatch m) =>
      '${m.status}|${m.statusText}|${m.resultText}|'
      '${m.teamAScoreText}|${m.teamBScoreText}';
}

/// Parsed chase numbers derived from a match's free-text status.
///
/// CricPro's data model carries NO structured target / runs-needed field — the
/// "Need X from Y" information arrives only as free text in `statusText`. This
/// parses it defensively; every field is nullable and the UI hides whatever is
/// missing (never invents a target).
class _ChaseInfo {
  const _ChaseInfo({
    this.needRuns,
    this.needBalls,
    this.currentRuns,
    this.target,
    this.battingShort,
    this.battingScoreText,
  });

  final int? needRuns;
  final int? needBalls;
  final int? currentRuns;
  final int? target;
  final String? battingShort;
  final String? battingScoreText;

  bool get hasEquation => needRuns != null && needBalls != null;
  bool get hasProgress =>
      currentRuns != null && target != null && target! > 0;

  double get progress {
    if (!hasProgress) return 0;
    return (currentRuns! / target!).clamp(0.0, 1.0);
  }
}

/// Leading integer from a score text like "145/3 (16.2 OV)" -> 145.
int? _leadingRuns(String scoreText) {
  final m = RegExp(r'(\d+)').firstMatch(scoreText.trim());
  if (m == null) return null;
  return int.tryParse(m.group(1)!);
}

/// Derives chase info for a live match from its status text + score texts.
_ChaseInfo _deriveChase(CricketMatch match) {
  // Look for "need 26 from 22" / "need 26 runs in 22 balls" / "... off 22".
  final status = '${match.statusText} ${match.resultText}';
  final eq = RegExp(
    r'need\s+(\d+)\s*(?:runs?\s+)?(?:from|in|off|of)\s+(\d+)',
    caseSensitive: false,
  ).firstMatch(status);

  if (eq == null) {
    return const _ChaseInfo();
  }

  final needRuns = int.tryParse(eq.group(1)!);
  final needBalls = int.tryParse(eq.group(2)!);

  // Determine the batting (chasing) side. Prefer whichever team's short code
  // appears in the status text; else the team with the higher score (the
  // chaser is usually batting second with the live, climbing total). Falls
  // back to team A. Label-only — never blocks render.
  final aRuns = _leadingRuns(match.teamAScoreText);
  final bRuns = _leadingRuns(match.teamBScoreText);

  bool battingIsA;
  final lower = status.toLowerCase();
  final aCode = match.teamAShort.toLowerCase();
  final bCode = match.teamBShort.toLowerCase();
  if (aCode.isNotEmpty && lower.contains(aCode)) {
    battingIsA = true;
  } else if (bCode.isNotEmpty && lower.contains(bCode)) {
    battingIsA = false;
  } else {
    battingIsA = (aRuns ?? -1) >= (bRuns ?? -1);
  }

  final currentRuns = battingIsA ? aRuns : bRuns;
  final battingShort = battingIsA ? match.teamAShort : match.teamBShort;
  final battingScoreText =
      battingIsA ? match.teamAScoreText : match.teamBScoreText;

  int? target;
  if (currentRuns != null && needRuns != null) {
    target = currentRuns + needRuns;
  }

  return _ChaseInfo(
    needRuns: needRuns,
    needBalls: needBalls,
    currentRuns: currentRuns,
    target: target,
    battingShort: battingShort,
    battingScoreText: battingScoreText,
  );
}

/// Splits a score text "145/3 (16.2 OV)" into ("145/3", "16.2 ov").
(String score, String overs) _splitScore(String text) {
  final t = text.trim();
  if (t.isEmpty) return ('', '');
  final overMatch =
      RegExp(r'\(?\s*([\d.]+)\s*(?:ov|overs?)\s*\)?', caseSensitive: false)
          .firstMatch(t);
  final overs = overMatch != null ? '${overMatch.group(1)} ov' : '';
  // Score = everything before the first parenthesis / "ov" marker.
  var score = t;
  final cut = t.indexOf('(');
  if (cut > 0) score = t.substring(0, cut).trim();
  if (overMatch != null && cut < 0) {
    score = t.substring(0, overMatch.start).trim();
  }
  return (score, overs);
}

/// The compact floating live-score card shown when a match is minimized.
///
/// Premium dark-navy/cyan in dark mode, clean white card in light mode — all
/// driven by [CricColors] (`context.cric`), auto-switching with the app theme.
/// Pure presentation: reads its data from [match], reports taps via callbacks.
class MinimizedScoreBar extends StatelessWidget {
  const MinimizedScoreBar({
    super.key,
    required this.match,
    required this.onTap,
    required this.onClose,
  });

  final CricketMatch match;

  /// Tap the card body -> reopen match details.
  final VoidCallback onTap;

  /// Tap the X -> dismiss the bar.
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final compact = context.w <= 360;

    final chase = match.isLive ? _deriveChase(match) : const _ChaseInfo();

    final radius = compact ? 18.0 : 22.0;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(compact ? 10 : 14, 0, compact ? 10 : 14, 8),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(radius),
            child: Container(
              decoration: BoxDecoration(
                gradient: c.cardGradient,
                borderRadius: BorderRadius.circular(radius),
                border: Border.all(
                  color: c.isDark
                      ? c.cyan.withValues(alpha: .45)
                      : c.border,
                  width: 1.1,
                ),
                boxShadow: c.cardShadow,
              ),
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 10 : 14,
                vertical: compact ? 8 : 10,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // LEFT TEAM ──────────────────────────────────────────
                  _TeamBlock(
                    logoUrl: match.teamALogo,
                    name: match.teamA,
                    short: match.teamAShort,
                    innings: match.teamAInnings,
                    live: match.isLive,
                    currentInningsIndex:
                        match.currentScoredIndexForTeam(isTeamA: true),
                    color: const Color(0xff22d3ee),
                    logoLeading: true,
                    compact: compact,
                  ),
                  SizedBox(width: compact ? 6 : 10),
                  // CENTER ─────────────────────────────────────────────
                  Expanded(
                    child: _CenterBlock(
                      match: match,
                      chase: chase,
                      compact: compact,
                    ),
                  ),
                  SizedBox(width: compact ? 6 : 10),
                  // RIGHT TEAM ─────────────────────────────────────────
                  _TeamBlock(
                    logoUrl: match.teamBLogo,
                    name: match.teamB,
                    short: match.teamBShort,
                    innings: match.teamBInnings,
                    live: match.isLive,
                    currentInningsIndex:
                        match.currentScoredIndexForTeam(isTeamA: false),
                    color: const Color(0xfff59e0b),
                    logoLeading: false,
                    compact: compact,
                  ),
                  // DIVIDER + CLOSE ────────────────────────────────────
                  SizedBox(width: compact ? 6 : 10),
                  Container(
                    width: 1,
                    height: compact ? 38 : 46,
                    color: c.border.withValues(alpha: c.isDark ? .5 : .8),
                  ),
                  GestureDetector(
                    onTap: onClose,
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: EdgeInsets.only(left: compact ? 4 : 8),
                      child: Icon(
                        Icons.close_rounded,
                        size: compact ? 20 : 22,
                        color: c.muted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One team's logo + code + score + overs. [logoLeading] puts the logo on the
/// left (home team) or right (away team) to mirror the reference layout.
class _TeamBlock extends StatelessWidget {
  const _TeamBlock({
    required this.logoUrl,
    required this.name,
    required this.short,
    required this.innings,
    required this.live,
    required this.color,
    required this.logoLeading,
    required this.compact,
    this.currentInningsIndex = -1,
  });

  final String? logoUrl;
  final String name;
  final String short;
  final List<InningsScore> innings;
  final bool live;
  final Color color;
  final bool logoLeading;
  final bool compact;
  final int currentInningsIndex;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final logoSize = compact ? 28.0 : 34.0;

    final logo = TeamLogoWidget(
      logoUrl: logoUrl,
      teamName: name,
      abbreviation: short,
      color: color,
      size: logoSize,
    );

    final align =
        logoLeading ? CrossAxisAlignment.start : CrossAxisAlignment.end;
    final text = Column(
      crossAxisAlignment: align,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          teamCodeOf(short, name),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          softWrap: false,
          style: TextStyle(
            color: c.muted,
            fontWeight: FontWeight.w700,
            fontSize: compact ? 11 : 12,
            letterSpacing: .2,
          ),
        ),
        const SizedBox(height: 1),
        // Centralized professional score — `145/3` / `16.2 ov`, or a Test's
        // `362/10 & 45/3` / `87.1 • 13.5 ov`, scaled to fit, never truncated.
        TeamScoreView(
          innings: innings,
          mode: ScoreDisplayMode.compactBar,
          mainSize: compact ? 18 : 21,
          oversSize: compact ? 10 : 11,
          live: live,
          currentInningsIndex: currentInningsIndex,
          color: c.text,
          oversColor: c.muted,
          align: align,
          textAlign: logoLeading ? TextAlign.left : TextAlign.right,
          compactOvers: true,
          placeholder: '–',
          gap: 1,
        ),
      ],
    );

    final children = logoLeading
        ? [logo, SizedBox(width: compact ? 6 : 8), Flexible(child: text)]
        : [Flexible(child: text), SizedBox(width: compact ? 6 : 8), logo];

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: compact ? 104 : 124),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}

/// LIVE badge + chase equation + progress bar + score/target labels.
class _CenterBlock extends StatelessWidget {
  const _CenterBlock({
    required this.match,
    required this.chase,
    required this.compact,
  });

  final CricketMatch match;
  final _ChaseInfo chase;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    // Single source of truth for the live badge + status note, so the floating
    // bar never shows a generic LIVE while the note says "Day 1: Stumps" — a
    // paused live match reads STUMPS/LUNCH/TEA/INN BREAK in both places.
    final status = MatchStatusDisplay.of(context, match);

    // Status / equation line.
    final Widget statusLine;
    if (match.isFinished) {
      final resultRaw = status.phaseLabel.isNotEmpty
          ? status.phaseLabel
          : (match.resultText.isNotEmpty ? match.resultText : match.statusText);
      final result =
          resultRaw.isEmpty ? '' : shortMatchStatus(resultRaw, match);
      statusLine = Text(
        result.isNotEmpty ? result : 'Match ended',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: c.muted,
          fontWeight: FontWeight.w600,
          fontSize: compact ? 11 : 12,
        ),
      );
    } else if (chase.hasEquation) {
      statusLine = Text(
        'Need ${chase.needRuns} from ${chase.needBalls}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: c.text,
          fontWeight: FontWeight.w700,
          fontSize: compact ? 11 : 13,
        ),
      );
    } else {
      // For a live match use the resolver's phase label (e.g. "Day 1 Stumps");
      // fall back to the status text, then the coarse status label.
      final s = status.phaseLabel.isNotEmpty
          ? shortMatchStatus(status.phaseLabel, match)
          : (match.statusText.isNotEmpty
              ? shortMatchStatus(match.statusText, match)
              : (match.isLive ? 'Live' : match.statusLabel));
      statusLine = Text(
        s,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: c.muted,
          fontWeight: FontWeight.w600,
          fontSize: compact ? 11 : 12,
        ),
      );
    }

    final showProgress = match.isLive && chase.hasProgress;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (match.isLive)
          _LiveBadge(
            compact: compact,
            label: status.badge,
            // Suppress the pulsing dot for a stoppage (stumps/lunch/tea/…).
            pulsing: status.subPhase == MatchSubPhase.live,
          ),
        if (match.isLive) const SizedBox(height: 3),
        statusLine,
        if (showProgress) ...[
          SizedBox(height: compact ? 5 : 6),
          _ProgressBar(value: chase.progress, compact: compact),
          SizedBox(height: compact ? 3 : 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${formatTeamCode(chase.battingShort ?? '')} ${chase.battingScoreText != null ? _splitScore(chase.battingScoreText!).$1 : ''}'
                      .trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: c.isDark ? c.cyan : c.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: compact ? 10 : 11,
                  ),
                ),
              ),
              Text(
                '${chase.target} Target',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: c.muted,
                  fontWeight: FontWeight.w600,
                  fontSize: compact ? 10 : 11,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge({required this.compact, this.label = 'LIVE', this.pulsing = true});
  final bool compact;

  /// Badge word — `LIVE` for an actively-bowling match, or `STUMPS`/`LUNCH`/
  /// `TEA`/`INN BREAK` for a paused live match, so the floating bar never
  /// contradicts the status note.
  final String label;

  /// Whether to show the pulsing live dot. Suppressed for a stoppage so the
  /// badge does not read "live now" while the note says "Day 1 Stumps".
  final bool pulsing;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: compact ? 7 : 8, vertical: compact ? 2 : 3),
      decoration: BoxDecoration(
        color: c.live.withValues(alpha: c.isDark ? .18 : .12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.live.withValues(alpha: .45), width: .8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (pulsing) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: c.live, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              color: c.live,
              fontWeight: FontWeight.w800,
              fontSize: compact ? 9 : 10,
              letterSpacing: .6,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.value, required this.compact});
  final double value;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final h = compact ? 5.0 : 6.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(h),
      child: Stack(
        children: [
          Container(
            height: h,
            color: c.isDark
                ? Colors.white.withValues(alpha: .12)
                : const Color(0xffd8dee8),
          ),
          FractionallySizedBox(
            widthFactor: value.clamp(0.0, 1.0),
            child: Container(
              height: h,
              decoration: BoxDecoration(gradient: c.primaryGradient),
            ),
          ),
        ],
      ),
    );
  }
}
