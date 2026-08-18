import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cricpro_flutter/app_theme.dart';
import 'package:cricpro_flutter/models/cricket_match.dart';
import 'package:cricpro_flutter/repositories/cricket_repository.dart';
import 'package:cricpro_flutter/screens/home/home_screen.dart'
    show HomeHeroCardHost;

/// Reproduces the EXACT failing fixture from the 352×856 screenshot:
///   India Women tour of England 2026 — Test / multi-innings, Stumps phase.
///   ENG-W: current 130/6* (40.0 ov), previous 170/10 (59.1 ov)
///   IND-W: current 341/7  (86.3 ov), previous innings available
///
/// The existing data-resilience tests do NOT cover this multi-innings hero at
/// the real device size, which is why a 0.639px BOTTOM OVERFLOW shipped. This
/// test fails on Flutter layout errors (including fractional overflows) so the
/// exact regression can never reappear silently.
void main() {
  /// Builds the India-Women-Test-match hero fixture used in the screenshot.
  CricketMatch engIndWomenTest() => CricketMatch.fromJson(<String, dynamic>{
        'match_id': 'eng-w-ind-w-test-2026',
        'status': 'stumps',
        'status_text': 'Day 2: Stumps - England Women trail by 211 runs',
        'phase': 'stumps',
        'series_name': 'India Women tour of England, 2026',
        'venue': 'The County Ground, Bristol',
        'start_time': '2026-07-10T10:30:00.000Z',
        'team1': <String, dynamic>{
          'name': 'England Women',
          'shortName': 'ENG-W',
          'id': 'eng-w',
        },
        'team2': <String, dynamic>{
          'name': 'India Women',
          'shortName': 'IND-W',
          'id': 'ind-w',
        },
        'curr_bat_team_id': 'eng-w',
        'score': <String, dynamic>{
          'team1': [
            // ENG-W 1st innings (closed): 170/10, 59.1 overs
            {'runs': 170, 'wickets': 10, 'overs': 59.1, 'innings_number': 1},
            // ENG-W 2nd innings (current, live): 130/6, 40.0 overs
            {'runs': 130, 'wickets': 6, 'overs': 40.0, 'innings_number': 3},
          ],
          'team2': [
            // IND-W 1st innings (closed): 341/7, 86.3 overs
            {'runs': 341, 'wickets': 7, 'overs': 86.3, 'innings_number': 2},
          ],
        },
      });

  Widget host(Widget child) => MaterialApp(
        theme: cricTheme(true), // dark theme (the screenshot is dark)
        home: Scaffold(
          backgroundColor: const Color(0xff020b1b),
          body: child,
        ),
      );

  // Pump at an exact physical size with a device pixel ratio of 1.0 so the
  // layout pixels equal the screenshot's 352×856. Optionally simulates the
  // real-device taller font metrics by inflating the text height via a custom
  // strut, which reproduces the fractional BOTTOM OVERFLOW the screenshot shows.
  Future<void> pumpAt(
    WidgetTester tester,
    Size size,
    CricketMatch match, {
    double textScale = 1.0,
    double fontHeightBoost = 0.0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // A custom text style that adds to every line's height reproduces the
    // real-Android font-metric difference (ascent+descent > default) that makes
    // the hero's fixed SizedBox height 0.6px too short on the actual device.
    await tester.pumpWidget(host(MediaQuery(
      data:
          MediaQueryData(size: size, textScaler: TextScaler.linear(textScale)),
      child: DefaultTextStyle.merge(
        style: TextStyle(height: 1.0 + fontHeightBoost),
        child: HomeHeroCardHost(
          match: match,
          repository: CricketRepository(),
          streamEpoch: 0,
        ),
      ),
    )));
    await tester.pumpAndSettle(const Duration(milliseconds: 200));
  }

  testWidgets(
      '352×856 India-W Test hero: no BOTTOM OVERFLOW (the screenshot '
      'fixture)', (tester) async {
    await pumpAt(tester, const Size(352, 856), engIndWomenTest());
    // The single most important assertion: no layout exception was thrown —
    // a RenderFlex overflow throws a FlutterError which takeException() catches.
    expect(tester.takeException(), isNull,
        reason: 'A RenderFlex overflow was thrown — the hero card does not fit '
            'the 352×856 fixture. This is the exact 0.639px BOTTOM OVERFLOW '
            'from the screenshot.');
    // The landscape Home hero shows only the current/latest relevant innings.
    expect(find.textContaining('130/6'), findsWidgets);
    expect(find.text('2nd Inn'), findsOneWidget);
    expect(find.text('1st Inn'), findsOneWidget);
    expect(find.textContaining('170/10'), findsNothing);
    final score = tester.widget<Text>(find.text('130/6*'));
    // Compact hero (352-class) drops the primary-score floor to 24 so the
    // score no longer visually dominates the block. Still the largest hero
    // element by a comfortable margin.
    expect(score.style?.fontSize, greaterThanOrEqualTo(24));
    // Presentation hides history; the model retains it for Match Center and
    // Match Details scorecard views.
    expect(engIndWomenTest().teamAInnings, hasLength(2));
    expect(engIndWomenTest().teamAInnings.first.runs, 170);
  });

  testWidgets('352×856 India-W Test hero at text scale 1.15: no overflow',
      (tester) async {
    await pumpAt(tester, const Size(352, 856), engIndWomenTest(),
        textScale: 1.15);
    expect(tester.takeException(), isNull,
        reason: 'Overflow at text scale 1.15 — the hero must pass at 1.0 AND '
            '1.15 on a 352px device.');
  });

  testWidgets('491×912 India-W Test hero: no overflow (wider device)',
      (tester) async {
    await pumpAt(tester, const Size(491, 912), engIndWomenTest());
    expect(tester.takeException(), isNull);
  });

  // Reproduces the real-Android font-metric difference: the screenshot shows a
  // 0.639px BOTTOM OVERFLOW because the device's font ascent/descent is a hair
  // taller than the test environment's default. A small per-line height boost
  // simulates that and must STILL not overflow once the fix lands.
  testWidgets('352×856 India-W Test hero with taller font metrics: no overflow',
      (tester) async {
    await pumpAt(tester, const Size(352, 856), engIndWomenTest(),
        fontHeightBoost: 0.06);
    expect(tester.takeException(), isNull,
        reason: 'Overflow under taller font metrics — the hero height must '
            'carry a safety allowance for device-pixel/font rounding.');
  });
}
