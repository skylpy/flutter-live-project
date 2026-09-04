import 'package:dio/dio.dart';

import '../config/environment.dart';
import '../auth/token_storage.dart';
import 'api_exception.dart';
import 'api_response.dart';

/// Dio 的项目级封装。
///
/// DataSource 和页面不直接创建 Dio。超时、JWT 请求头、统一响应解析和
/// 网络错误翻译集中在这里，未来更换域名或增加公共拦截器只改一处。
class ApiClient {
  ApiClient(this._tokenStorage) : _dio = Dio() {
    // BaseOptions 是所有请求的默认配置；单个接口仅在确实需要时覆盖。
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
        onRequest: (options, handler) async {
          // 每次请求读取最新 Token，避免登录或退出登录后继续使用旧值。
          final token = await _tokenStorage.readToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
      ),
    ]);
  }

  final Dio _dio;
  final TokenStorage _tokenStorage;

  Future<ApiResponse<T>> get<T>(
    String path, {
    required T Function(Object? value) parseData,
  }) async {
    try {
      // 解析函数由调用方提供，ApiClient 不需要知道每个业务模型的字段。
      final response = await _dio.get<Object?>(path);
      final data = response.data;
      if (data is! Map) {
        throw const ApiException(message: '服务端返回格式不正确');
      }
      return _parseResponse(data, parseData);
    } on ApiException {
      rethrow;
    } on DioException catch (error) {
      throw _mapDioException(error);
    } on FormatException {
      throw const ApiException(message: '服务端返回格式不正确');
    }
  }

  Future<ApiResponse<T>> post<T>(
    String path, {
    Object? data,
    required T Function(Object? value) parseData,
  }) async {
    try {
      // POST 与 GET 共用同一套响应格式和异常翻译逻辑。
      final response = await _dio.post<Object?>(path, data: data);
      final responseData = response.data;
      if (responseData is! Map) {
        throw const ApiException(message: '服务端返回格式不正确');
      }
      return _parseResponse(responseData, parseData);
    } on ApiException {
      rethrow;
    } on DioException catch (error) {
      throw _mapDioException(error);
    } on FormatException {
      throw const ApiException(message: '服务端返回格式不正确');
    }
  }

  ApiResponse<T> _parseResponse<T>(
    Map responseData,
    T Function(Object? value) parseData,
  ) {
    // HTTP 200 只代表传输成功；只有业务 code=0 才代表接口成功。
    final apiResponse = ApiResponse<T>.fromJson(
      Map<String, Object?>.from(responseData),
      parseData,
    );
    if (apiResponse.code != 0) {
      throw ApiException(message: apiResponse.message, code: apiResponse.code);
    }
    return apiResponse;
  }

  // 把 Dio 的底层异常翻译成页面可读错误，并保留状态码供以后统一处理。
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
