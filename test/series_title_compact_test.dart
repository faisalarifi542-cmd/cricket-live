// Unit guards for [compactSeriesTitle] — the card-title compactor that stops
// long tour names ellipsizing mid-word ("Switzerland Women tour of G…").
//
// Rules under test:
//   • strip a REDUNDANT trailing ", 2026" (the year still shows in date meta),
//     including season suffixes like ", 2026-27" / ", 2026/27",
//   • strip any dangling trailing comma,
//   • PRESERVE the meaningful "tour of" body,
//   • leave normal tournament names (year WITHOUT a comma) untouched.

import 'package:flutter_test/flutter_test.dart';

import 'package:cricpro_flutter/utils/team_format.dart';

void main() {
  group('compactSeriesTitle', () {
    test('strips a redundant trailing ", YYYY" and keeps "tour of"', () {
      expect(
        compactSeriesTitle('Switzerland Women tour of Germany, 2026'),
        'Switzerland Women tour of Germany',
      );
      expect(
        compactSeriesTitle('India tour of Ireland, 2026'),
        'India tour of Ireland',
      );
      expect(
        compactSeriesTitle('Portugal tour of Sweden, 2026'),
        'Portugal tour of Sweden',
      );
    });

    test('strips season-suffixed trailing years (", 2026-27" / ", 2026/27")',
        () {
      expect(
        compactSeriesTitle('Australia tour of India, 2026-27'),
        'Australia tour of India',
      );
      expect(
        compactSeriesTitle('England tour of India, 2026/27'),
        'England tour of India',
      );
    });

    test('removes a dangling trailing comma', () {
      expect(
        compactSeriesTitle('India tour of Ireland,'),
        'India tour of Ireland',
      );
    });

    test('leaves tournament names with a NON-comma year untouched', () {
      expect(
        compactSeriesTitle("ICC Women's T20 World Cup 2026"),
        "ICC Women's T20 World Cup 2026",
      );
      expect(
        compactSeriesTitle('Afghanistan tour of India 2026'),
        'Afghanistan tour of India 2026',
      );
    });

    test('leaves names without a trailing year/comma untouched', () {
      expect(
        compactSeriesTitle("The Hundred Men's Competition 2026"),
        "The Hundred Men's Competition 2026",
      );
      expect(
        compactSeriesTitle('Major League Cricket'),
        'Major League Cricket',
      );
    });

    test('normalizes whitespace', () {
      expect(
        compactSeriesTitle('  India   tour of  Ireland , 2026 '),
        'India tour of Ireland',
      );
    });

    test('does not strip a mid-title year', () {
      // A year that is not the trailing token must survive.
      expect(
        compactSeriesTitle('2026 Emerging Teams Asia Cup'),
        '2026 Emerging Teams Asia Cup',
      );
    });

    test('empty / whitespace input returns empty', () {
      expect(compactSeriesTitle(''), '');
      expect(compactSeriesTitle('   '), '');
    });
  });

  group('cardSeriesTitle — tour titles compress to team codes (one line)', () {
    test('bilateral tour title uses broadcast codes, year preserved', () {
      expect(
        cardSeriesTitle('New Zealand tour of West Indies, 2026'),
        'NZ tour of WI, 2026',
      );
      expect(
        cardSeriesTitle('Australia tour of Bangladesh 2026'),
        'AUS tour of BAN 2026',
      );
    });

    test('women / A-team variants keep their spaced suffix', () {
      expect(
        cardSeriesTitle('Sri Lanka Women tour of India, 2026'),
        'SL W tour of IND, 2026',
      );
      expect(
        cardSeriesTitle('South Africa A tour of Bangladesh'),
        'SA A tour of BAN',
      );
    });

    test('unknown sides are never invented — left as-is', () {
      expect(
        cardSeriesTitle('Northern Superchargers tour of Ruritania 2026'),
        'Northern Superchargers tour of Ruritania 2026',
      );
    });

    test('tournament/league titles pass through shortSeriesTitle untouched',
        () {
      expect(
        cardSeriesTitle("ICC Women's T20 World Cup 2026"),
        "Women's T20 WC 2026",
      );
      expect(cardSeriesTitle('Major League Cricket'), 'Major League Cricket');
      // "India" inside a league name is not a tour — no compression.
      expect(
        cardSeriesTitle('Indian Premier League 2026'),
        'Indian Premier League 2026',
      );
    });
  });

  group('normalizeSeriesFormat', () {
    test('turns a ragged comma form into a clean bullet form', () {
      expect(normalizeSeriesFormat('3 T20s , 3 ODIs'), '3 T20s • 3 ODIs');
      expect(normalizeSeriesFormat('3 T20Is, 3 ODIs'), '3 T20Is • 3 ODIs');
    });

    test('normalizes slash and existing bullet separators consistently', () {
      expect(normalizeSeriesFormat('2 Tests / 3 ODIs'), '2 Tests • 3 ODIs');
      expect(normalizeSeriesFormat('1 Test  •  3 ODIs'), '1 Test • 3 ODIs');
    });

    test('leaves a single segment untouched (aside from whitespace)', () {
      expect(normalizeSeriesFormat('5 Matches'), '5 Matches');
      expect(normalizeSeriesFormat('  3   T20Is '), '3 T20Is');
    });

    test('drops empty segments and dangling separators', () {
      expect(normalizeSeriesFormat('3 T20Is, , 3 ODIs,'), '3 T20Is • 3 ODIs');
      expect(normalizeSeriesFormat(''), '');
      expect(normalizeSeriesFormat('  '), '');
    });
  });
}
