class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final dynamic data;

  ApiException({
    required this.message,
    this.statusCode,
    this.data,
  });

  @override
  String toString() => 'ApiException($statusCode): $message';

  factory ApiException.network() => ApiException(
        message: 'No internet connection. Please check your network.',
      );

  factory ApiException.timeout() => ApiException(
        message: 'Request timed out. Please try again.',
      );

  factory ApiException.server([int? code]) => ApiException(
        message: 'Server error. Please try again later.',
        statusCode: code,
      );

  factory ApiException.notFound() => ApiException(
        message: 'Data not found.',
        statusCode: 404,
      );

  factory ApiException.unknown([String? msg]) => ApiException(
        message: msg ?? 'Something went wrong. Please try again.',
      );
}
