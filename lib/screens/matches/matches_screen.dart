import 'package:flutter/material.dart';
import '../../app_theme.dart';
import '../../components.dart';
import '../../models.dart';
import '../../models/cricket_match.dart';
import '../../repositories/cricket_repository.dart';
import '../../screens.dart';

class MatchesScreen extends StatefulWidget {
  const MatchesScreen({
    super.key,
    required this.onOpenMatch,
    required this.onOpenSearch,
    required this.onOpenFilters,
    required this.onOpenReminders,
    required this.onOpenSeries,
  });

  final VoidCallback onOpenMatch;
  final VoidCallback onOpenSearch;
  final VoidCallback onOpenFilters;
  final VoidCallback onOpenReminders;
  final VoidCallback onOpenSeries;

  @override
  State<MatchesScreen> createState() => _MatchesScreenState();
}

class _MatchesScreenState extends State<MatchesScreen> {
  int topTab = 1;
  int category = 0;
  final CricketRepository _repository = CricketRepository();
  late Future<List<CricketMatch>> _apiMatches;

  @override
  void initState() {
    super.initState();
    _apiMatches = _loadMatches();
  }

  Future<List<CricketMatch>> _loadMatches() async {
    final response = await _repository.matchesForTab(topTab);
    return response.data;
  }

  void _setTopTab(int value) {
    setState(() {
      topTab = value;
      _apiMatches = _loadMatches();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final filters = ['All', 'International', 'League', 'Domestic'];
    final list =
        topTab == 2 ? AppData.matchesFinished : AppData.matchesUpcoming;
    return Container(
      decoration: BoxDecoration(gradient: c.bgGradient),
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(context.horizontalPadding, 18,
              context.horizontalPadding, context.mainBottomPadding),
          children: [
            AppHeader(
              showLogo: true,
              trailing: [
                GlowIconButton(
                    icon: Icons.search_rounded, onTap: widget.onOpenSearch),
                const SizedBox(width: 8),
                GlowIconButton(
                    icon: Icons.filter_alt_outlined,
                    onTap: widget.onOpenFilters),
              ],
            ),
            const SizedBox(height: 22),
            SegmentedTabs(
              items: const [
                ('Live', Icons.podcasts_rounded),
                ('Upcoming', Icons.calendar_month_rounded),
                ('Finished', Icons.check_circle_outline_rounded),
              ],
              selected: topTab,
              onChanged: _setTopTab,
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 46,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemBuilder: (_, i) => PillChip(filters[i],
                    selected: category == i,
                    onTap: () => setState(() => category = i)),
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemCount: filters.length,
              ),
            ),
            const SizedBox(height: 22),
            FutureBuilder<List<CricketMatch>>(
              future: _apiMatches,
              builder: (context, snapshot) {
                final apiItems = snapshot.data ?? const <CricketMatch>[];
                final items = apiItems.isEmpty
                    ? list
                    : apiItems.map((match) => match.toCompactFixture(finished: topTab == 2)).toList();

                if (snapshot.connectionState == ConnectionState.waiting && apiItems.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 26),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                return Column(
                  children: [
                    for (final item in items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 18),
                        child: topTab == 2
                            ? FinishedMatchCard(match: item, onTap: widget.onOpenMatch)
                            : UpcomingMatchCard(
                                match: item,
                                onTap: widget.onOpenMatch,
                                onReminder: widget.onOpenReminders),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
