class ApiEndpoints {
  static const String baseUrl = 'https://api.webcrichd.co';

  // System
  static const String health = '/health';
  static const String providers = '/providers';

  // Matches
  static const String matchesLive = '/matches/live';
  static const String matchesUpcoming = '/matches/upcoming';
  static const String matchesRecent = '/matches/recent';
  static String matchDetail(String id) => '/match/$id';
  static String matchScorecard(String id) => '/match/$id/scorecard';
  static String matchCommentary(String id) => '/match/$id/commentary';
  static String matchInnings(String id) => '/match/$id/innings';
  static String matchOvers(String id) => '/match/$id/overs';
  static String matchStats(String id) => '/match/$id/stats';
  static String matchNews(String id) => '/match/$id/news';
  static String fullCommentary(String id, int inningsId) => '/match/$id/full-commentary/$inningsId';
  static String matchHighlights(String id, int inningsId) => '/match/$id/highlights/$inningsId';
  static String matchHighlightsAll(String id) => '/match/$id/highlights';
  static String ballsMap(String id, int inningsId) => '/match/$id/balls-map/$inningsId';
  static String overByOver(String id, int inningsId) => '/match/$id/over-by-over/$inningsId';

  // Series
  static const String series = '/series';
  static String seriesDetail(String id) => '/series/$id';
  static String seriesMatches(String id) => '/series/$id/matches';
  static String pointsTable(String seriesId) => '/points-table/$seriesId';

  static String seriesStatsTypes(String id) => '/series/$id/stats';
  static String seriesStatsTable(String id, String type) => '/series/$id/stats/$type';
  static String seriesNews(String id) => '/series/$id/news';

  // News
  static const String news = '/news';
  static String newsDetail(String id) => '/news/$id';

  // Schedule
  static const String scheduleUpcoming = '/schedule/upcoming';
  static String scheduleByType(String type) => '/schedule/upcoming/$type';

  // Players & Teams
  static String player(String id) => '/player/$id';
  static String team(String id) => '/team/$id';
}
