import 'package:cricpro_flutter/api_models.dart';
import 'package:cricpro_flutter/core/api/api_config.dart';

import 'cricket_match.dart';

/// A manual "Featured Series" entry managed entirely from the Admin Panel.
///
/// The cricket provider does not expose a featured-series feed, so operators
/// add these by hand with a poster image, name, date range and location. Every
/// field except [title] is optional so partially-filled rows still render.
class HomeFeaturedSeries {
  const HomeFeaturedSeries({
    required this.id,
    required this.seriesExternalId,
    required this.title,
    required this.subtitle,
    required this.dateRange,
    required this.location,
    required this.imageUrl,
    required this.ctaLabel,
    required this.ctaUrl,
    required this.formatText,
    required this.teamAName,
    required this.teamAShort,
    required this.teamALogo,
    required this.teamBName,
    required this.teamBShort,
    required this.teamBLogo,
  });

  final String id;
  final String seriesExternalId;
  final String title;
  final String subtitle;
  final String dateRange;
  final String location;
  final String imageUrl;
  final String ctaLabel;
  final String ctaUrl;

  /// Optional descriptors from the Admin Panel row (e.g. `3 T20s , 3 ODIs`).
  final String formatText;
  final String teamAName;
  final String teamAShort;
  final String teamALogo;
  final String teamBName;
  final String teamBShort;
  final String teamBLogo;

  bool get hasImage => imageUrl.trim().isNotEmpty;
  bool get hasSeriesLink => seriesExternalId.trim().isNotEmpty;
  bool get hasTeams => teamAShort.isNotEmpty || teamBShort.isNotEmpty;
  bool get isRenderable => title.isNotEmpty || hasImage;

  factory HomeFeaturedSeries.fromJson(dynamic value) {
    final json = apiMap(value);
    String pick(List<String> keys) {
      for (final k in keys) {
        final v = apiString(json[k], '').trim();
        if (v.isNotEmpty) return v;
      }
      return '';
    }

    return HomeFeaturedSeries(
      id: pick(const ['id', 'series_id']),
      seriesExternalId:
          pick(const ['series_external_id', 'seriesExternalId', 'external_id']),
      title: pick(const ['title', 'name', 'series_name', 'seriesName']),
      subtitle: pick(const ['subtitle']),
      dateRange: pick(const ['date_range', 'dateRange', 'dates']),
      location: pick(const ['location', 'country', 'host', 'venue']),
      imageUrl: _resolveUrl(pick(const ['image_url', 'imageUrl', 'poster', 'image'])),
      ctaLabel: pick(const ['cta_label', 'ctaLabel']),
      ctaUrl: pick(const ['cta_url', 'ctaUrl']),
      formatText: pick(const ['format_text', 'formatText', 'format']),
      teamAName: pick(const ['team_a_name', 'teamAName', 'team_a']),
      teamAShort: pick(const ['team_a_short', 'teamAShort']),
      teamALogo: _resolveUrl(pick(const ['team_a_logo', 'teamALogo'])),
      teamBName: pick(const ['team_b_name', 'teamBName', 'team_b']),
      teamBShort: pick(const ['team_b_short', 'teamBShort']),
      teamBLogo: _resolveUrl(pick(const ['team_b_logo', 'teamBLogo'])),
    );
  }

  /// Admin-uploaded media can be returned either as a full `https://…` URL or
  /// as a server-relative path like `/uploads/…`; resolve the latter against
  /// the API base so the image actually loads on-device.
  static String _resolveUrl(String url) {
    final u = url.trim();
    if (u.isEmpty) return '';
    if (u.startsWith('http://') || u.startsWith('https://')) return u;
    const base = ApiConfig.baseUrl;
    if (u.startsWith('/')) return '$base$u';
    return '$base/$u';
  }
}

// ============================================================================
// Home layout configuration (mirrors backend src/lib/home-layout.js).
// Every field has a safe default so the screen still renders if the API
// returns nothing or an older response shape.
// ============================================================================

class TopFeaturedConfig {
  const TopFeaturedConfig({
    required this.enabled,
    required this.showDots,
  });
  final bool enabled;
  final bool showDots;

  factory TopFeaturedConfig.fromJson(Map<String, dynamic> j) => TopFeaturedConfig(
        enabled: _boolOr(j['enabled'], true),
        showDots: _boolOr(j['showDots'], true),
      );
  static const fallback = TopFeaturedConfig(enabled: true, showDots: true);
}

class MainMatchesConfig {
  const MainMatchesConfig({
    required this.enabled,
    required this.showStatusTabs,
    required this.defaultTab,
    required this.showCategoryFilter,
    required this.defaultCategory,
    required this.maxItems,
    required this.showWatchLive,
    required this.showViewMatch,
  });
  final bool enabled;
  final bool showStatusTabs;
  final String defaultTab; // live | upcoming | finished
  final bool showCategoryFilter;
  final String defaultCategory; // all | international | league | domestic
  final int maxItems;
  final bool showWatchLive;
  final bool showViewMatch;

  int get defaultTabIndex => switch (defaultTab) {
        'upcoming' => 1,
        'finished' => 2,
        _ => 0,
      };

  int get defaultCategoryIndex => switch (defaultCategory) {
        'international' => 1,
        'league' => 2,
        'domestic' => 3,
        _ => 0,
      };

