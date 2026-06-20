import 'models/cricket_match.dart';
import 'services/favorite_countries_service.dart';

/// Shared upcoming-match ordering used by both Home and the Matches screen so
/// fixtures appear in the same, sensible order everywhere.
///
/// Order of intent:
///   1. Soonest matches first (by start time) — never bury a match starting
///      today under a favourite-country match days away.
///   2. Within the same time bucket (same calendar day), prefer favourite
///      countries, then international, then major leagues, then domestic/other.
///
/// The time bucket keeps favourites from breaking chronological order too much:
/// a favourite match tomorrow still sits below any match today.
class UpcomingSort {
  const UpcomingSort._();

  /// Far-future sentinel for matches with no parseable start time so they sort
  /// last instead of jumping to the front.
  static final DateTime _noTime =
      DateTime.fromMillisecondsSinceEpoch(8640000000000000, isUtc: true);

  static DateTime matchStartTime(CricketMatch m) =>
      m.startDateTime?.toUtc() ?? _noTime;

  static bool isFavoriteCountryMatch(CricketMatch m) =>
      FavoriteCountriesService.instance.isFavoriteMatch(m);

  static final RegExp _intlRe = RegExp(
      r'(international|tour|world cup|champions trophy|t20i|odi|test|asia cup|bilateral|tri-?nation|tri series|vs)',
      caseSensitive: false);
  static final RegExp _leagueRe = RegExp(
      r'(league|premier|\bipl\b|\bbbl\b|\bpsl\b|\bcpl\b|the hundred|blast|super smash|mumbai|\bilt20\b|\bsa20\b|\blpl\b|\bbpl\b)',
      caseSensitive: false);
  static final RegExp _domesticRe = RegExp(
      r'(county|domestic|ranji|shield|division|first[- ]class|state|club)',
      caseSensitive: false);

  static String _haystack(CricketMatch m) =>
      '${m.series} ${m.matchDesc} ${m.title}';

  static bool isMajorLeague(CricketMatch m) =>
      _leagueRe.hasMatch(_haystack(m));

  static bool isDomesticOrOther(CricketMatch m) =>
      _domesticRe.hasMatch(_haystack(m));

  /// International if it reads international and is not a league/domestic comp.
  static bool isInternationalMatch(CricketMatch m) {
    final s = _haystack(m);
    if (_leagueRe.hasMatch(s) || _domesticRe.hasMatch(s)) return false;
    return _intlRe.hasMatch(s) || FavoriteCountriesService.instance
            .isFavoriteMatch(m); // favourite nations are international sides
  }

  /// Lower = higher priority within the same time bucket.
  static int _categoryRank(CricketMatch m) {
    if (isInternationalMatch(m)) return 1;
    if (isMajorLeague(m)) return 2;
    if (isDomesticOrOther(m)) return 3;
    return 2; // unknown → treat like a league so it sits mid-pack
  }

  /// Comparator implementing the documented order. Buckets by calendar day
  /// (UTC) so "same day or similar time" favourites float up without
  /// overtaking earlier days.
  static int compare(CricketMatch a, CricketMatch b) {
    final ta = matchStartTime(a);
    final tb = matchStartTime(b);
    final dayA = DateTime.utc(ta.year, ta.month, ta.day);
    final dayB = DateTime.utc(tb.year, tb.month, tb.day);
    final dayCmp = dayA.compareTo(dayB);
    if (dayCmp != 0) return dayCmp;

    // Same day: favourites first.
    final favA = isFavoriteCountryMatch(a);
    final favB = isFavoriteCountryMatch(b);
    if (favA != favB) return favA ? -1 : 1;

    // Then by category (international → league → domestic).
    final catCmp = _categoryRank(a).compareTo(_categoryRank(b));
    if (catCmp != 0) return catCmp;

    // Finally exact start time so the earliest of the day leads.
    return ta.compareTo(tb);
  }

  /// Returns a new list sorted for display. Does not mutate [matches].
  static List<CricketMatch> sortUpcoming(List<CricketMatch> matches) {
    final out = List<CricketMatch>.from(matches);
    out.sort(compare);
    return out;
  }
}
