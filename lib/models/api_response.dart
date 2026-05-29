class ApiMeta {
  const ApiMeta({
    required this.provider,
    required this.cache,
    required this.isStale,
    this.lastUpdated,
    this.ttl,
  });

  final String provider;
  final String cache;
  final bool isStale;
  final DateTime? lastUpdated;
  final int? ttl;

  factory ApiMeta.fromJson(Map<String, dynamic>? json) {
    return ApiMeta(
      provider: json?['provider']?.toString() ?? 'webcrichd',
      cache: json?['cache']?.toString() ?? 'MISS',
      isStale: json?['isStale'] == true,
      lastUpdated: DateTime.tryParse(json?['lastUpdated']?.toString() ?? ''),
      ttl: int.tryParse(json?['ttl']?.toString() ?? ''),
    );
  }
}

class ApiEnvelope<T> {
  const ApiEnvelope({
    required this.data,
    required this.meta,
  });

  final T data;
  final ApiMeta meta;

  factory ApiEnvelope.fromJson(
    Map<String, dynamic> json,
    T Function(dynamic value) parser,
  ) {
    return ApiEnvelope<T>(
      data: parser(json['data']),
      meta: ApiMeta.fromJson(json['meta'] as Map<String, dynamic>?),
    );
  }
}
