import '../models/feed_post.dart';

/// 动态业务对外暴露的最小契约。
abstract interface class FeedRepository {
  Future<List<FeedPost>> getPosts(String tab);

  Future<FeedInteraction> toggleLike(int postId);

  Future<FeedPost> getPost(int postId);

  Future<List<FeedComment>> getComments(int postId);

  Future<FeedComment> createComment({
    required int postId,
    required String body,
    int? parentId,
  });

  Future<void> deletePost(int postId);

  Future<FeedAuthorProfile> getAuthorProfile(int userId);

  Future<FeedInteraction> toggleUserFollow(int userId);

  Future<FeedPost> createPost({
    required String body,
    required List<int> fileIds,
  });
}
