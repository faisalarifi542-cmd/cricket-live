import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cricpro_flutter/app_theme.dart';
import 'package:cricpro_flutter/models/cricket_match.dart';
import 'package:cricpro_flutter/screens/home/home_hero_order.dart';
import 'package:cricpro_flutter/screens/home/home_screen.dart' show homeVisibleScoreKey;
import 'package:cricpro_flutter/utils/score_presentation.dart';
import 'package:cricpro_flutter/widgets/team_score_view.dart';

CricketMatch _m(
  String id, {
  String status = 'live',
  String series = 'Series',
  String title = '',
  String? logo,
  String venue = '',
  List<Map<String, dynamic>> team1 = const [],
  List<Map<String, dynamic>> team2 = const [],
  String statusText = '',
}) {
  return CricketMatch.fromJson(<String, dynamic>{
    'match_id': id,
    'status': status,
    'status_text': statusText,
    'series_name': series,
    if (title.isNotEmpty) 'title': title,
    'team1': <String, dynamic>{
      'name': 'New Zealand',
      'shortName': 'NZ',
      'id': '13',
      if (logo != null) 'logoUrl': logo,
    },
    'team2': <String, dynamic>{'name': 'England', 'shortName': 'ENG', 'id': '9'},
    if (venue.isNotEmpty) 'venue': venue,
    'score': <String, dynamic>{
      if (team1.isNotEmpty) 'team1': team1,
      if (team2.isNotEmpty) 'team2': team2,
    },
  });
}

