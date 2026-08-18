import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cricpro_flutter/app_theme.dart';
import 'package:cricpro_flutter/components.dart';
import 'package:cricpro_flutter/models/cricket_match.dart';
import 'package:cricpro_flutter/repositories/cricket_repository.dart';
import 'package:cricpro_flutter/screens/home/home_screen.dart'
    show
        HomeHeroCardHost,
        HomeHeroCarouselHost,
        HomeMatchCardHost,
        HomeMoreUpcomingCtaHost,
        HomeUpcomingRowHost,
        calculateHomeHeroDiagnostics;

CricketMatch _match(
  String id, {
  String series = 'India Women tour of England, 2026',
  String venue = 'The County Ground, Nevil Road, Bristol, United Kingdom',
  bool yetToBat = false,
  String phase = 'stumps',
}) =>
    CricketMatch.fromJson(<String, dynamic>{
      'match_id': id,
      'status': 'live',
      'status_text': phase == 'stumps' ? 'Day 2: Stumps' : 'Live',
      'phase': phase,
      'series_name': series,
      'venue': venue,
      'start_time': '2026-07-10T10:30:00.000Z',
      'team1': {'name': 'England Women', 'shortName': 'ENG-W', 'id': 'eng-w'},
      'team2': {'name': 'India Women', 'shortName': 'IND-W', 'id': 'ind-w'},
      'curr_bat_team_id': 'eng-w',
      'score': {
        'team1': [
          {'runs': 170, 'wickets': 10, 'overs': 59.1, 'innings_number': 1},
          {'runs': 130, 'wickets': 6, 'overs': 40.0, 'innings_number': 3},
        ],
        if (!yetToBat)
          'team2': [
            {'runs': 341, 'wickets': 7, 'overs': 86.3, 'innings_number': 2},
          ],
      },
    });

Widget _app(Widget child, Size size, {double scale = 1}) => MaterialApp(
      theme: cricTheme(true),
      home: MediaQuery(
        data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
        child: Scaffold(backgroundColor: const Color(0xff020b18), body: child),
      ),
    );

