// A11Y-1 guards: every image in the app must either carry a MEANINGFUL
// accessible name or be explicitly silent — never an anonymous "image" node and
// never a duplicate of adjacent text.
//
// Flutter's `Image` emits `Semantics(image: true, label: '')` by DEFAULT, so an
// unlabelled decorative image is real screen-reader noise ("image, image,
// image…"). These tests assert the USER-FACING outcome (what a screen reader
// would announce), not the widget-tree shape, so they keep holding if the
// internals are refactored.
//
// Contract under test:
//   * informative artwork  → announced exactly once, with a human label
//   * redundant artwork    → silent (the adjacent Text already says it)
//   * decorative artwork   → silent
//   * interactive artwork  → the CONTROL is named + has a role; art is silent

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cricpro_flutter/components.dart';
import 'package:cricpro_flutter/models.dart';
import 'package:cricpro_flutter/screens/series/series_components.dart';
import 'package:cricpro_flutter/screens/series/widgets/series_poster_cards.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: ThemeData(brightness: Brightness.dark),
      home: Scaffold(body: Center(child: child)),
    );

/// Every non-empty semantics label currently exposed to assistive tech.
///
/// Uses the public semantics finder rather than walking the node tree, so the
/// assertions describe what a screen reader would announce.
List<String> _labels(WidgetTester tester) {
  return find.semantics
      .byPredicate((SemanticsNode node) => node.label.trim().isNotEmpty)
      .evaluate()
      .map((SemanticsNode node) => node.label.trim())
      .toList();
}

/// [testWidgets] with semantics switched on for the whole body.
///
/// Semantics are OFF by default in tests, so without this the tree carries no
/// labels at all and every assertion below would vacuously pass. The handle is
/// disposed inside the body because Flutter verifies handle disposal *before*
/// `addTearDown` callbacks run.
void testSemantics(
  String description,
  Future<void> Function(WidgetTester tester) body,
) {
  testWidgets(description, (WidgetTester tester) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    try {
      await body(tester);
    } finally {
      handle.dispose();
    }
  });
}

