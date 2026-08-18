import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:cricpro_flutter/utils/json_diff.dart';

/// Tests for the change-detection primitive that replaced
/// `jsonEncode(a) != jsonEncode(b)` on the match-details 5s polling path
/// (match_details_screen.dart `_jsonChanged`, called at :579 and :581).
///
/// The contract that matters: for realistic API payloads jsonDeepEquals must
/// return the SAME verdict the jsonEncode comparison did, or the screen will
/// either stop updating (missed change) or rebuild forever (false change).
void main() {
  // Mirrors the shape of the real /match/:id summary payload closely enough to
  // exercise nesting, lists, nulls and mixed types.
  Map<String, dynamic> summary() => <String, dynamic>{
        'match_id': '12345',
        'status': 'live',
        'team1': <String, dynamic>{
          'name': 'India',
          'short': 'IND',
          'score': <String, dynamic>{'runs': 287, 'wickets': 4, 'overs': 45.2},
        },
        'team2': <String, dynamic>{
          'name': 'Australia',
          'short': 'AUS',
          'score': null,
        },
        'commentary': <Map<String, dynamic>>[
          <String, dynamic>{'ball': '45.2', 'text': 'FOUR! Driven through covers', 'runs': 4},
          <String, dynamic>{'ball': '45.1', 'text': 'single taken', 'runs': 1},
        ],
        'officials': <String>['Umpire A', 'Umpire B'],
        'is_featured': false,
      };

  group('jsonDeepEquals — agreement with the jsonEncode idiom it replaced', () {
    test('identical payloads are equal', () {
      expect(jsonDeepEquals(summary(), summary()), isTrue);
    });

    test('identical instance short-circuits', () {
      final a = summary();
      expect(jsonDeepEquals(a, a), isTrue);
    });

    test('a changed nested score is detected', () {
      final a = summary();
      final b = summary();
      (b['team1'] as Map)['score'] = {'runs': 288, 'wickets': 4, 'overs': 45.3};
      expect(jsonDeepEquals(a, b), isFalse);
      // Same verdict the old implementation gave.
      expect(jsonEncode(a) != jsonEncode(b), isTrue);
    });

    test('an appended commentary ball is detected', () {
      final a = summary();
      final b = summary();
      (b['commentary'] as List).insert(0, {'ball': '45.3', 'text': 'WICKET!', 'runs': 0});
      expect(jsonDeepEquals(a, b), isFalse);
    });

    test('a changed status string is detected', () {
      final a = summary();
      final b = summary()..['status'] = 'complete';
      expect(jsonDeepEquals(a, b), isFalse);
    });

    test('a changed bool is detected', () {
      final a = summary();
      final b = summary()..['is_featured'] = true;
      expect(jsonDeepEquals(a, b), isFalse);
    });

    test('null -> value is detected', () {
      final a = summary();
      final b = summary();
      (b['team2'] as Map)['score'] = {'runs': 0, 'wickets': 0, 'overs': 0.0};
      expect(jsonDeepEquals(a, b), isFalse);
    });

    test('value -> null is detected', () {
      final a = summary();
      final b = summary();
      (b['team1'] as Map)['score'] = null;
      expect(jsonDeepEquals(a, b), isFalse);
    });

    test('a removed key is detected (not just a changed one)', () {
      final a = summary();
      final b = summary()..remove('is_featured');
      expect(jsonDeepEquals(a, b), isFalse);
      expect(jsonDeepEquals(b, a), isFalse, reason: 'must be symmetric');
    });

    test('an added key is detected', () {
      final a = summary();
      final b = summary()..['new_field'] = 1;
      expect(jsonDeepEquals(a, b), isFalse);
    });

    test('a key present-but-null is NOT equal to a missing key', () {
      // The subtle one: b[key] returns null for both cases, so a naive
      // implementation without containsKey() reports these as equal.
      expect(jsonDeepEquals({'a': 1, 'b': null}, {'a': 1}), isFalse);
      expect(jsonDeepEquals({'a': 1}, {'a': 1, 'b': null}), isFalse);
    });

    test('list order is significant', () {
      expect(
        jsonDeepEquals({'o': ['Umpire A', 'Umpire B']}, {'o': ['Umpire B', 'Umpire A']}),
        isFalse,
      );
    });

    test('list length change is detected', () {
      expect(jsonDeepEquals({'o': [1, 2, 3]}, {'o': [1, 2]}), isFalse);
    });

    test('type change with equal text is detected', () {
      expect(jsonDeepEquals({'runs': 4}, {'runs': '4'}), isFalse);
    });

    test('empty vs populated collections', () {
      expect(jsonDeepEquals({'c': []}, {'c': [1]}), isFalse);
      expect(jsonDeepEquals({'c': {}}, {'c': {'a': 1}}), isFalse);
      expect(jsonDeepEquals({'c': []}, {'c': []}), isTrue);
      expect(jsonDeepEquals({'c': {}}, {'c': {}}), isTrue);
    });

    test('map vs list vs primitive are never equal', () {
      expect(jsonDeepEquals({'a': 1}, [1]), isFalse);
      expect(jsonDeepEquals([1], 'x'), isFalse);
      expect(jsonDeepEquals(null, {}), isFalse);
    });

    test('deeply nested difference is found', () {
      final a = {'l1': {'l2': {'l3': {'l4': [1, {'l5': 'deep'}]}}}};
      final b = {'l1': {'l2': {'l3': {'l4': [1, {'l5': 'deeper'}]}}}};
      expect(jsonDeepEquals(a, b), isFalse);
      expect(jsonDeepEquals(a, a), isTrue);
    });
  });

  group('jsonDeepEquals — documented deliberate differences from jsonEncode', () {
    test('map key ORDER is ignored (jsonEncode was order-sensitive)', () {
      final a = {'x': 1, 'y': 2};
      final b = {'y': 2, 'x': 1};
      // The old idiom saw a spurious "change" here and rebuilt the subtree.
      expect(jsonEncode(a) != jsonEncode(b), isTrue);
      expect(jsonDeepEquals(a, b), isTrue, reason: 'reordered keys are not a data change');
    });

    test('int and double of equal value compare equal', () {
      expect(jsonEncode({'v': 1}) != jsonEncode({'v': 1.0}), isTrue);
      expect(jsonDeepEquals({'v': 1}, {'v': 1.0}), isTrue);
    });
  });

  group('jsonDeepEquals — behaviour on the real polling payload', () {
    test('a full unchanged poll response is reported unchanged', () {
      final decoded1 = jsonDecode(jsonEncode(summary())) as Map<String, dynamic>;
      final decoded2 = jsonDecode(jsonEncode(summary())) as Map<String, dynamic>;
      expect(jsonDeepEquals(decoded1, decoded2), isTrue);
    });

    test('early exit: a first-field difference does not require a full walk', () {
      // 5000 commentary entries after the differing field. If this were still
      // doing a full serialise-both-then-compare, the cost would scale with the
      // tail; jsonDeepEquals returns as soon as match_id differs. Asserting
      // correctness here, not timing (timings are measured separately).
      Map<String, dynamic> big(String id) => {
            'match_id': id,
            'commentary': List.generate(
              5000,
              (i) => {'ball': '$i', 'text': 'ball number $i in this long test innings', 'runs': i % 7},
            ),
          };
      expect(jsonDeepEquals(big('a'), big('b')), isFalse);
      expect(jsonDeepEquals(big('a'), big('a')), isTrue);
    });
  });
}
