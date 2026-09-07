import '../models/followed_user.dart';

abstract interface class FollowingRepository {
  Future<List<FollowedUser>> getFollowing();
}
