import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_provider.dart';
import '../../data/datasources/auth_remote_data_source.dart';
import '../../data/models/auth_session.dart';
import '../../data/repositories/auth_repository_impl.dart';
import '../../domain/repositories/auth_repository.dart';

// DataSource → Repository → Controller 的依赖通过 Provider 组装，便于替换和测试。
final authRemoteDataSourceProvider = Provider<AuthRemoteDataSource>(
  (ref) => AuthRemoteDataSource(ref.watch(apiClientProvider)),
);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepositoryImpl(ref.watch(authRemoteDataSourceProvider)),
);

/// 登录状态的 Riverpod 入口；null 表示当前没有登录用户。
final authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthSession?>(AuthController.new);

class AuthController extends AsyncNotifier<AuthSession?> {
  AuthRepository get _repository => ref.read(authRepositoryProvider);

  @override
  Future<AuthSession?> build() async {
    // App 启动时先读本地 Token，再调用 /auth/me 验证它是否仍有效。
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
    // AsyncLoading 让页面可以显示提交中的状态，AsyncValue.guard 统一捕获异常。
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
    // 退出登录只需清除本地 Token，并把状态切回 null。
    await ref.read(tokenStorageProvider).clearToken();
    state = const AsyncData(null);
  }
}
