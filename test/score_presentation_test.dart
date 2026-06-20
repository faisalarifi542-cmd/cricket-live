import 'package:flutter_test/flutter_test.dart';

import 'package:cricpro_flutter/models/cricket_match.dart';
import 'package:cricpro_flutter/utils/score_presentation.dart';

void main() {
  group('TeamScorePresentation — limited overs / single innings', () {
    test('renders main score and overs', () {
      const p = TeamScorePresentation([
        InningsScore(runs: 218, wickets: 10, overs: '44.2'),
      ]);
      expect(p.hasScore, isTrue);
      expect(p.isMultiInnings, isFalse);
      expect(p.combinedScore, '218/10');
      expect(p.oversLine(), '44.2 ov');
    });

    test('no wickets shows runs only', () {
      const p = TeamScorePresentation([InningsScore(runs: 224, overs: '28.4')]);
      expect(p.combinedScore, '224');
      expect(p.oversLine(), '28.4 ov');
    });
  });

  group('TeamScorePresentation — Test / multi-innings', () {
    const nz = TeamScorePresentation([
      InningsScore(runs: 362, wickets: 10, overs: '87.1'),
      InningsScore(runs: 391, wickets: 10, overs: '96.2'),
    ]);

    test('combines both innings oldest-first, never one only', () {
      expect(nz.isMultiInnings, isTrue);
      expect(nz.combinedScore, '362/10 & 391/10');
    });

    test('overs line shows both innings (roomy)', () {
      expect(nz.oversLine(), '87.1 ov • 96.2 ov');
    });

    test('overs line compact units-at-end for tight cards', () {
      expect(nz.oversLine(unitEach: false), '87.1 • 96.2 ov');
    });

    test('live second innings keeps the first (ENG example)', () {
      const eng = TeamScorePresentation([
        InningsScore(runs: 291, wickets: 10, overs: '84.0'),
        InningsScore(runs: 45, wickets: 3, overs: '13.5'),
      ]);
      expect(eng.combinedScore, '291/10 & 45/3');
      expect(eng.oversLine(), '84.0 ov • 13.5 ov');
    });

    test('declared innings carries the d suffix', () {
      const p = TeamScorePresentation([
        InningsScore(runs: 490, wickets: 8, overs: '120.0', declared: true),
        InningsScore(runs: 232, wickets: 10, overs: '63.2'),
      ]);
      expect(p.combinedScore, '490/8d & 232/10');
    });
  });

  group('TeamScorePresentation — yet to bat / partial', () {
    test('empty innings has no score', () {
      const p = TeamScorePresentation([]);
      expect(p.hasScore, isFalse);
      expect(p.combinedScore, '');
      expect(p.oversLine(), '');
    });

    test('only scored innings count toward multi-innings', () {
      const p = TeamScorePresentation([
        InningsScore(runs: 67, wickets: 4, overs: '12.5'),
      ]);
      expect(p.isMultiInnings, isFalse);
      expect(p.combinedScore, '67/4');
    });
  });

  group('CricketMatch parses + round-trips structured innings', () {
    final testMatch = CricketMatch.fromJson(<String, dynamic>{
      'id': 'm1',
      'status': 'live',
      'team1': <String, dynamic>{
        'name': 'New Zealand',
        'short': 'NZ',
        'innings': <Map<String, dynamic>>[
          {'runs': 362, 'wickets': 10, 'overs': 87.1},
          {'runs': 391, 'wickets': 10, 'overs': 96.2},
        ],
      },
      'team2': <String, dynamic>{
        'name': 'England',
        'short': 'ENG',
        'innings': <Map<String, dynamic>>[
          {'runs': 291, 'wickets': 10, 'overs': 84.0},
          {'runs': 45, 'wickets': 3, 'overs': 13.5},
        ],
      },
    });

    test('fromJson preserves per-innings overs (oldest first)', () {
      expect(testMatch.teamAInnings.length, 2);
      final p = TeamScorePresentation(testMatch.teamAInnings);
      expect(p.combinedScore, '362/10 & 391/10');
      expect(p.oversLine(), '87.1 ov • 96.2 ov');

      final eng = TeamScorePresentation(testMatch.teamBInnings);
      expect(eng.combinedScore, '291/10 & 45/3');
      expect(eng.oversLine(), '84.0 ov • 13.5 ov');
    });

    test('cache round-trip is lossless', () {
      final restored = CricketMatch.fromCacheJson(testMatch.toCacheJson());
      expect(restored.teamAInnings.length, 2);
      final p = TeamScorePresentation(restored.teamAInnings);
      expect(p.combinedScore, '362/10 & 391/10');
      expect(p.oversLine(), '87.1 ov • 96.2 ov');
    });
  });

  group('Innings order is normalized chronologically at parse', () {
    // Provider returns the innings array in REVERSED order, but carries the
    // chronological `inningsId` on each entry (global across the match:
    // 1 = NZ 1st, 2 = ENG 1st, 3 = NZ 2nd, 4 = ENG 2nd).
    CricketMatch parseReversed() => CricketMatch.fromJson(<String, dynamic>{
          'id': 'm2',
          'status': 'live',
          'team1': <String, dynamic>{
            'name': 'New Zealand',
            'short': 'NZ',
            'innings': <Map<String, dynamic>>[
              {'runs': 391, 'wickets': 10, 'overs': 96.2, 'inningsId': 3},
              {'runs': 362, 'wickets': 10, 'overs': 87.1, 'inningsId': 1},
            ],
          },
          'team2': <String, dynamic>{
            'name': 'England',
            'short': 'ENG',
            'innings': <Map<String, dynamic>>[
              {'runs': 90, 'wickets': 3, 'overs': 20.1, 'inningsId': 4},
              {'runs': 291, 'wickets': 10, 'overs': 84.0, 'inningsId': 2},
            ],
          },
        });

    test('NZ always reads 362/10 then 391/10 (oldest first)', () {
      final m = parseReversed();
      final nz = TeamScorePresentation(m.teamAInnings);
      expect(nz.combinedScore, '362/10 & 391/10');
      expect(nz.oversLine(), '87.1 ov • 96.2 ov');
    });

    test('ENG always reads 291/10 then 90/3, current NOT moved to front', () {
      final m = parseReversed();
      final eng = TeamScorePresentation(m.teamBInnings);
      expect(eng.combinedScore, '291/10 & 90/3');
      expect(eng.oversLine(), '84.0 ov • 20.1 ov');
    });

    test('different endpoint orderings yield the SAME normalized order', () {
      // Endpoint A: chronological. Endpoint B: reversed. Same inningsIds.
      CricketMatch parse(List<Map<String, dynamic>> nzInns) =>
          CricketMatch.fromJson(<String, dynamic>{
            'id': 'm3',
            'status': 'live',
            'team1': {'name': 'New Zealand', 'short': 'NZ', 'innings': nzInns},
          });
      final a = parse([
        {'runs': 362, 'wickets': 10, 'overs': 87.1, 'inningsId': 1},
        {'runs': 391, 'wickets': 10, 'overs': 96.2, 'inningsId': 3},
      ]);
      final b = parse([
        {'runs': 391, 'wickets': 10, 'overs': 96.2, 'inningsId': 3},
        {'runs': 362, 'wickets': 10, 'overs': 87.1, 'inningsId': 1},
      ]);
      expect(
        TeamScorePresentation(a.teamAInnings).combinedScore,
        TeamScorePresentation(b.teamAInnings).combinedScore,
      );
      expect(TeamScorePresentation(b.teamAInnings).combinedScore,
          '362/10 & 391/10');
    });

    test('no innings ordinal → original array order preserved (no reorder)', () {
      final m = CricketMatch.fromJson(<String, dynamic>{
        'id': 'm4',
        'status': 'live',
        'team1': <String, dynamic>{
          'name': 'New Zealand',
          'short': 'NZ',
          'innings': <Map<String, dynamic>>[
            {'runs': 362, 'wickets': 10, 'overs': 87.1},
            {'runs': 391, 'wickets': 10, 'overs': 96.2},
          ],
        },
      });
      expect(
          TeamScorePresentation(m.teamAInnings).combinedScore, '362/10 & 391/10');
    });

    test('flat score string is oldest-first with lowercase ov', () {
      final m = parseReversed();
      // Legacy flat text (used for change-detection / scoreLine) must agree
      // with the structured order and never use uppercase "OV".
      expect(m.teamAScoreText, '362/10 & 391/10 (96.2 ov)');
      expect(m.teamBScoreText, '291/10 & 90/3 (20.1 ov)');
      expect(m.teamAScoreText.contains('OV'), isFalse);
    });
  });

  group('ordinal labels', () {
    test('1st/2nd/3rd/4th', () {
      expect(TeamScorePresentation.ordinal(1), '1st');
      expect(TeamScorePresentation.ordinal(2), '2nd');
      expect(TeamScorePresentation.ordinal(3), '3rd');
      expect(TeamScorePresentation.ordinal(4), '4th');
    });
  });
}
