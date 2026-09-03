import '../../domain/repositories/auth_repository.dart';
import '../datasources/auth_remote_data_source.dart';
import '../models/auth_session.dart';

class AuthRepositoryImpl implements AuthRepository {
  const AuthRepositoryImpl(this._dataSource);

  final AuthRemoteDataSource _dataSource;

  @override
  Future<AuthSession> login(String username, String password) =>
      _dataSource.login(username, password);

  @override
  Future<AuthSession> register(
    String username,
    String password,
    String displayName,
  ) => _dataSource.register(username, password, displayName);

  @override
  Future<AuthUser> getCurrentUser() => _dataSource.getCurrentUser();
}
