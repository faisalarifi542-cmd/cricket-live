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
    show HomeHeroCardHost;

const _generate = bool.fromEnvironment('GENERATE_HOME_VISUAL_EVIDENCE');
const _evidenceFont = 'HomeEvidenceSans';

CricketMatch _fixture(String state) => CricketMatch.fromJson({
      'match_id': 'evidence-$state',
      'status': 'live',
      'status_text': state == 'multi' ? 'Day 2: Stumps' : 'Live',
      'phase': state == 'multi' ? 'stumps' : 'live',
      'series_name': 'India Women tour of England, 2026',
      'venue': 'The County Ground, Nevil Road, Bristol, United Kingdom',
      'start_time': '2026-07-10T10:30:00.000Z',
      'team1': {'name': 'England Women', 'shortName': 'ENG-W', 'id': 'eng-w'},
      'team2': {'name': 'India Women', 'shortName': 'IND-W', 'id': 'ind-w'},
      'curr_bat_team_id': 'eng-w',
      'score': {
        'team1': state == 'single'
            ? [
                {'runs': 138, 'wickets': 10, 'overs': 36.0, 'innings_number': 1}
              ]
            : [
                {
                  'runs': 170,
                  'wickets': 10,
                  'overs': 59.1,
                  'innings_number': 1
                },
                {'runs': 130, 'wickets': 6, 'overs': 40.0, 'innings_number': 3},
              ],
        if (state != 'yet_to_bat')
          'team2': [
            {'runs': 341, 'wickets': 7, 'overs': 86.3, 'innings_number': 2},
          ],
      },
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

  for (final size in const <Size>[
    Size(352, 856),
    Size(391, 844),
    Size(477, 922),
    Size(491, 912),
  ]) {
    for (final state in const ['single', 'multi', 'yet_to_bat']) {
      testWidgets(
          'render ${size.width.toInt()}x${size.height.toInt()} $state evidence',
          (tester) async {
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
                child: Align(
                  alignment: Alignment.topCenter,
                  child: HomeHeroCardHost(
                    match: _fixture(state),
                    repository: CricketRepository(),
                    streamEpoch: 0,
                  ),
                ),
              ),
            ),
          ),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('home-hero-card')), findsOneWidget);

        if (_generate) {
          final boundary = boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          final path = 'build/home_visual_evidence/'
              'home_${size.width.toInt()}x${size.height.toInt()}_$state.png';
          final file = File(path);
          file.parent.createSync(recursive: true);
          file.writeAsBytesSync(data!.buffer.asUint8List(), flush: true);
        }
        // Tear down image streams/repository futures before the test binding
        // shuts down; Windows raster tests otherwise keep the process alive
        // after a `toImage` capture.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });
    }
  }
}
