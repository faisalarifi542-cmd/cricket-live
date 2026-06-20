import 'package:flutter/material.dart';
import '../../app_theme.dart';
import '../../components.dart';
import '../../models/ad_config.dart';
import '../../services/favorite_countries_service.dart';
import '../../widgets/ads/banner_ad_widget.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({
    super.key,
    required this.isDark,
    required this.onThemeChanged,
    required this.onOpenRanking,
    required this.onOpenWomenRanking,
    required this.onOpenTeams,
    required this.onOpenFavorites,
    required this.onOpenContact,
    required this.onOpenPolicy,
    required this.onOpenTerms,
    required this.onOpenHighlights,
    required this.onOpenNotificationSettings,
    required this.showPrivacyOptions,
    required this.onOpenPrivacyOptions,
    this.onOpenFloatingScore,
  });

  final bool isDark;
  final ValueChanged<bool> onThemeChanged;
  final VoidCallback onOpenRanking;
  final VoidCallback onOpenWomenRanking;
  final VoidCallback onOpenTeams;
  final VoidCallback onOpenFavorites;
  final VoidCallback onOpenContact;
  final VoidCallback onOpenPolicy;
  final VoidCallback onOpenTerms;
  final VoidCallback onOpenHighlights;
  final VoidCallback onOpenNotificationSettings;
  final bool showPrivacyOptions;
  final VoidCallback onOpenPrivacyOptions;

  /// Opens the "Floating Score over other apps" settings (Android only). When
  /// null (e.g. iOS), the tile is hidden.
  final VoidCallback? onOpenFloatingScore;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      decoration: BoxDecoration(gradient: c.bgGradient),
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(context.horizontalPadding, 18,
              context.horizontalPadding, context.mainBottomPadding),
          children: [
            const AppHeader(
              showLogo: true,
              trailing: [
                GlowIconButton(icon: Icons.notifications_none_rounded),
              ],
            ),
            const SizedBox(height: 22),
            ValueListenableBuilder<Set<String>>(
              valueListenable: FavoriteCountriesService.instance.selected,
              builder: (context, favorites, _) => _MenuGroup(
                title: 'EXPLORE',
                items: [
                  (
                    'Favorite Countries',
                    Icons.public_rounded,
                    const Color(0xff22d3ee),
                    onOpenFavorites,
                    favorites.isEmpty ? null : '${favorites.length} SELECTED'
                  ),
                  (
                    'ICC Men Ranking',
                    Icons.bar_chart_rounded,
                    const Color(0xff22d3ee),
                    onOpenRanking,
                    null
                  ),
                  (
                    'ICC Women Ranking',
                    Icons.show_chart_rounded,
                    const Color(0xff8b5cf6),
                    onOpenWomenRanking,
                    null
                  ),
                  (
                    'Teams',
                    Icons.groups_rounded,
                    const Color(0xff36d399),
                    onOpenTeams,
                    null
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _MenuGroup(
              title: 'SUPPORT & MORE',
              items: [
                (
                  'Notification Settings',
                  Icons.notifications_active_rounded,
                  const Color(0xff22d3ee),
                  onOpenNotificationSettings,
                  null
                ),
                (
                  'Invite Friends',
                  Icons.share_rounded,
                  const Color(0xff22d3ee),
                  () {},
                  null
                ),
                if (onOpenFloatingScore != null)
                  (
                    'Floating Score over other apps',
                    Icons.picture_in_picture_alt_rounded,
                    const Color(0xff22d3ee),
                    onOpenFloatingScore!,
                    null
                  ),
                (
                  'Contact Us',
                  Icons.email_outlined,
                  const Color(0xffffc83d),
                  onOpenContact,
                  null
                ),
                (
                  'Terms & Conditions',
                  Icons.description_outlined,
                  const Color(0xff8b5cff),
                  onOpenTerms,
                  null
                ),
                (
                  'Privacy Policy',
                  Icons.shield_outlined,
                  const Color(0xff38f28b),
                  onOpenPolicy,
                  null
                ),
                if (showPrivacyOptions)
                  (
                    'Privacy Choices',
                    Icons.privacy_tip_outlined,
                    const Color(0xff22d3ee),
                    onOpenPrivacyOptions,
                    null
                  ),
              ],
              footer: _AppearanceRow(isDark: isDark, onChanged: onThemeChanged),
            ),
            const SizedBox(height: 16),
            const BannerAdWidget(placement: AdPlacement.more),
          ],
        ),
      ),
    );
  }
}

class _MenuGroup extends StatelessWidget {
  const _MenuGroup({required this.title, required this.items, this.footer});

  final String title;
  final List<(String, IconData, Color, VoidCallback, String?)> items;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: c.muted,
            letterSpacing: 2.2,
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 12),
        PremiumCard(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            children: [
              for (final item in items)
                InkWell(
                  onTap: item.$4,
                  child: SizedBox(
                    height: 74,
                    child: Row(
                      children: [
                        const SizedBox(width: 18),
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: item.$3.withValues(alpha: .14),
                          ),
                          child: Icon(item.$2, color: item.$3),
                        ),
                        const SizedBox(width: 18),
                        Expanded(
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item.$1,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: c.text,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                              if (item.$5 != null) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: item.$3.withValues(alpha: .16),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                        color: item.$3.withValues(alpha: .45)),
                                  ),
                                  child: Text(
                                    item.$5!,
                                    style: TextStyle(
                                      color: item.$3,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded, color: c.muted),
                        const SizedBox(width: 18),
                      ],
                    ),
                  ),
                ),
              if (footer != null) footer!,
            ],
          ),
        ),
      ],
    );
  }
}

class _AppearanceRow extends StatelessWidget {
  const _AppearanceRow({required this.isDark, required this.onChanged});

  final bool isDark;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return SizedBox(
      height: 78,
      child: Row(
        children: [
          const SizedBox(width: 18),
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.cyan.withValues(alpha: .14),
            ),
            child: Icon(
                isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                color: c.cyan),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Appearance',
                    style: TextStyle(
                        color: c.text,
                        fontWeight: FontWeight.w700,
                        fontSize: 17)),
                Text(isDark ? 'Dark Mode' : 'Light Mode',
                    style: TextStyle(color: c.muted, fontSize: 13)),
              ],
            ),
          ),
          Switch(value: isDark, onChanged: onChanged),
          const SizedBox(width: 18),
        ],
      ),
    );
  }
}
