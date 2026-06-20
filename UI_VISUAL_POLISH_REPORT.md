# CricPro UI Visual Polish Report

Play Store readiness polish pass. **Polish only** — no redesign, no brand/color change,
no new style. Existing dark premium neon identity preserved. All changes reuse existing
infrastructure (`team_format.dart`, `normalizeOversText`, `PlayerImageResolver`,
`CricColors`).

Delivered in two batches. `flutter analyze lib/` run after each: **No issues found** both
times.

---

## Files changed (this pass)

| File | Change |
|------|--------|
| `lib/utils/team_format.dart` | `shortMatchStatus()` gains `keepUnits` param (keeps "runs"/"balls"); `_kNameToCode` extended with ~70 associate/emerging nations |
| `lib/screens/home/widgets/home_featured.dart` | `homeShortStatus` now passes `keepUnits: true` |
| `lib/screens/matches/widgets/matches_cards.dart` | status note uses `keepUnits: true` |
| `lib/screens/match_details/widgets/match_details_ui.dart` | hero status uses `keepUnits: true` |
| `lib/screens/home/widgets/home_hero.dart` | "Yet to bat" only when live + innings empty; hero title 1→2 lines; venue via `shortVenue()` |
| `lib/screens/live/widgets/live_player_info.dart` | overs routed through `normalizeOversText()` (2 sites) |
| `lib/screens/live/widgets/live_player_sheets.dart` | innings overs normalized |
| `lib/screens/match_details/widgets/live_match_tab.dart` | last-wicket (fall-of-wicket) overs normalized |
| `lib/components.dart` | reduced glow (TeamLogo, fallback circle, StatusBadge); bottom nav slimmer + dimmer inactive |
| `lib/screens/matches/widgets/matches_header.dart` | glow reduced; bell button 46→44 |
| `lib/screens/schedule/widgets/schedule_header.dart` | glow reduced (glass btn, date card, chip) |
| `lib/screens/home/widgets/home_header.dart` | notif glow reduced; button 42→44 |
| `lib/screens/rankings/rankings_screen.dart` | player image now honors global image mode |
| `lib/screens/player/widgets/player_hero.dart` | profile photo now honors global image mode |

---

## Visual issues fixed

- **Cricket score wording (#5):** card/hero status notes now read naturally
  "AFG need 178 runs in 50 balls" instead of "AFG need 178 in 50". Backend already sends
  correct units; the app was stripping them. Tight contexts (minimized score bar) still
  shortened.
- **Over formatting (#5):** invalid overs (e.g. `42.6`) roll to `43.0` everywhere via the
  existing `normalizeOversText()`. The model score-text builder was already normalized;
  added the missing live-stream score panel, innings sheets, and fall-of-wicket lines.
  Bowler figures (e.g. `6.2`) left as-is — valid partial overs.
- **"Yet to bat" on upcoming (#4):** removed from the Home hero for upcoming matches. Now
  appears only while a match is live and that team's innings hasn't started.
- **Truncation (#3):** associate-nation team codes now resolve (`Rwanda W → RWA W`,
  `Brazil W → BRA W`, `Cyprus W → CYP W`, `Malta W → MAL W`, +many) instead of ugly
  `RW… / BRA… / CYP… / MA…`. Home hero series title allowed 2 lines. Venue routed through
  `shortVenue()` (drops junk placeholders, clean 1-line ellipsis).
- **Glow reduction ~20–30% (#1):** secondary surfaces dimmed — team logos, fallback
  circles, status badges, header icon buttons, filter chips/date cards. Strong glow kept
  on active bottom-nav underline, CTA buttons, live badges, and selected states.
- **Bottom nav (#6):** slightly slimmer (less vertical padding, icon 23→22), inactive
  icons/labels dimmed (~18%), active glow kept strong. `SafeArea(top:false)` already
  correct; content bottom padding already clears the bar (`mainBottomPadding`).
- **Header consistency (#2):** circular glass icon buttons aligned to 44px across Home /
  Matches / Schedule.

## Layout / responsive issues

- `flutter analyze lib/` clean — no widget/type errors.
- Existing responsive helpers (`context.bp`, `context.sp()`, `computeGridChildWidth`)
  retained; no fixed widths introduced.
- Title 2-line change uses `Expanded` in a center-aligned Row (no overflow).
- Bottom nav reductions reduce, not increase, height — safe on short screens.

## Player image / admin-setting issues (#8)

Audited every avatar site against `PlayerImageResolver` (modes: adminFirst, cricbuzzFirst,
adminOnly, cricbuzzOnly, initialsOnly):

- Already correct: Squad (`squad.dart`), live batter/bowler cards (`live_match_tab.dart`),
  series stats, and `PlayerAvatar` (resolves at model parse).
- **Fixed:** Rankings screen and Player profile hero bypassed the resolver and showed raw
  API images — now routed through `resolvePlayerImageUrl()`, so `admin_only` /
  `initials_only` modes are respected (this was the documented "Rankings leak").
- No default mode changed. Initials shown only when the mode requires it or no valid image
  exists.

## Cricket wording / over formatting

- Units preserved in full-width notes (see above).
- All score-derived over displays normalized to valid 6-ball overs with consistent ` ov`.

## Watch Live gating (#16)

Untouched — `match.hasStreamInfo` / `showWatchLive` gate intact. Button still hidden when
no stream exists.

---

## Remaining known issues / not changed

- **Match Details "Pull to refresh":** the clean "Updated just now / Updated Xs ago" row
  (`MDUpdatedRow`) was already implemented; "Pull to refresh" shows only in the initial
  pre-load state. Left as-is.
- **Live Stream quality cards (#10):** already filter unavailable HLS qualities (FHD shown
  subtly disabled at .55 opacity, selected card distinct). Verified against screenshots —
  no change needed.
- **Commentary / Match Details top (#9):** screen already wraps content in `SafeArea` with
  top padding; the screenshot clip was a mid-pull/scroll artifact, not a layout bug.
- **Matches list-card series title:** kept 1 line — constrained by the inline date on the
  same row; widening would require restructuring (out of polish scope).
- Light mode: changes are theme-aware (`c.isDark` branches preserved); not exhaustively
  re-shot.

## Testing performed

- `flutter analyze lib/` after Batch 1: **No issues found**.
- `flutter analyze lib/` after Batch 2: **No issues found**.
- Static verification against the 10 provided screenshots for wording, overs, yet-to-bat,
  team codes, glow.
- No release build run (per safety rules).

## Build / analyze result

`flutter analyze lib/` → **No issues found.**
