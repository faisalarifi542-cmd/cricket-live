import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'package:cricpro_flutter/app_theme.dart';
import 'package:cricpro_flutter/api_models.dart';
import 'package:cricpro_flutter/components.dart';
import 'package:cricpro_flutter/models/ad_config.dart';
import 'package:cricpro_flutter/models/api_response.dart';
import 'package:cricpro_flutter/repositories/cricket_repository.dart';
import 'package:cricpro_flutter/screens/series/series_detail_screen.dart';
import 'package:cricpro_flutter/widgets/ads/banner_ad_widget.dart';
import 'package:cricpro_flutter/widgets/ads/native_ad_card.dart';

class SeriesListScreen extends StatefulWidget {
  const SeriesListScreen({super.key, required this.onOpenSeries});

  final ValueChanged<String> onOpenSeries;

  @override
  State<SeriesListScreen> createState() => _SeriesListScreenState();
}

class _SeriesListScreenState extends State<SeriesListScreen> {
  final CricketRepository _repository = CricketRepository();
  late Future<ApiEnvelope<List<ApiSeries>>> _series;

  @override
  void initState() {
    super.initState();
    _series = _repository.seriesList();
  }

  Future<void> _refresh() async {
    setState(() => _series = _repository.seriesList(forceRefresh: true));
    await _series;
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
            child: ListView(
              padding: EdgeInsets.fromLTRB(context.horizontalPadding, 18,
                  context.horizontalPadding, context.detailBottomPadding),
              children: [
                AppHeader(
                  leading: IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.arrow_back_rounded, color: c.text),
                  ),
                  title: 'Series',
                ),
                const SizedBox(height: 18),
                FutureBuilder<ApiEnvelope<List<ApiSeries>>>(
                  future: _series,
                  builder: (context, snapshot) {
                    final items = snapshot.data?.data ?? const <ApiSeries>[];
                    if (snapshot.connectionState == ConnectionState.waiting &&
                        items.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 28),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (snapshot.hasError) {
                      return _SeriesStateCard(
                        title: 'Unable to load series',
                        message: 'Please check your connection and try again.',
                        onRetry: () => setState(() => _series =
                            _repository.seriesList(forceRefresh: true)),
                      );
                    }
                    if (items.isEmpty) {
                      return _SeriesStateCard(
                        title: 'No series available',
                        message: 'Series will appear here when available.',
                        onRetry: () => setState(() => _series =
                            _repository.seriesList(forceRefresh: true)),
                      );
                    }
                    return Column(
                      children: [
                        for (final entry in items.indexed) ...[
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _SeriesCard(
                              series: entry.$2,
                              onTap: () {
                                if (kDebugMode) {
                                  debugPrint(
                                      'SERIES_TAP id=${entry.$2.id} name=${entry.$2.name} raw=${entry.$2.id}/${entry.$2.name}');
                                }
                                Navigator.of(context).push(MaterialPageRoute(
                                  builder: (_) => SeriesDetailScreen(
                                    seriesId: entry.$2.id,
                                    initialSeries: entry.$2,
                                    onOpenReminders: () {},
                                    onOpenCalendar: () {},
                                    onOpenPlayer: () {},
                                  ),
                                ));
                              },
                            ),
                          ),
                          if ((entry.$1 + 1) % 6 == 0)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 12),
                              child: NativeAdCard(placement: AdPlacement.series),
                            ),
                        ],
                        const BannerAdWidget(placement: AdPlacement.series),
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
}

class _SeriesCard extends StatelessWidget {
  const _SeriesCard({required this.series, required this.onTap});

  final ApiSeries series;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final dateRange = [
      if (series.startDate?.isNotEmpty == true) series.startDate!,
      if (series.endDate?.isNotEmpty == true) series.endDate!,
    ].join(' - ');
    return PremiumCard(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      gradient: LinearGradient(
        colors: [c.card, c.cyan.withValues(alpha: 0.08)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: c.cyan.withValues(alpha: 0.13),
                  border: Border.all(color: c.cyan.withValues(alpha: 0.28)),
                ),
                child:
                    Icon(Icons.emoji_events_outlined, color: c.cyan, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  series.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: c.text,
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                      height: 1.15),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: c.muted),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SeriesChip(text: series.status),
              if (series.format?.isNotEmpty == true)
                _SeriesChip(text: series.format!),
              if (series.country?.isNotEmpty == true)
                _SeriesChip(text: series.country!),
              if (series.matchCount != null)
                _SeriesChip(text: '${series.matchCount} matches'),
            ],
          ),
          if (dateRange.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.calendar_month_rounded, color: c.muted, size: 16),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(dateRange,
                        style: TextStyle(
                            color: c.muted, fontWeight: FontWeight.w700))),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SeriesChip extends StatelessWidget {
  const _SeriesChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: c.cyan.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.cyan.withValues(alpha: 0.24)),
      ),
      child: Text(text,
          style: TextStyle(
              color: c.cyan, fontSize: 11, fontWeight: FontWeight.w900)),
    );
  }
}

class _SeriesStateCard extends StatelessWidget {
  const _SeriesStateCard({
    required this.title,
    required this.message,
    required this.onRetry,
  });

  final String title;
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        children: [
          Icon(Icons.emoji_events_outlined, color: c.cyan, size: 38),
          const SizedBox(height: 12),
          Text(title,
              style: TextStyle(
                  color: c.text, fontWeight: FontWeight.w900, fontSize: 18)),
          const SizedBox(height: 8),
          Text(message,
              textAlign: TextAlign.center,
              style: TextStyle(color: c.muted, height: 1.4)),
          const SizedBox(height: 16),
          GradientButton(
              label: 'Retry', icon: Icons.refresh_rounded, onTap: onRetry),
        ],
      ),
    );
  }
}
