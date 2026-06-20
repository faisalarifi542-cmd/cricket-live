// Proves the Live tab renders its compact two-column dashboard grid at a real
// 360px Android width (the previous bug stacked every card full-width because
// the two-column breakpoint sat above the ~328px content width).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cricpro_flutter/app_theme.dart';
import 'package:cricpro_flutter/screens/match_details/widgets/live_match_tab.dart';

Map<String, dynamic> _liveCenter() => {
      'match_state': 'live',
      'current_batters': [
        {
          'name': 'Saiteja Mukkamalla',
          'runs': '1',
          'balls': '2',
          'fours': '0',
          'sixes': '0',
          'strike_rate': '33.333333',
          'is_striker': true,
        },
        {
          'name': 'Shehan Jayasuriya',
          'runs': '3',
          'balls': '14',
          'fours': '0',
          'sixes': '0',
          'strike_rate': '21.4',
        },
      ],
      'current_bowler': {
        'name': 'Alexander Roy',
        'overs': '2',
        'maidens': '0',
        'runs': '9',
        'wickets': '0',
        'economy': '4.5',
      },
      'partnership': {'runs': '1', 'balls': '2'},
      'last_wicket': 'Monank Patel 25(40) c Max O\'Dowd b Aryan Dutt - 48/2 in 12.4 ov',
      'recent_balls': [
        {'over': '12', 'ball': '1', 'value': '0', 'type': 'dot'},
        {'over': '12', 'ball': '2', 'value': '0', 'type': 'dot'},
        {'over': '12', 'ball': '3', 'value': '1', 'type': 'run'},
        {'over': '12', 'ball': '4', 'value': 'W', 'type': 'wicket'},
        {'over': '12', 'ball': '5', 'value': '0', 'type': 'dot'},
        {'over': '12', 'ball': '6', 'value': '1', 'type': 'run'},
      ],
      'commentary': [
        {'over': '17.6', 'ball': '108', 'text': 'Kyle Klein to Saiteja, 1 run.'},
        {'over': '17.5', 'ball': '107', 'text': 'Kyle Klein to Saiteja, no run.'},
      ],
    };

Future<void> _pumpLiveTab(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(360, 804));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: cricTheme(true),
      home: Scaffold(
        body: MediaQuery(
          data: const MediaQueryData(size: Size(360, 804)),
          child: ListView(
            // Mirrors the real screen: 16px horizontal padding -> 328px content.
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              LiveMatchTab(
                summary: const {'status': 'live'},
                liveCenter: _liveCenter(),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('Bowler and Partnership are side-by-side at 360px',
      (tester) async {
    await _pumpLiveTab(tester);

    expect(find.text('Current Bowler'), findsOneWidget);
    expect(find.text('Partnership'), findsOneWidget);

    final bowler = tester.getCenter(find.text('Current Bowler'));
    final partnership = tester.getCenter(find.text('Partnership'));

    // Side-by-side => header centers share roughly the same vertical line and
    // Partnership sits to the right of the Bowler card.
    expect((bowler.dy - partnership.dy).abs(), lessThan(40),
        reason: 'cards stacked vertically instead of side-by-side');
    expect(partnership.dx, greaterThan(bowler.dx));
  });

  testWidgets('Last Wicket and Recent Over are side-by-side at 360px',
      (tester) async {
    await _pumpLiveTab(tester);

    expect(find.text('Last Wicket'), findsOneWidget);
    expect(find.text('Recent Over'), findsOneWidget);

    final lastWicket = tester.getCenter(find.text('Last Wicket'));
    final recentOver = tester.getCenter(find.text('Recent Over'));

    expect((lastWicket.dy - recentOver.dy).abs(), lessThan(40),
        reason: 'cards stacked vertically instead of side-by-side');
    expect(recentOver.dx, greaterThan(lastWicket.dx));
  });

  testWidgets('Live tab has no overflow at 360x804', (tester) async {
    final errors = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = previous);

    await _pumpLiveTab(tester);

    expect(
      errors.where((e) => e.exceptionAsString().contains('overflowed')),
      isEmpty,
      reason: 'Live tab overflowed at 360px width',
    );
  });

  testWidgets('strike rate is formatted and not ellipsized', (tester) async {
    await _pumpLiveTab(tester);
    // "33.333333" must render as a clean "33.33", never "33...." .
    expect(find.text('33.33'), findsOneWidget);
    expect(find.textContaining('....'), findsNothing);
  });

  testWidgets('commentary over labels are clean and single-line',
      (tester) async {
    await _pumpLiveTab(tester);
    // The provider sends over "17.6" + ball "108"; the label must collapse to
    // "17.6" (not "17.6.108" wrapping onto two lines).
    expect(find.text('17.6'), findsOneWidget);
    expect(find.text('17.5'), findsOneWidget);
    expect(find.textContaining('17.6.108'), findsNothing);
  });

  test('formatCompactPlayerName shortens long names cleanly', () {
    expect(formatCompactPlayerName('Saiteja Mukkamalla'), 'S. Mukkamalla');
    expect(formatCompactPlayerName('Shehan Jayasuriya'), 'S. Jayasuriya');
    expect(formatCompactPlayerName('Mohammad Saleem Safi'), 'M. Safi');
    // Short enough names are left untouched.
    expect(formatCompactPlayerName('Aryan Dutt'), 'Aryan Dutt');
    expect(formatCompactPlayerName('Kyle Klein'), 'Kyle Klein');
  });

  test('formatStatNumber caps decimals without clipping', () {
    expect(formatStatNumber('33.333333'), '33.33');
    expect(formatStatNumber('60.61'), '60.61');
    expect(formatStatNumber('45'), '45');
    expect(formatStatNumber('—'), '—');
  });

  test('formatOverLabel strips trailing ball/sequence ids', () {
    expect(formatOverLabel('17.6', '108'), '17.6');
    expect(formatOverLabel('17.6.108', ''), '17.6');
    expect(formatOverLabel('18', '3'), '18.3');
    expect(formatOverLabel('', ''), '');
  });

  test('scorecard SR/Econ format to one decimal (no multi-line wrap)', () {
    // The scorecard renders these via formatStatNumber(decimals: 1); the long
    // raw values were what wrapped onto two lines ("54.3" / "9").
    expect(formatStatNumber('54.39', decimals: 1), '54.4');
    expect(formatStatNumber('105.88', decimals: 1), '105.9');
    expect(formatStatNumber('71.43', decimals: 1), '71.4');
    expect(formatStatNumber('40', decimals: 1), '40');
    expect(formatStatNumber('5', decimals: 1), '5');
  });

  test('scorecard shortens long batter/bowler names', () {
    expect(formatCompactPlayerName('Saurabh Netravalkar', maxLen: 18),
        'S. Netravalkar');
    expect(formatCompactPlayerName('Sanjay Krishnamurthi', maxLen: 18),
        'S. Krishnamurthi');
    expect(formatCompactPlayerName('Roelof van der Merwe', maxLen: 18),
        'R. Merwe');
    // Short enough names stay intact.
    expect(formatCompactPlayerName('Zach Lion-Cachet', maxLen: 18),
        'Zach Lion-Cachet');
    expect(formatCompactPlayerName('Max O\'Dowd', maxLen: 18), 'Max O\'Dowd');
  });
}
