class ApiSeries {
  final String seriesId;
  final String name;
  final String season;
  final DateTime? startDate;
  final DateTime? endDate;

  ApiSeries({
    required this.seriesId,
    required this.name,
    required this.season,
    this.startDate,
    this.endDate,
  });

  factory ApiSeries.fromJson(Map<String, dynamic> json) {
    return ApiSeries(
      seriesId: json['series_id']?.toString() ?? '',
      name: (json['name']?.toString() ?? '').replaceAll('\\', '').trim(),
      season: json['season']?.toString() ?? '',
      startDate: json['start_date'] != null ? DateTime.tryParse(json['start_date'].toString()) : null,
      endDate: json['end_date'] != null ? DateTime.tryParse(json['end_date'].toString()) : null,
    );
  }

  String get cleanName => name.replaceAll('\\', '').trim();
}
