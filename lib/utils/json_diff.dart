/// Structural equality for decoded-JSON values (maps, lists, primitives).
///
/// PERF: this exists to replace `jsonEncode(a) != jsonEncode(b)` change-detection
/// on the live-polling path. That idiom is correct but expensive — it fully
/// serialises BOTH operands to strings on the main isolate before comparing a
/// single character, so its cost is O(total size) with large intermediate string
/// allocations, even when the very first field already differs. On the
/// match-details screen it ran 4× every 5 seconds over payloads that include the
/// whole accumulated commentary list.
///
/// [jsonDeepEquals] instead walks the two structures and returns on the FIRST
/// difference, allocating nothing. Typical live-poll case (a score changed) exits
/// almost immediately; the worst case (genuinely identical payloads) is one pass
/// with no string building.
///
/// Semantics vs the `jsonEncode` comparison it replaces:
/// - Same verdict for every JSON-shaped value, with one deliberate improvement:
///   map key ORDER is ignored. `jsonEncode` is order-sensitive, so a server that
///   reordered keys without changing data looked like a change and triggered a
///   pointless full-subtree rebuild. Ignoring order is strictly more correct for
///   "did the data change".
/// - `int` vs `double` follows Dart `==`, so `1 == 1.0` is true. `jsonEncode`
///   would render `1` vs `1.0` and report a change. Treating them as equal is
///   intended: a numeric value that did not change is not a change.
/// - Cyclic structures are not supported (decoded JSON cannot contain cycles).
bool jsonDeepEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;

  if (a is Map) {
    if (b is! Map || a.length != b.length) return false;
    for (final entry in a.entries) {
      // Distinguish "missing key" from "key present holding null": a null value
      // would otherwise compare equal to an absent key.
      if (!b.containsKey(entry.key)) return false;
      if (!jsonDeepEquals(entry.value, b[entry.key])) return false;
    }
    return true;
  }

  if (a is List) {
    if (b is! List || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!jsonDeepEquals(a[i], b[i])) return false;
    }
    return true;
  }

  // Primitives: String, num, bool, null.
  return a == b;
}
