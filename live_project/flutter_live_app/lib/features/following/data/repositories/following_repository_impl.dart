import '../datasources/following_remote_data_source.dart';
import '../models/followed_user.dart';
import 'following_repository.dart';

class FollowingRepositoryImpl implements FollowingRepository {
  const FollowingRepositoryImpl(this._dataSource);

  final FollowingRemoteDataSource _dataSource;

  @override
  Future<List<FollowedUser>> getFollowing() => _dataSource.getFollowing();
}
