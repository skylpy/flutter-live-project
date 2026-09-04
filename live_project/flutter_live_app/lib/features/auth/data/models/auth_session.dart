/// 服务端返回的用户资料模型。
///
/// Model 只描述数据，不负责发请求或修改 Riverpod 状态。
class AuthUser {
  const AuthUser({
    required this.id,
    required this.username,
    required this.displayName,
  });

  final int id;
  final String username;
  final String displayName;

  factory AuthUser.fromJson(Map<String, Object?> json) {
    return AuthUser(
      id: _asInt(json['id']),
      username: _asString(json['username']),
      displayName: _asString(json['displayName'] ?? json['display_name']),
    );
  }

  static int _asInt(Object? value) =>
      value is int ? value : int.tryParse('$value') ?? 0;

  static String _asString(Object? value) => value is String ? value : '';
}

/// 登录/注册成功后得到的会话模型。
///
/// Token 保存到 TokenStorage 后，后续 ApiClient 会自动把它放进请求头。
class AuthSession {
  const AuthSession({
    required this.accessToken,
    required this.tokenType,
    required this.user,
  });

  final String accessToken;
  final String tokenType;
  final AuthUser user;

  factory AuthSession.fromJson(Map<String, Object?> json) {
    final rawUser = json['user'];
    return AuthSession(
      accessToken:
          json['accessToken'] as String? ??
          json['access_token'] as String? ??
          '',
      tokenType:
          json['tokenType'] as String? ??
          json['token_type'] as String? ??
          'bearer',
      user: AuthUser.fromJson(
        rawUser is Map
            ? Map<String, Object?>.from(rawUser)
            : const <String, Object?>{},
      ),
    );
  }
}
