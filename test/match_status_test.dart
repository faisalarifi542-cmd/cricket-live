// Tests for `MatchStatusDisplay` — the single source of truth for the status
// badge + phase label, which eliminates the "LIVE NOW" + "Day 1: Stumps"
// contradiction. Verifies the backend `phase` field is honoured, the status-
// text heuristic fallback works for cached payloads, and the badge + label
// never disagree.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cricpro_flutter/app_theme.dart';
import 'package:cricpro_flutter/models/cricket_match.dart';
import 'package:cricpro_flutter/utils/match_status.dart';

CricketMatch _m({
  required String status,
  String phase = '',
  String statusText = '',
  String resultText = '',
}) =>
    CricketMatch.fromJson(<String, dynamic>{
      'id': '1',
      'status': status,
      if (phase.isNotEmpty) 'phase': phase,
      if (statusText.isNotEmpty) 'statusText': statusText,
      if (resultText.isNotEmpty) 'resultText': resultText,
      'team1': <String, dynamic>{'name': 'India', 'short': 'IND'},
      'team2': <String, dynamic>{'name': 'Australia', 'short': 'AUS'},
    });

/// Pumps a widget to obtain a BuildContext carrying the CricColors theme
/// extension, then runs [verify] with that context.
Future<void> _withTheme(
  WidgetTester tester,
  void Function(BuildContext) verify, {
  bool dark = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: cricTheme(dark),
      home: Builder(
        builder: (context) {
          verify(context);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
}

void main() {
  group('MatchStatusDisplay — backend phase field honoured', () {
    testWidgets('stumps phase → STUMPS badge, isLiveFamily, in break',
        (tester) async {
      await _withTheme(tester, (ctx) {
        final m = _m(
            status: 'live',
            phase: 'stumps',
            statusText: 'Stumps, Day 1');
        final d = MatchStatusDisplay.of(ctx, m);
        expect(d.badge, 'STUMPS');
        expect(d.isLiveFamily, isTrue);
        expect(d.isInBreak, isTrue);
        expect(d.phaseLabel, contains('Stumps'));
      });
    });

    testWidgets('lunch phase → LUNCH badge, in break', (tester) async {
      await _withTheme(tester, (ctx) {
        final m = _m(status: 'live', phase: 'lunch', statusText: 'Lunch');
        final d = MatchStatusDisplay.of(ctx, m);
        expect(d.badge, 'LUNCH');
        expect(d.isInBreak, isTrue);
      });
    });

    testWidgets('innings_break phase → INN BREAK badge', (tester) async {
      await _withTheme(tester, (ctx) {
        final m = _m(
            status: 'innings_break',
            phase: 'innings_break',
            statusText: 'Innings Break');
        final d = MatchStatusDisplay.of(ctx, m);
        expect(d.badge, 'INN BREAK');
        expect(d.isInBreak, isTrue);
      });
    });

    testWidgets('plain live phase → LIVE badge, NOT in break', (tester) async {
      await _withTheme(tester, (ctx) {
        final m = _m(status: 'live', phase: 'live', statusText: 'IND 45/1');
        final d = MatchStatusDisplay.of(ctx, m);
        expect(d.badge, 'LIVE');
        expect(d.isInBreak, isFalse);
        expect(d.isLiveFamily, isTrue);
      });
    });
  });

  group('MatchStatusDisplay — status-text heuristic fallback (cached data)', () {
    testWidgets('statusText "Stumps Day 1" with no phase → STUMPS',
        (tester) async {
      await _withTheme(tester, (ctx) {
        final m = _m(status: 'live', statusText: 'Stumps Day 1');
        final d = MatchStatusDisplay.of(ctx, m);
        expect(d.badge, 'STUMPS');
        expect(d.isInBreak, isTrue);
      });
    });

    testWidgets('statusText "Innings Break" with no phase → INN BREAK',
        (tester) async {
      await _withTheme(tester, (ctx) {
        final m = _m(status: 'live', statusText: 'Innings Break');
        final d = MatchStatusDisplay.of(ctx, m);
        expect(d.badge, 'INN BREAK');
      });
    });

    testWidgets('statusText "Rain delay" with no phase → RAIN', (tester) async {
      await _withTheme(tester, (ctx) {
        final m = _m(status: 'live', statusText: 'Rain delay');
        final d = MatchStatusDisplay.of(ctx, m);
        expect(d.badge, 'RAIN');
        expect(d.isInBreak, isTrue);
      });
    });
  });

  group('MatchStatusDisplay — terminal + upcoming', () {
    testWidgets('finished match → RESULT badge + result text', (tester) async {
      await _withTheme(tester, (ctx) {
        final m = _m(
            status: 'completed',
            resultText: 'India won by 6 wickets');
        final d = MatchStatusDisplay.of(ctx, m);
        expect(d.badge, 'RESULT');
        expect(d.phaseLabel, 'India won by 6 wickets');
        expect(d.isLiveFamily, isFalse);
      });
    });

    testWidgets('abandoned match → ABANDONED badge', (tester) async {
      await _withTheme(tester, (ctx) {
        final m = _m(status: 'abandoned', statusText: 'Match abandoned');
        final d = MatchStatusDisplay.of(ctx, m);
        expect(d.badge, 'ABANDONED');
      });
    });

    testWidgets('upcoming match → UPCOMING badge, empty phase label',
        (tester) async {
      await _withTheme(tester, (ctx) {
        final m = _m(status: 'upcoming');
        final d = MatchStatusDisplay.of(ctx, m);
        expect(d.badge, 'UPCOMING');
        expect(d.phaseLabel, isEmpty);
        expect(d.isLiveFamily, isFalse);
      });
    });
  });

  group('MatchStatusDisplay — phase note normalization (no malformed strings)',
      () {
    testWidgets('"Stumps - WI trail by 491 runs" → no leading dash, phase last',
        (tester) async {
      await _withTheme(tester, (ctx) {
        final m = _m(
            status: 'live',
            phase: 'stumps',
            statusText: 'Stumps - WI trail by 491 runs');
        final d = MatchStatusDisplay.of(ctx, m);
        // Must NOT start with a dash and must NOT duplicate/append "runs Stumps".
        expect(d.phaseLabel.trimLeft().startsWith('-'), isFalse);
        expect(d.phaseLabel, isNot(contains('runs Stumps')));
        expect(d.phaseLabel, 'WI trail by 491 runs · Stumps');
      });
    });

    testWidgets('"Day 3: Stumps - India A lead by 175 runs" → Day lifted, clean',
        (tester) async {
      await _withTheme(tester, (ctx) {
        final m = _m(
            status: 'live',
            phase: 'stumps',
            statusText: 'Day 3: Stumps - India A lead by 175 runs');
        final d = MatchStatusDisplay.of(ctx, m);
        expect(d.phaseLabel, 'Day 3: Stumps · India A lead by 175 runs');
        expect(d.phaseLabel, isNot(contains(' - ')));
      });
    });

    testWidgets('bare "Stumps" stays "Stumps"', (tester) async {
      await _withTheme(tester, (ctx) {
        final m = _m(status: 'live', phase: 'stumps', statusText: 'Stumps');
        final d = MatchStatusDisplay.of(ctx, m);
        expect(d.phaseLabel, 'Stumps');
      });
    });
  });

  testWidgets('badge + label never contradict for a stumps Test', (tester) async {
    // The exact bug from the brief: a live Test at "Day 1: Stumps" must NOT
    // show a generic LIVE badge alongside "Day 1: Stumps" text. The badge is
    // STUMPS and the label carries the stumps wording — they agree.
    await _withTheme(tester, (ctx) {
      final m = _m(status: 'live', statusText: 'Stumps, Day 1');
      final d = MatchStatusDisplay.of(ctx, m);
      expect(d.badge, isNot('LIVE'));
      expect(d.badge, 'STUMPS');
      expect(d.phaseLabel.toLowerCase(), contains('stumps'));
    });
  });
}
