class NewsModel {
  final String id;
  final String context;
  final String headline;
  final String intro;
  final String publishedTime;
  final String storyType;
  final bool isPremium;
  final String? imageId;
  final String? imageUrl;
  final bool isNewsPage;
  final String? content;
  final String? author;
  final List<NewsModel> relatedStories;

  NewsModel({
    required this.id,
    this.context = '',
    required this.headline,
    this.intro = '',
    this.publishedTime = '',
    this.storyType = '',
    this.isPremium = false,
    this.imageId,
    this.imageUrl,
    this.isNewsPage = false,
    this.content,
    this.author,
    this.relatedStories = const [],
  });

  // Backward-compatible getters for existing UI
  String get category => storyType.isNotEmpty ? storyType.toUpperCase() : 'NEWS';
  String get title => headline;
  String get timeAgo => publishedTime;
  String get readTime => '${(headline.length / 50).ceil()} min read';

  factory NewsModel.fromJson(Map<String, dynamic> json) {
    return NewsModel(
      id: json['id']?.toString() ?? '',
      context: json['context'] ?? '',
      headline: json['headline'] ?? '',
      intro: json['intro'] ?? '',
      publishedTime: json['publishedTime'] ?? '',
      storyType: json['storyType'] ?? '',
      isPremium: json['isPremium'] ?? false,
      imageId: json['imageId']?.toString(),
      imageUrl: json['imageUrl']?.toString(),
      isNewsPage: json['isNewsPage'] ?? false,
      content: json['content']?.toString(),
      author: json['author']?.toString(),
      relatedStories: json['relatedStories'] != null
          ? (json['relatedStories'] as List)
              .map((e) => NewsModel.fromJson(e as Map<String, dynamic>))
              .toList()
          : [],
    );
  }
}

class NewsListResponse {
  final List<NewsModel> stories;
  final String? nextCursor;

  NewsListResponse({required this.stories, this.nextCursor});

  factory NewsListResponse.fromJson(Map<String, dynamic> json) {
    return NewsListResponse(
      stories: (json['stories'] as List?)
              ?.map((e) => NewsModel.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      nextCursor: json['nextCursor']?.toString(),
    );
  }
}
