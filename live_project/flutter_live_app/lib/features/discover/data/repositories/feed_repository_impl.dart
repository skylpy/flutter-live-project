import '../datasources/feed_remote_data_source.dart';
import '../models/feed_post.dart';
import 'feed_repository.dart';

/// 真实后端实现；页面不再依赖 FeedMockRepository。
class FeedRepositoryImpl implements FeedRepository {
  const FeedRepositoryImpl(this._dataSource);

  final FeedRemoteDataSource _dataSource;

  @override
  Future<List<FeedPost>> getPosts(String tab) => _dataSource.getPosts(tab);

  @override
  Future<FeedInteraction> toggleLike(int postId) =>
      _dataSource.toggleLike(postId);

  @override
  Future<FeedPost> getPost(int postId) => _dataSource.getPost(postId);

  @override
  Future<List<FeedComment>> getComments(int postId) =>
      _dataSource.getComments(postId);

  @override
  Future<FeedComment> createComment({
    required int postId,
    required String body,
    int? parentId,
  }) =>
      _dataSource.createComment(postId: postId, body: body, parentId: parentId);

  @override
  Future<void> deletePost(int postId) => _dataSource.deletePost(postId);

  @override
  Future<FeedAuthorProfile> getAuthorProfile(int userId) =>
      _dataSource.getAuthorProfile(userId);

  @override
  Future<FeedInteraction> toggleUserFollow(int userId) =>
      _dataSource.toggleUserFollow(userId);

  @override
  Future<FeedPost> createPost({
    required String body,
    required List<int> fileIds,
  }) => _dataSource.createPost(body: body, fileIds: fileIds);
}
