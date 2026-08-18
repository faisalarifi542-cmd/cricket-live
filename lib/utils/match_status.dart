// Centralized match status display — the single source of truth for the status
// BADGE + phase LABEL shown on every match card (Home hero, Home live/upcoming/
// finished cards, Matches list cards, minimized score bar). It reconciles the
// coarse [CricketMatch.status] (live/upcoming/completed/…) with the finer-grained
// backend `phase` field (stumps/lunch/tea/drinks/rain/innings_break) so the badge
// and the phase label NEVER contradict each other — the bug where a card showed a
// red "LIVE NOW" pill alongside "Day 1: Stumps" text.
//
// Resolution order:
//   1. The backend `phase` field (added to all three providers) — authoritative
//      when present.
//   2. A heuristic on [CricketMatch.statusText] ("Stumps Day 1", "Lunch", "Tea",
//      "Innings Break", "Drinks", "Rain delay") so cached/older payloads that
//      predate the `phase` field still classify correctly without a forced
//      refresh.
//   3. The coarse [CricketMatch.status] / isLive/isFinished flags as the final
//      fallback.
//
// This is DISPLAY ONLY: it does not change [MatchPhase] classification, polling,
// or tab selection. A stumps/lunch/tea match is still coarse `live` for polling
// purposes — it just shows a STUMPS/LUNCH/TEA badge instead of a generic LIVE.
import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../models/cricket_match.dart';

/// The canonical live sub-phase, surfaced by the backend `phase` field. Mirrors
/// the backend `derivePhase` token set. `unknown` = not provided.
enum MatchSubPhase {
  live,
  stumps,
  lunch,
  tea,
  drinks,
  rain,
  inningsBreak,
  upcoming,
  completed,
  abandoned,
  noResult,
  unknown,
}

MatchSubPhase _parsePhase(String phase) {
  switch (phase) {
    case 'live':
      return MatchSubPhase.live;
    case 'stumps':
      return MatchSubPhase.stumps;
    case 'lunch':
      return MatchSubPhase.lunch;
    case 'tea':
      return MatchSubPhase.tea;
    case 'drinks':
      return MatchSubPhase.drinks;
    case 'rain':
      return MatchSubPhase.rain;
    case 'innings_break':
    case 'inningsbreak':
      return MatchSubPhase.inningsBreak;
    case 'upcoming':
      return MatchSubPhase.upcoming;
    case 'completed':
      return MatchSubPhase.completed;
    case 'abandoned':
      return MatchSubPhase.abandoned;
    case 'no_result':
    case 'noresult':
      return MatchSubPhase.noResult;
    default:
      return MatchSubPhase.unknown;
  }
}

/// Detects a live sub-phase from free-form status text (the fallback when the
/// backend `phase` field is absent, e.g. cached payloads predating the field).
/// Order matters: most-specific phrases first so "innings break" beats a bare
/// "break" and "tea break" beats "tea".
MatchSubPhase _phaseFromText(String text) {
  final t = text.toLowerCase();
  if (t.isEmpty) return MatchSubPhase.unknown;
  if (t.contains('stumps')) return MatchSubPhase.stumps;
  if (t.contains('innings break') || t.contains('innings_break')) {
    return MatchSubPhase.inningsBreak;
  }
  if (t.contains('lunch')) return MatchSubPhase.lunch;
  if (t.contains('tea break') ||
      t.contains('tea interval') ||
      t.contains(' tea')) {
    return MatchSubPhase.tea;
  }
  if (t.contains('drinks')) return MatchSubPhase.drinks;
  if (t.contains('rain') ||
      t.contains('wet outfield') ||
      t.contains('bad light')) {
    return MatchSubPhase.rain;
  }
  return MatchSubPhase.unknown;
}

/// The resolved status display for a match: the short BADGE word (LIVE / STUMPS /
/// LUNCH / TEA / INN BREAK / UPCOMING / RESULT / ABANDONED) plus a human PHASE
/// LABEL for the note/center-pill area, and the badge color. Both come from one
/// place so they can never disagree.
class MatchStatusDisplay {
  const MatchStatusDisplay({
    required this.badge,
    required this.phaseLabel,
    required this.color,
    required this.subPhase,
  });

