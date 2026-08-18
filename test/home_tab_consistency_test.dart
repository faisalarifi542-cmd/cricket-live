import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cricpro_flutter/app_theme.dart';
import 'package:cricpro_flutter/screens/home/home_screen.dart'
    show
        HomeEmptyStateHost,
        HomeStatusTabsHost,
        homeResolvedTab,
        homeSectionHeading;

/// Tab interaction/state consistency: the segmented-control highlight, the
/// section heading and the main list data source ALL derive from a single
/// resolved tab. The user's selection is ALWAYS honoured — tapping Live keeps
/// Live selected even with zero live matches (the region shows the Live empty
/// state instead of silently re-resolving to Upcoming, which made the Live tab
/// feel non-clickable).
void main() {
  group('homeResolvedTab honours the user selection', () {
    test('Live with matches stays Live', () {
      expect(homeResolvedTab(selectedTab: 0, liveLoadedEmpty: false), 0);
    });

    test('empty Live STAYS Live (empty state shown, no silent fallback)', () {
      expect(homeResolvedTab(selectedTab: 0, liveLoadedEmpty: true), 0);
    });

    test('Upcoming passes through', () {
      expect(homeResolvedTab(selectedTab: 1, liveLoadedEmpty: false), 1);
    });

    test('Finished passes through', () {
      expect(homeResolvedTab(selectedTab: 2, liveLoadedEmpty: false), 2);
      expect(homeResolvedTab(selectedTab: 2, liveLoadedEmpty: true), 2);
    });
  });

  group('segment / heading / list agree', () {
    void expectConsistent({
      required int selectedTab,
      required bool liveLoadedEmpty,
      required int expectedResolved,
      required String expectedHeading,
    }) {
      final resolved = homeResolvedTab(
        selectedTab: selectedTab,
        liveLoadedEmpty: liveLoadedEmpty,
      );
      final highlightIndex = resolved;
      final heading = homeSectionHeading(resolved);
      final listSourceTab = resolved;

      expect(resolved, expectedResolved);
      expect(highlightIndex, resolved);
      expect(listSourceTab, resolved);
      expect(heading, expectedHeading);
    }

    test('Live with matches → all three say Live', () {
      expectConsistent(
        selectedTab: 0,
        liveLoadedEmpty: false,
        expectedResolved: 0,
        expectedHeading: 'Live Matches',
      );
    });

    test('empty Live → all three STILL say Live (heading + empty state)', () {
      expectConsistent(
        selectedTab: 0,
        liveLoadedEmpty: true,
        expectedResolved: 0,
        expectedHeading: 'Live Matches',
      );
    });

    test('Upcoming → all three say Upcoming', () {
      expectConsistent(
        selectedTab: 1,
        liveLoadedEmpty: false,
        expectedResolved: 1,
        expectedHeading: 'Upcoming Matches',
      );
    });

    test('Finished → all three say Finished', () {
      expectConsistent(
        selectedTab: 2,
        liveLoadedEmpty: false,
        expectedResolved: 2,
        expectedHeading: 'Finished Matches',
      );
    });
  });

  group('segmented control interaction (widget)', () {
    Widget host(int selected, ValueChanged<int> onChanged) => MaterialApp(
          theme: cricTheme(true),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child:
                  HomeStatusTabsHost(selected: selected, onChanged: onChanged),
            ),
          ),
        );

    testWidgets('every tab is tappable and reports its index', (tester) async {
      final taps = <int>[];
      await tester.pumpWidget(host(1, taps.add));
      await tester.tap(find.text('Live'));
      await tester.tap(find.text('Finished'));
      await tester.tap(find.text('Upcoming'));
      expect(taps, [0, 2, 1]);
    });

    testWidgets('Live is tappable even while another tab is selected',
        (tester) async {
      // Regression for the "Live tab not clickable when nothing is live"
      // defect: the segment itself must always fire, whatever is selected.
      final taps = <int>[];
      await tester.pumpWidget(host(1, taps.add));
      await tester.tap(find.text('Live'));
      expect(taps, [0]);
    });
  });

  group('Live empty state (widget)', () {
    testWidgets('shows polished copy and a switch-to-Upcoming CTA',
        (tester) async {
      var switched = 0;
      await tester.pumpWidget(MaterialApp(
        theme: cricTheme(true),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: HomeEmptyStateHost(
              topTab: 0,
              onSwitchUpcoming: () => switched++,
            ),
          ),
        ),
      ));
      expect(find.text('No live matches right now'), findsOneWidget);
      expect(find.text('Check Upcoming matches for scheduled games.'),
          findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('home-empty-live-cta')));
      expect(switched, 1);
    });

    testWidgets('non-Live tabs render their own copy without the CTA',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: cricTheme(true),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: HomeEmptyStateHost(topTab: 1, onSwitchUpcoming: () {}),
          ),
        ),
      ));
      expect(find.text('No upcoming matches'), findsOneWidget);
      expect(find.byKey(const ValueKey('home-empty-live-cta')), findsNothing);
    });

    testWidgets('empty state fits a 352-wide viewport without overflow',
        (tester) async {
      tester.view.physicalSize = const Size(352, 856);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: cricTheme(true),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: HomeEmptyStateHost(topTab: 0, onSwitchUpcoming: () {}),
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
    });
  });
}
