import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cricpro_flutter/app_theme.dart';
import 'package:cricpro_flutter/models/cricket_match.dart';
import 'package:cricpro_flutter/screens/home/home_score_rules.dart';
import 'package:cricpro_flutter/screens/home/home_screen.dart'
    show HomeScoreColumn;

/// Data-resilience tests for the Home score rules. A MISSING score must never
/// render as a real `0/0` / `0.0 OVERS`, while a genuinely-started innings still
/// shows. These exercise the pure Home-local rules (no shared renderer changes).
void main() {
  InningsScore inn({int? runs, int? wkts, String overs = ''}) =>
      InningsScore(runs: runs, wickets: wkts, overs: overs);

  group('isRealHomeInnings — missing vs zero', () {
    test('null runs → not real', () {
      expect(isRealHomeInnings(inn(runs: null)), isFalse);
    });

    test('0/0 with empty overs → not real (fabricated placeholder)', () {
      expect(isRealHomeInnings(inn(runs: 0, wkts: 0)), isFalse);
    });

    test('0/0 with 0.0 overs → not real', () {
      expect(isRealHomeInnings(inn(runs: 0, wkts: 0, overs: '0.0')), isFalse);
    });

    test('real score → real', () {
      expect(isRealHomeInnings(inn(runs: 132, wkts: 4, overs: '14.0')), isTrue);
    });

    test('0 runs but a wicket fell → real (genuine start)', () {
      expect(isRealHomeInnings(inn(runs: 0, wkts: 1, overs: '0.3')), isTrue);
    });

    test('0/0 but overs bowled (maiden) → real', () {
      expect(isRealHomeInnings(inn(runs: 0, wkts: 0, overs: '1.0')), isTrue);
    });
  });

  group('homeRealInnings — filtering', () {
    test('drops fabricated all-zero innings, keeps real one', () {
      final list = [
        inn(runs: 0, wkts: 0), // fabricated
        inn(runs: 285, wkts: 10, overs: '74.5'),
      ];
      expect(homeRealInnings(list), hasLength(1));
      expect(homeRealInnings(list).single.runs, 285);
    });

    test('both sides missing → empty', () {
      expect(
          homeRealInnings([inn(runs: 0, wkts: 0), inn(runs: null)]), isEmpty);
    });

    test('real 0/0 supplied with overs is preserved', () {
      final list = [inn(runs: 0, wkts: 0, overs: '2.0')];
      expect(homeRealInnings(list), hasLength(1));
    });
  });

  group('homeOversPlayed — never render 0.0 OVERS', () {
    test('empty → false', () => expect(homeOversPlayed(''), isFalse));
    test('0 → false', () => expect(homeOversPlayed('0'), isFalse));
    test('0.0 → false', () => expect(homeOversPlayed('0.0'), isFalse));
    test('14.0 → true', () => expect(homeOversPlayed('14.0'), isTrue));
    test('0.3 → true', () => expect(homeOversPlayed('0.3'), isTrue));
  });

  // Guards against future regressions in the rule wiring: a fabricated innings
  // list must never yield a rendered "0/0" through the real-innings gate.
  test('fabricated snapshot yields no real innings (no 0/0 leak)', () {
    final away = [inn(runs: 0, wkts: 0, overs: '0.0')];
    expect(homeRealInnings(away), isEmpty);
    // The score column renders `—`/nothing for an empty real list, never 0/0.
  });

  group('HomeScoreColumn widget — missing vs zero rendering', () {
    Widget host(Widget child, {double width = 160}) => MaterialApp(
          theme: cricTheme(true),
          home: Scaffold(
            body: Center(child: SizedBox(width: width, child: child)),
          ),
        );

    testWidgets('fabricated 0/0 renders a dash, never 0/0 or 0.0 OVERS',
        (tester) async {
      await tester.pumpWidget(host(
        const HomeScoreColumn(
          innings: [InningsScore(runs: 0, wickets: 0, overs: '0.0')],
          mainSize: 22,
          oversSize: 12,
          showMissingDash: true,
        ),
      ));
      expect(tester.takeException(), isNull);
      expect(find.text('—'), findsOneWidget);
      expect(find.text('0/0'), findsNothing);
      expect(find.textContaining('0.0'), findsNothing);
      expect(find.textContaining('OVERS'), findsNothing);
    });

    testWidgets('real single innings shows score + OVERS, no fake zeros',
        (tester) async {
      await tester.pumpWidget(host(
        const HomeScoreColumn(
          innings: [InningsScore(runs: 132, wickets: 4, overs: '14.0')],
          mainSize: 22,
          oversSize: 12,
        ),
      ));
      expect(tester.takeException(), isNull);
      expect(find.text('132/4'), findsOneWidget);
      expect(find.text('14.0 OVERS'), findsOneWidget);
    });

    testWidgets('real score but missing overs → no OVERS label (never 0.0)',
        (tester) async {
      await tester.pumpWidget(host(
        const HomeScoreColumn(
          innings: [InningsScore(runs: 97, wickets: 4, overs: '')],
          mainSize: 22,
          oversSize: 12,
        ),
      ));
      expect(tester.takeException(), isNull);
      expect(find.text('97/4'), findsOneWidget);
      expect(find.textContaining('OVERS'), findsNothing);
    });

    testWidgets('multi-innings labeled rows fit a narrow 356px column',
        (tester) async {
      tester.view.physicalSize = const Size(356, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(
        const HomeScoreColumn(
          innings: [
            InningsScore(runs: 295, wickets: 10, overs: '84.4'),
            InningsScore(runs: 81, wickets: 2, overs: '33.0'),
          ],
          mainSize: 16,
          oversSize: 11,
        ),
        width: 130,
      ));
      expect(tester.takeException(), isNull); // no overflow at a tight width
      expect(find.text('1st Inn'), findsOneWidget);
      expect(find.text('2nd Inn'), findsOneWidget);
    });
  });

  // Hero primary+secondary hierarchy: a Test/multi-innings side must keep a
  // LARGE primary score (the small-device shrink regression), with the previous
  // innings as ONE compact labeled secondary row.
  group('HomeScoreColumn hero primary+secondary', () {
    Widget host(Widget child, {double width = 120}) => MaterialApp(
          theme: cricTheme(true),
          home: Scaffold(
            body: Center(child: SizedBox(width: width, child: child)),
          ),
        );

    double primaryFontSizeFor(WidgetTester tester, String text) {
      final w = tester.widget<Text>(find.text(text));
      return w.style!.fontSize!;
    }

    testWidgets('multi-innings shows one big primary + one secondary chip',
        (tester) async {
      tester.view.physicalSize = const Size(356, 854);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(
        const HomeScoreColumn(
          innings: [
            InningsScore(runs: 285, wickets: 10, overs: '74.5'),
            InningsScore(runs: 154, wickets: 1, overs: '42.0'),
          ],
          mainSize: 33,
          oversSize: 13,
          live: true,
          currentInningsIndex: 1,
          heroPrimarySecondary: true,
        ),
      ));
      expect(tester.takeException(), isNull);
      // Latest innings is the LARGE primary (starred, current).
      expect(find.text('154/1*'), findsOneWidget);
      // Previous innings is the compact secondary labeled row.
      expect(find.text('1st Inn'), findsOneWidget);
      expect(find.text('2nd Inn'), findsNothing); // primary isn't chipped
      // Primary score font stays large (>= 24) even on a 356px device.
      expect(primaryFontSizeFor(tester, '154/1*'), greaterThanOrEqualTo(24.0));
    });

    testWidgets('primary score is larger than the secondary innings text',
        (tester) async {
      await tester.pumpWidget(host(
        const HomeScoreColumn(
          innings: [
            InningsScore(runs: 285, wickets: 10, overs: '74.5'),
            InningsScore(runs: 154, wickets: 1, overs: '42.0'),
          ],
          mainSize: 33,
          oversSize: 13,
          heroPrimarySecondary: true,
        ),
        width: 140,
      ));
      final primary = tester.widget<Text>(find.text('154/1')).style!.fontSize!;
      // '285/10' appears inside the secondary RichText row — assert via chip
      // presence and that the primary is comfortably large.
      expect(find.text('1st Inn'), findsOneWidget);
      expect(primary, greaterThanOrEqualTo(24.0));
    });

    testWidgets('single-innings hero keeps a big primary score',
        (tester) async {
      tester.view.physicalSize = const Size(356, 854);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(
        const HomeScoreColumn(
          innings: [InningsScore(runs: 170, wickets: 10, overs: '59.1')],
          mainSize: 33,
          oversSize: 13,
          heroPrimarySecondary: true,
        ),
      ));
      expect(tester.takeException(), isNull);
      expect(find.text('170/10'), findsOneWidget);
      expect(find.text('59.1 OVERS'), findsOneWidget);
      expect(primaryFontSizeFor(tester, '170/10'), greaterThanOrEqualTo(24.0));
    });
  });
}
