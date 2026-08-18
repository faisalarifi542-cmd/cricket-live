// Reusable, professional team-score renderer used by every score block in the
// app (Home hero, Home/Matches cards, Match Details header, minimized score
// bar). It renders ONLY the score area (the lines under a team's code/logo), so
// each call site keeps its own logo, code, colors and glow while the score
// presentation itself is centralized here.
//
// It is CONTEXT-AWARE via [ScoreDisplayMode]: each mode owns its own font
// sizing, layout type, spacing and current-innings highlight — instead of one
// generic FittedBox layout forced onto every screen. Rules enforced everywhere:
//   • Limited-overs / single innings →   218/10  /  44.2 ov
//   • Test / multi-innings (hero / cards / match details header) → ONE clean
//     combined score line, premium cricket style, NEVER prefixed with `1st`/
//     `2nd`:
//         438/10 & 126/3*               ← score line (current innings starred)
//         87.1 ov • 96.2 ov             ← overs line (roomy), or
//         87.1 • 96.2 ov                ← overs line (tight cards / compact bar)
//     Innings ordinal labels (`1st`/`2nd`) belong ONLY to the Scorecard tab
//     headers (see `md_panels.dart`), never inline before a score value.
//   • Scores NEVER ellipsize. Innings stay in chronological order (oldest
//     first); the current/live innings is highlighted (brighter + a small `*`)
//     but is NEVER reordered ahead of an earlier innings.
//   • Overs unit matches the Home premium style everywhere: a single innings
//     reads `44.2 OVERS`, multi-innings rows read `87.1 OV` — so a score looks
//     IDENTICAL on Home, Matches, Schedule, Match Details and the compact bar.
//     (The pure presentation layer + legacy flat strings keep lowercase `ov`;
//     the uppercase treatment is display-only, applied here.)
import 'package:flutter/material.dart';

import 'package:cricpro_flutter/app_theme.dart';
import 'package:cricpro_flutter/models/cricket_match.dart';
import 'package:cricpro_flutter/utils/score_presentation.dart';
// Re-export the display mode so call sites that import this widget can name it
// without a separate import.
export 'package:cricpro_flutter/utils/score_presentation.dart'
    show ScoreDisplayMode;

class TeamScoreView extends StatelessWidget {
  const TeamScoreView({
    super.key,
    required this.innings,
    required this.mainSize,
    required this.oversSize,
    this.mode = ScoreDisplayMode.cardLimitedOvers,
    this.color,
    this.oversColor,
    this.live = false,
    this.currentInningsIndex = -1,
    this.align = CrossAxisAlignment.center,
    this.textAlign = TextAlign.center,
    this.placeholder = '',
    this.compactOvers = false,
    this.gap = 2,
  });

  /// Structured innings for this team (e.g. `match.teamAInnings`), already in
  /// chronological order (the model normalizes it once at parse).
  final List<InningsScore> innings;

  /// Base font size for the score line / per-innings score rows.
  final double mainSize;

  /// Base font size for the overs line / per-innings overs.
  final double oversSize;

  /// Rendering context (hero / card / details / bar). Drives layout + sizing.
  final ScoreDisplayMode mode;

  /// Score color. Defaults to white when [live] (dark) / cyan otherwise.
  final Color? color;

  /// Overs color. Defaults to a muted cyan.
  final Color? oversColor;

  final bool live;

  /// Index, within this team's SCORED innings (oldest-first), of the innings to
  /// highlight as the current/live one (gets the `*` + full brightness).
  ///
  /// Supplied by the call site from `CricketMatch.currentScoredIndexForTeam`, so
  /// the star reflects the real batting side. Special values:
  ///   • `-1` (default, "auto"): when [live] and the score is multi-innings, the
  ///     latest innings is starred — the standalone fallback when the caller only
  ///     knows the match is live.
  ///   • `kNoCurrentInnings` (-2): never star — used for the team that is NOT
  ///     currently batting, so a live match never stars both teams.
  /// The current innings is never reordered ahead of an earlier one.
  final int currentInningsIndex;
  final CrossAxisAlignment align;
  final TextAlign textAlign;

  /// Shown when there is no score (e.g. `Yet to bat`). Caller decides when this
  /// is appropriate (live match, team genuinely yet to bat); empty hides it.
  final String placeholder;

