class VideoModel {
  final String id;
  final String title;
  final String subtitle;
  final String duration;
  final String? imageUrl;

  VideoModel({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.duration,
    this.imageUrl,
  });
}