void main() {
  // -------------------------------------------------------------------------
  // Informative: a badge that is the sole carrier of team identity
  // -------------------------------------------------------------------------

  testSemantics('TeamLogoWidget announces "<team> logo" exactly once',
      (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(const TeamLogoWidget(
      logoUrl: null,
      teamName: 'India',
      abbreviation: 'IND',
      color: Color(0xff22d3ee),
      size: 56,
    )));

    final logoLabels =
        _labels(tester).where((l) => l.contains('India')).toList();
    expect(logoLabels, ['India logo'],
        reason: 'The badge must be announced once, as a named logo.');
  });

  testSemantics('TeamLogoWidget never leaks the raw initials glyphs',
      (WidgetTester tester) async {
    // An unknown team has no flag asset, so this renders the INITIALS circle —
    // the branch most likely to read out "IND" as if it were prose.
    await tester.pumpWidget(_wrap(const TeamLogoWidget(
      logoUrl: null,
      teamName: 'Nowhere Cricket Club',
      abbreviation: 'NWC',
      color: Color(0xff22d3ee),
      size: 56,
    )));

    // The glyphs are painted (visible design is unchanged) …
    expect(find.text('NWC'), findsOneWidget);
    // … but never announced on their own.
    expect(_labels(tester), ['Nowhere Cricket Club logo']);
  });

  testSemantics('TeamLogoWidget falls back to the abbreviation when unnamed',
      (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(const TeamLogoWidget(
      logoUrl: null,
      teamName: '',
      abbreviation: 'NWC',
      color: Color(0xff22d3ee),
      size: 56,
    )));

    expect(_labels(tester), ['NWC logo'],
        reason: 'An empty team name must degrade to the code, not to "".');
  });

  testSemantics('TeamLogoWidget with no name and no code stays silent',
      (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(const TeamLogoWidget(
      logoUrl: null,
      teamName: '',
      abbreviation: '',
      color: Color(0xff22d3ee),
      size: 56,
    )));

    expect(_labels(tester), isEmpty,
        reason: 'Never announce a bare "logo" or an empty image node.');
  });

  // -------------------------------------------------------------------------
  // Redundant: the same badge where adjacent text already names the team
  // -------------------------------------------------------------------------

  testSemantics('TeamLogoWidget(excludeSemantics: true) contributes no label',
      (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(const TeamLogoWidget(
      logoUrl: null,
      teamName: 'India',
      abbreviation: 'IND',
      color: Color(0xff22d3ee),
      size: 56,
      excludeSemantics: true,
    )));

    expect(_labels(tester), isEmpty,
        reason: 'Where a sibling Text names the team, the badge must be silent.');
  });

  testSemantics('a score row announces the team name once, not twice',
      (WidgetTester tester) async {
    // This is the real-world shape the exclusion exists for.
    await tester.pumpWidget(_wrap(const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TeamLogoWidget(
          logoUrl: null,
          teamName: 'India',
          abbreviation: 'IND',
          color: Color(0xff22d3ee),
          size: 22,
          excludeSemantics: true,
        ),
        SizedBox(width: 8),
        Text('India'),
        Text('250/4'),
      ],
    )));

    expect(_labels(tester).where((l) => l.contains('India')).length, 1,
        reason: 'The badge must not double-announce the adjacent team name.');
  });

  // -------------------------------------------------------------------------
  // TeamBadge forwards the same contract
  // -------------------------------------------------------------------------

  testSemantics('TeamBadge forwards excludeSemantics to the shared badge',
      (WidgetTester tester) async {
    const team = TeamInfo(
      code: 'IND',
      name: 'India',
      shortName: 'IND',
      color: Color(0xff22d3ee),
    );

    await tester.pumpWidget(_wrap(const TeamBadge(team, size: 46)));
    expect(_labels(tester), ['India logo']);

    await tester.pumpWidget(
      _wrap(const TeamBadge(team, size: 46, excludeSemantics: true)),
    );
    expect(_labels(tester), isEmpty);
  });

  // -------------------------------------------------------------------------
  // Player avatars
  // -------------------------------------------------------------------------

  testSemantics('PlayerAvatarWidget announces the plain player name',
      (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(const PlayerAvatarWidget(
      name: 'Virat Kohli',
      size: 56,
    )));

    // The name, NOT "Virat Kohli photo"/"image of…" — screen readers already
    // announce the image role, so restating it is noise.
    expect(_labels(tester), ['Virat Kohli']);
    // The initials fallback is decorative shorthand, never read as prose.
    expect(find.text('VK'), findsOneWidget);
  });

  testSemantics('PlayerAvatarWidget(excludeSemantics: true) is silent',
      (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(const PlayerAvatarWidget(
      name: 'Virat Kohli',
      size: 56,
      excludeSemantics: true,
    )));

    expect(_labels(tester), isEmpty,
        reason: 'Squad/scorecard rows already show the player name as text.');
  });

  testSemantics('PlayerAvatar honours the same contract on the local-asset path',
      (WidgetTester tester) async {
    const player = PlayerInfo(
      name: 'Virat Kohli',
      role: 'Batter',
      team: TeamInfo(
        code: 'IND',
        name: 'India',
        shortName: 'IND',
        color: Color(0xff22d3ee),
      ),
      // A local asset path (not http) exercises the bespoke asset branch.
      asset: 'assets/images/players/virat.webp',
    );

    await tester.pumpWidget(_wrap(const PlayerAvatar(player: player, size: 62)));
    expect(_labels(tester), ['Virat Kohli']);

    await tester.pumpWidget(_wrap(
      const PlayerAvatar(player: player, size: 62, excludeSemantics: true),
    ));
    expect(_labels(tester), isEmpty);
  });

  // -------------------------------------------------------------------------
  // Interactive: icon-only controls need a name AND a role
  // -------------------------------------------------------------------------

  testSemantics('GlowIconButton exposes an accessible name and button role',
      (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(GlowIconButton(
      icon: Icons.notifications_rounded,
      tooltip: 'Notifications',
      onTap: () {},
    )));

    expect(
      tester.getSemantics(find.bySemanticsLabel('Notifications')),
      isSemantics(label: 'Notifications', isButton: true),
      reason: 'An icon glyph carries no text; without a label this is a '
          'nameless "button" to a screen reader.',
    );
  });

  testSemantics('GlowIconButton keeps its badge count readable',
      (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(GlowIconButton(
      icon: Icons.notifications_rounded,
      tooltip: 'Notifications',
      badge: '3',
      onTap: () {},
    )));

    // The unread count is genuine information, so it must NOT be excluded.
    expect(find.text('3'), findsOneWidget);
    expect(_labels(tester).any((l) => l.contains('Notifications')), isTrue);
  });

  testSemantics('GlowIconButton renders unchanged when no tooltip is given',
      (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(GlowIconButton(
      icon: Icons.notifications_rounded,
      onTap: () {},
    )));

    // Backwards compatible: the new param is additive, so legacy call sites
    // keep working (they simply stay unnamed until a tooltip is supplied) and
    // no Tooltip/Semantics wrapper is introduced around them.
    expect(find.byIcon(Icons.notifications_rounded), findsOneWidget);
    expect(find.byType(Tooltip), findsNothing);
    expect(_labels(tester), isEmpty);
  });

  testSemantics('the favourite star is a named, toggleable button',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // A tournament (no opposing sides) avoids any network team logo.
    final series = SeriesView(
      id: 'mlc',
      name: 'Major League Cricket 2026',
      status: SeriesStatus.ongoing,
      category: SeriesCategory.league,
      startDate: DateTime(2026, 6, 18),
      endDate: DateTime(2026, 7, 18),
      formatLabel: '19 T20s',
      teams: const [],
    );

    await tester.pumpWidget(
      _wrap(TournamentSeriesCard(series: series, onTap: () {})),
    );

    // The star bitmap IS the control, and there is no adjacent text — so the
    // semantics live on the tappable ancestor, with STATE, and the artwork
    // underneath stays silent (no "button, image" echo).
    expect(
      tester.getSemantics(find.bySemanticsLabel('Favorite series')),
      isSemantics(
        label: 'Favorite series',
        isButton: true,
        hasToggledState: true,
        isToggled: false,
      ),
    );
    expect(_labels(tester).where((l) => l == 'Favorite series').length, 1);
  });

  // -------------------------------------------------------------------------
  // Decorative: backdrops must be completely silent
  // -------------------------------------------------------------------------

  testSemantics('StadiumImage backdrops emit no image label',
      (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(const SizedBox(
      width: 300,
      height: 160,
      child: StadiumImage('assets/images/hero_stadium_bg.webp'),
    )));

    expect(_labels(tester), isEmpty,
        reason: 'Pure background texture must never be announced.');
    // And the bitmap is genuinely excluded, not merely unlabelled.
    for (final image in tester.widgetList<Image>(find.byType(Image))) {
      expect(image.excludeFromSemantics, isTrue);
    }
  });
}
