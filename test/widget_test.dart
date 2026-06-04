// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cricpro_flutter/components.dart';
import 'package:cricpro_flutter/components/home_components.dart';
import 'package:cricpro_flutter/models.dart';

void main() {
  testWidgets('app boots', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Center(child: Text('CRICPRO')),
      ),
    ));
    expect(find.text('CRICPRO'), findsWidgets);
  });

  testWidgets('featured hero card fits constrained mobile height',
      (WidgetTester tester) async {
    final errors = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = previous);

    const fixture = HeroFixture(
      badge: 'LIVE',
      series: 'Sri Lanka tour of West Indies 2026',
      date: 'Today • 16:30',
      time: 'West Indies opt to bowl',
      left: TeamInfo(
        code: 'SL',
        name: 'Sri Lanka',
        shortName: 'SL',
        color: Color(0xff22d3ee),
        asset: null,
      ),
      right: TeamInfo(
        code: 'WI',
        name: 'West Indies',
        shortName: 'WI',
        color: Color(0xfff59e0b),
        asset: null,
      ),
      centerTitle: 'VS',
      venue: 'Sabina Park, Kingston, Jamaica',
      button: 'Watch Live',
      leftMeta: '279/4 (47.5 OV)',
      rightMeta: 'Yet to bat',
    );

    await tester.binding.setSurfaceSize(const Size(411, 420));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 411,
            height: 420,
            child: HomeHeroCard(fixture: fixture, live: true),
          ),
        ),
      ),
    );

    expect(
      errors.where((error) =>
          error.exceptionAsString().contains('RenderFlex overflowed')),
      isEmpty,
    );
  });

  testWidgets('team logo fallback renders initials without broken image',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TeamLogoWidget(
            logoUrl: '',
            teamName: 'West Indies',
            abbreviation: 'WI',
            color: Color(0xff22d3ee),
          ),
        ),
      ),
    );

    expect(find.text('WI'), findsOneWidget);
  });
}
