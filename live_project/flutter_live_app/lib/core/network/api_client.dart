import 'package:dio/dio.dart';

import '../config/environment.dart';
import '../auth/token_storage.dart';
import 'api_exception.dart';
import 'api_response.dart';
import 'auth_expired_event_bus.dart';

/// Dio 的项目级封装。
///
/// DataSource 和页面不直接创建 Dio。超时、JWT 请求头、统一响应解析和
/// 网络错误翻译集中在这里，未来更换域名或增加公共拦截器只改一处。
class ApiClient {
  ApiClient(this._tokenStorage, this._authExpiredEventBus) : _dio = Dio() {
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
  final AuthExpiredEventBus _authExpiredEventBus;

  Future<ApiResponse<T>> get<T>(
    String path, {
    CancelToken? cancelToken,
    required T Function(Object? value) parseData,
  }) async {
    try {
      // 解析函数由调用方提供，ApiClient 不需要知道每个业务模型的字段。
      final response = await _dio.get<Object?>(path, cancelToken: cancelToken);
      final data = response.data;
      if (data is! Map) {
        throw const ApiException(message: '服务端返回格式不正确');
      }
      return _parseResponse(data, parseData);
    } on ApiException {
      rethrow;
    } on DioException catch (error) {
      throw await _handleDioException(error);
    } on FormatException {
      throw const ApiException(message: '服务端返回格式不正确');
    }
  }

  Future<ApiResponse<T>> post<T>(
    String path, {
    Object? data,
    CancelToken? cancelToken,
    required T Function(Object? value) parseData,
  }) async {
    try {
      // POST 与 GET 共用同一套响应格式和异常翻译逻辑。
      final response = await _dio.post<Object?>(
        path,
        data: data,
        cancelToken: cancelToken,
      );
      final responseData = response.data;
      if (responseData is! Map) {
        throw const ApiException(message: '服务端返回格式不正确');
      }
      return _parseResponse(responseData, parseData);
    } on ApiException {
      rethrow;
    } on DioException catch (error) {
      throw await _handleDioException(error);
    } on FormatException {
      throw const ApiException(message: '服务端返回格式不正确');
    }
  }

  Future<ApiResponse<T>> put<T>(
    String path, {
    Object? data,
    required T Function(Object? value) parseData,
  }) async {
    try {
      final response = await _dio.put<Object?>(path, data: data);
      final responseData = response.data;
      if (responseData is! Map) {
        throw const ApiException(message: '服务端返回格式不正确');
      }
      return _parseResponse(responseData, parseData);
    } on ApiException {
      rethrow;
    } on DioException catch (error) {
      throw await _handleDioException(error);
    } on FormatException {
      throw const ApiException(message: '服务端返回格式不正确');
    }
  }

  Future<void> delete(String path) async {
    try {
      final response = await _dio.delete<Object?>(path);
      if (response.data is! Map) {
        throw const ApiException(message: '服务端返回格式不正确');
      }
      _parseResponse<Object?>(response.data as Map, (value) => value);
    } on DioException catch (error) {
      throw await _handleDioException(error);
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

  // 401 先清理旧 Token、发布全局事件，再把底层异常翻译成页面可读错误。
  Future<ApiException> _handleDioException(DioException error) async {
    if (error.response?.statusCode == 401) {
      // 无论请求是否携带 Token，都统一清理本地状态并通知 UI。这样未登录
      // 用户访问需要登录的动态/消息接口时，也能得到明确的登录入口。
      await _tokenStorage.clearToken();
      _authExpiredEventBus.emit();
    }
    return _mapDioException(error);
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
