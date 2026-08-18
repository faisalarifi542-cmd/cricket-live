part of 'home_screen.dart';

// ---------------------------------------------------------------------------
// Shared, authoritative geometry for Home LIVE cards.
//
// Both the live match-card skeleton (`_CardSkeleton`) and the loaded live match
// card (`_HomeLiveMatchCard`) MUST route through these helpers so the two
// widgets keep identical outer height / emblem / VS metrics — otherwise the
// skeleton and the first real card have different geometry and the list jumps
// when data arrives.
//
// Scope of this PR: LIVE variant only. Upcoming and Finished remain on their
// existing sizing until measured separately. A later change may add
// `homeUpcomingCardResolvedHeight` / `homeFinishedCardResolvedHeight` behind
// the same contract.
//
// Width vocabulary used throughout Home:
//   outerCardWidth  = actual rendered OUTER card width (from the parent's
//                     LayoutBuilder, computed ONCE and passed down explicitly).
//   contentWidth    = outerCardWidth - kHomeCardPadding.horizontal — the inner
//                     content region width after horizontal padding.
// Nested widgets never reinterpret their own inner LayoutBuilder.maxWidth as
// outerCardWidth; the parent supplies it explicitly.
// ---------------------------------------------------------------------------

/// Compact (narrow) card threshold. Below or equal → 264 px base; above → 270.
const double kHomeCompactCardWidth = 430.0;

/// Authoritative outer height for a LIVE Home card row.
///
/// - `outerCardWidth`: actual rendered OUTER card width.
/// - Progressive accessibility allowance, bounded to 22 px max so text scale
///   1.01 doesn't get the same headroom as 1.20. The scale is derived from the
///   score font (21 px) rather than 1 px so nonlinear text scalers land
///   correctly.
double homeLiveCardResolvedHeight({
  required double outerCardWidth,
  required TextScaler textScaler,
}) {
  final base = outerCardWidth <= kHomeCompactCardWidth ? 264.0 : 270.0;
  const baseScoreSize = 21.0;
  final scaledScoreSize = textScaler.scale(baseScoreSize);
  final effectiveScale = scaledScoreSize / baseScoreSize;
  final extra = ((effectiveScale - 1.0) * 110.0).clamp(0.0, 22.0);
  return base + extra;
}

/// Authoritative outer height for an UPCOMING Home card row.
///
/// Upcoming cards carry no score column, so the live card's 264/270 reserve
/// left ~35px of dead space pooling under the footer (the "floating button in
/// empty space" defect). The upcoming reserve is tighter — sized for header +
/// emblem/VS body + footer — while every upcoming card still shares ONE stable
/// equal height. Same bounded accessibility allowance as the live card.
double homeUpcomingCardResolvedHeight({
  required double outerCardWidth,
  required TextScaler textScaler,
}) {
  final base = outerCardWidth <= kHomeCompactCardWidth ? 236.0 : 242.0;
  const baseScoreSize = 21.0;
  final scaledScoreSize = textScaler.scale(baseScoreSize);
  final effectiveScale = scaledScoreSize / baseScoreSize;
  final extra = ((effectiveScale - 1.0) * 110.0).clamp(0.0, 22.0);
  return base + extra;
}

/// Inner padding shared by every Home card variant.
const EdgeInsets kHomeCardPadding = EdgeInsets.fromLTRB(15, 12, 15, 12);

/// Border radius shared by every Home card variant (loaded + skeleton).
const double kHomeCardRadius = 22;

/// Vertical gap constants — the shared card timeline. Skeleton and loaded card
/// must use these same gaps so their inner regions align.
const double kHomeCardHeaderToBody = 6;
const double kHomeCardBodyToDivider = 8;
const double kHomeCardDividerToFooter = 8;

/// Emblem circle diameter, clamped so it stays legible on very narrow phones
/// and doesn't dominate wider layouts.
double homeCardEmblemSize({required double contentWidth}) =>
    (contentWidth * .145).clamp(48.0, 64.0);

/// VS pill width. Height is derived by callers as `vsWidth * .69`.
double homeCardVsWidth({required double contentWidth}) =>
    (contentWidth * .16).clamp(54.0, 68.0);

// ---------------------------------------------------------------------------
// Key factories — every card in the tree gets a unique key so element
// reconciliation and test finders stay unambiguous when multiple cards are
// rendered side-by-side.
// ---------------------------------------------------------------------------

Key homeSkeletonCardKey(int index) => ValueKey('home-skeleton-card:$index');

Key homeLoadedLiveCardKey(String matchId) =>
    ValueKey('home-loaded-live-card:$matchId');

Key homeCardFooterKey(String matchId) => ValueKey('home-card-footer:$matchId');

// ---------------------------------------------------------------------------
// HomePresentation — value-based snapshot of the Home screen's current visible
// identity/order/content. `_silentPoll` compares the freshly computed
// presentation against `_lastPresentation` before firing a rebuild; if they
// compare equal the setState is skipped entirely. Value equality prevents
// two newly constructed lists (identical content) from being treated as
// different, which naive `List.==` would do.
// ---------------------------------------------------------------------------

@immutable
class HomePresentation {
  const HomePresentation({
    required this.heroPrimaryId,
    required this.heroIdsOrder,
    required this.listIdsOrder,
    required this.heroContentKey,
    required this.listContentKey,
  });

  final String heroPrimaryId;
  final List<String> heroIdsOrder;
  final List<String> listIdsOrder;
  final String heroContentKey;
  final String listContentKey;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HomePresentation &&
          heroPrimaryId == other.heroPrimaryId &&
          listEquals(heroIdsOrder, other.heroIdsOrder) &&
          listEquals(listIdsOrder, other.listIdsOrder) &&
          heroContentKey == other.heroContentKey &&
          listContentKey == other.listContentKey;

  @override
  int get hashCode => Object.hash(
        heroPrimaryId,
        Object.hashAll(heroIdsOrder),
        Object.hashAll(listIdsOrder),
        heroContentKey,
        listContentKey,
      );
}
