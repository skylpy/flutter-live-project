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
}
