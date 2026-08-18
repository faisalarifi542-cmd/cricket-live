import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cricpro_flutter/app_theme.dart';
import 'package:cricpro_flutter/models/cricket_match.dart';
import 'package:cricpro_flutter/widgets/team_score_view.dart';

Widget _host(Widget child, {double width = 90}) {
  return MaterialApp(
    theme: cricTheme(true),
    home: Scaffold(
      body: Center(
        child: SizedBox(width: width, child: child),
      ),
    ),
  );
}

void main() {
  testWidgets('Test score fits a tight card width without overflow',
      (tester) async {
    await tester.pumpWidget(_host(
      const TeamScoreView(
        innings: [
          InningsScore(runs: 362, wickets: 10, overs: '87.1'),
          InningsScore(runs: 391, wickets: 10, overs: '96.2'),
        ],
        mainSize: 16,
        oversSize: 11.5,
        compactOvers: true,
      ),
      width: 90,
    ));
    // No RenderFlex/overflow exception was thrown laying out two innings.
    expect(tester.takeException(), isNull);
    // Stacked per-innings rows with inline overs, no `1st`/`2nd` prefix.
    expect(find.text('362/10 · 87.1 OV'), findsOneWidget);
    expect(find.text('391/10 · 96.2 OV'), findsOneWidget);
  });

  testWidgets('limited-overs score shows main score and overs', (tester) async {
    await tester.pumpWidget(_host(
      const TeamScoreView(
        innings: [InningsScore(runs: 218, wickets: 10, overs: '44.2')],
        mainSize: 21,
        oversSize: 12.5,
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.text('218/10'), findsOneWidget);
    expect(find.text('44.2 OVERS'), findsOneWidget);
  });

  testWidgets('yet-to-bat placeholder renders when there is no score',
      (tester) async {
    await tester.pumpWidget(_host(
      const TeamScoreView(
        innings: [],
        mainSize: 21,
        oversSize: 12.5,
        placeholder: 'Yet to bat',
      ),
    ));
    expect(find.text('Yet to bat'), findsOneWidget);
  });

  testWidgets('hero multi-innings shows stacked rows with inline overs',
      (tester) async {
    await tester.pumpWidget(_host(
      const TeamScoreView(
        innings: [
          InningsScore(runs: 362, wickets: 10, overs: '87.1'),
          InningsScore(runs: 391, wickets: 10, overs: '96.2'),
        ],
        mode: ScoreDisplayMode.heroMultiInnings,
        mainSize: 22,
        oversSize: 13,
      ),
      width: 150,
    ));
    expect(tester.takeException(), isNull);
    // Premium stacked format — never the old `1st`/`2nd`-prefixed rows.
    expect(find.text('362/10 · 87.1 OV'), findsOneWidget);
    expect(find.text('391/10 · 96.2 OV'), findsOneWidget);
    expect(find.text('1st'), findsNothing);
    expect(find.text('2nd'), findsNothing);
  });

  testWidgets('matches card multi-innings: stacked rows, not-live has no star',
      (tester) async {
    await tester.pumpWidget(_host(
      const TeamScoreView(
        innings: [
          InningsScore(runs: 291, wickets: 10, overs: '84.0'),
          InningsScore(runs: 90, wickets: 3, overs: '20.1'),
        ],
        mode: ScoreDisplayMode.cardMultiInnings,
        mainSize: 16,
        oversSize: 11.5,
        compactOvers: true,
      ),
      width: 120,
    ));
    expect(tester.takeException(), isNull);
    expect(find.text('291/10 · 84.0 OV'), findsOneWidget);
    expect(find.text('90/3 · 20.1 OV'), findsOneWidget); // no * — not live
  });

  testWidgets('current (live) innings gets a * but order is NOT reversed',
      (tester) async {
    await tester.pumpWidget(_host(
      const TeamScoreView(
        innings: [
          InningsScore(runs: 291, wickets: 10, overs: '84.0'),
          InningsScore(runs: 90, wickets: 3, overs: '20.1'),
        ],
        mode: ScoreDisplayMode.heroMultiInnings,
        mainSize: 22,
        oversSize: 13,
        live: true,
      ),
      width: 160,
    ));
    expect(tester.takeException(), isNull);
    // 1st innings first (no star), current 2nd innings starred — order kept.
    expect(find.text('291/10 · 84.0 OV'), findsOneWidget);
    expect(find.text('90/3* · 20.1 OV'), findsOneWidget);
  });

  testWidgets(
      'hero Test preset: overs smaller than score, score 15–18, overs 12–14, '
      'overs WHITE not cyan', (tester) async {
    await tester.pumpWidget(_host(
      const TeamScoreView(
        innings: [
          InningsScore(runs: 438, wickets: 10, overs: '114.5'),
          InningsScore(runs: 288, wickets: 9, overs: '94.0', declared: true),
        ],
        mode: ScoreDisplayMode.heroMultiInnings,
        mainSize: 26, // intentionally oversized — must be clamped down
        oversSize: 18, // intentionally oversized — must be clamped down
        live: true,
        currentInningsIndex: 1,
      ),
      width: 220,
    ));
    expect(tester.takeException(), isNull);

    final richTexts = tester
        .widgetList<Text>(find.byType(Text))
        .where((t) => t.textSpan != null)
        .toList();
    expect(richTexts, isNotEmpty);
    final root = richTexts.first.textSpan! as TextSpan;
    final children = root.children!.cast<TextSpan>();
    // [score, separator(·), overs] for a row that carries overs.
    final scoreSize = children.first.style!.fontSize!;
    final oversSpan = children.last;
    final oversSize = oversSpan.style!.fontSize!;
    final oversColor = oversSpan.style!.color!;

    expect(scoreSize, inInclusiveRange(15.0, 18.0));
    expect(oversSize, inInclusiveRange(12.0, 14.0));
    expect(oversSize < scoreSize, isTrue,
        reason: 'overs must be smaller than the runs/wickets');
    // Overs are white / near-white in dark mode — NOT cyan (cyan luminance
    // ~0.71, white ~1.0).
    expect(oversColor.computeLuminance() > 0.85, isTrue,
        reason: 'overs text must be white/near-white, not cyan');
  });

  testWidgets('Home hero white-ball score is capped (not oversized)',
      (tester) async {
    await tester.pumpWidget(_host(
      const TeamScoreView(
        innings: [InningsScore(runs: 112, wickets: 6, overs: '16.4')],
        mode: ScoreDisplayMode.heroLimitedOvers,
        mainSize: 46, // oversized request
        oversSize: 28,
        live: true,
      ),
      width: 200,
    ));
    expect(tester.takeException(), isNull);
    final score = tester.widget<Text>(find.text('112/6'));
    expect(score.style!.fontSize! <= 34.0, isTrue,
        reason: 'white-ball hero score must be capped at 34');
    expect(score.style!.fontSize! >= 26.0, isTrue);
  });

  testWidgets('Matches Test card score stays readable (>=18)', (tester) async {
    await tester.pumpWidget(_host(
      const TeamScoreView(
        innings: [
          InningsScore(runs: 438, wickets: 10, overs: '114.5'),
          InningsScore(runs: 288, wickets: 9, overs: '94.0', declared: true),
        ],
        mode: ScoreDisplayMode.cardMultiInnings,
        mainSize: 22,
        oversSize: 14,
        compactOvers: true,
      ),
      width: 150,
    ));
    expect(tester.takeException(), isNull);
    final richTexts = tester
        .widgetList<Text>(find.byType(Text))
        .where((t) => t.textSpan != null)
        .toList();
    final root = richTexts.first.textSpan! as TextSpan;
    final children = root.children!.cast<TextSpan>();
    expect(children.first.style!.fontSize!, inInclusiveRange(18.0, 22.0));
    expect(children.last.style!.fontSize!, inInclusiveRange(13.0, 15.0));
  });

  testWidgets(
      'Schedule Test score uses the shared card component (not mini text) and '
      'does not overflow a narrow side-by-side column', (tester) async {
    // Schedule places the logo BESIDE the text, so the score column is narrow;
    // it must still use the shared card preset (score 18–22 / overs 13–15) and
    // never throw an overflow.
    await tester.pumpWidget(_host(
      const TeamScoreView(
        innings: [
          InningsScore(runs: 438, wickets: 10, overs: '114.5'),
          InningsScore(runs: 288, wickets: 9, overs: '94.0', declared: true),
        ],
        mode: ScoreDisplayMode.cardMultiInnings,
        mainSize: 17,
        oversSize: 13,
        align: CrossAxisAlignment.start,
        textAlign: TextAlign.left,
        compactOvers: true,
      ),
      width: 96,
    ));
    expect(tester.takeException(), isNull);
    expect(find.text('438/10 · 114.5 OV'), findsOneWidget);
    expect(find.text('288/9d · 94.0 OV'), findsOneWidget);
    final richTexts = tester
        .widgetList<Text>(find.byType(Text))
        .where((t) => t.textSpan != null)
        .toList();
    final children = (richTexts.first.textSpan! as TextSpan).children!.cast<TextSpan>();
    // The shared card preset is applied (NOT a tiny one-off size).
    expect(children.first.style!.fontSize!, inInclusiveRange(18.0, 22.0));
    expect(children.last.style!.fontSize!, inInclusiveRange(13.0, 15.0));
  });

  testWidgets(
      'same Test match renders the SAME row structure in hero and card modes',
      (tester) async {
    const innings = [
      InningsScore(runs: 438, wickets: 10, overs: '114.5'),
      InningsScore(runs: 288, wickets: 9, overs: '94.0', declared: true),
    ];
    for (final mode in const [
      ScoreDisplayMode.heroMultiInnings,
      ScoreDisplayMode.cardMultiInnings,
      ScoreDisplayMode.matchDetailsMultiInnings,
    ]) {
      await tester.pumpWidget(_host(
        TeamScoreView(
          innings: innings,
          mode: mode,
          mainSize: 18,
          oversSize: 13,
        ),
        width: 200,
      ));
      expect(tester.takeException(), isNull, reason: '$mode overflowed');
      // Identical row strings everywhere — no `1st`/`2nd`, declared `d` kept.
      expect(find.text('438/10 · 114.5 OV'), findsOneWidget, reason: '$mode');
      expect(find.text('288/9d · 94.0 OV'), findsOneWidget, reason: '$mode');
      expect(find.text('1st'), findsNothing);
      expect(find.text('2nd'), findsNothing);
    }
  });
}
