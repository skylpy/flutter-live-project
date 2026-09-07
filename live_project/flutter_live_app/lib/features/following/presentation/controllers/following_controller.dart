import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_provider.dart';
import '../../data/datasources/following_remote_data_source.dart';
import '../../data/models/followed_user.dart';
import '../../data/repositories/following_repository.dart';
import '../../data/repositories/following_repository_impl.dart';

final followingRepositoryProvider = Provider<FollowingRepository>(
  (ref) => FollowingRepositoryImpl(
    FollowingRemoteDataSource(ref.watch(apiClientProvider)),
  ),
);

final followingControllerProvider =
    AsyncNotifierProvider<FollowingController, List<FollowedUser>>(
      FollowingController.new,
    );

class FollowingController extends AsyncNotifier<List<FollowedUser>> {
  @override
  Future<List<FollowedUser>> build() =>
      ref.read(followingRepositoryProvider).getFollowing();
}
