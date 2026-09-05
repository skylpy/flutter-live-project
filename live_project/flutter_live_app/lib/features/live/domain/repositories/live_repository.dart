import '../../data/models/live_room.dart';

/// 直播业务需要的最小数据接口。
///
/// 把接口放在 domain 层，可以让上层业务与 Dio、JSON 和具体网络实现解耦。
abstract interface class LiveRepository {
  Future<List<LiveRoom>> getLiveRooms();

  Future<LiveRoom> getLiveRoomDetail(String roomId);

  Future<LiveRoom> createLiveRoom({
    required String title,
    required String anchorName,
    required String category,
  });

  Future<LiveRoom> startLiveRoom(String roomId);

  Future<LiveRoom> stopLiveRoom(String roomId);
}
