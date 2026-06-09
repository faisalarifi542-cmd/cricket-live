// Visual contract for the commentary timeline ball marker (MDBallChip):
//  * the marker is a circle with a fully OPAQUE fill (so the timeline line
//    behind it is hidden, never showing through the circle), and
//  * a numbered run renders bold, bright-white text.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cricpro_flutter/app_theme.dart';
import 'package:cricpro_flutter/screens/match_details/widgets/match_details_ui.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: cricTheme(true),
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

BoxDecoration _decorationOf(WidgetTester tester) {
  // The marker's own Container is the first one inside MDBallChip.
  final container = tester.widget<Container>(
    find.descendant(
      of: find.byType(MDBallChip),
      matching: find.byType(Container),
    ).first,
  );
  return container.decoration as BoxDecoration;
}

void main() {
  testWidgets('run marker is a circle with an opaque fill', (tester) async {
    await _pump(tester, const MDBallChip(label: '1', size: 40));
    final deco = _decorationOf(tester);
    expect(deco.shape, BoxShape.circle);
    expect(deco.color, isNotNull);
    // Opaque => alpha at full (no see-through line).
    expect(deco.color!.a, 1.0);
  });

  testWidgets('numbered run text is bold and bright white', (tester) async {
    await _pump(tester, const MDBallChip(label: '2', size: 40));
    final text = tester.widget<Text>(find.text('2'));
    expect(text.style!.fontWeight, FontWeight.w900);
    expect(text.style!.color, Colors.white);
  });

  testWidgets('wicket marker shows a bold white W on an opaque circle',
      (tester) async {
    await _pump(tester, const MDBallChip(label: 'W', wicket: true, size: 44));
    expect(find.text('W'), findsOneWidget);
    final deco = _decorationOf(tester);
    expect(deco.shape, BoxShape.circle);
    expect(deco.color!.a, 1.0);
  });

  testWidgets('marker fits with no overflow in a narrow timeline rail',
      (tester) async {
    final errors = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = previous);

    await _pump(
      tester,
      const SizedBox(width: 46, child: MDBallChip(label: '4', size: 42)),
    );
    expect(
      errors.where((e) => e.exceptionAsString().contains('overflowed')),
      isEmpty,
    );
  });
}
