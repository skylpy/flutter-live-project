import '../../../../core/network/api_client.dart';
import '../models/followed_user.dart';

class FollowingRemoteDataSource {
  const FollowingRemoteDataSource(this._apiClient);

  final ApiClient _apiClient;

  Future<List<FollowedUser>> getFollowing() async {
    final response = await _apiClient.get<List<FollowedUser>>(
      '/following',
      parseData: (value) {
        final items = value is List ? value : const <Object?>[];
        return items
            .whereType<Map>()
            .map(
              (item) => FollowedUser.fromJson(Map<String, Object?>.from(item)),
            )
            .toList(growable: false);
      },
    );
    return response.data;
  }
}
