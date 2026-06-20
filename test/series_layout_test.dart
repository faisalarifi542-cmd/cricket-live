// Layout regression tests for the redesigned premium Series screen widgets.
//
// These guard the two parts most prone to overflow on small (360dp) devices:
// the vertical Series list card and the All/Ongoing/Upcoming/Completed filter
// chip row.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cricpro_flutter/screens/series/series_components.dart';
import 'package:cricpro_flutter/screens/series/series_premium.dart';

SeriesView _fixture() => SeriesView(
      id: 'series-1',
      name: 'Afghanistan tour of India 2026',
      status: SeriesStatus.ongoing,
      category: SeriesCategory.international,
      startDate: DateTime(2026, 6, 6),
      endDate: DateTime(2026, 6, 22),
      formats: const ['T20I', 'ODI', 'Test'],
      formatLabel: '3 T20Is • 3 ODIs • 2 Tests',
      matchCount: 8,
      host: 'India',
      teams: const [
        SeriesTeamRef(name: 'India', shortName: 'IND'),
        SeriesTeamRef(name: 'Afghanistan', shortName: 'AFG'),
      ],
    );

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: ThemeData(brightness: Brightness.dark),
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: child,
      ),
    ),
  );
}

void main() {
  testWidgets('SeriesListCard renders without overflow at 360dp',
      (WidgetTester tester) async {
    final errors = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = previous);

    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var tapped = false;
    await tester.pumpWidget(
      _wrap(SeriesListCard(series: _fixture(), onTap: () => tapped = true)),
    );

    expect(
      errors.where((e) =>
          e.exceptionAsString().contains('RenderFlex overflowed') ||
          e.exceptionAsString().contains('overflowed')),
      isEmpty,
    );

    // Key card content from the target is present.
    expect(find.text('Afghanistan tour of India 2026'), findsOneWidget);
    expect(find.text('3 T20Is • 3 ODIs • 2 Tests'), findsOneWidget);
    expect(find.text('ONGOING'), findsOneWidget);
    expect(find.text('VS'), findsOneWidget);

    // "View Series" action opens the series.
    await tester.tap(find.text('View Series'));
    expect(tapped, isTrue);
  });

  testWidgets('Series filter chips fit without overflow at 360dp',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      _wrap(
        SeriesCategoryChips(
          items: const [
            ('All', Icons.grid_view_rounded),
            ('Ongoing', Icons.play_circle_fill_rounded),
            ('Upcoming', Icons.calendar_month_rounded),
            ('Completed', Icons.check_circle_rounded),
          ],
          selected: 0,
          onChanged: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The chips live in a horizontally-scrolling list, so off-screen chips
    // (e.g. "Completed") are lazily built rather than overflowing. Finding the
    // leading chips plus no thrown exception confirms a clean 360dp layout.
    expect(find.text('All'), findsOneWidget);
    expect(find.text('Ongoing'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Scrolling reveals the trailing chip without any overflow.
    await tester.drag(find.text('All'), const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(find.text('Completed'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('SeriesHeroData.fromJson parses admin hero payload', () {
    final hero = SeriesHeroData.fromJson({
      'seriesId': '9237',
      'title': 'Afghanistan tour of India 2026',
      'subtitle': 'Afghanistan tour of',
      'formatText': '3 T20Is • 3 ODIs • 2 Tests',
      'dateRange': '6 Jun – 22 Jun 2026',
      'backgroundImage': 'https://api.example.com/uploads/hero.png',
      'teamA': {
        'name': 'India',
        'shortName': 'IND',
        'logoUrl': 'https://api.example.com/uploads/teams/flags/india.png',
      },
      'teamB': {'name': 'Afghanistan', 'shortName': 'AFG', 'logoUrl': ''},
    });

    expect(hero, isNotNull);
    expect(hero!.seriesId, '9237');
    expect(hero.title, 'Afghanistan tour of India 2026');
    expect(hero.formatText, '3 T20Is • 3 ODIs • 2 Tests');
    expect(hero.teamA?.shortName, 'IND');
    expect(hero.teamA?.logoUrl, contains('/uploads/teams/flags/india.png'));
    expect(hero.teamB?.shortName, 'AFG');
    expect(hero.hasContent, isTrue);
  });

  test('SeriesHeroData.fromJson returns null for empty/absent hero', () {
    expect(SeriesHeroData.fromJson(null), isNull);
    expect(SeriesHeroData.fromJson(const <String, dynamic>{}), isNull);
  });
}
