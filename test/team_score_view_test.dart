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
    // The overs line for both innings is present (not hidden behind ellipsis).
    expect(find.text('87.1 • 96.2 ov'), findsOneWidget);
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
    expect(find.text('44.2 ov'), findsOneWidget);
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

  testWidgets('hero multi-innings shows stacked rows with readable overs',
      (tester) async {
    await tester.pumpWidget(_host(
      const TeamScoreView(
        innings: [
          InningsScore(runs: 362, wickets: 10, overs: '87.1'),
          InningsScore(runs: 391, wickets: 10, overs: '96.2'),
        ],
        mode: ScoreDisplayMode.heroMultiInnings,
        mainSize: 26,
        oversSize: 13,
      ),
      width: 150,
    ));
    expect(tester.takeException(), isNull);
    // Both innings + ordinals + per-row overs are present (none hidden/tiny).
    expect(find.text('1st'), findsOneWidget);
    expect(find.text('2nd'), findsOneWidget);
    expect(find.text('362/10'), findsOneWidget);
    expect(find.text('391/10'), findsOneWidget);
    expect(find.text('87.1 ov'), findsOneWidget);
    expect(find.text('96.2 ov'), findsOneWidget);
  });

  testWidgets('matches card multi-innings: stacked scores + one overs line',
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
      width: 110,
    ));
    expect(tester.takeException(), isNull);
    expect(find.text('291/10'), findsOneWidget);
    expect(find.text('90/3'), findsOneWidget); // not 90/3* — this is not live
    expect(find.text('84.0 • 20.1 ov'), findsOneWidget);
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
        mainSize: 26,
        oversSize: 13,
        live: true,
      ),
      width: 160,
    ));
    expect(tester.takeException(), isNull);
    // 1st innings unchanged, current (2nd) innings marked with * — never moved
    // ahead of the first.
    expect(find.text('291/10'), findsOneWidget);
    expect(find.text('90/3*'), findsOneWidget);
    final first = find.text('1st');
    final second = find.text('2nd');
    expect(first, findsOneWidget);
    expect(second, findsOneWidget);
    expect(tester.getTopLeft(first).dy, lessThan(tester.getTopLeft(second).dy));
  });
}
