// Validates the /app/home parsing contract: safe defaults when config is
// empty, disabled sections, manual-id handling, and that real score/team data
// survives parsing unchanged.

import 'package:flutter_test/flutter_test.dart';
import 'package:cricpro_flutter/models/home_feed.dart';

void main() {
  group('HomeLayoutConfig', () {
    test('empty json falls back to safe defaults', () {
      final cfg = HomeLayoutConfig.fromJson(<String, dynamic>{});
      expect(cfg.sectionOrder,
          ['topFeatured', 'mainMatches', 'featuredMatches', 'featuredSeries']);
      expect(cfg.topFeatured.enabled, true);
      expect(cfg.topFeatured.showDots, true);
      expect(cfg.mainMatches.enabled, true);
      expect(cfg.mainMatches.defaultTabIndex, 0);
      expect(cfg.mainMatches.defaultCategoryIndex, 0);
      expect(cfg.mainMatches.maxItems, 12);
      expect(cfg.featuredMatches.title, 'Featured Matches');
      expect(cfg.featuredSeries.title, 'Featured Series');
    });

    test('null falls back to defaults', () {
      final cfg = HomeLayoutConfig.fromJson(null);
      expect(cfg.topFeatured.enabled, true);
      expect(cfg.featuredSeries.showSeeAll, true);
    });

    test('partial config merges over defaults', () {
      final cfg = HomeLayoutConfig.fromJson({
        'sectionOrder': ['featuredSeries', 'mainMatches'],
        'sections': {
          'topFeatured': {'enabled': false, 'showDots': false},
          'mainMatches': {
            'defaultTab': 'finished',
            'defaultCategory': 'league',
            'showStatusTabs': false,
            'maxItems': 5,
          },
          'featuredMatches': {'title': 'Hot Games', 'showSeeAll': false},
        },
      });
      // Unknown-safe: defaults fill any missing sections in the order.
      expect(cfg.sectionOrder.contains('topFeatured'), true);
      expect(cfg.sectionOrder.first, 'featuredSeries');
      expect(cfg.topFeatured.enabled, false);
      expect(cfg.topFeatured.showDots, false);
      expect(cfg.mainMatches.defaultTabIndex, 2);
      expect(cfg.mainMatches.defaultCategoryIndex, 2);
      expect(cfg.mainMatches.showStatusTabs, false);
      expect(cfg.mainMatches.maxItems, 5);
      expect(cfg.featuredMatches.title, 'Hot Games');
      expect(cfg.featuredMatches.showSeeAll, false);
    });
  });

  group('HomeFeed', () {
    test('empty payload yields empty lists and default config', () {
      final feed = HomeFeed.fromJson(<String, dynamic>{});
      expect(feed.topFeatured, isEmpty);
      expect(feed.featuredMatches, isEmpty);
      expect(feed.featuredSeries, isEmpty);
      expect(feed.config.topFeatured.enabled, true);
    });

    test('parses featured series and skips empty entries', () {
      final feed = HomeFeed.fromJson({
        'featuredSeriesList': [
          {
            'id': 7,
            'title': 'ICC T20 World Cup 2026',
            'date_range': 'Jun – Jul 2026',
            'location': 'India',
            'image_url': 'https://x/p.png',
            'series_external_id': '9237',
          },
          {'id': 8}, // no title/image → skipped
        ],
      });
      expect(feed.featuredSeries.length, 1);
      final s = feed.featuredSeries.first;
      expect(s.title, 'ICC T20 World Cup 2026');
      expect(s.dateRange, 'Jun – Jul 2026');
      expect(s.location, 'India');
      expect(s.hasImage, true);
      expect(s.hasSeriesLink, true);
    });

    test('preserves real match score/team fields from top-featured', () {
      final feed = HomeFeed.fromJson({
        'topFeaturedMatches': [
          {
            'match_id': 'm1',
            'status': 'live',
            'team1': {'name': 'India', 'short_name': 'IND'},
            'team2': {'name': 'Australia', 'short_name': 'AUS'},
            'team1Score': {'runs': 284, 'wickets': 8, 'overs': '50.0'},
          },
        ],
      });
      expect(feed.topFeatured.length, 1);
      final m = feed.topFeatured.first;
      expect(m.teamA, 'India');
      expect(m.teamAShort, 'IND');
      expect(m.teamB, 'Australia');
      expect(m.isLive, true);
      expect(m.teamAScoreText.contains('284/8'), true);
    });

    test('invalid matches (no id) are skipped safely', () {
      final feed = HomeFeed.fromJson({
        'featuredMatches': [
          {'status': 'live'}, // no id → skipped
          {'match_id': 'ok', 'team1': {'name': 'A'}, 'team2': {'name': 'B'}},
        ],
      });
      expect(feed.featuredMatches.length, 1);
      expect(feed.featuredMatches.first.id, 'ok');
    });
  });
}
