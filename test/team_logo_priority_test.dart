// Verifies the centralized team-logo priority used everywhere in the app:
//   server/admin (or Cricbuzz) http URL → local rounded flag asset → initials.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:cricpro_flutter/components.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  testWidgets('prefers a server/Cricbuzz http logo over the local flag asset',
      (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(const TeamLogoWidget(
      logoUrl: 'https://api.example.com/uploads/teams/flags/afghanistan.png',
      teamName: 'Afghanistan',
      abbreviation: 'AFG',
      color: Color(0xff22d3ee),
      size: 56,
    )));

    // F6: network logos render via CachedNetworkImage. The priority behaviour
    // (http logo wins over the bundled flag asset) is unchanged.
    final cached =
        tester.widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage));
    final usesNetwork =
        cached.any((i) => i.imageUrl.contains('afghanistan.png'));
    expect(usesNetwork, isTrue,
        reason: 'An http logo URL must win over the bundled flag asset.');
  });

  testWidgets('falls back to the local flag asset when no logo URL is given',
      (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(const TeamLogoWidget(
      logoUrl: null,
      teamName: 'Afghanistan',
      abbreviation: 'AFG',
      color: Color(0xff22d3ee),
      size: 56,
    )));

    final images = tester.widgetList<Image>(find.byType(Image));
    expect(images.any((i) => i.image is AssetImage), isTrue,
        reason: 'A known team with no server logo should use its flag asset.');
  });

  testWidgets('shows initials when no logo URL and no known flag asset exist',
      (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(const TeamLogoWidget(
      logoUrl: null,
      teamName: 'Nowhere Cricket Club',
      abbreviation: 'NWC',
      color: Color(0xff22d3ee),
      size: 56,
    )));

    expect(find.byType(Image), findsNothing);
    expect(find.textContaining('N'), findsOneWidget);
  });
}
