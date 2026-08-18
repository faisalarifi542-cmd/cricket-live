import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cricpro_flutter/app_theme.dart';
import 'package:cricpro_flutter/models/cricket_match.dart';
import 'package:cricpro_flutter/repositories/cricket_repository.dart';
import 'package:cricpro_flutter/screens/home/home_screen.dart'
    show
        HomeMatchCardHost,
        HomeMatchListSkeletonHost,
        homeCardEmblemSize,
        homeLiveCardResolvedHeight,
        homeSkeletonCardKey,
        kHomeCardPadding;

/// Reproduces the field failure: a yellow/black RenderFlex overflow stripe
/// inside the first normal-card skeleton during the initial load. Also
/// asserts the fix's stronger contract: skeleton and loaded live card share
/// one resolved outer geometry so the tree does not jump when data arrives.
void main() {
  Widget app(Widget child, Size size, {double scale = 1}) => MaterialApp(
        theme: cricTheme(true),
        home: MediaQuery(
          data:
              MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
          child: Scaffold(
            backgroundColor: const Color(0xff020b1b),
            body: child,
          ),
        ),
      );

  Future<List<FlutterErrorDetails>> pump(
    WidgetTester tester,
    Size size,
    Widget child, {
    double scale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final errors = <FlutterErrorDetails>[];
    final old = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = old);
    await tester.pumpWidget(app(child, size, scale: scale));
    // Two frames: one to lay out, one to let the shimmer's first tick paint.
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pump(const Duration(milliseconds: 40));
    FlutterError.onError = old;
    return errors;
  }

  Iterable<FlutterErrorDetails> overflows(List<FlutterErrorDetails> e) =>
      e.where((d) => d.exceptionAsString().contains('overflowed'));

  testWidgets('352×856 skeleton — no RenderFlex overflow', (tester) async {
    final errors = await pump(
      tester,
      const Size(352, 856),
      const Padding(
        padding: EdgeInsets.all(16),
        child: HomeMatchListSkeletonHost(),
      ),
    );
    expect(overflows(errors), isEmpty,
        reason: 'Skeleton overflowed — the fixed 210px container from the '
            'field failure is back. Skeleton must fit inside the resolved '
            'live-card height.');
    // Two skeletons are visible during the loading state (top + second card).
    expect(find.byKey(homeSkeletonCardKey(0)), findsOneWidget);
    expect(find.byKey(homeSkeletonCardKey(1)), findsOneWidget);
  });

  testWidgets('352×856 skeleton — no overflow at text scale 1.15',
      (tester) async {
    final errors = await pump(
      tester,
      const Size(352, 856),
      const Padding(
        padding: EdgeInsets.all(16),
        child: HomeMatchListSkeletonHost(),
      ),
      scale: 1.15,
    );
    expect(overflows(errors), isEmpty,
        reason: 'Skeleton overflowed at text scale 1.15 — the resolved '
            'height must include the accessibility allowance.');
  });

  testWidgets('skeleton outer height uses homeLiveCardResolvedHeight (352×856)',
      (tester) async {
    const size = Size(352, 856);
    await pump(
      tester,
      size,
      const Padding(
        padding: EdgeInsets.all(16),
        child: HomeMatchListSkeletonHost(),
      ),
    );
    // Padding(16) on all sides → outer card width = 352 − 32 = 320.
    const outerCardWidth = 320.0;
    final expected = homeLiveCardResolvedHeight(
      outerCardWidth: outerCardWidth,
      textScaler: TextScaler.noScaling,
    );
    final rect = tester.getRect(find.byKey(homeSkeletonCardKey(0)));
    expect(rect.width, closeTo(outerCardWidth, 0.5));
    expect(rect.height, closeTo(expected, 0.5),
        reason: 'Skeleton height must equal homeLiveCardResolvedHeight; '
            'expected $expected got ${rect.height}.');
  });

  testWidgets('skeleton and loaded live card share outer height ±2 px',
      (tester) async {
    const size = Size(352, 856);
    // Skeleton first.
    await pump(
      tester,
      size,
      const Padding(
        padding: EdgeInsets.all(16),
        child: HomeMatchListSkeletonHost(),
      ),
    );
    final skeletonRect = tester.getRect(find.byKey(homeSkeletonCardKey(0)));

    // Loaded live card next.
    final match = CricketMatch.fromJson(<String, dynamic>{
      'match_id': 'match-x',
      'status': 'live',
      'status_text': 'Live',
      'series_name': 'Series X',
      'venue': 'Ground X',
      'start_time': '2026-07-13T01:00:00.000Z',
      'team1': {'name': 'Team A', 'shortName': 'AAA', 'id': 'a'},
      'team2': {'name': 'Team B', 'shortName': 'BBB', 'id': 'b'},
      'score': {
        'team1': [
          {'runs': 120, 'wickets': 3, 'overs': 20.0, 'innings_number': 1},
        ],
      },
    });
    await pump(
      tester,
      size,
      Padding(
        padding: const EdgeInsets.all(16),
        child: HomeMatchCardHost(
          match: match,
          repository: CricketRepository(),
        ),
      ),
    );
    final loadedRect =
        tester.getRect(find.byKey(const ValueKey('home-normal-card')));

    // Loaded card includes the shell's 1 px top+bottom border (adds 2). The
    // resolved-height contract is that the two rectangles differ by ≤ 2 px.
    expect(
        (loadedRect.height - skeletonRect.height).abs(), lessThanOrEqualTo(2.0),
        reason: 'Skeleton height ${skeletonRect.height} and loaded height '
            '${loadedRect.height} differ by more than 2 px — the tree will '
            'jump when data arrives.');
    // Widths must be equal.
    expect(loadedRect.width, closeTo(skeletonRect.width, 0.5));
  });

  testWidgets('skeleton content width feeds homeCardEmblemSize correctly',
      (tester) async {
    const size = Size(352, 856);
    await pump(
      tester,
      size,
      const Padding(
        padding: EdgeInsets.all(16),
        child: HomeMatchListSkeletonHost(),
      ),
    );
    // The skeleton's emblem circle is a Container(width==height==emblem) child
    // of the team column. Its rectangle width MUST equal
    // homeCardEmblemSize(contentWidth: cardWidth - kHomeCardPadding.horizontal).
    const outerCardWidth = 320.0;
    final expectedEmblem = homeCardEmblemSize(
      contentWidth: outerCardWidth - kHomeCardPadding.horizontal,
    );
    // The skeleton renders 2 emblem circles (one per team). Both must match.
    final circles = find.byWidgetPredicate((w) =>
        w is Container &&
        w.decoration is BoxDecoration &&
        (w.decoration as BoxDecoration).shape == BoxShape.circle);
    // At least the two team emblems + the top-right star circle exist.
    expect(circles, findsWidgets);
    // Confirm at least ONE of the rendered circles has the expected emblem
    // diameter (float-tolerant): the two team circles in the team row.
    final emblemHits = tester
        .widgetList<Container>(circles)
        .where((w) =>
            w.constraints != null &&
            (w.constraints!.maxWidth - expectedEmblem).abs() < 0.5)
        .toList();
    expect(emblemHits, isNotEmpty,
        reason:
            'No emblem circle matched homeCardEmblemSize($expectedEmblem).');
  });
}
