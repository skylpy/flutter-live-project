import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_provider.dart';
import '../../data/datasources/profile_remote_data_source.dart';
import '../../data/models/profile.dart';
import '../../data/repositories/profile_repository.dart';
import '../../data/repositories/profile_repository_impl.dart';

final profileRepositoryProvider = Provider<ProfileRepository>(
  (ref) => ProfileRepositoryImpl(
    ProfileRemoteDataSource(ref.watch(apiClientProvider)),
  ),
);

final profileControllerProvider =
    AsyncNotifierProvider<ProfileController, Profile?>(ProfileController.new);

/// Profile 页面通过 Controller 读取真实资料，未登录时保持匿名状态。
class ProfileController extends AsyncNotifier<Profile?> {
  @override
  Future<Profile?> build() async {
    final token = await ref.read(tokenStorageProvider).readToken();
    if (token == null || token.isEmpty) return null;
    return ref.read(profileRepositoryProvider).getProfile();
  }

  Future<void> updateDisplayName(String displayName) async {
    state = await AsyncValue.guard<Profile?>(
      () => ref.read(profileRepositoryProvider).updateDisplayName(displayName),
    );
  }
}
