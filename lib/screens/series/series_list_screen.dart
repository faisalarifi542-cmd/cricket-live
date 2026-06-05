import 'package:flutter/material.dart';

import 'package:cricpro_flutter/app_theme.dart';
import 'package:cricpro_flutter/api_models.dart';
import 'package:cricpro_flutter/components.dart';
import 'package:cricpro_flutter/models/api_response.dart';
import 'package:cricpro_flutter/repositories/cricket_repository.dart';
import 'package:cricpro_flutter/screens/series/series_components.dart';
import 'package:cricpro_flutter/screens/series/series_detail_screen.dart';

class SeriesListScreen extends StatefulWidget {
  const SeriesListScreen({
    super.key,
    required this.onOpenSeries,
    this.showBack = false,
  });

  final ValueChanged<String> onOpenSeries;
  final bool showBack;

  @override
  State<SeriesListScreen> createState() => _SeriesListScreenState();
}

class _SeriesListScreenState extends State<SeriesListScreen> {
  final CricketRepository _repository = CricketRepository();
  late Future<ApiEnvelope<List<ApiSeries>>> _series;
  int _category = 0;
  int _status = 0;

  static const _categories = ['All', 'International', 'League', 'Domestic'];
  static const _statuses = ['Ongoing', 'Upcoming', 'Completed'];

  @override
  void initState() {
    super.initState();
    _series = _repository.seriesList();
  }

  Future<void> _refresh() async {
    setState(() => _series = _repository.seriesList(forceRefresh: true));
    await _series;
  }

  void _open(SeriesView series) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SeriesDetailScreen(
        seriesId: series.id,
        initialSeries: ApiSeries(
          id: series.id,
          name: series.name,
          status: series.statusLabel,
          startDate: series.startDate?.toIso8601String(),
          endDate: series.endDate?.toIso8601String(),
          format: series.formats.join(', '),
          country: series.host,
          matchCount: series.matchCount,
        ),
        onOpenReminders: () {},
        onOpenCalendar: () {},
        onOpenPlayer: () {},
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: c.bgGradient),
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: _refresh,
            color: c.cyan,
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                context.horizontalPadding,
                18,
                context.horizontalPadding,
                widget.showBack
                    ? context.detailBottomPadding
                    : context.mainBottomPadding,
              ),
              children: [
                AppHeader(
                  leading: widget.showBack
                      ? IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: Icon(Icons.arrow_back_rounded, color: c.text),
                        )
                      : null,
                  title: widget.showBack ? 'All Series' : null,
                  showLogo: !widget.showBack,
                  trailing: const [
                    GlowIconButton(icon: Icons.search_rounded),
                    SizedBox(width: 8),
                    GlowIconButton(icon: Icons.notifications_none_rounded),
                  ],
                ),
                const SizedBox(height: 18),
                FutureBuilder<ApiEnvelope<List<ApiSeries>>>(
                  future: _series,
                  builder: (context, snapshot) {
                    final all = (snapshot.data?.data ?? const <ApiSeries>[])
                        .map(SeriesView.fromApi)
                        .toList();

                    final waiting =
                        snapshot.connectionState == ConnectionState.waiting &&
                            all.isEmpty;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!widget.showBack && all.isNotEmpty) ...[
                          _FeaturedSeriesBanner(series: all.take(4).toList()),
                          const SizedBox(height: 18),
                        ],
                        SeriesFilterPills(
                          items: _categories,
                          selected: _category,
                          onChanged: (v) => setState(() => _category = v),
                        ),
                        const SizedBox(height: 12),
                        SeriesFilterPills(
                          items: _statuses,
                          selected: _status,
                          onChanged: (v) => setState(() => _status = v),
                        ),
                        const SizedBox(height: 18),
                        if (waiting)
                          const SeriesLoading()
                        else if (snapshot.hasError && all.isEmpty)
                          SeriesStateCard(
                            title: 'Unable to load series',
                            message:
                                'Please check your connection and try again.',
                            icon: Icons.cloud_off_rounded,
                            onRetry: () => setState(() => _series =
                                _repository.seriesList(forceRefresh: true)),
                          )
                        else
                          _buildList(all),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildList(List<SeriesView> all) {
    final items = _filtered(all);
    if (items.isEmpty) {
      return SeriesStateCard(
        title: 'No ${_statuses[_status].toLowerCase()} series',
        message:
            'There are no ${_statuses[_status].toLowerCase()} ${_categories[_category] == 'All' ? '' : '${_categories[_category].toLowerCase()} '}series right now. Try another filter.',
        icon: Icons.event_busy_rounded,
      );
    }
    return Column(
      children: [
        for (final series in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: SeriesListCard(series: series, onTap: () => _open(series)),
          ),
      ],
    );
  }

  List<SeriesView> _filtered(List<SeriesView> items) {
    final category = _categories[_category].toLowerCase();
    final wantStatus = switch (_status) {
      0 => SeriesStatus.ongoing,
      1 => SeriesStatus.upcoming,
      _ => SeriesStatus.completed,
    };
    return items.where((s) {
      final categoryOk = category == 'all' ||
          s.categoryLabel.toLowerCase() == category;
      return categoryOk && s.status == wantStatus;
    }).toList(growable: false);
  }
}

/// Premium auto-scrolling featured banner shown above the filters on the
/// Series tab (matches the reference "International Series" hero).
class _FeaturedSeriesBanner extends StatefulWidget {
  const _FeaturedSeriesBanner({required this.series});

  final List<SeriesView> series;

  @override
  State<_FeaturedSeriesBanner> createState() => _FeaturedSeriesBannerState();
}

class _FeaturedSeriesBannerState extends State<_FeaturedSeriesBanner> {
  final PageController _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Column(
      children: [
        SizedBox(
          height: 168,
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.series.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (context, i) => _BannerCard(series: widget.series[i]),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < widget.series.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: i == _page ? 22 : 7,
                height: 7,
                decoration: BoxDecoration(
                  color: i == _page ? c.cyan : c.border,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _BannerCard extends StatelessWidget {
  const _BannerCard({required this.series});

  final SeriesView series;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: c.cyan.withValues(alpha: .25)),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            'assets/images/stadium_live.png',
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                const ColoredBox(color: Color(0xff071726)),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xff041228).withValues(alpha: .55),
                  const Color(0xff05101f).withValues(alpha: .92),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: c.cyan.withValues(alpha: .18),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: c.cyan.withValues(alpha: .5)),
                  ),
                  child: Text(
                    series.categoryLabel.toUpperCase(),
                    style: TextStyle(
                      color: c.cyan,
                      fontWeight: FontWeight.w900,
                      fontSize: 10.5,
                      letterSpacing: .6,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  series.cleanName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 22,
                    height: 1.1,
                  ),
                ),
                if (series.formatSummary.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    series.formatSummary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.cyan,
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
