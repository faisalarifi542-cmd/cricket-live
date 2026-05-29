import 'package:flutter/material.dart';
import '../../app_theme.dart';
import '../../components.dart';
import '../../models.dart';
import '../../screens.dart';

class NewsScreen extends StatefulWidget {
  const NewsScreen({
    super.key,
    required this.onOpenSearch,
    required this.onOpenFilters,
    required this.onOpenArticle,
  });

  final VoidCallback onOpenSearch;
  final VoidCallback onOpenFilters;
  final VoidCallback onOpenArticle;

  @override
  State<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends State<NewsScreen> {
  int tab = 0;

  List<NewsArticle> get articles => switch (tab) {
        0 => AppData.newsAll,
        1 => AppData.newsInternational,
        2 => AppData.newsLeagues,
        _ => AppData.newsLatest,
      };

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final current = articles;
    return Container(
      decoration: BoxDecoration(gradient: c.bgGradient),
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(context.horizontalPadding, 18,
              context.horizontalPadding, context.mainBottomPadding),
          children: [
            AppHeader(
              showLogo: true,
              subtitle: 'NEWS',
              trailing: [
                GlowIconButton(
                    icon: Icons.search_rounded, onTap: widget.onOpenSearch),
                const SizedBox(width: 8),
                GlowIconButton(
                    icon: Icons.filter_alt_outlined,
                    onTap: widget.onOpenFilters),
              ],
            ),
            const SizedBox(height: 18),
            SegmentedTabs(
              items: const [
                ('All', null),
                ('International', null),
                ('Leagues', null),
                ('Latest', null),
              ],
              selected: tab,
              onChanged: (v) => setState(() => tab = v),
            ),
            const SizedBox(height: 18),
            FeaturedNewsCard(
                article: current.first, onTap: widget.onOpenArticle),
            const SizedBox(height: 14),
            for (final article in current.skip(1))
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child:
                    NewsListCard(article: article, onTap: widget.onOpenArticle),
              ),
          ],
        ),
      ),
    );
  }
}
