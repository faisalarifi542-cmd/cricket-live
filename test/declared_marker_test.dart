// Tests for the DECLARED (`d`) marker: it must be derived consistently from the
// data every feed carries (so the Matches screen shows it too, not just the
// fast live-score poll) and must NOT flicker out for a poll tick.
//
// Proven root cause (live API, 2026-06-29): `/matches/live` and `/app/home`
// emit `288/9` with NO `declared` flag while `/app/live-scores` emits
// `declared:true` — so the marker blinked on Home as the feeds alternated and
// was permanently missing on the Matches screen.
import 'package:flutter_test/flutter_test.dart';

import 'package:cricpro_flutter/models/cricket_match.dart';

Map<String, dynamic> _match({
  required List<Map<String, dynamic>> team1,
  required List<Map<String, dynamic>> team2,
  String status = 'live',
  String battingTeamId = '',
}) =>
    <String, dynamic>{
      'match_id': '129574',
      'status': status,
      if (battingTeamId.isNotEmpty) 'curr_bat_team_id': battingTeamId,
      'series_name': 'New Zealand tour of England, 2026',
      'match_desc': '3rd Test',
      'team1': {'name': 'New Zealand', 'shortName': 'NZ', 'id': '13'},
      'team2': {'name': 'England', 'shortName': 'ENG', 'id': '9'},
      'score': {'team1': team1, 'team2': team2},
    };

void main() {
  group('declared derivation (works on feeds that omit isDeclared)', () {
    test(
        'NZ 288/9 (#3) closed by a later innings #4, not all out → derives `d` '
        'even though the feed sent no declared flag', () {
      // Exact `/matches/live` shape: NO `declared` field anywhere.
      final m = CricketMatch.fromJson(_match(
        battingTeamId: '9', // ENG now batting the 4th innings
        team1: [
          {'runs': 438, 'wickets': 10, 'overs': 114.5, 'innings_number': 1},
          {'runs': 288, 'wickets': 9, 'overs': 94.0, 'innings_number': 3},
        ],
        team2: [
          {'runs': 354, 'wickets': 10, 'overs': 88.2, 'innings_number': 2},
          {'runs': 103, 'wickets': 4, 'overs': 15.0, 'innings_number': 4},
        ],
      ));
      // 288/9 is declared (closed by #4, 9 wickets); 438/10 all out → no `d`;
      // the live 103/4 (#4, max ordinal) is NOT declared.
      expect(m.teamAInnings[1].declared, isTrue);
      expect(m.teamAInnings[1].scoreText, '288/9d');
      expect(m.teamAInnings[0].declared, isFalse); // all out
      expect(m.teamBInnings[1].declared, isFalse); // current innings
    });

    test('T20 single innings 154/8 never gains a spurious `d`', () {
      final m = CricketMatch.fromJson(_match(
        status: 'live',
        team1: [
          {'runs': 154, 'wickets': 8, 'overs': 20.0, 'innings_number': 1},
        ],
        team2: [
          {'runs': 60, 'wickets': 2, 'overs': 7.0, 'innings_number': 2},
        ],
      ));
      expect(m.teamAInnings.first.declared, isFalse);
      expect(m.teamAInnings.first.scoreText, '154/8');
    });

    test('an explicit feed declared flag is respected', () {
      final m = CricketMatch.fromJson(_match(
        team1: [
          {
            'runs': 500,
            'wickets': 3,
            'overs': 90.0,
            'innings_number': 1,
            'declared': true,
          },
        ],
        team2: [
          {'runs': 40, 'wickets': 1, 'overs': 10.0, 'innings_number': 2},
        ],
      ));
      expect(m.teamAInnings.first.declared, isTrue);
      expect(m.teamAInnings.first.scoreText, '500/3d');
    });
  });

  group('declared stays stable across a poll (no flicker)', () {
    test(
        'mergeLiveScore keeps `d` when a fresh tick drops the flag but the '
        'innings runs/wickets are unchanged', () {
      final stable = CricketMatch.fromJson(_match(
        team1: [
          {'runs': 438, 'wickets': 10, 'overs': 114.5, 'innings_number': 1},
          {
            'runs': 288,
            'wickets': 9,
            'overs': 94.0,
            'innings_number': 3,
            'declared': true,
          },
        ],
        team2: [
          {'runs': 354, 'wickets': 10, 'overs': 88.2, 'innings_number': 2},
          {'runs': 103, 'wickets': 4, 'overs': 15.0, 'innings_number': 4},
        ],
      ));
      // A degraded tick: SAME 288/9 but no declared and (hypothetically) no
      // later innings to derive from — the marker must not blink out.
      final degraded = CricketMatch.fromJson(_match(
        team1: [
          {'runs': 438, 'wickets': 10, 'overs': 114.5, 'innings_number': 1},
          {'runs': 288, 'wickets': 9, 'overs': 94.0, 'innings_number': 3},
        ],
        team2: const [],
      ));
      // Sanity: the degraded copy on its own lost the `d` (no later innings).
      expect(degraded.teamAInnings[1].declared, isFalse);

      final merged = stable.mergeLiveScore(degraded);
      expect(merged.teamAInnings[1].declared, isTrue,
          reason: 'previously-declared unchanged innings keeps its `d`');
      expect(merged.teamAInnings[1].scoreText, '288/9d');
    });

    test('a genuinely new innings score does NOT inherit a stale `d`', () {
      final prev = CricketMatch.fromJson(_match(
        team1: [
          {
            'runs': 288,
            'wickets': 9,
            'overs': 94.0,
            'innings_number': 3,
            'declared': true,
          },
        ],
        team2: const [],
      ));
      // Fresh: the same innings ordinal but a DIFFERENT (advanced) score → it is
      // a live, batting innings, not the old declared one.
      final fresh = CricketMatch.fromJson(_match(
        team1: [
          {'runs': 312, 'wickets': 9, 'overs': 99.0, 'innings_number': 3},
        ],
        team2: const [],
      ));
      final merged = prev.mergeLiveScore(fresh);
      expect(merged.teamAInnings.first.declared, isFalse);
      expect(merged.teamAInnings.first.scoreText, '312/9');
    });
  });
}
