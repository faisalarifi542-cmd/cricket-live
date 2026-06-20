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
//   • Test / multi-innings, roomy (hero / match details):
//         1st 362/10   87.1 ov
//         2nd 391/10   96.2 ov          ← each innings on its own row,
//                                          readable overs, never tiny.
//   • Test / multi-innings, tight (matches card):
//         1st 362/10
//         2nd 391/10
//         87.1 • 96.2 ov
//   • Compact bar → single combined line `362/10 & 391/10` / `87.1 • 96.2 ov`.
//   • Scores NEVER ellipsize. Innings stay in chronological order (oldest
//     first); the current/live innings is highlighted (brighter + a small `*`)
//     but is NEVER reordered ahead of an earlier innings.
//   • Overs use a lowercase `ov` unit, always.
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
  /// highlight as the current/live one (gets the `*` + full brightness). `-1`
  /// (default) means none — used for finished matches and for the team that is
  /// NOT currently batting. Supplied by the call site from
  /// `CricketMatch.currentScoredIndexForTeam`, so the star reflects the real
  /// batting side rather than "the last innings of whichever team is live".
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

  MainAxisAlignment get _rowMainAlign => switch (align) {
        CrossAxisAlignment.start => MainAxisAlignment.start,
        CrossAxisAlignment.end => MainAxisAlignment.end,
        _ => MainAxisAlignment.center,
      };

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final pres = TeamScorePresentation(innings);

    final mainColor =
        color ?? (live ? (c.isDark ? Colors.white : c.text) : c.cyan);
    final ovColor = oversColor ?? c.cyan.withValues(alpha: .84);

    if (!pres.hasScore) {
      if (placeholder.isEmpty) return const SizedBox.shrink();
      return Text(
        placeholder,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: textAlign,
        style: TextStyle(
          color: c.onImageText,
          fontWeight: FontWeight.w600,
          fontSize: oversSize + 1.5,
        ),
      );
    }

    // Multi-innings (Test / first-class) gets a dedicated layout per family so
    // both innings + their overs stay readable — never squeezed onto one tiny
    // FittedBox line. A single batted innings always uses the limited-overs
    // layout regardless of the hinted mode.
    if (pres.isMultiInnings) {
      switch (mode.family) {
        case ScoreLayoutFamily.hero:
        case ScoreLayoutFamily.details:
          return _stackedRows(context, pres, mainColor, ovColor, roomy: true);
        case ScoreLayoutFamily.card:
          return _stackedRows(context, pres, mainColor, ovColor, roomy: false);
        case ScoreLayoutFamily.bar:
          return _combinedLine(pres, mainColor, ovColor);
      }
    }
    return _singleInnings(pres, mainColor, ovColor);
  }

  // ── Single innings / limited overs ─────────────────────────────────────────
  Widget _singleInnings(
      TeamScorePresentation pres, Color mainColor, Color ovColor) {
    final mainStyle = TextStyle(
      color: mainColor,
      fontWeight: FontWeight.w900,
      fontSize: mainSize,
      height: 1.02,
      letterSpacing: .2,
    );
    final oversLine = pres.oversLine(unitEach: !compactOvers);
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
                fontWeight: FontWeight.w700,
                fontSize: oversSize,
                height: 1.05,
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ── Multi-innings: stacked per-innings rows ────────────────────────────────
  /// `roomy` (hero / details) renders each row as `1st  362/10   87.1 ov`.
  /// Tight (matches card) splits into `1st 362/10` rows + one combined overs
  /// line `87.1 • 96.2 ov` underneath so the score never has to shrink to fit
  /// the overs alongside it.
  Widget _stackedRows(BuildContext context, TeamScorePresentation pres,
      Color mainColor, Color ovColor,
      {required bool roomy}) {
    final scored = pres.scored;
    final currentIdx = pres.resolveCurrentIndex(currentInningsIndex);
    // Only dim earlier innings when THIS team has a live/current innings. The
    // non-batting team (currentIdx == -1) keeps all innings at full strength.
    final hasCurrent = currentIdx >= 0;
    final dim = mainColor.withValues(alpha: .62);

    // Readable floors so the overs never collapse into hidden metadata. The
    // caller sizes per mode; we only clamp the overs/ordinal to stay legible.
    final scoreFont = mainSize;
    final oversFont = oversSize.clamp(11.0, 22.0);
    final ordinalFont = (oversFont - 0.5).clamp(9.5, 14.0);

    final rows = <Widget>[];
    for (var i = 0; i < scored.length; i++) {
      final inn = scored[i];
      final isCurrent = i == currentIdx;
      final scoreColor = (live && hasCurrent && !isCurrent) ? dim : mainColor;
      final scoreText = inn.scoreText + (isCurrent ? '*' : '');
      final ordinal = TeamScorePresentation.ordinal(i + 1);
      final overs = inn.oversText;

      final ordinalWidget = Text(
        ordinal,
        style: TextStyle(
          color: ovColor.withValues(alpha: .9),
          fontWeight: FontWeight.w800,
          fontSize: ordinalFont,
          height: 1.0,
        ),
      );
      final scoreWidget = Text(
        scoreText,
        maxLines: 1,
        softWrap: false,
        style: TextStyle(
          color: scoreColor,
          fontWeight: FontWeight.w900,
          fontSize: scoreFont,
          height: 1.05,
          letterSpacing: .2,
        ),
      );

      final rowChildren = <Widget>[
        ordinalWidget,
        SizedBox(width: roomy ? 6 : 5),
        scoreWidget,
        if (roomy && overs.isNotEmpty) ...[
          const SizedBox(width: 8),
          Text(
            '$overs ov',
            maxLines: 1,
            softWrap: false,
            style: TextStyle(
              color: ovColor,
              fontWeight: FontWeight.w700,
              fontSize: oversFont,
              height: 1.05,
            ),
          ),
        ],
      ];

      rows.add(Padding(
        padding: EdgeInsets.only(top: i == 0 ? 0 : (roomy ? 3 : 2)),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: _fitAlign,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: _rowMainAlign,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: rowChildren,
          ),
        ),
      ));
    }

    // Tight card: a single combined overs line beneath the score rows.
    if (!roomy) {
      final oversLine = pres.oversLine(unitEach: false);
      if (oversLine.isNotEmpty) {
        rows.add(Padding(
          padding: EdgeInsets.only(top: gap + 1),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: _fitAlign,
            child: Text(
              oversLine,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                color: ovColor,
                fontWeight: FontWeight.w700,
                fontSize: oversFont,
                height: 1.05,
              ),
            ),
          ),
        ));
      }
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: align,
      children: rows,
    );
  }

  // ── Multi-innings: single combined line (compact bar only) ─────────────────
  Widget _combinedLine(
      TeamScorePresentation pres, Color mainColor, Color ovColor) {
    final base = TextStyle(
      color: mainColor,
      fontWeight: FontWeight.w900,
      fontSize: mainSize,
      height: 1.02,
      letterSpacing: .2,
    );
    final oversLine = pres.oversLine(unitEach: !compactOvers);
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
                fontWeight: FontWeight.w700,
                fontSize: oversSize,
                height: 1.05,
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// `362/10 & 391/10` with the current (last, live) innings full strength + a
  /// small `*`, earlier innings dimmed — order preserved, never reversed.
  Widget _combinedScoreRich(
      TeamScorePresentation pres, TextStyle base, Color mainColor) {
    final scored = pres.scored;
    final currentIdx = pres.resolveCurrentIndex(currentInningsIndex);
    final hasCurrent = currentIdx >= 0;
    final dim = (live && hasCurrent) ? mainColor.withValues(alpha: .62) : mainColor;
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
    return RichText(
      maxLines: 1,
      softWrap: false,
      textAlign: textAlign,
      text: TextSpan(children: spans),
    );
  }
}
