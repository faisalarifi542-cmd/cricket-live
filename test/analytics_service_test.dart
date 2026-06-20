import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cricpro_flutter/services/analytics_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    AnalyticsService.instance.dispose();
  });

  test('initialize creates a device id and queues app_open + session_start', () async {
    await AnalyticsService.instance.initialize();
    // app_open + session_start queued on init.
    expect(AnalyticsService.instance.queueLength, greaterThanOrEqualTo(2));
    expect(AnalyticsService.instance.debugSessionId, isNotNull);
  });

  test('track is fire-and-forget and never throws', () {
    expect(() => AnalyticsService.instance.track('screen_view', {'screen_name': 'home'}),
        returnsNormally);
  });

  test('queue is capped at the max size', () async {
    for (var i = 0; i < 500; i++) {
      AnalyticsService.instance.track('screen_view', {'i': i});
    }
    // Hard cap is 200.
    expect(AnalyticsService.instance.queueLength, lessThanOrEqualTo(200));
  });

  test('startSession rotates the session id', () async {
    await AnalyticsService.instance.initialize();
    final first = AnalyticsService.instance.debugSessionId;
    AnalyticsService.instance.startSession();
    expect(AnalyticsService.instance.debugSessionId, isNot(equals(first)));
  });
}