  /// Short all-caps badge word, e.g. `LIVE`, `STUMPS`, `LUNCH`, `UPCOMING`,
  /// `RESULT`, `ABANDONED`. Always short enough for a pill.
  final String badge;

  /// Human phase/result label for the note line or center pill, e.g.
  /// `Day 1 Stumps`, `Lunch break`, `Innings break`, or the provider result text
  /// for a finished match. Empty when the caller should fall back to its own
  /// date/time note (upcoming matches with no status text).
  final String phaseLabel;

  /// Badge color. Live-family uses the live red (stumps/lunch/tea/drinks/rain
  /// are still live matches, just paused), upcoming uses cyan, finished uses
  /// success green, abandoned uses warning amber.
  final Color color;

  /// The resolved sub-phase (useful for callers that want to know whether the
  /// match is in a stoppage without re-parsing strings).
  final MatchSubPhase subPhase;

  /// True for a live match that is currently in a stoppage/break (stumps, lunch,
  /// tea, drinks, rain, innings break) — i.e. NOT actively bowling. Convenience
  /// for callers that want to suppress a pulsing "live now" animation.
  bool get isInBreak => subPhase == MatchSubPhase.stumps ||
      subPhase == MatchSubPhase.lunch ||
      subPhase == MatchSubPhase.tea ||
      subPhase == MatchSubPhase.drinks ||
      subPhase == MatchSubPhase.rain ||
      subPhase == MatchSubPhase.inningsBreak;

  /// True when the badge represents a live (possibly paused) match.
  bool get isLiveFamily => subPhase == MatchSubPhase.live || isInBreak;

  /// Resolves the status display for [match]. [context] supplies the theme
  /// colors; pass a build context from any card.
  factory MatchStatusDisplay.of(BuildContext context, CricketMatch match) {
    final c = context.cric;
    final phase = _parsePhase(match.phase);
    final fromText = _phaseFromText(match.statusText);

    // Finished / terminal — show RESULT (or ABANDONED) + the result text.
    if (match.isFinished) {
      if (match.status == 'abandoned' ||
          phase == MatchSubPhase.abandoned ||
          match.statusText.toLowerCase().contains('abandon')) {
        return MatchStatusDisplay(
          badge: 'ABANDONED',
          phaseLabel: match.statusText.isNotEmpty
              ? match.statusText
              : 'Match abandoned',
          color: c.warning,
          subPhase: MatchSubPhase.abandoned,
        );
      }
      if (match.status == 'no_result' || phase == MatchSubPhase.noResult) {
        return MatchStatusDisplay(
          badge: 'NO RESULT',
          phaseLabel:
              match.statusText.isNotEmpty ? match.statusText : 'No result',
          color: c.warning,
          subPhase: MatchSubPhase.noResult,
        );
      }
      final result = match.resultText.isNotEmpty
          ? match.resultText
          : match.statusText;
      return MatchStatusDisplay(
        badge: 'RESULT',
        phaseLabel: result,
        color: c.success,
        subPhase: MatchSubPhase.completed,
      );
    }

    // Upcoming — badge UPCOMING, no phase label (caller shows the date/time).
    if (!match.isLive) {
      return MatchStatusDisplay(
        badge: 'UPCOMING',
        phaseLabel: '',
        color: c.cyan,
        subPhase: MatchSubPhase.upcoming,
      );
    }

    // Live — refine into a sub-phase. Prefer the backend `phase` field; fall
    // back to the status-text heuristic; else a plain LIVE.
    final sub = phase != MatchSubPhase.unknown
        ? phase
        : (fromText != MatchSubPhase.unknown ? fromText : MatchSubPhase.live);

    switch (sub) {
      case MatchSubPhase.stumps:
        return MatchStatusDisplay(
          badge: 'STUMPS',
          phaseLabel: _composePhaseNote(match.statusText, 'Stumps'),
          color: c.live,
          subPhase: MatchSubPhase.stumps,
        );
      case MatchSubPhase.lunch:
        return MatchStatusDisplay(
          badge: 'LUNCH',
          phaseLabel: _composePhaseNote(match.statusText, 'Lunch'),
          color: c.live,
          subPhase: MatchSubPhase.lunch,
        );
      case MatchSubPhase.tea:
        return MatchStatusDisplay(
          badge: 'TEA',
          phaseLabel: _composePhaseNote(match.statusText, 'Tea'),
          color: c.live,
          subPhase: MatchSubPhase.tea,
        );
      case MatchSubPhase.drinks:
        return MatchStatusDisplay(
          badge: 'DRINKS',
          phaseLabel: _composePhaseNote(match.statusText, 'Drinks'),
          color: c.live,
          subPhase: MatchSubPhase.drinks,
        );
      case MatchSubPhase.rain:
        return MatchStatusDisplay(
          badge: 'RAIN',
          phaseLabel: _composePhaseNote(match.statusText, 'Rain',
              emptyFallback: 'Rain delay'),
          color: c.live,
          subPhase: MatchSubPhase.rain,
        );
      case MatchSubPhase.inningsBreak:
        return MatchStatusDisplay(
          badge: 'INN BREAK',
          phaseLabel: _composePhaseNote(match.statusText, 'Innings Break',
              emptyFallback: 'Innings break'),
          color: c.live,
          subPhase: MatchSubPhase.inningsBreak,
        );
      case MatchSubPhase.live:
      case MatchSubPhase.upcoming:
      case MatchSubPhase.completed:
      case MatchSubPhase.abandoned:
      case MatchSubPhase.noResult:
      case MatchSubPhase.unknown:
        return MatchStatusDisplay(
          badge: 'LIVE',
          phaseLabel: match.statusText,
          color: c.live,
          subPhase: MatchSubPhase.live,
        );
    }
  }

