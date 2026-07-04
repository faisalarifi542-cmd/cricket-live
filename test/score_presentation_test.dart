import 'package:flutter_test/flutter_test.dart';

import 'package:cricpro_flutter/models/cricket_match.dart';
import 'package:cricpro_flutter/utils/score_presentation.dart';
import 'package:cricpro_flutter/upcoming_sort.dart';

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

  group('Real /app/home & /matches/live shape — innings_number ordering', () {
    // Mirrors the ACTUAL backend payload shape: `score.team1` is an array and
    // each innings carries the backend's snake_case `innings_number` ordinal
    // (emitted by extractHomeInnings/extractInningsScore). Here it arrives
    // REVERSED (2nd innings first) — the exact Home-hero bug — and must be
    // normalized to chronological order with the live innings starred LAST.
    CricketMatch parseHome() => CricketMatch.fromJson(<String, dynamic>{
          'match_id': 'h1',
          'status': 'live',
          'team1': <String, dynamic>{'name': 'New Zealand', 'shortName': 'NZ'},
          'team2': <String, dynamic>{'name': 'England', 'shortName': 'ENG'},
          'score': <String, dynamic>{
            'team1': <Map<String, dynamic>>[
              {'runs': 209, 'wickets': 7, 'overs': 71.2, 'innings_number': 2},
              {'runs': 438, 'wickets': 10, 'overs': 114.5, 'innings_number': 1},
            ],
            'team2': <Map<String, dynamic>>[
              {'runs': 354, 'wickets': 10, 'overs': 88.2, 'innings_number': 1},
            ],
          },
        });

    test('NZ reads 438/10 & 209/7 (1st innings first), never reversed', () {
      final p = TeamScorePresentation(parseHome().teamAInnings);
      expect(p.combinedScore, '438/10 & 209/7');
      expect(p.oversLine(), '114.5 ov • 71.2 ov');
    });

    test('overs order follows the score order', () {
      final m = parseHome();
      // Flat string also follows the corrected order.
      expect(m.teamAScoreText, '438/10 & 209/7 (71.2 ov)');
    });
  });

  group('Innings order WITHOUT any provider ordinal (closed-before-open)', () {
    // The live backend may NOT send an ordinal (and old caches never did).
    // Order must still be deterministic: a CLOSED innings (all out / declared)
    // precedes an in-progress one. This is the real Home-hero `215/7 & 438/10*`
    // case — reversed array, no innings_number — and must self-correct.
    CricketMatch parseNoOrdinal(List<Map<String, dynamic>> nz) =>
        CricketMatch.fromJson(<String, dynamic>{
          'match_id': 'no1',
          'status': 'live',
          'curr_bat_team_id': '13',
          'team1': <String, dynamic>{'name': 'NZ', 'shortName': 'NZ', 'id': '13'},
          'team2': <String, dynamic>{'name': 'ENG', 'shortName': 'ENG', 'id': '9'},
          'score': <String, dynamic>{'team1': nz},
        });

    test('reversed [open, closed] becomes [closed, open] = 438/10 & 215/7', () {
      final m = parseNoOrdinal([
        {'runs': 215, 'wickets': 7, 'overs': 76.0}, // open (current) listed 1st
        {'runs': 438, 'wickets': 10, 'overs': 114.5}, // closed (completed)
      ]);
      final p = TeamScorePresentation(m.teamAInnings);
      expect(p.combinedScore, '438/10 & 215/7');
      expect(p.oversLine(), '114.5 ov • 76.0 ov');
    });

    test('star lands on the OPEN current innings, never the completed one', () {
      final m = parseNoOrdinal([
        {'runs': 215, 'wickets': 7, 'overs': 76.0},
        {'runs': 438, 'wickets': 10, 'overs': 114.5},
      ]);
      // NZ (team1, id 13) is batting → current scored index is the LAST after
      // ordering, i.e. the open 215/7 innings (index 1), not the completed 438.
      final idx = m.currentScoredIndexForTeam(isTeamA: true);
      expect(idx, 1);
      expect(m.teamAInnings[idx].runs, 215);
      expect(m.teamAInnings[idx].isClosed, isFalse);
      expect(m.teamAInnings[0].runs, 438);
      expect(m.teamAInnings[0].isClosed, isTrue);
    });

    test('declared first innings also sorts before an open second', () {
      final m = parseNoOrdinal([
        {'runs': 120, 'wickets': 4, 'overs': 30.0}, // open, listed first
        {'runs': 500, 'wickets': 7, 'overs': 130.0, 'declared': true},
      ]);
      expect(TeamScorePresentation(m.teamAInnings).combinedScore,
          '500/7d & 120/4');
    });

    test('a POSITIONAL ordinal that lies cannot reverse the order', () {
      // Exactly the /app/live-scores fast-poll payload: the live innings is
      // listed FIRST and numbered #1, the completed innings #2. A naive
      // sort-by-ordinal would render `224/8 & 438/10*`. closed-before-open
      // (physically invariant) must win → `438/10 & 224/8*`.
      final m = parseNoOrdinal([
        {'runs': 224, 'wickets': 8, 'overs': 81.1, 'innings_number': 1}, // open
        {'runs': 438, 'wickets': 10, 'overs': 114.5, 'innings_number': 2}, // closed
      ]);
      final p = TeamScorePresentation(m.teamAInnings);
      expect(p.combinedScore, '438/10 & 224/8');
      expect(p.oversLine(), '114.5 ov • 81.1 ov');
      // Star is the OPEN (current) innings, which sorts LAST.
      final idx = m.currentScoredIndexForTeam(isTeamA: true);
      expect(m.teamAInnings[idx].runs, 224);
    });
  });

  group('Schedule category filters (IRE vs IND international / MLC league)', () {
    CricketMatch make(String series, String desc) =>
        CricketMatch.fromJson(<String, dynamic>{
          'id': 'x',
          'status': 'live',
          'series_name': series,
          'match_desc': desc,
          'team1': <String, dynamic>{'name': 'A', 'shortName': 'A'},
          'team2': <String, dynamic>{'name': 'B', 'shortName': 'B'},
        });

    final ireVsInd = make('India tour of Ireland, 2026', '2nd T20I');
    final lakrVsSor = make('Major League Cricket 2026', '14th Match');

    test('IRE vs IND classifies as international, not league', () {
      expect(UpcomingSort.isInternationalMatch(ireVsInd), isTrue);
      expect(UpcomingSort.isMajorLeague(ireVsInd), isFalse);
    });

    test('LAKR vs SOR classifies as league, not international', () {
      expect(UpcomingSort.isMajorLeague(lakrVsSor), isTrue);
      expect(UpcomingSort.isInternationalMatch(lakrVsSor), isFalse);
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
