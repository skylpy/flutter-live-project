import '../models/feed_post.dart';
import 'feed_repository.dart';

/// 动态页的稳定演示数据源。
class FeedMockRepository implements FeedRepository {
  const FeedMockRepository();

  static const _posts = <FeedPost>[
    FeedPost(
      id: 1,
      authorId: 1,
      author: '小猫软糖',
      body: '生活碎片 ✨ 今天也要开心地发光呀～',
      timeLabel: '3 分钟前',
      likes: 128,
      comments: 32,
      shares: 8,
      liked: false,
      mediaKind: FeedMediaKind.portrait,
    ),
    FeedPost(
      id: 2,
      authorId: 2,
      author: '雾里听风',
      body: '晚风很温柔，而你刚好出现 🌙',
      timeLabel: '5 小时前',
      likes: 286,
      comments: 68,
      shares: 16,
      liked: true,
      mediaKind: FeedMediaKind.landscape,
    ),
    FeedPost(
      id: 3,
      authorId: 1,
      author: '小猫软糖',
      body: '新歌练习中，有喜欢听的歌可以告诉我～',
      timeLabel: '昨天',
      likes: 64,
      comments: 12,
      shares: 3,
      liked: false,
      mediaKind: FeedMediaKind.none,
    ),
  ];

  @override
  Future<List<FeedPost>> getPosts(String tab) async => _posts;

  @override
  Future<FeedInteraction> toggleLike(int postId) async =>
      FeedInteraction(active: false, count: 0);

  @override
  Future<FeedPost> getPost(int postId) => throw UnimplementedError();

  @override
  Future<List<FeedComment>> getComments(int postId) =>
      throw UnimplementedError();

  @override
  Future<FeedComment> createComment({
    required int postId,
    required String body,
  }) => throw UnimplementedError();

  @override
  Future<void> deletePost(int postId) => throw UnimplementedError();

  @override
  Future<FeedAuthorProfile> getAuthorProfile(int userId) =>
      throw UnimplementedError();

  @override
  Future<FeedInteraction> toggleUserFollow(int userId) =>
      throw UnimplementedError();

  @override
  Future<FeedPost> createPost({
    required String body,
    required List<int> fileIds,
  }) => throw UnimplementedError('演示数据源不支持发布动态');
}
