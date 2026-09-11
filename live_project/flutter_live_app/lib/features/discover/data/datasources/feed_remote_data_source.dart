import '../../../../core/network/api_client.dart';
import '../models/feed_post.dart';

/// 动态 REST 数据来源。
///
/// 页面不直接知道 `/feed/posts` 的路径和 JSON 字段；将来增加分页、缓存或
/// 图片地址时，只改这一层和模型，Controller/UI 的职责不变。
class FeedRemoteDataSource {
  const FeedRemoteDataSource(this._apiClient);

  final ApiClient _apiClient;

  Future<List<FeedPost>> getPosts(String tab) async {
    final response = await _apiClient.get<List<FeedPost>>(
      '/feed/posts?tab=${Uri.encodeQueryComponent(tab)}',
      parseData: (value) {
        final items = value is List ? value : const <Object?>[];
        return items
            .whereType<Map>()
            .map((item) => FeedPost.fromJson(Map<String, Object?>.from(item)))
            .toList(growable: false);
      },
    );
    return response.data;
  }

  Future<FeedInteraction> toggleLike(int postId) async {
    final response = await _apiClient.post<FeedInteraction>(
      '/feed/posts/$postId/like',
      parseData: (value) => FeedInteraction.fromJson(value),
    );
    return response.data;
  }

  Future<FeedPost> getPost(int postId) async {
    final response = await _apiClient.get<FeedPost>(
      '/feed/posts/$postId',
      parseData: (value) =>
          FeedPost.fromJson(Map<String, Object?>.from(value as Map)),
    );
    return response.data;
  }

  Future<List<FeedComment>> getComments(int postId) async {
    final response = await _apiClient.get<List<FeedComment>>(
      '/feed/posts/$postId/comments',
      parseData: (value) => (value is List ? value : const <Object?>[])
          .whereType<Map>()
          .map((item) => FeedComment.fromJson(Map<String, Object?>.from(item)))
          .toList(growable: false),
    );
    return response.data;
  }

  Future<FeedComment> createComment({
    required int postId,
    required String body,
    int? parentId,
  }) async {
    final data = <String, Object?>{'body': body};
    if (parentId != null) data['parent_id'] = parentId;
    final response = await _apiClient.post<FeedComment>(
      '/feed/posts/$postId/comments',
      data: data,
      parseData: (value) =>
          FeedComment.fromJson(Map<String, Object?>.from(value as Map)),
    );
    return response.data;
  }

  Future<void> deletePost(int postId) =>
      _apiClient.delete('/feed/posts/$postId');

  Future<FeedAuthorProfile> getAuthorProfile(int userId) async {
    final response = await _apiClient.get<FeedAuthorProfile>(
      '/feed/users/$userId',
      parseData: (value) =>
          FeedAuthorProfile.fromJson(Map<String, Object?>.from(value as Map)),
    );
    return response.data;
  }

  Future<FeedInteraction> toggleUserFollow(int userId) async {
    final response = await _apiClient.post<FeedInteraction>(
      '/users/$userId/follow',
      parseData: FeedInteraction.fromJson,
    );
    return response.data;
  }

  Future<FeedPost> createPost({
    required String body,
    required List<int> fileIds,
  }) async {
    final response = await _apiClient.post<FeedPost>(
      '/feed/posts',
      data: {'body': body, 'file_ids': fileIds},
      parseData: (value) =>
          FeedPost.fromJson(Map<String, Object?>.from(value as Map)),
    );
    return response.data;
  }
}