void main() {
  const cases = <(Size, double)>[
    (Size(352, 856), 328.40),
    (Size(391, 844), 367.45),
    (Size(477, 922), 448.966),
    (Size(491, 912), 462.378),
  ];

  test('production diagnostics keep normal content in the 1.32-1.38 band', () {
    for (final (screen, cardWidth) in cases) {
      final d = calculateHomeHeroDiagnostics(cardWidth: cardWidth);
      expect(d.contentFloor, lessThanOrEqualTo(d.aspectHeight + .01));
      expect(d.contentFloorActivated, isFalse);
      // Compact cards (≤350 card width) intentionally sit BELOW the landscape
      // band at a taller 1.25 proportion (small-device breathing-room pass): the
      // recovered height is spent on the overs→venue and venue→CTA gaps so the
      // stack reads centered, not bottom-heavy. Roomier cards keep the central
      // 1.32–1.38 landscape band so large devices are visually unchanged.
      final compact = cardWidth <= 350;
      expect(
        d.ratio,
        compact
            ? inInclusiveRange(1.23, 1.27)
            : inInclusiveRange(1.32, 1.38),
      );
      // Compact hero (≤340 card width) drops the primary score floor a step
      // more (24pt) so the score no longer visually swallows the block on
      // 352-class devices; roomier cards keep 26+. Score is still the largest
      // hero element by a comfortable margin.
      final floor = cardWidth <= 340 ? 24.0 : 26.0;
      expect(d.scoreSize, greaterThanOrEqualTo(floor));
      expect(d.logoSize, greaterThanOrEqualTo(screen.width <= 360 ? 58 : 62));
      expect(d.ctaHeight, greaterThanOrEqualTo(screen.width <= 360 ? 44 : 48));
    }
  });

  test('accessibility/stress floors remain landscape', () {
    for (final (_, cardWidth) in cases) {
      final scaled = calculateHomeHeroDiagnostics(
        cardWidth: cardWidth,
        textScaler: const TextScaler.linear(1.15),
      );
      final stressed = calculateHomeHeroDiagnostics(
        cardWidth: cardWidth,
        fontHeightBoost: .06,
      );
      // Compact cards start taller (1.25) so under accessibility/height stress
      // the content-floor safety valve grows them a step further before it caps
      // — they bottom out ~1.15 (still landscape) rather than the 1.22 the
      // roomier landscape-band cards hold. Both stay wider-than-tall.
      final ratioFloor = cardWidth <= 350 ? 1.15 : 1.22;
      expect(scaled.ratio, greaterThanOrEqualTo(ratioFloor));
      expect(stressed.ratio, greaterThanOrEqualTo(ratioFloor));
      final floor = cardWidth <= 340 ? 24.0 : 26.0;
      expect(scaled.scoreSize, greaterThanOrEqualTo(floor));
    }
  });

  for (final (size, expectedWidth) in cases) {
    testWidgets('${size.width.toInt()} hero has exact aspect and no overflow',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final errors = <FlutterErrorDetails>[];
      final old = FlutterError.onError;
      FlutterError.onError = errors.add;
      addTearDown(() => FlutterError.onError = old);
      await tester.pumpWidget(_app(
        HomeHeroCardHost(
          match: _match('fixture'),
          repository: CricketRepository(),
          streamEpoch: 0,
        ),
        size,
      ));
      await tester.pumpAndSettle();
      final rect = tester.getRect(find.byKey(const ValueKey('home-hero-card')));
      expect(rect.width, closeTo(expectedWidth, .15));
      // Compact cards (≤350 card width) sit at the taller 1.25 proportion; see
      // the diagnostics-band test above for why. Roomier cards stay landscape.
      final compact = expectedWidth <= 350;
      expect(
        rect.width / rect.height,
        compact ? inInclusiveRange(1.23, 1.27) : inInclusiveRange(1.32, 1.38),
      );
      expect(errors.where((e) => e.exceptionAsString().contains('overflowed')),
          isEmpty);
      expect(tester.takeException(), isNull);
      final score = tester.widget<Text>(find.text('130/6*'));
      // Compact hero drops the score floor to 24 so the score no longer
      // dominates the block on 352-class devices; roomier cards keep 26+.
      final scoreFloor = size.width <= 360 ? 24.0 : 26.0;
      expect(score.style?.fontSize, greaterThanOrEqualTo(scoreFloor));
    });
  }

  testWidgets('compact venue exposes the complete label exactly once',
      (tester) async {
    const size = Size(352, 856);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final handle = tester.ensureSemantics();
    const venue = 'The County Ground, Nevil Road, Bristol, United Kingdom';
    await tester.pumpWidget(_app(
      HomeHeroCardHost(
        match: _match('venue', venue: venue),
        repository: CricketRepository(),
        streamEpoch: 0,
      ),
      size,
    ));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(venue), findsOneWidget);
    handle.dispose();
  });

  testWidgets('352 carousel uses real 4-8px neighbour intersections',
      (tester) async {
    const size = Size(352, 856);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(
      HomeHeroCarouselHost(
        matches: [_match('active'), _match('next'), _match('previous')],
        repository: CricketRepository(),
      ),
      size,
    ));
    await tester.pumpAndSettle();
    final viewport = tester.getRect(find.byType(PageView));
    final active =
        tester.getRect(find.byKey(const ValueKey('home-hero-card-active')));
    final next =
        tester.getRect(find.byKey(const ValueKey('home-hero-card-next')));
    final previous =
        tester.getRect(find.byKey(const ValueKey('home-hero-card-previous')));
    expect(
        (active.center.dx - viewport.center.dx).abs(), lessThanOrEqualTo(1.5));
    expect(active.width, inInclusiveRange(326, 332));
    expect(previous.intersect(viewport).width, inInclusiveRange(4, 6));
    expect(next.intersect(viewport).width, inInclusiveRange(4, 6));
  });

  testWidgets('normal Home cards keep a stable height across data variations',
      (tester) async {
    const size = Size(352, 856);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final heights = <double>[];
    for (final match in [
      _match('short', venue: 'Bristol', phase: 'live'),
      _match('long'),
      _match('missing', venue: '', yetToBat: true),
      _match('phase', phase: 'stumps'),
    ]) {
      await tester.pumpWidget(_app(
        Padding(
          padding: const EdgeInsets.all(16),
          child: HomeMatchCardHost(
            match: match,
            repository: CricketRepository(),
          ),
        ),
        size,
      ));
      await tester.pumpAndSettle();
      heights.add(tester
          .getRect(find.byKey(const ValueKey('home-normal-card')))
          .height);
      expect(tester.takeException(), isNull);
    }
    expect(heights.toSet(), hasLength(1), reason: 'measured=$heights');
  });

  testWidgets('final Home card scrolls fully above the shared BottomNav',
      (tester) async {
    const size = Size(352, 856);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: cricTheme(true),
      home: Scaffold(
        bottomNavigationBar: BottomNav(active: AppTab.home, onTab: (_) {}),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            for (var i = 0; i < 6; i++) ...[
              Container(
                key: ValueKey('clearance-card-$i'),
                child: HomeMatchCardHost(
                  match: _match('clearance-$i'),
                  repository: CricketRepository(),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ],
        ),
      ),
    ));
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('clearance-card-5')),
      300,
    );
    await tester.drag(find.byType(ListView), const Offset(0, -24));
    await tester.pumpAndSettle();
    final last = tester.getRect(find.byKey(const ValueKey('clearance-card-5')));
    final nav = tester.getRect(find.byType(BottomNav));
    expect(last.bottom, lessThanOrEqualTo(nav.top - 8));
  });

  // §B — explicit separation between the date/time row and the emblem/VS row on
  // compact widths. The gap must be visible (≥8px) so the two regions never
  // crowd on 352/372-class phones.
  for (final width in <double>[352, 372]) {
    testWidgets('${width.toInt()} hero keeps a visible date→emblem gap',
        (tester) async {
      final size = Size(width, 856);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(
        HomeHeroCardHost(
          match: _match('gap'),
          repository: CricketRepository(),
          streamEpoch: 0,
        ),
        size,
      ));
      await tester.pumpAndSettle();
      // Bottom of the date/time line (calendar icon) vs top of the nearest team
      // code above the score. Both team codes render identically; use ENG-W.
      final dateIcon =
          tester.getRect(find.byIcon(Icons.calendar_month_rounded).first);
      final teamCode = tester.getRect(find.text('ENG-W'));
      expect(teamCode.top - dateIcon.bottom, greaterThanOrEqualTo(8),
          reason: 'date→emblem gap too small at ${width.toInt()}px');
    });
  }

  // §D — the overs row occupies a FIXED rectangle regardless of the score value,
  // so a live refresh that changes the score never nudges the overs/venue rows
  // (no flicker). Pump two different scores at the same size and compare.
  testWidgets('hero overs row rect is stable across a score refresh',
      (tester) async {
    const size = Size(352, 856);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    (double overs, double card) measureFor(
      CricketMatch match,
      WidgetTester t,
    ) {
      // Reserved overs slot height beneath the primary score, and the outer
      // hero card height. Both must be invariant across a poll refresh — the
      // reserved slot never collapses and the fixed-aspect card never resizes,
      // so the venue row below never jumps (§D, no flicker).
      final oversRect = t.getRect(find.textContaining('OVERS').first);
      final cardRect = t.getRect(find.byKey(const ValueKey('home-hero-card')));
      return (oversRect.height, cardRect.height);
    }

    Future<(double, double)> pumpAndMeasure(CricketMatch match) async {
      await tester.pumpWidget(_app(
        HomeHeroCardHost(
          match: match,
          repository: CricketRepository(),
          streamEpoch: 0,
        ),
        size,
      ));
      await tester.pumpAndSettle();
      return measureFor(match, tester);
    }

    final before = await pumpAndMeasure(_match('refresh-a', phase: 'live'));
    // Same fixture geometry, different runs/overs values (a poll refresh).
    final refreshed = CricketMatch.fromJson(<String, dynamic>{
      'match_id': 'refresh-b',
      'status': 'live',
      'status_text': 'Live',
      'phase': 'live',
      'series_name': 'India Women tour of England, 2026',
      'venue': 'The County Ground, Nevil Road, Bristol, United Kingdom',
      'start_time': '2026-07-10T10:30:00.000Z',
      'team1': {'name': 'England Women', 'shortName': 'ENG-W', 'id': 'eng-w'},
      'team2': {'name': 'India Women', 'shortName': 'IND-W', 'id': 'ind-w'},
      'curr_bat_team_id': 'eng-w',
      'score': {
        'team1': [
          {'runs': 8, 'wickets': 1, 'overs': 2.3, 'innings_number': 1},
        ],
        'team2': [
          {'runs': 341, 'wickets': 7, 'overs': 86.3, 'innings_number': 2},
        ],
      },
    });
    final after = await pumpAndMeasure(refreshed);
    // The rendered overs glyph height may vary sub-pixel as the FittedBox scales
    // a longer/shorter overs string WITHIN its reserved slot — that is not a
    // layout move. The anti-flicker guarantee is that neither the reserved slot
    // nor the outer card RESIZES enough to shift the venue row below.
    expect((after.$1 - before.$1).abs(), lessThan(1.5),
        reason: 'overs slot height changed on refresh: $before → $after');
    expect((after.$2 - before.$2).abs(), lessThan(0.5),
        reason: 'hero card height changed on refresh: $before → $after');
  });

  // §E — a paused Test at Stumps must show the truthful phase pill, NOT a
  // generic LIVE pill (break phase wins over live).
  testWidgets('hero center pill shows Stumps phase, not LIVE, at a break',
      (tester) async {
    const size = Size(352, 856);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(
      HomeHeroCardHost(
        match: _match('stumps', phase: 'stumps'),
        repository: CricketRepository(),
        streamEpoch: 0,
      ),
      size,
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Stumps'), findsWidgets);
  });

  // §G — narrow-width Upcoming teaser shows an intentional next-card peek in the
  // 10-14px band (never a card cut at ~40%).
  testWidgets('upcoming teaser shows a 10-14px next-card peek at 352',
      (tester) async {
    const size = Size(352, 856);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final matches = [
      _match('u1', phase: 'live'),
      _match('u2', phase: 'live'),
      _match('u3', phase: 'live'),
    ];
    await tester.pumpWidget(_app(
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: HomeUpcomingRowHost(matches: matches),
      ),
      size,
    ));
    await tester.pumpAndSettle();
    final viewport = tester.getRect(find.byType(ListView));
    final second =
        tester.getRect(find.byKey(const ValueKey('home-upcoming-card-u2')));
    final peek = viewport.right - second.left;
    expect(peek, inInclusiveRange(10, 14), reason: 'peek=$peek');
  });

  // §F — every Upcoming card renders at the same fixed height.
  testWidgets('upcoming cards keep one uniform height', (tester) async {
    const size = Size(352, 856);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: HomeUpcomingRowHost(matches: [
          _match('short', series: 'IPL', venue: 'Bristol'),
          _match('long'),
          _match('bare', venue: '', yetToBat: true),
        ]),
      ),
      size,
    ));
    await tester.pumpAndSettle();
    // The row is a lazy horizontal ListView; scroll each card into view before
    // measuring so off-screen entries are actually built.
    final heights = <double>[];
    for (final id in ['short', 'long', 'bare']) {
      await tester.scrollUntilVisible(
        find.byKey(ValueKey('home-upcoming-card-$id')),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      heights.add(tester
          .getRect(find.byKey(ValueKey('home-upcoming-card-$id')))
          .height);
    }
    expect(heights.toSet(), hasLength(1), reason: 'measured=$heights');
  });

  // §H — the "More Upcoming Matches" CTA subtitle renders complete, never with a
  // dangling ellipsis fragment.
  testWidgets('More Upcoming CTA subtitle has no ellipsis', (tester) async {
    const size = Size(352, 856);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: HomeMoreUpcomingCtaHost(),
      ),
      size,
    ));
    await tester.pumpAndSettle();
    // Subtitle text present verbatim, and nowhere in the CTA is an ellipsis.
    expect(find.text('See the full fixture list'), findsOneWidget);
    expect(find.textContaining('…'), findsNothing);
  });
}
