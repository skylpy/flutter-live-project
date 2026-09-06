import '../../../../core/network/api_client.dart';
import '../models/profile.dart';

/// 个人资料 REST 数据源。
class ProfileRemoteDataSource {
  const ProfileRemoteDataSource(this._apiClient);

  final ApiClient _apiClient;

  Future<Profile> getProfile() async {
    final response = await _apiClient.get<Profile>(
      '/profile/me',
      parseData: _parseProfile,
    );
    return response.data;
  }

  Future<Profile> updateDisplayName(String displayName) async {
    final response = await _apiClient.put<Profile>(
      '/profile/me',
      data: <String, Object?>{'displayName': displayName},
      parseData: _parseProfile,
    );
    return response.data;
  }

  Profile _parseProfile(Object? value) {
    if (value is! Map) throw const FormatException('个人资料格式不正确');
    return Profile.fromJson(Map<String, Object?>.from(value));
  }
}
