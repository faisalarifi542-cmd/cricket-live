import 'package:flutter/foundation.dart' show listEquals;

import '../../models/cricket_match.dart';

/// Carousel stability core (pure + testable).
///
/// A silent score poll must NEVER reorder the hero carousel — reordering makes
/// the position-based `PageView` show a different match under the same page
/// (the "hero slides/jumps on score update" bug). So when the membership (the
/// SET of match ids) is unchanged, keep the EXISTING visible order and overlay
/// each card by id; only when matches actually start/finish (membership
/// changes) is the freshly-prioritised order adopted.
///
/// Returns the list to render: same length/ids as [resolved], but ordered like
/// [prev] when the id sets match.
List<CricketMatch> preserveHeroOrder(
  List<CricketMatch>? prev,
  List<CricketMatch> resolved,
) {
  if (prev == null || prev.isEmpty) return resolved;
  final prevIds = prev.map((m) => m.id).toSet();
  final freshIds = resolved.map((m) => m.id).toSet();
  if (prevIds.length != freshIds.length || !prevIds.containsAll(freshIds)) {
    return resolved; // membership changed → adopt the new (prioritised) order.
  }
  final byId = {for (final m in resolved) m.id: m};
  return [
    for (final m in prev) byId[m.id] ?? m,
  ];
}

/// True when two hero/match-id lists are identical in order — used to decide
/// whether the `PageController` needs re-seating at all.
bool sameOrder(List<String> a, List<String> b) => listEquals(a, b);
