import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../components.dart';
import '../../services/favorite_countries_service.dart';

/// Lets the user pick favourite cricket nations. Selections persist locally
/// (no login) and are used to prioritise matches on Home and the Matches
/// screen. An empty selection means normal sorting.
class FavoriteCountriesScreen extends StatefulWidget {
  const FavoriteCountriesScreen({super.key});

  @override
  State<FavoriteCountriesScreen> createState() =>
      _FavoriteCountriesScreenState();
}

class _FavoriteCountriesScreenState extends State<FavoriteCountriesScreen> {
  final _service = FavoriteCountriesService.instance;

  Future<void> _toggle(String code) async {
    await _service.toggle(code);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final selectedCount = _service.selected.value.length;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: c.bgGradient),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                    context.horizontalPadding, 18, context.horizontalPadding, 0),
                child: AppHeader(
                  leading: IconButton(
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Back',
                    icon: Icon(Icons.arrow_back_rounded, color: c.text),
                  ),
                  title: 'Favorite Countries',
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: context.horizontalPadding),
                child: _IntroCard(selectedCount: selectedCount),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.separated(
                  padding: EdgeInsets.fromLTRB(
                      context.horizontalPadding,
                      0,
                      context.horizontalPadding,
                      context.detailBottomPadding),
                  itemCount: FavoriteCountriesService.catalog.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final country = FavoriteCountriesService.catalog[i];
                    return _CountryTile(
                      country: country,
                      selected: _service.isSelected(country.code),
                      onTap: () => _toggle(country.code),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IntroCard extends StatelessWidget {
  const _IntroCard({required this.selectedCount});

  final int selectedCount;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.cyan.withValues(alpha: .14),
              border: Border.all(color: c.cyan.withValues(alpha: .4)),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.public_rounded, color: c.cyan, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Pick your favourite teams',
                  style: TextStyle(
                      color: c.text,
                      fontWeight: FontWeight.w800,
                      fontSize: 15),
                ),
                const SizedBox(height: 3),
                Text(
                  selectedCount == 0
                      ? 'Their matches move higher on Home and Matches.'
                      : '$selectedCount selected • we prioritise their matches.',
                  style: TextStyle(color: c.muted, fontSize: 12.5, height: 1.3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CountryTile extends StatelessWidget {
  const _CountryTile({
    required this.country,
    required this.selected,
    required this.onTap,
  });

  final FavoriteCountry country;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? c.cyan.withValues(alpha: c.isDark ? .16 : .12)
              : (c.isDark ? c.card.withValues(alpha: .45) : c.card),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? c.cyan.withValues(alpha: .9)
                : c.cyan.withValues(alpha: .22),
            width: selected ? 1.6 : 1,
          ),
          boxShadow: selected && c.isDark
              ? [
                  BoxShadow(
                    color: c.cyan.withValues(alpha: .28),
                    blurRadius: 14,
                    spreadRadius: -3,
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            _FlagBadge(country: country, accent: c.cyan),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    country.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.text,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    country.code,
                    style: TextStyle(
                      color: c.muted,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      letterSpacing: .4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected ? c.cyan : c.muted.withValues(alpha: .6),
              size: 24,
            ),
          ],
        ),
      ),
    );
  }
}

/// Round badge using a flag asset when available, otherwise initials. Flag
/// assets are looked up by lowercase code under assets/images/flags/; a missing
/// asset falls back gracefully to the initials circle.
class _FlagBadge extends StatelessWidget {
  const _FlagBadge({required this.country, required this.accent});

  final FavoriteCountry country;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: accent.withValues(alpha: .14),
        border: Border.all(color: accent.withValues(alpha: .55), width: 1.4),
      ),
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      child: Text(
        country.code.length <= 3 ? country.code : country.initials,
        style: TextStyle(
          color: c.text,
          fontWeight: FontWeight.w900,
          fontSize: country.code.length >= 3 ? 11 : 13,
          letterSpacing: .3,
        ),
      ),
    );
  }
}
