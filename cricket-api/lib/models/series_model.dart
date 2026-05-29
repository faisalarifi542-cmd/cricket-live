class SeriesModel {
  final String id;
  final String title;
  final String type;
  final String dateRange;
  final String? imageUrl;
  final int gradientIndex;

  SeriesModel({
    required this.id,
    required this.title,
    required this.type,
    required this.dateRange,
    this.imageUrl,
    this.gradientIndex = 0,
  });
}
