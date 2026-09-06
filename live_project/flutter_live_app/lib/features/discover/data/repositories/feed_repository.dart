import '../models/feed_post.dart';

/// 动态业务对外暴露的最小契约。
abstract interface class FeedRepository {
  Future<List<FeedPost>> getPosts(String tab);

  Future<FeedInteraction> toggleLike(int postId);
}
