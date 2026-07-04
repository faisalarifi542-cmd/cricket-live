// Widget guards for the redesigned Series card: it must read as a SERIES, not a
// single match — no "TBD vs TBD", a trophy emblem for multi-team tournaments,
// and a "View Series" (not "View Match") action.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cricpro_flutter/api_models.dart';
import 'package:cricpro_flutter/screens/series/series_components.dart';

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
  testWidgets('Tournament/league card shows a trophy emblem and no TBD',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // A league with no derivable two nations — must NOT render a fixture.
    final league = SeriesView(
      id: 'mlc',
      name: 'Major League Cricket 2026',
      status: SeriesStatus.ongoing,
      category: SeriesCategory.league,
      startDate: DateTime(2026, 6, 18),
      endDate: DateTime(2026, 7, 18),
      formatLabel: '19 T20s',
      teams: const [], // tournament: no opposing sides
    );

    await tester.pumpWidget(
      _wrap(SeriesListCard(series: league, onTap: () {})),
    );

    expect(league.isBilateral, isFalse);
    // No misleading single-fixture placeholders.
    expect(find.text('TBD'), findsNothing);
    expect(find.text('VS'), findsNothing); // no bilateral VS badge
    // Trophy emblem present.
    expect(find.byIcon(Icons.emoji_events_rounded), findsWidgets);
    // It's a SERIES action, not a match.
    expect(find.text('View Series'), findsOneWidget);
    expect(find.textContaining('View Match'), findsNothing);
    // Metadata row: date range (not a single match start time) and format/count.
    expect(find.text('18 Jun – 18 Jul 2026'), findsOneWidget);
    expect(find.text('19 T20s'), findsOneWidget);
  });

  testWidgets('Bilateral card shows both teams and no TBD',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final bilateral = SeriesView(
      id: 'afg-ind',
      name: 'Afghanistan tour of India 2026',
      status: SeriesStatus.completed,
      category: SeriesCategory.international,
      startDate: DateTime(2026, 6, 6),
      endDate: DateTime(2026, 6, 20),
      teams: const [
        SeriesTeamRef(name: 'Afghanistan', shortName: 'AFG'),
        SeriesTeamRef(name: 'India', shortName: 'IND'),
      ],
    );

    await tester.pumpWidget(
      _wrap(SeriesListCard(series: bilateral, onTap: () {})),
    );

    expect(bilateral.isBilateral, isTrue);
    expect(find.text('AFG'), findsOneWidget);
    expect(find.text('IND'), findsOneWidget);
    expect(find.text('v'), findsOneWidget); // small quiet VS badge between sides
    expect(find.text('TBD'), findsNothing);
    expect(find.text('View Series'), findsOneWidget);
    expect(find.text('COMPLETED'), findsOneWidget);
    // Favourite star top-right.
    expect(find.byIcon(Icons.star_border_rounded), findsOneWidget);
    // Date range metadata is shown (host omitted -> no location item).
    expect(find.text('6 – 20 Jun 2026'), findsOneWidget);
  });

  testWidgets('Host is derived from a "tour of" title and shown as location',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // No explicit teams/host: SeriesView.fromApi must derive both AFG/IND and
    // the host (India) from the title alone, so the location item appears.
    final view = SeriesView.fromApi(ApiSeries(
      id: 's-host',
      name: 'Afghanistan Tour Of India 2026',
      status: 'Upcoming',
      startDate: '2026-06-23',
      endDate: '2026-06-25',
    ));
    expect(view.host, 'India');

    await tester.pumpWidget(
      _wrap(SeriesListCard(series: view, onTap: () {})),
    );

    expect(find.text('India'), findsOneWidget);
    expect(find.byIcon(Icons.location_on_rounded), findsOneWidget);
  });
}
