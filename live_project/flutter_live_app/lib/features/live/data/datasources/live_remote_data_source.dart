import '../../../../core/network/api_client.dart';
import '../models/live_room.dart';

/// 直播间 REST 数据来源。
///
/// 这里只负责接口路径和 JSON 转换，不管理 loading/error 状态，也不直接更新 UI。
class LiveRemoteDataSource {
  const LiveRemoteDataSource(this._apiClient);

  final ApiClient _apiClient;

  Future<List<LiveRoom>> getLiveRooms() async {
    // data 不是数组时按空列表处理，让页面可以正常显示空状态。
    final response = await _apiClient.get<List<LiveRoom>>(
      '/live/rooms',
      parseData: (value) {
        final items = value is List ? value : const <Object?>[];
        return items
            .whereType<Map>()
            .map((item) => LiveRoom.fromJson(Map<String, Object?>.from(item)))
            .toList(growable: false);
      },
    );
    return response.data;
  }

  Future<LiveRoom> getLiveRoomDetail(String roomId) async {
    // 详情单独请求，保证从深链接进入直播间时也能获得最新数据。
    final response = await _apiClient.get<LiveRoom>(
      '/live/rooms/$roomId',
      parseData: (value) {
        if (value is! Map) {
          throw const FormatException('直播间详情格式不正确');
        }
        return LiveRoom.fromJson(Map<String, Object?>.from(value));
      },
    );
    return response.data;
  }
}
