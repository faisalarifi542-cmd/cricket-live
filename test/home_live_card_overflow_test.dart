import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cricpro_flutter/app_theme.dart';
import 'package:cricpro_flutter/models/cricket_match.dart';
import 'package:cricpro_flutter/repositories/cricket_repository.dart';
import 'package:cricpro_flutter/screens/home/home_screen.dart'
    show HomeMatchCardHost, homeLiveCardResolvedHeight;

/// Reproduces the EXACT production failure captured in the field report:
///
///   BOTTOM OVERFLOWED BY 5.4 PIXELS
///
/// Fixture (a maximum-height normal live card):
///   India Under-19s tour of Sri Lanka 2026 — Stumps
///   SL19  424/9  • 106.4 overs
///   IND19 186/0  •  58.0 overs
///   Venue: Galle
///   Date : Jul 13 • 06:30 AM
///   Screen: 352×856
///
/// Root cause: `_HomeCardShell` used `BoxConstraints.tightFor(height: minHeight)`
/// — a FIXED height (min == max). The maximum-content live card's natural height
/// (~258px in the test env, ~262.6px at text-scale 1.15, and a few pixels taller
/// again under real-device font metrics) exceeded that fixed 256px region, so the
/// content Column overflowed at the bottom. The fix relaxes the constraint to a
/// true minimum (the Stack may grow) and lifts the compact floor to 264px, so
/// every compact card keeps one uniform height with device/scale headroom.
void main() {
  CricketMatch indSlU19Stumps({
    String series = 'India Under-19s tour of Sri Lanka 2026',
    String venue = 'Galle',
    String phase = 'stumps',
    bool bothScores = true,
    bool twoLineTitle = true,
  }) =>
      CricketMatch.fromJson(<String, dynamic>{
        'match_id': 'ind-sl-u19-stumps-2026',
        'status': 'live',
        'status_text': phase == 'stumps' ? 'Day 3: Stumps' : 'Live',
        'phase': phase,
        'series_name': twoLineTitle ? series : 'India tour of Sri Lanka',
        'venue': venue,
        'start_time': '2026-07-13T01:00:00.000Z',
        'team1': <String, dynamic>{
          'name': 'Sri Lanka Under-19s',
          'shortName': 'SL19',
          'id': 'sl-19',
        },
        'team2': <String, dynamic>{
          'name': 'India Under-19s',
          'shortName': 'IND19',
          'id': 'ind-19',
        },
        'curr_bat_team_id': 'ind-19',
        'score': <String, dynamic>{
          'team1': [
            {'runs': 424, 'wickets': 9, 'overs': 106.4, 'innings_number': 1},
          ],
          if (bothScores)
            'team2': [
              {'runs': 186, 'wickets': 0, 'overs': 58.0, 'innings_number': 2},
            ],
        },
      });

  Widget app(Widget child, Size size, {double scale = 1}) => MaterialApp(
        theme: cricTheme(true), // dark theme (matches the field screenshot)
        home: MediaQuery(
          data:
              MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
          child: Scaffold(
            backgroundColor: const Color(0xff020b1b),
            body: child,
          ),
        ),
      );

  /// Pumps the card and collects any Flutter layout errors via
  /// FlutterError.onError. Uses fixed pumps (NOT pumpAndSettle) because the live
  /// action bar runs an async stream-availability check that never "settles".
  Future<List<FlutterErrorDetails>> pump(
    WidgetTester tester,
    Size size,
    CricketMatch match, {
    double scale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final errors = <FlutterErrorDetails>[];
    final old = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = old);
    await tester.pumpWidget(app(
      Padding(
        padding: const EdgeInsets.all(16),
        child: HomeMatchCardHost(
          match: match,
          repository: CricketRepository(),
        ),
      ),
      size,
      scale: scale,
    ));
    await tester.pump(const Duration(milliseconds: 60));
    // Restore before any expect() so a failing expectation can't leave
    // FlutterError.onError overridden (the "overrode onError" binding assert).
    FlutterError.onError = old;
    return errors;
  }

  Iterable<FlutterErrorDetails> overflows(List<FlutterErrorDetails> e) =>
      e.where((d) => d.exceptionAsString().contains('overflowed'));

  testWidgets('352×856 IND/SL U19 Stumps live card: no BOTTOM OVERFLOW',
      (tester) async {
    final errors = await pump(tester, const Size(352, 856), indSlU19Stumps());

    expect(overflows(errors), isEmpty,
        reason: 'A RenderFlex overflowed — the normal live card does not fit '
            'the 352×856 Galle/Stumps fixture (the "BOTTOM OVERFLOWED BY 5.4 '
            'PIXELS" field failure).');

    // Nothing may be hidden: venue, date and the action button must all render.
    expect(find.text('Galle'), findsOneWidget);
    expect(find.textContaining(RegExp(r'\w+ \d+ • \d')), findsWidgets,
        reason: 'The date/time line (e.g. "Jul 13 • 06:30 AM") must be shown.');
    expect(find.text('View Match'), findsOneWidget);

    // Both scores remain visible (current-innings rules unchanged).
    expect(find.textContaining('424/9'), findsWidgets);
    expect(find.textContaining('186/0'), findsWidgets);

    // A real phase (Stumps) OVERRIDES the generic "LIVE NOW" pill as the
    // primary center pill — a paused match must not read as live.
    expect(find.text('LIVE NOW'), findsNothing);
    expect(find.textContaining('Stumps'), findsWidgets);

    // The action button rectangle sits fully inside the card rectangle.
    final card = tester.getRect(find.byKey(const ValueKey('home-normal-card')));
    final button = tester.getRect(find.text('View Match'));
    expect(card.contains(button.topLeft), isTrue,
        reason: 'button.topLeft outside card: card=$card button=$button');
    expect(card.contains(button.bottomRight), isTrue,
        reason: 'button.bottomRight outside card: card=$card button=$button');

    // The whole footer (venue → date/action) sits inside the card too.
    final venue = tester.getRect(find.text('Galle'));
    expect(card.contains(venue.topLeft), isTrue);
    expect(button.bottom, lessThanOrEqualTo(card.bottom + 0.01));
  });

  testWidgets('352×856 IND/SL U19 Stumps live card: no overflow at scale 1.15',
      (tester) async {
    final errors = await pump(tester, const Size(352, 856), indSlU19Stumps(),
        scale: 1.15);
    expect(overflows(errors), isEmpty,
        reason: 'Overflow at text scale 1.15 — must pass at 1.0 AND 1.15.');
  });

  testWidgets(
      'compact live cards keep one uniform height across content variations',
      (tester) async {
    const size = Size(352, 856);
    final heights = <String, double>{};
    for (final entry in <String, CricketMatch>{
      'twoLineTitle': indSlU19Stumps(),
      'oneLineTitle': indSlU19Stumps(twoLineTitle: false),
      'noPhase': indSlU19Stumps(phase: 'live'),
      'oneScore': indSlU19Stumps(bothScores: false),
      'shortVenue': indSlU19Stumps(venue: 'Galle'),
      'longVenue': indSlU19Stumps(
          venue: 'Rangiri Dambulla International Stadium, Dambulla'),
      'missingVenue': indSlU19Stumps(venue: ''),
    }.entries) {
      final errors = await pump(tester, size, entry.value);
      expect(overflows(errors), isEmpty,
          reason: 'Overflow for variant ${entry.key}.');
      heights[entry.key] =
          tester.getRect(find.byKey(const ValueKey('home-normal-card'))).height;
    }
    final distinct = heights.values.map((h) => (h * 10).round()).toSet();
    expect(distinct, hasLength(1),
        reason: 'Compact live cards must share ONE height; got $heights');
    // Loaded height is now resolved by `homeLiveCardResolvedHeight` (shared
    // with the skeleton). The host wraps the card in Padding(16), so the
    // outer card width is 352 − 32 = 320 (compact bucket → 264 base). The
    // outer SizedBox is authoritative; the shell border is drawn inside it.
    const outerCardWidth = 320.0;
    final expectedHeight = homeLiveCardResolvedHeight(
      outerCardWidth: outerCardWidth,
      textScaler: TextScaler.noScaling,
    );
    expect(heights.values.first, closeTo(expectedHeight, 0.5));
  });
}
