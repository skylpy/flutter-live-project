import '../../data/models/auth_session.dart';

abstract interface class AuthRepository {
  Future<AuthSession> login(String username, String password);

  Future<AuthSession> register(
    String username,
    String password,
    String displayName,
  );

  Future<AuthUser> getCurrentUser();
}