void main() {
  group('Carousel stability — preserveHeroOrder (Test 1)', () {
    test('same id set: keeps the existing visible ORDER (carousel never jumps)',
        () {
      final prev = [_m('a'), _m('b'), _m('c')];
      // A poll returns the SAME matches re-prioritised into a different order.
      final resolved = [_m('c'), _m('a'), _m('b')];
      final out = preserveHeroOrder(prev, resolved);
      expect(out.map((m) => m.id).toList(), ['a', 'b', 'c']); // prev order kept
    });

    test('membership changed: adopts the new prioritised order', () {
      final prev = [_m('a'), _m('b')];
      final resolved = [_m('x'), _m('a'), _m('b')]; // a match started
      final out = preserveHeroOrder(prev, resolved);
      expect(out.map((m) => m.id).toList(), ['x', 'a', 'b']);
    });

    test('null/empty prev returns resolved unchanged', () {
      final resolved = [_m('a')];
      expect(preserveHeroOrder(null, resolved), resolved);
      expect(preserveHeroOrder(const [], resolved), resolved);
    });
  });

  group('Change-detection — homeVisibleScoreKey (Test 3)', () {
    test('identical score/status → identical key (poll does NOT notify)', () {
      final a = _m('m1',
          statusText: 'Day 4',
          team1: [
            {'runs': 438, 'wickets': 10, 'overs': 114.5, 'innings_number': 1},
            {'runs': 234, 'wickets': 8, 'overs': 83.0, 'innings_number': 3},
          ]);
      final b = _m('m1',
          statusText: 'Day 4',
          team1: [
            {'runs': 438, 'wickets': 10, 'overs': 114.5, 'innings_number': 1},
            {'runs': 234, 'wickets': 8, 'overs': 83.0, 'innings_number': 3},
          ]);
      expect(homeVisibleScoreKey(a), homeVisibleScoreKey(b));
    });

    test('score moved → key changes (poll repaints)', () {
      final a = _m('m1', team1: [
        {'runs': 234, 'wickets': 8, 'overs': 83.0, 'innings_number': 3},
        {'runs': 438, 'wickets': 10, 'overs': 114.5, 'innings_number': 1},
      ]);
      final b = _m('m1', team1: [
        {'runs': 240, 'wickets': 8, 'overs': 84.0, 'innings_number': 3},
        {'runs': 438, 'wickets': 10, 'overs': 114.5, 'innings_number': 1},
      ]);
      expect(homeVisibleScoreKey(a) == homeVisibleScoreKey(b), isFalse);
    });
  });

  group('mergeLiveScore preserves stable UI fields (Test 4)', () {
    test('score/status update; series/title/venue/logo preserved', () {
      final old = _m(
        'm1',
        series: 'New Zealand tour of England, 2026',
        title: 'New Zealand vs England',
        logo: 'https://static.example/nz.png',
        venue: 'Trent Bridge, Nottingham',
        statusText: 'Day 3',
        team1: [
          {'runs': 438, 'wickets': 10, 'overs': 114.5, 'innings_number': 1},
        ],
        team2: [
          {'runs': 354, 'wickets': 10, 'overs': 88.2, 'innings_number': 2},
        ],
      );
      // The fast /app/live-scores shape: only score/status, reversed positional
      // innings, no series/title/venue/logo.
      final fresh = _m(
        'm1',
        series: '',
        statusText: 'Day 4: 2nd Session - NZ lead by 308 runs',
        team1: [
          {'runs': 224, 'wickets': 8, 'overs': 81.1, 'innings_number': 1},
          {'runs': 438, 'wickets': 10, 'overs': 114.5, 'innings_number': 2},
        ],
        team2: [
          {'runs': 354, 'wickets': 10, 'overs': 88.2, 'innings_number': 1},
        ],
      );

      final merged = old.mergeLiveScore(fresh);

      // Stable identity/metadata preserved from the old rich object.
      expect(merged.series, 'New Zealand tour of England, 2026');
      expect(merged.title, 'New Zealand vs England');
      expect(merged.venue, 'Trent Bridge, Nottingham');
      expect(merged.teamALogo, old.teamALogo); // logo preserved, not lost
      expect(merged.teamALogo, isNotNull);
      // Live-mutable fields taken from fresh.
      expect(merged.statusText, contains('NZ lead by 308'));
      // Innings updated AND chronological (closed-before-open invariant).
      expect(TeamScorePresentation(merged.teamAInnings).combinedScore,
          '438/10 & 224/8');
    });
  });

  group('Hero score layout + Yet to bat (Test 5 & 6)', () {
    Widget host(Widget child, double width) => MaterialApp(
          theme: cricTheme(true),
          home: Scaffold(body: Center(child: SizedBox(width: width, child: child))),
        );

    testWidgets('Test multi-innings hero score fits a compact 360dp width',
        (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(
        const TeamScoreView(
          innings: [
            InningsScore(runs: 438, wickets: 10, overs: '114.5'),
            InningsScore(runs: 234, wickets: 8, overs: '83.0'),
          ],
          mode: ScoreDisplayMode.heroMultiInnings,
          mainSize: 22,
          oversSize: 13,
          live: true,
          currentInningsIndex: 1,
        ),
        150,
      ));
      expect(tester.takeException(), isNull); // no overflow
      expect(find.text('438/10 · 114.5 OV'), findsOneWidget);
      expect(find.text('234/8* · 83.0 OV'), findsOneWidget);
    });

    testWidgets('Yet to bat is muted/small, not a big score, with no overs',
        (tester) async {
      await tester.pumpWidget(host(
        const TeamScoreView(
          innings: [],
          mainSize: 34,
          oversSize: 13,
          placeholder: 'Yet to bat',
          live: true,
        ),
        120,
      ));
      expect(find.text('Yet to bat'), findsOneWidget);
      final t = tester.widget<Text>(find.text('Yet to bat'));
      // Capped small (never the big 34px score) and not heavy/black weight.
      expect(t.style!.fontSize! <= 14.5, isTrue);
      expect(t.style!.fontWeight, isNot(FontWeight.w900));
      // No overs line rendered for a yet-to-bat side.
      expect(find.textContaining(' OV'), findsNothing);
    });

    testWidgets(
        'T20/ODI hero single score is strong + overs readable below, fits a '
        'short hero slot at 360dp (no overflow)', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      // Simulate the hero score slot: a narrow, height-bounded box (like the
      // team column's Expanded score area) — must not overflow.
      await tester.pumpWidget(host(
        const SizedBox(
          height: 56,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.topCenter,
            child: TeamScoreView(
              innings: [InningsScore(runs: 154, wickets: 7, overs: '20.0')],
              mode: ScoreDisplayMode.heroLimitedOvers,
              mainSize: 32,
              oversSize: 15,
              live: true,
            ),
          ),
        ),
        150,
      ));
      expect(tester.takeException(), isNull);
      expect(find.text('154/7'), findsOneWidget);
      expect(find.text('20.0 OVERS'), findsOneWidget);
      // Score stays strong (single-innings hero preset 26–34, capped) and the
      // overs line sits clearly below it.
      final score = tester.widget<Text>(find.text('154/7'));
      expect(score.style!.fontSize!, inInclusiveRange(26.0, 34.0));
      final overs = tester.widget<Text>(find.text('20.0 OVERS'));
      expect(overs.style!.fontSize!, inInclusiveRange(13.0, 15.0));
      expect(overs.style!.fontSize! < score.style!.fontSize!, isTrue);
    });
  });
}
