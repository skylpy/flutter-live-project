import '../../domain/repositories/live_repository.dart';
import '../datasources/live_remote_data_source.dart';
import '../models/live_room.dart';

/// LiveRepository 的 HTTP 实现。
///
/// 上层只依赖 domain 接口，不知道数据实际来自 REST、缓存还是本地 Mock。
class LiveRepositoryImpl implements LiveRepository {
  const LiveRepositoryImpl(this._dataSource);

  final LiveRemoteDataSource _dataSource;

  @override
  Future<List<LiveRoom>> getLiveRooms() => _dataSource.getLiveRooms();

  @override
  Future<LiveRoom> getLiveRoomDetail(String roomId) =>
      _dataSource.getLiveRoomDetail(roomId);
}
