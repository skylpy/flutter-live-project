import '../../../../core/network/api_client.dart';
import '../models/auth_session.dart';

class AuthRemoteDataSource {
  const AuthRemoteDataSource(this._apiClient);

  final ApiClient _apiClient;

  Future<AuthSession> login(String username, String password) async {
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
    if (value is! Map) throw const FormatException('登录响应格式不正确');
    return AuthSession.fromJson(Map<String, Object?>.from(value));
  }
}
