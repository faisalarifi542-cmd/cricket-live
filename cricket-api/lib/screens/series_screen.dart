import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/network/network_result.dart';
import '../data/repositories/cricket_repository.dart';
import '../models/api/api_series_model.dart';
import '../widgets/custom_header.dart';
import '../widgets/api_state_widgets.dart';
import 'series_detail_screen.dart';

class SeriesScreen extends StatefulWidget {
  const SeriesScreen({super.key});

  @override
  State<SeriesScreen> createState() => _SeriesScreenState();
}

class _SeriesScreenState extends State<SeriesScreen> {
  final _repo = CricketRepository.instance;
  List<ApiSeries> _seriesList = [];
  bool _isLoading = true;
  String? _errorMessage;

  static const List<List<Color>> _cardGradients = [
    [Color(0xFF1B4D3E), Color(0xFF0D2818)],
    [Color(0xFF2D1B69), Color(0xFF1A0D3D)],
    [Color(0xFF1A3A6C), Color(0xFF0D1F3C)],
    [Color(0xFF3D1B1B), Color(0xFF2D0D0D)],
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    final result = await _repo.getSeries();
    if (mounted) {
      setState(() {
        _isLoading = false;
        if (result is NetworkSuccess<List<ApiSeries>>) {
          _seriesList = result.data;
        } else if (result is NetworkError<List<ApiSeries>>) {
          _errorMessage = result.exception.message;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CustomHeader(showBackButton: true),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  'Series',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _isLoading
                    ? const LoadingWidget(message: 'Loading series...')
                    : _errorMessage != null
                        ? ErrorRetryWidget(message: _errorMessage!, onRetry: _loadData)
                        : _seriesList.isEmpty
                            ? const EmptyStateWidget(message: 'No series available')
                            : RefreshIndicator(
                                color: AppColors.cyan,
                                backgroundColor: AppColors.cardBg,
                                onRefresh: _loadData,
                                child: ListView.builder(
                                  padding: const EdgeInsets.symmetric(horizontal: 16),
                                  itemCount: _seriesList.length,
                                  itemBuilder: (context, index) {
                                    final series = _seriesList[index];
                                    return GestureDetector(
                                      onTap: () {
                                        Navigator.of(context).push(MaterialPageRoute(
                                          builder: (_) => SeriesDetailScreen(seriesId: series.seriesId, seriesName: series.cleanName),
                                        ));
                                      },
                                      child: _buildSeriesCard(series, index),
                                    );
                                  },
                                ),
                              ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSeriesCard(ApiSeries series, int index) {
    final colors = _cardGradients[index % _cardGradients.length];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      height: 100,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: colors,
        ),
        border: Border.all(
          color: AppColors.borderColor.withOpacity(0.4),
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: ClipRRect(
              borderRadius: const BorderRadius.horizontal(right: Radius.circular(16)),
              child: Container(
                width: 120,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Colors.transparent,
                      colors[0].withOpacity(0.5),
                    ],
                  ),
                ),
                child: Center(
                  child: Icon(
                    Icons.sports_cricket,
                    color: Colors.white.withOpacity(0.15),
                    size: 50,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  series.cleanName,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (series.season.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    series.season,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
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