  /// Tight layouts (list cards) use `87.1 • 96.2 ov`; roomy ones (hero,
  /// details) use `87.1 ov • 96.2 ov`.
  final bool compactOvers;

  /// Vertical gap between score and overs lines.
  final double gap;

  Alignment get _fitAlign => switch (align) {
        CrossAxisAlignment.start => Alignment.centerLeft,
        CrossAxisAlignment.end => Alignment.centerRight,
        _ => Alignment.center,
      };

  /// Display-only overs unit, unified with the Home premium style: a roomy
  /// single-innings line spells `OVERS`; multi-innings rows and the tight
  /// compact bar use the short `OV`. Applied at render time only — the pure
  /// presentation layer (`oversLine`) and legacy flat strings keep `ov`.
  String _displayOvers(String rawOversLine, {required bool single}) {
    if (rawOversLine.isEmpty) return rawOversLine;
    final up = rawOversLine.replaceAll(RegExp(r'\bov\b'), 'OV');
    if (!single) return up;
    return mode.family == ScoreLayoutFamily.bar
        ? up
        : up.replaceFirst(RegExp(r'\bOV$'), 'OVERS');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final pres = TeamScorePresentation(innings);
    final preset = scorePresetFor(mode, multi: pres.isMultiInnings);

    final mainColor =
        color ?? (live ? (c.isDark ? Colors.white : c.text) : c.cyan);
    // Overs read WHITE / near-white (low-contrast cyan on the blue stadium
    // backdrop was hard to read). Only the small separator dot stays cyan.
    final ovColor =
        oversColor ?? (c.isDark ? Colors.white.withValues(alpha: .92) : c.text);
    final sepColor = c.cyan.withValues(alpha: c.isDark ? .9 : .8);

    if (!pres.hasScore) {
      if (placeholder.isEmpty) return const SizedBox.shrink();
      // A side yet to bat must read as MUTED secondary text — never a big white
      // score. Capped small and de-emphasised so it sits quietly under the code.
      return Text(
        placeholder,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: textAlign,
        style: TextStyle(
          color: c.onImageText.withValues(alpha: c.isDark ? .70 : .66),
          fontWeight: FontWeight.w600,
          fontSize: oversSize.clamp(11.0, 14.5),
          letterSpacing: .2,
        ),
      );
    }

    // Multi-innings (Test / first-class): a per-innings STACKED layout with the
    // overs inline on each row — premium and readable on small devices:
    //     438/10 · 114.5 ov
    //     288/9d* · 94.0 ov     (current innings starred; declared shows `d`)
    // NO `1st`/`2nd` prefixes; the current/live innings is brighter + starred,
    // earlier innings dimmed; order is chronological (never reversed). The
    // compact score bar keeps the single combined line. A single batted innings
    // always uses the limited-overs layout regardless of the hinted mode.
    if (pres.isMultiInnings) {
      if (mode.family == ScoreLayoutFamily.bar) {
        return _combinedLine(pres, preset, mainColor, ovColor);
      }
      return _stackedInlineRows(pres, preset, mainColor, ovColor, sepColor);
    }
    return _singleInnings(pres, preset, mainColor, ovColor);
  }

