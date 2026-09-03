import '../../domain/repositories/live_repository.dart';
import '../datasources/live_remote_data_source.dart';
import '../models/live_room.dart';

class LiveRepositoryImpl implements LiveRepository {
  const LiveRepositoryImpl(this._dataSource);

  final LiveRemoteDataSource _dataSource;

  @override
  Future<List<LiveRoom>> getLiveRooms() => _dataSource.getLiveRooms();

  @override
  Future<LiveRoom> getLiveRoomDetail(String roomId) =>
      _dataSource.getLiveRoomDetail(roomId);
}
