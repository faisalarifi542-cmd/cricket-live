import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cricpro_flutter/app_theme.dart';
import 'package:cricpro_flutter/models/cricket_match.dart';
import 'package:cricpro_flutter/repositories/cricket_repository.dart';
import 'package:cricpro_flutter/screens/home/home_screen.dart'
    show HomeEmptyStateHost, HomeHeroCardHost, HomeUpcomingListCardHost;

/// Visual evidence for the July 2026 Home-only refinement (§1/§2/§3/§4):
/// upcoming hero (date→team gap + complete "Starts Soon" pill), the refined
/// vertical-list Upcoming card, and the Live empty state. Same generation
/// switch as home_visual_evidence_test.dart.
const _generate = bool.fromEnvironment('GENERATE_HOME_VISUAL_EVIDENCE');
const _evidenceFont = 'HomeEvidenceSans';

CricketMatch _upcoming(String id, {String series = 'T20 Blast 2026'}) =>
    CricketMatch.fromJson(<String, dynamic>{
      'match_id': id,
      'status': 'upcoming',
      'status_text': 'Match starts at 12:30 PM',
      'series_name': series,
      'venue': 'Queens Sports Club, Bulawayo',
      'start_time': '2026-07-15T07:00:00.000Z',
      'team1': {'name': 'Zimbabwe', 'shortName': 'ZIM', 'id': 'zim'},
      'team2': {'name': 'Bangladesh', 'shortName': 'BAN', 'id': 'ban'},
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final systemFont = File(r'C:\Windows\Fonts\segoeui.ttf');
    if (systemFont.existsSync()) {
      final loader = FontLoader(_evidenceFont)
        ..addFont(systemFont.readAsBytes().then(ByteData.sublistView));
      await loader.load();
    }
  });

  Future<void> capture(
    WidgetTester tester,
    Size size,
    String name,
    Widget child,
  ) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final boundaryKey = GlobalKey();
    final baseTheme = cricTheme(true);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en', 'GB'),
      theme: baseTheme.copyWith(
        textTheme: baseTheme.textTheme.apply(fontFamily: _evidenceFont),
        primaryTextTheme:
            baseTheme.primaryTextTheme.apply(fontFamily: _evidenceFont),
      ),
      home: MediaQuery(
        data: MediaQueryData(
          size: size,
          devicePixelRatio: 1,
          textScaler: TextScaler.noScaling,
          disableAnimations: true,
        ),
        child: Scaffold(
          backgroundColor: const Color(0xff020b18),
          body: RepaintBoundary(
            key: boundaryKey,
            child: Align(alignment: Alignment.topCenter, child: child),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    if (_generate) {
      final boundary = boundaryKey.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final path = 'build/home_visual_evidence/'
          '${name}_${size.width.toInt()}x${size.height.toInt()}.png';
      final file = File(path);
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(data!.buffer.asUint8List(), flush: true);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  for (final size in const <Size>[Size(352, 856), Size(391, 844)]) {
    testWidgets('upcoming hero evidence ${size.width.toInt()}',
        (tester) async {
      await capture(
        tester,
        size,
        'upcoming_hero',
        HomeHeroCardHost(
          match: _upcoming('hero',
              series: 'Bangladesh tour of Zimbabwe, 2026'),
          repository: CricketRepository(),
          streamEpoch: 0,
        ),
      );
    });

    testWidgets('upcoming list card evidence ${size.width.toInt()}',
        (tester) async {
      await capture(
        tester,
        Size(size.width, 700),
        'upcoming_card',
        Padding(
          padding: const EdgeInsets.all(16),
          child: HomeUpcomingListCardHost(matches: [
            _upcoming('a'),
            _upcoming('b',
                series: 'Asia Pacific Cricket Championship Qualifier, 2026'),
          ]),
        ),
      );
    });

    testWidgets('live empty state evidence ${size.width.toInt()}',
        (tester) async {
      await capture(
        tester,
        Size(size.width, 500),
        'live_empty_state',
        Padding(
          padding: const EdgeInsets.all(16),
          child: HomeEmptyStateHost(topTab: 0, onSwitchUpcoming: () {}),
        ),
      );
    });
  }
}
