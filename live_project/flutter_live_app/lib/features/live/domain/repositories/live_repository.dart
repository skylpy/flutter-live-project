import '../../data/models/live_room.dart';

abstract interface class LiveRepository {
  Future<List<LiveRoom>> getLiveRooms();

  Future<LiveRoom> getLiveRoomDetail(String roomId);
}
