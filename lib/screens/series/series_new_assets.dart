/// Asset paths for the redesigned CricPro Series screen.
///
/// These point at the "new" clean reusable asset kit
/// (`assets/images/series/new/`) which ships:
///  • `core_clean_assets/`  — reusable backgrounds, border glows, rings,
///    status pills, buttons, chips and icons (NO baked text / NO team logos)
///  • `auto_extracted/sheet{1..4}_*` — per-type card art (tournament purple
///    panel + trophy, bilateral castle panel + connector, league cyber stadium
///    + neon batsman, misc).
///
/// Dynamic team logos/flags are NEVER baked into these images — the rings here
/// are decorative frames that clip a real [TeamLogoWidget] inside them.
class SeriesNewAssets {
  SeriesNewAssets._();

  static const base = 'assets/images/series/new';
  static const core = '$base/core_clean_assets';
  static const tournament = '$base/auto_extracted/sheet1_tournament';
  static const bilateral = '$base/auto_extracted/sheet2_bilateral';
  static const league = '$base/auto_extracted/sheet3_league';
  static const misc = '$base/auto_extracted/sheet4_misc';

  // --- Screen ---------------------------------------------------------------
  static const screenBg = '$core/series_screen_dark_gradient_bg.png';

  // --- Hero -----------------------------------------------------------------
  static const heroBorder = '$core/series_hero_card_border_glow.png';
  static const trophyGold = '$core/trophy_gold_laurel_icon.png';
  static const carouselDots = '$core/carousel_dots_4_active_first.png';
  static const carouselDotActive = '$core/carousel_dot_active.png';
  static const carouselDotInactive = '$core/carousel_dot_inactive.png';

  // --- Card border glows ----------------------------------------------------
  static const listCardLarge = '$core/series_list_card_large_border_glow.png';
  static const listCardCompact =
      '$core/series_list_card_compact_border_glow.png';
  static const cardCompleted = '$core/series_card_completed_border_glow.png';

  // --- Filter chips ---------------------------------------------------------
  static const filterActive = '$core/filter_chip_active_base.png';
  static const filterInactive = '$core/filter_chip_inactive_base.png';
  static const filterInactiveWide = '$core/filter_chip_inactive_wide_base.png';

  // --- Status pills ---------------------------------------------------------
  static const statusOngoing = '$core/status_pill_ongoing_base.png';
  static const statusUpcoming = '$core/status_pill_upcoming_base.png';
  static const statusCompleted = '$core/status_pill_completed_base.png';

  // --- Buttons --------------------------------------------------------------
  static const buttonPrimary = '$core/series_button_primary_base.png';
  static const buttonSecondary = '$core/series_button_secondary_base.png';
  static const buttonDisabled = '$core/series_button_disabled_base.png';

  // --- Rings ----------------------------------------------------------------
  static const ringSmall = '$core/team_logo_ring_small.png';
  static const ringBlueGlow = '$core/team_logo_ring_blue_glow.png';
  static const ringOrangeGreenGlow = '$core/team_logo_ring_orange_green_glow.png';

  // --- Misc decoration ------------------------------------------------------
  static const favoriteStar = '$core/favorite_star_outline.png';
  static const notificationCircle = '$core/notification_circle_base.png';
  static const chevronRight = '$core/chevron_right_cyan.png';
  static const cardLightOverlay = '$core/cyan_green_card_light_overlay.png';
  static const bottomNavActive = '$core/bottom_nav_active_tab_base.png';

  // --- Tournament sheet (purple cup card) -----------------------------------
  // NOTE: earlier comments here claimed a baked-in "VERIFIED BY N PIXELS"
  // watermark. That was a MISDIAGNOSIS — no such text is in these assets. The
  // text seen on cards was Flutter's DEBUG RenderFlex "OVERFLOWED BY N PIXELS"
  // stripe (fixed in series_poster_cards.dart CTA rows). The `_clean.png` files
  // are kept (harmless, already bundled); the trophy is overlaid by Flutter.
  static const tournamentBg = '$tournament/sheet1_tournament_asset_01_clean.png';
  static const tournamentTrophy = '$tournament/sheet1_tournament_asset_06.png';
  static const tournamentBurst = '$tournament/sheet1_tournament_asset_04.png';

  // --- Bilateral sheet (castle / landscape card) ----------------------------
  static const bilateralBg = '$bilateral/sheet2_bilateral_asset_01.png';
  static const bilateralRingLeft = '$bilateral/sheet2_bilateral_asset_07.png';
  static const bilateralRingRight = '$bilateral/sheet2_bilateral_asset_08.png';
  static const bilateralConnector = '$bilateral/sheet2_bilateral_asset_11.png';
  static const bilateralShield = '$bilateral/sheet2_bilateral_asset_10.png';

  // --- League sheet (cyber stadium + neon batsman) --------------------------
  // See the tournament note above re: the "watermark" (a debug overflow stripe,
  // not a baked-in asset). Clean bg kept as-is.
  static const leagueBg = '$league/sheet3_league_asset_01_clean.png';
  static const leagueBgAlt = '$league/sheet3_league_asset_02.png';
  static const leagueBatsman = '$league/sheet3_league_asset_05.png';

  // Aspect ratios of the border-glow frames (width:height) — used to size the
  // cards responsively so the cyan frame never stretches. Source PNG sizes:
  //   hero 790x369, list-large 790x327, list-compact 790x232, completed 790x201
  static const double heroAspect = 790 / 369; // ≈ 2.14
  static const double largeAspect = 790 / 327; // ≈ 2.42
  static const double compactAspect = 790 / 232; // ≈ 3.40
  static const double completedAspect = 790 / 201; // ≈ 3.93
}
