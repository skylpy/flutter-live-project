import '../../data/models/auth_session.dart';

/// 认证业务需要的最小数据接口。
///
/// Domain 不依赖 Dio 或具体 DataSource，这就是 Feature First 分层的边界。
abstract interface class AuthRepository {
  Future<AuthSession> login(String username, String password);

  Future<AuthSession> register(
    String username,
    String password,
    String displayName,
  );

  Future<AuthUser> getCurrentUser();
}
