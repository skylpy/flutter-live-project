import 'package:dio/dio.dart';

import '../config/environment.dart';
import 'api_exception.dart';
import 'api_response.dart';

class ApiClient {
  ApiClient() : _dio = Dio() {
    _dio.options = BaseOptions(
      baseUrl: Environment.apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      headers: <String, Object>{'Content-Type': 'application/json'},
      responseType: ResponseType.json,
    );
    _dio.interceptors.addAll([
      LogInterceptor(requestBody: false, responseBody: false),
      InterceptorsWrapper(
        onRequest: (options, handler) {
          // JWT will be supplied here once authentication is introduced.
          // options.headers['Authorization'] = 'Bearer $token';
          handler.next(options);
        },
      ),
    ]);
  }

  final Dio _dio;

  Future<ApiResponse<T>> get<T>(
    String path, {
    required T Function(Object? value) parseData,
  }) async {
    try {
      final response = await _dio.get<Object?>(path);
      final data = response.data;
      if (data is! Map) {
        throw const ApiException(message: '服务端返回格式不正确');
      }
      final apiResponse = ApiResponse<T>.fromJson(
        Map<String, Object?>.from(data),
        parseData,
      );
      if (apiResponse.code != 0) {
        throw ApiException(
          message: apiResponse.message,
          code: apiResponse.code,
        );
      }
      return apiResponse;
    } on ApiException {
      rethrow;
    } on DioException catch (error) {
      throw _mapDioException(error);
    } on FormatException {
      throw const ApiException(message: '服务端返回格式不正确');
    }
  }

  ApiException _mapDioException(DioException error) {
    final statusCode = error.response?.statusCode;
    final message = switch (statusCode) {
      400 => '请求参数错误',
      401 => '登录状态已失效',
      403 => '没有权限访问',
      404 => '请求资源不存在',
      422 => '请求数据校验失败',
      500 => '服务器内部错误',
      _ => switch (error.type) {
        DioExceptionType.connectionTimeout => '连接服务器超时',
        DioExceptionType.receiveTimeout => '等待服务器响应超时',
        DioExceptionType.connectionError => '网络连接失败，请检查网络或服务端是否启动',
        _ => '网络请求失败',
      },
    };
    return ApiException(message: message, statusCode: statusCode);
  }
}