  factory MainMatchesConfig.fromJson(Map<String, dynamic> j) => MainMatchesConfig(
        enabled: _boolOr(j['enabled'], true),
        showStatusTabs: _boolOr(j['showStatusTabs'], true),
        defaultTab: apiString(j['defaultTab'], 'live'),
        showCategoryFilter: _boolOr(j['showCategoryFilter'], true),
        defaultCategory: apiString(j['defaultCategory'], 'all'),
        maxItems: apiInt(j['maxItems']) ?? 12,
        showWatchLive: _boolOr(j['showWatchLive'], true),
        showViewMatch: _boolOr(j['showViewMatch'], true),
      );
  static const fallback = MainMatchesConfig(
    enabled: true,
    showStatusTabs: true,
    defaultTab: 'live',
    showCategoryFilter: true,
    defaultCategory: 'all',
    maxItems: 12,
    showWatchLive: true,
    showViewMatch: true,
  );
}

class FeaturedSectionConfig {
  const FeaturedSectionConfig({
    required this.enabled,
    required this.title,
    required this.maxItems,
    required this.showSeeAll,
  });
  final bool enabled;
  final String title;
  final int maxItems;
  final bool showSeeAll;

  factory FeaturedSectionConfig.fromJson(
    Map<String, dynamic> j, {
    required String defaultTitle,
    int defaultMax = 6,
  }) =>
      FeaturedSectionConfig(
        enabled: _boolOr(j['enabled'], true),
        title: apiString(j['title'], defaultTitle).isEmpty
            ? defaultTitle
            : apiString(j['title'], defaultTitle),
        maxItems: apiInt(j['maxItems']) ?? defaultMax,
        showSeeAll: _boolOr(j['showSeeAll'], true),
      );
}

class HomeLayoutConfig {
  const HomeLayoutConfig({
    required this.sectionOrder,
    required this.topFeatured,
    required this.mainMatches,
    required this.featuredMatches,
    required this.featuredSeries,
  });

  final List<String> sectionOrder;
  final TopFeaturedConfig topFeatured;
  final MainMatchesConfig mainMatches;
  final FeaturedSectionConfig featuredMatches;
  final FeaturedSectionConfig featuredSeries;

  static const fallback = HomeLayoutConfig(
    sectionOrder: ['topFeatured', 'mainMatches', 'featuredMatches', 'featuredSeries'],
    topFeatured: TopFeaturedConfig.fallback,
    mainMatches: MainMatchesConfig.fallback,
    featuredMatches: FeaturedSectionConfig(
        enabled: true, title: 'Featured Matches', maxItems: 6, showSeeAll: true),
    featuredSeries: FeaturedSectionConfig(
        enabled: true, title: 'Featured Series', maxItems: 10, showSeeAll: true),
  );

  factory HomeLayoutConfig.fromJson(dynamic value) {
    final json = apiMap(value);
    if (json.isEmpty) return fallback;
    final sections = apiMap(json['sections']);
    final order = apiList(json['sectionOrder'])
        .map((e) => e.toString())
        .where((e) => fallback.sectionOrder.contains(e))
        .toList();
    // Ensure every known section appears exactly once (append any missing),
    // mirroring the backend so sections are never silently dropped.
    for (final key in fallback.sectionOrder) {
      if (!order.contains(key)) order.add(key);
    }
    return HomeLayoutConfig(
      sectionOrder: order.isEmpty ? fallback.sectionOrder : order,
      topFeatured: TopFeaturedConfig.fromJson(apiMap(sections['topFeatured'])),
      mainMatches: MainMatchesConfig.fromJson(apiMap(sections['mainMatches'])),
      featuredMatches: FeaturedSectionConfig.fromJson(
        apiMap(sections['featuredMatches']),
        defaultTitle: 'Featured Matches',
        defaultMax: 6,
      ),
      featuredSeries: FeaturedSectionConfig.fromJson(
        apiMap(sections['featuredSeries']),
        defaultTitle: 'Featured Series',
        defaultMax: 10,
      ),
    );
  }
}

bool _boolOr(dynamic v, bool fallback) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final s = v.toLowerCase();
    if (s == 'true' || s == '1') return true;
    if (s == 'false' || s == '0') return false;
  }
  return fallback;
}

/// Parsed view of the `/app/home` payload covering the new home layout:
/// config, top-featured carousel, featured matches and admin-managed series.
class HomeFeed {
  const HomeFeed({
    required this.config,
    required this.topFeatured,
    required this.featuredMatches,
    required this.featuredSeries,
    required this.liveMatches,
    required this.upcomingMatches,
    required this.recentMatches,
  });

  final HomeLayoutConfig config;
  final List<CricketMatch> topFeatured;
  final List<CricketMatch> featuredMatches;
  final List<HomeFeaturedSeries> featuredSeries;
  final List<CricketMatch> liveMatches;
  final List<CricketMatch> upcomingMatches;
  final List<CricketMatch> recentMatches;

  static const empty = HomeFeed(
    config: HomeLayoutConfig.fallback,
    topFeatured: [],
    featuredMatches: [],
    featuredSeries: [],
    liveMatches: [],
    upcomingMatches: [],
    recentMatches: [],
  );

  factory HomeFeed.fromJson(Map<String, dynamic> json) {
    List<CricketMatch> matches(String key) => apiList(json[key])
        .map(CricketMatch.fromJson)
        .where((m) => m.id.isNotEmpty)
        .toList(growable: false);

    final series = apiList(json['featuredSeriesList'])
        .map(HomeFeaturedSeries.fromJson)
        .where((s) => s.isRenderable)
        .toList(growable: false);

    return HomeFeed(
      config: HomeLayoutConfig.fromJson(json['homeConfig']),
      topFeatured: matches('topFeaturedMatches'),
      featuredMatches: matches('featuredMatches'),
      featuredSeries: series,
      liveMatches: matches('liveMatches'),
      upcomingMatches: matches('upcomingMatches'),
      recentMatches: matches('recentMatches'),
    );
  }
}
