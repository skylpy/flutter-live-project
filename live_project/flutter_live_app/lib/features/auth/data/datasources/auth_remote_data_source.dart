import '../../../../core/network/api_client.dart';
import '../models/auth_session.dart';

/// 认证接口的数据来源。
///
/// 这一层只知道后端路径和 JSON 解析，不保存登录状态，也不决定页面如何展示。
class AuthRemoteDataSource {
  const AuthRemoteDataSource(this._apiClient);

  final ApiClient _apiClient;

  Future<AuthSession> login(String username, String password) async {
    // ApiClient 会自动附加公共配置；登录接口本身不需要 Token。
    final response = await _apiClient.post<AuthSession>(
      '/auth/login',
      data: <String, String>{'username': username, 'password': password},
      parseData: _parseSession,
    );
    return response.data;
  }

  Future<AuthSession> register(
    String username,
    String password,
    String displayName,
  ) async {
    // 注册成功后后端直接返回会话，客户端可以立即进入已登录状态。
    final response = await _apiClient.post<AuthSession>(
      '/auth/register',
      data: <String, String>{
        'username': username,
        'password': password,
        'display_name': displayName,
      },
      parseData: _parseSession,
    );
    return response.data;
  }

  Future<AuthUser> getCurrentUser() async {
    // 用当前 Token 查询用户，用于 App 重启后恢复登录状态。
    final response = await _apiClient.get<AuthUser>(
      '/auth/me',
      parseData: (value) => AuthUser.fromJson(
        value is Map
            ? Map<String, Object?>.from(value)
            : const <String, Object?>{},
      ),
    );
    return response.data;
  }

  AuthSession _parseSession(Object? value) {
    // 后端 data 不是对象时主动抛出格式异常，避免后面出现难定位的类型错误。
    if (value is! Map) throw const FormatException('登录响应格式不正确');
    return AuthSession.fromJson(Map<String, Object?>.from(value));
  }
}
