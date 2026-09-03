import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_provider.dart';
import '../../data/datasources/auth_remote_data_source.dart';
import '../../data/models/auth_session.dart';
import '../../data/repositories/auth_repository_impl.dart';
import '../../domain/repositories/auth_repository.dart';

final authRemoteDataSourceProvider = Provider<AuthRemoteDataSource>(
  (ref) => AuthRemoteDataSource(ref.watch(apiClientProvider)),
);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepositoryImpl(ref.watch(authRemoteDataSourceProvider)),
);

final authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthSession?>(AuthController.new);

class AuthController extends AsyncNotifier<AuthSession?> {
  AuthRepository get _repository => ref.read(authRepositoryProvider);

  @override
  Future<AuthSession?> build() async {
    final token = await ref.read(tokenStorageProvider).readToken();
    if (token == null || token.isEmpty) return null;
    try {
      final user = await _repository.getCurrentUser();
      return AuthSession(accessToken: token, tokenType: 'bearer', user: user);
    } catch (_) {
      await ref.read(tokenStorageProvider).clearToken();
      return null;
    }
  }

  Future<void> login(String username, String password) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final session = await _repository.login(username, password);
      await ref.read(tokenStorageProvider).saveToken(session.accessToken);
      return session;
    });
  }

  Future<void> register(
    String username,
    String password,
    String displayName,
  ) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final session = await _repository.register(
        username,
        password,
        displayName,
      );
      await ref.read(tokenStorageProvider).saveToken(session.accessToken);
      return session;
    });
  }

  Future<void> logout() async {
    await ref.read(tokenStorageProvider).clearToken();
    state = const AsyncData(null);
  }
}
