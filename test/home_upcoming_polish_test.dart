import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cricpro_flutter/app_theme.dart';
import 'package:cricpro_flutter/components.dart';
import 'package:cricpro_flutter/models/cricket_match.dart';
import 'package:cricpro_flutter/repositories/cricket_repository.dart';
import 'package:cricpro_flutter/screens/home/home_screen.dart'
    show HomeHeroCardHost, HomeUpcomingListCardHost;

/// Home-only visual refinement regression tests:
///   §1/§B — compact UPCOMING hero keeps visible breathing room between the
///           date/time row and the team emblem row (8+ logical px).
///   §2    — the hero centre status pill for an upcoming match renders a SHORT
///           complete label ("Starts Soon"), never a truncated fragment.
///   §4/§7 — vertical-list Upcoming cards share one fixed equal height, fit
///           compact widths without overflow, and keep the footer rows visible.
CricketMatch _upcoming(
  String id, {
  String series = 'Bangladesh tour of Zimbabwe, 2026',
  String venue = 'Queens Sports Club, Bulawayo',
}) =>
    CricketMatch.fromJson(<String, dynamic>{
      'match_id': id,
      'status': 'upcoming',
      'status_text': 'Match starts at 12:30 PM',
      'series_name': series,
      'venue': venue,
      'start_time': '2026-07-15T07:00:00.000Z',
      'team1': {'name': 'Zimbabwe', 'shortName': 'ZIM', 'id': 'zim'},
      'team2': {'name': 'Bangladesh', 'shortName': 'BAN', 'id': 'ban'},
    });

Widget _app(Widget child, Size size) => MaterialApp(
      theme: cricTheme(true),
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: Scaffold(
          backgroundColor: const Color(0xff020b18),
          body: child,
        ),
      ),
    );

/// True when [finder]'s RenderParagraph had to ellipsise: its intrinsic
/// single-line width exceeds the width it actually laid out at.
bool _textTruncated(WidgetTester tester, Finder finder) {
  final p = tester.renderObject<RenderParagraph>(finder);
  final painter = TextPainter(
    text: p.text,
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout();
  return painter.size.width > p.size.width + 0.5;
}

void main() {
  // §2 — the upcoming hero centre pill must be fully readable on every compact
  // width (the "Starts J..." defect).
  for (final width in <double>[352, 372, 391]) {
    testWidgets(
        '${width.toInt()} upcoming hero status pill is complete, never truncated',
        (tester) async {
      final size = Size(width, 856);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(
        HomeHeroCardHost(
          match: _upcoming('pill'),
          repository: CricketRepository(),
          streamEpoch: 0,
        ),
        size,
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final pill = find.text('Starts Soon');
      expect(pill, findsOneWidget,
          reason: 'upcoming hero must use the short complete label');
      expect(_textTruncated(tester, pill), isFalse,
          reason: 'the centre pill label must never ellipsise');
    });
  }

  // §1/§B — measured breathing room between the bottom of the date row and the
  // top of the team emblem row on compact upcoming heroes.
  for (final width in <double>[352, 372, 391]) {
    testWidgets(
        '${width.toInt()} upcoming hero date→emblem gap is a visible 8+px',
        (tester) async {
      final size = Size(width, 856);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(
        HomeHeroCardHost(
          match: _upcoming('gap'),
          repository: CricketRepository(),
          streamEpoch: 0,
        ),
        size,
      ));
      await tester.pumpAndSettle();
      final dateIcon =
          tester.getRect(find.byIcon(Icons.calendar_month_rounded).first);
      // Top of the emblem row = the highest team logo circle.
      final logos = find.byType(TeamLogoWidget);
      expect(logos, findsNWidgets(2));
      final logoTop = math.min(
          tester.getRect(logos.first).top, tester.getRect(logos.last).top);
      final gap = logoTop - dateIcon.bottom;
      debugPrint('upcoming hero date→emblem gap at ${width.toInt()}px: '
          '${gap.toStringAsFixed(1)}px');
      expect(gap, greaterThanOrEqualTo(8),
          reason: 'date row crowds the emblem row at ${width.toInt()}px '
              '(gap=$gap)');
      expect(tester.takeException(), isNull);
    });
  }

  // §4 — vertical-list Upcoming cards: one fixed equal height across content
  // variations, no overflow at compact widths, footer rows visible + aligned.
  for (final width in <double>[352, 372, 391]) {
    testWidgets(
        '${width.toInt()} upcoming list cards share one height, no overflow',
        (tester) async {
      final size = Size(width, 1400);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final matches = [
        _upcoming('a', series: 'T20 Blast 2026', venue: 'Headingley'),
        _upcoming('b'),
        _upcoming('c',
            series: 'Asia Pacific Cricket Championship Qualifier, 2026',
            venue:
                'The Kent County Cricket Ground, Old Dover Road, Canterbury'),
      ];
      await tester.pumpWidget(_app(
        SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: HomeUpcomingListCardHost(matches: matches),
          ),
        ),
        size,
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final heights = <double>[];
      for (final id in ['a', 'b', 'c']) {
        heights.add(tester
            .getRect(find.byKey(ValueKey('home-upcoming-list-card-$id')))
            .height);
      }
      expect(heights.toSet(), hasLength(1),
          reason: 'upcoming cards must share one stable height: $heights');

      // Footer rows visible on every card: venue icon, date icon, CTA.
      expect(find.byIcon(Icons.location_on_outlined), findsNWidgets(3));
      expect(find.text('View Match'), findsNWidgets(3));
      // The CTA sits inside its card (right-aligned, not floating below).
      final card = tester
          .getRect(find.byKey(const ValueKey('home-upcoming-list-card-a')));
      final cta = tester.getRect(find.text('View Match').first);
      expect(cta.bottom, lessThanOrEqualTo(card.bottom));
      expect(cta.top, greaterThanOrEqualTo(card.top));
    });
  }
}