  // ── Multi-innings: stacked rows with inline overs (`438/10 · 114.5 ov`) ─────
  Widget _stackedInlineRows(TeamScorePresentation pres, ScorePreset preset,
      Color mainColor, Color ovColor, Color sepColor) {
    final scored = pres.scored;
    final currentIdx =
        pres.resolveCurrentIndex(currentInningsIndex, live: live);
    final hasCurrent = currentIdx >= 0;
    final dim = mainColor.withValues(alpha: .62);
    // Premium hierarchy enforced centrally by the preset: runs/wickets stay
    // dominant, overs stay clearly readable and WHITE, and the score is small
    // enough that the inline row fits a 360dp column without the FittedBox
    // shrinking the overs into the unreadable range.
    final scoreFont = mainSize.clamp(preset.scoreMin, preset.scoreMax);
    final oversFont = oversSize.clamp(preset.oversMin, preset.oversMax);
    final rowGap = preset.rowSpacing;

    final rows = <Widget>[];
    for (var i = 0; i < scored.length; i++) {
      final inn = scored[i];
      final isCurrent = i == currentIdx;
      final scoreColor = (live && hasCurrent && !isCurrent) ? dim : mainColor;
      final scoreText = inn.scoreText + (isCurrent ? '*' : '');
      final overs = inn.oversText;
      final spans = <InlineSpan>[
        TextSpan(
          text: scoreText,
          style: TextStyle(
            color: scoreColor,
            fontWeight: preset.scoreWeight,
            fontSize: scoreFont,
            height: preset.scoreHeight,
            letterSpacing: .2,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        if (overs.isNotEmpty) ...[
          // The separator dot stays cyan (a deliberate accent); the overs
          // NUMBER itself is white/near-white for contrast on the backdrop. A
          // little letterSpacing gives the dot real breathing room without
          // changing the rendered string.
          TextSpan(
            text: ' · ',
            style: TextStyle(
              color: sepColor,
              fontWeight: FontWeight.w800,
              fontSize: oversFont,
              height: preset.oversHeight,
              letterSpacing: 1.6,
            ),
          ),
          TextSpan(
            text: '$overs OV',
            style: TextStyle(
              color: ovColor,
              fontWeight: preset.oversWeight,
              fontSize: oversFont,
              height: preset.oversHeight,
              letterSpacing: .1,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ];
      rows.add(Padding(
        padding: EdgeInsets.only(top: i == 0 ? 0 : rowGap),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: _fitAlign,
          child: Text.rich(
            TextSpan(children: spans),
            maxLines: 1,
            softWrap: false,
            textAlign: textAlign,
          ),
        ),
      ));
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: align,
      children: rows,
    );
  }

  // ── Single innings / limited overs ─────────────────────────────────────────
  Widget _singleInnings(TeamScorePresentation pres, ScorePreset preset,
      Color mainColor, Color ovColor) {
    final scoreFont = mainSize.clamp(preset.scoreMin, preset.scoreMax);
    final oversFont = oversSize.clamp(preset.oversMin, preset.oversMax);
    final mainStyle = TextStyle(
      color: mainColor,
      fontWeight: preset.scoreWeight,
      fontSize: scoreFont,
      height: 1.02,
      letterSpacing: .2,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final oversLine =
        _displayOvers(pres.oversLine(unitEach: !compactOvers), single: true);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: align,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: _fitAlign,
          child: Text(
            pres.combinedScore,
            maxLines: 1,
            softWrap: false,
            style: mainStyle,
          ),
        ),
        if (oversLine.isNotEmpty) ...[
          SizedBox(height: gap),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: _fitAlign,
            child: Text(
              oversLine,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                color: ovColor,
                fontWeight: preset.oversWeight,
                fontSize: oversFont,
                height: preset.oversHeight,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ── Multi-innings: single combined line ────────────────────────────────────
  Widget _combinedLine(TeamScorePresentation pres, ScorePreset preset,
      Color mainColor, Color ovColor) {
    final scoreFont = mainSize.clamp(preset.scoreMin, preset.scoreMax);
    final oversFont = oversSize.clamp(preset.oversMin, preset.oversMax);
    final base = TextStyle(
      color: mainColor,
      fontWeight: preset.scoreWeight,
      fontSize: scoreFont,
      height: 1.02,
      letterSpacing: .2,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final oversLine =
        _displayOvers(pres.oversLine(unitEach: !compactOvers), single: false);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: align,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: _fitAlign,
          child: _combinedScoreRich(pres, base, mainColor),
        ),
        if (oversLine.isNotEmpty) ...[
          SizedBox(height: gap),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: _fitAlign,
            child: Text(
              oversLine,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                color: ovColor,
                fontWeight: preset.oversWeight,
                fontSize: oversFont,
                height: preset.oversHeight,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// `438/10 & 126/3*` with the current (last, live) innings full strength + a
  /// small `*`, earlier innings dimmed — order preserved, never reversed. Uses
  /// `Text.rich` so the whole combined string is a single discoverable Text.
  Widget _combinedScoreRich(
      TeamScorePresentation pres, TextStyle base, Color mainColor) {
    final scored = pres.scored;
    final currentIdx =
        pres.resolveCurrentIndex(currentInningsIndex, live: live);
    final hasCurrent = currentIdx >= 0;
    final dim =
        (live && hasCurrent) ? mainColor.withValues(alpha: .62) : mainColor;
    final spans = <TextSpan>[];
    for (var i = 0; i < scored.length; i++) {
      final isCurrent = i == currentIdx;
      if (i > 0) {
        spans.add(TextSpan(text: ' & ', style: base.copyWith(color: dim)));
      }
      spans.add(TextSpan(
        text: scored[i].scoreText + (isCurrent ? '*' : ''),
        style: base.copyWith(color: isCurrent ? mainColor : dim),
      ));
    }
    return Text.rich(
      TextSpan(children: spans),
      maxLines: 1,
      softWrap: false,
      textAlign: textAlign,
    );
  }
}

/// Centralized score typography preset — the single source of truth for score
/// vs overs sizing/weight/spacing per context AND match type, so the same
/// shared renderer looks right on the Home hero, live/upcoming cards, the
/// Matches screen, Schedule and Match Details without per-screen patching.
///
/// Sizes are responsive BOUNDS: the call site passes a device-tuned target
/// (`mainSize`/`oversSize`) and the renderer clamps it into `[min, max]`, so a
/// white-ball hero score can never balloon and a Test card score can never
/// shrink to an unreadable size. Overs never fall below `oversMin`.
class ScorePreset {
  const ScorePreset({
    required this.scoreMin,
    required this.scoreMax,
    required this.oversMin,
    required this.oversMax,
    this.scoreWeight = FontWeight.w900,
    this.oversWeight = FontWeight.w700,
    this.scoreHeight = 1.1,
    this.oversHeight = 1.08,
    this.rowSpacing = 4,
  });

  final double scoreMin;
  final double scoreMax;
  final double oversMin;
  final double oversMax;
  final FontWeight scoreWeight;
  final FontWeight oversWeight;
  final double scoreHeight;
  final double oversHeight;
  final double rowSpacing;
}

/// Resolves the preset for a [ScoreDisplayMode] and match type. White-ball
/// (single innings) and Test (multi-innings) get DIFFERENT presets so a T20
/// hero score stays balanced while a Test shows two readable innings rows.
///
/// Targets (overs are WHITE everywhere, 13–15 except the tight compact/bar):
///   • Home hero white-ball  → score 26–34, overs 13–15
///   • Home hero Test        → score 17–20 per row, overs 13–15
///   • Match list white-ball → score 22–26, overs 13–15
///   • Match list Test       → score 18–22 per row, overs 13–15
///   • Match details         → score 24–28 / Test 17–20, overs 13–15
///   • Compact grid cell     → score 16–20 / Test 16–18, overs 12.5–14
///   • Compact bar           → score 13–18, overs 12–14
ScorePreset scorePresetFor(ScoreDisplayMode mode, {required bool multi}) {
  switch (mode.family) {
    case ScoreLayoutFamily.hero:
      return multi
          ? const ScorePreset(
              scoreMin: 15,
              scoreMax: 18,
              oversMin: 12,
              oversMax: 14,
              rowSpacing: 6)
          : const ScorePreset(
              scoreMin: 26, scoreMax: 34, oversMin: 13, oversMax: 15);
    case ScoreLayoutFamily.card:
      return multi
          ? const ScorePreset(
              scoreMin: 18,
              scoreMax: 22,
              oversMin: 13,
              oversMax: 15,
              rowSpacing: 5)
          : const ScorePreset(
              scoreMin: 22, scoreMax: 26, oversMin: 13, oversMax: 15);
    case ScoreLayoutFamily.details:
      return multi
          ? const ScorePreset(
              scoreMin: 17,
              scoreMax: 20,
              oversMin: 13,
              oversMax: 15,
              rowSpacing: 6)
          : const ScorePreset(
              scoreMin: 24, scoreMax: 28, oversMin: 13, oversMax: 15);
    case ScoreLayoutFamily.compact:
      return multi
          ? const ScorePreset(
              scoreMin: 16,
              scoreMax: 18,
              oversMin: 12.5,
              oversMax: 14,
              rowSpacing: 4)
          : const ScorePreset(
              scoreMin: 16, scoreMax: 20, oversMin: 12.5, oversMax: 14);
    case ScoreLayoutFamily.bar:
      return const ScorePreset(
          scoreMin: 13, scoreMax: 18, oversMin: 12, oversMax: 14);
  }
}
