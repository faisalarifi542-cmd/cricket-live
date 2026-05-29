import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'api_endpoints.dart';
import 'api_exception.dart';

class ApiClient {
  static ApiClient? _instance;
  late final Dio _dio;

  ApiClient._() {
    _dio = Dio(BaseOptions(
      baseUrl: ApiEndpoints.baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 15),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ));

    if (kDebugMode) {
      _dio.interceptors.add(LogInterceptor(
        requestBody: false,
        responseBody: true,
        logPrint: (obj) => debugPrint('[API] $obj'),
      ));
    }
  }

  static ApiClient get instance {
    _instance ??= ApiClient._();
    return _instance!;
  }

  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) async {
    try {
      final response = await _dio.get(
        path,
        queryParameters: queryParameters,
      );

      if (response.statusCode == 200) {
        final data = response.data;
        if (data is Map<String, dynamic>) {
          if (data['success'] == true) {
            return data['data'];
          } else {
            throw ApiException(
              message: data['message'] ?? 'Request failed',
              statusCode: response.statusCode,
              data: data,
            );
          }
        }
        return data;
      } else {
        throw ApiException.server(response.statusCode);
      }
    } on DioException catch (e) {
      switch (e.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          throw ApiException.timeout();
        case DioExceptionType.connectionError:
          throw ApiException.network();
        case DioExceptionType.badResponse:
          final statusCode = e.response?.statusCode;
          if (statusCode == 404) {
            throw ApiException.notFound();
          }
          throw ApiException.server(statusCode);
        default:
          throw ApiException.unknown(e.message);
      }
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException.unknown(e.toString());
    }
  }

  Future<bool> checkHealth() async {
    try {
      final data = await get(ApiEndpoints.health);
      if (data is Map<String, dynamic>) {
        return data['status'] == 'healthy';
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}