  /// Normalizes a break-phase status note into a clean, natural sentence and
  /// kills the malformed provider shapes seen in the wild:
  ///   "- WI trail by 491 runs Stumps"          -> "WI trail by 491 runs · Stumps"
  ///   "Day 3: Stumps - India A lead by 175 runs"-> "Day 3: Stumps · India A lead by 175 runs"
  ///   "Stumps"                                  -> "Stumps"
  /// It (1) lifts a "Day N" token to the front, (2) removes the phase word from
  /// the body wherever it sits, (3) strips leading/trailing dashes/colons/·, and
  /// (4) recomposes: with a Day prefix the phase leads ("Day N: Phase · note");
  /// without one, the note leads and the phase trails ("note · Phase"). Both read
  /// naturally and never start with a dash.
  static String _composePhaseNote(String statusText, String phase,
      {String? emptyFallback}) {
    var t = statusText.trim();
    if (t.isEmpty) return emptyFallback ?? phase;

    // Lift a "Day N" token to the front and remove it from the body.
    String dayLabel = '';
    final dayMatch =
        RegExp(r'\bday\s*(\d+)\b', caseSensitive: false).firstMatch(t);
    if (dayMatch != null) {
      dayLabel = 'Day ${dayMatch.group(1)}';
      t = t.replaceRange(dayMatch.start, dayMatch.end, ' ');
    }

    // Drop the phase word wherever it appears (whole word, case-insensitive).
    t = t.replaceAll(
        RegExp(r'\b' + RegExp.escape(phase) + r'\b', caseSensitive: false),
        ' ');

    // Strip separators/punctuation left dangling and collapse whitespace so the
    // body never leads with "- " or a stray colon.
    final rest = t
        .replaceAll(RegExp(r'[·•\-–—:,]+'), ' ')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();

    final head = dayLabel.isNotEmpty ? '$dayLabel: $phase' : phase;
    if (rest.isEmpty) return head;
    return dayLabel.isNotEmpty ? '$head · $rest' : '$rest · $phase';
  }
}
