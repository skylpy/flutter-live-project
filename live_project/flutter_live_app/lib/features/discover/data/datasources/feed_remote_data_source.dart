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
}
