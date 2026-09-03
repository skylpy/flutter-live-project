import '../../../../core/network/api_client.dart';
import '../models/live_room.dart';

class LiveRemoteDataSource {
  const LiveRemoteDataSource(this._apiClient);

  final ApiClient _apiClient;

  Future<List<LiveRoom>> getLiveRooms() async {
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
