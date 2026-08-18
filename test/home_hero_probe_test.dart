import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cricpro_flutter/app_theme.dart';
import 'package:cricpro_flutter/components.dart';
import 'package:cricpro_flutter/models/cricket_match.dart';
import 'package:cricpro_flutter/repositories/cricket_repository.dart';
import 'package:cricpro_flutter/screens/home/home_screen.dart'
    show HomeHeroCardHost;

/// TEMPORARY measurement probe — prints the real rendered geometry of the LIVE
/// hero (screenshot fixture: ZIM batting 129/4, BAN yet to bat) at the target
/// widths so the §1/§3/§5 fixes are driven by measured rectangles.
CricketMatch _zimBan() => CricketMatch.fromJson(<String, dynamic>{
      'match_id': 'zim-ban-live',
      'status': 'live',
      'status_text': 'Live',
      'phase': 'live',
      'series_name': 'Bangladesh tour of Zimbabwe, 2026',
      'venue': 'Queens Sports Club, Bulawayo',
      'start_time': '2026-07-15T07:00:00.000Z',
      'team1': {'name': 'Zimbabwe', 'shortName': 'ZIM', 'id': 'zim'},
      'team2': {'name': 'Bangladesh', 'shortName': 'BAN', 'id': 'ban'},
      'curr_bat_team_id': 'zim',
      'score': {
        'team1': [
          {'runs': 129, 'wickets': 4, 'overs': 15.3, 'innings_number': 1},
        ],
      },
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

void main() {
  for (final size in const <Size>[
    Size(352, 856),
    Size(372, 878),
    Size(391, 844),
    Size(477, 922),
    Size(491, 912),
  ]) {
    testWidgets('probe live hero ${size.width.toInt()}', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_app(
        HomeHeroCardHost(
          match: _zimBan(),
          repository: CricketRepository(),
          streamEpoch: 0,
        ),
        size,
      ));
      await tester.pumpAndSettle();
      final card = tester.getRect(find.byKey(const ValueKey('home-hero-card')));
      final dateIcon =
          tester.getRect(find.byIcon(Icons.calendar_month_rounded).first);
      final logos = find.byType(TeamLogoWidget);
      final logoTop = math.min(
          tester.getRect(logos.first).top, tester.getRect(logos.last).top);
      final score = tester.getRect(find.text('129/4'));
      final overs = tester.getRect(find.text('15.3 OVERS'));
      final yet = tester.getRect(find.text('Yet to bat'));
      final venueIcon =
          tester.getRect(find.byIcon(Icons.location_on_outlined).first);
      final cta = tester.getRect(find.text('Match Center'));
      final codeZim = tester.getRect(find.text('ZIM'));
      final codeBan = tester.getRect(find.text('BAN'));
      debugPrint('PROBE ${size.width.toInt()}: card=$card');
      debugPrint('  dateIcon.bottom=${dateIcon.bottom} logoTop=$logoTop '
          'gap=${(logoTop - dateIcon.bottom).toStringAsFixed(1)}');
      debugPrint('  codeZim=$codeZim codeBan=$codeBan');
      debugPrint('  score=$score overs=$overs yet=$yet');
      debugPrint(
          '  oversBottom=${overs.bottom} venueIconTop=${venueIcon.top} '
          'gap=${(venueIcon.top - overs.bottom).toStringAsFixed(1)}');
      debugPrint('  cta=$cta cardBottom=${card.bottom}');
      final exception = tester.takeException();
      debugPrint('  exception=$exception');
    });
  }
}
