import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cricpro_flutter/models/cricket_match.dart';
import 'package:cricpro_flutter/services/persistent_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CricketMatch cache round-trip (F1)', () {
    test('toCacheJson -> fromCacheJson preserves all fields', () {
      final original = CricketMatch.fromJson(<String, dynamic>{
        'match_id': 'm123',
        'status': 'live',
        'statusText': 'IND need 40 runs',
        'team1': {'name': 'India', 'short_name': 'IND'},
        'team2': {'name': 'Australia', 'short_name': 'AUS'},
        'venue': 'MCG',
        'hasLiveStream': true,
        'streamCount': 2,
      });

      final restored = CricketMatch.fromCacheJson(original.toCacheJson());

      expect(restored.id, original.id);
      expect(restored.title, original.title);
      expect(restored.status, original.status);
      expect(restored.statusText, original.statusText);
      expect(restored.teamA, original.teamA);
      expect(restored.teamB, original.teamB);
      expect(restored.teamAShort, original.teamAShort);
      expect(restored.teamBShort, original.teamBShort);
      expect(restored.venue, original.venue);
      expect(restored.isLive, original.isLive);
      expect(restored.isFinished, original.isFinished);
      expect(restored.isUpcoming, original.isUpcoming);
      expect(restored.hasLiveStream, original.hasLiveStream);
      expect(restored.streamCount, original.streamCount);
      expect(restored.teamAScoreText, original.teamAScoreText);
      expect(restored.teamBScoreText, original.teamBScoreText);
    });

    test('fromCacheJson on empty map does not throw', () {
      final m = CricketMatch.fromCacheJson(const <String, dynamic>{});
      expect(m.id, '');
      expect(m.isUpcoming, true);
    });
  });

  group('PersistentCache (F1)', () {
    setUp(() {
      // In-memory SharedPreferences for tests (no platform channel needed).
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('write then read returns the same payload', () async {
      const key = 'test:app:home';
      await PersistentCache.instance
          .write(key, <String, dynamic>{'hello': 'world', 'n': 1});
      final out = await PersistentCache.instance.read<Map<String, dynamic>>(
          key, (p) => Map<String, dynamic>.from(p as Map));
      expect(out, isNotNull);
      expect(out!['hello'], 'world');
      expect(out['n'], 1);
    });

    test('read of missing key returns null', () async {
      final out = await PersistentCache.instance
          .read<Object?>('test:does:not:exist', (p) => p);
      expect(out, isNull);
    });

    test('corrupt entry is dropped and reports a miss', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'cache_v1:test:bad': 'not-json{{{',
      });
      final out = await PersistentCache.instance
          .read<Object?>('test:bad', (p) => p);
      expect(out, isNull);
    });
  });
}
