import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/environment.dart';
import '../../../../core/network/api_provider.dart';
import '../../data/datasources/live_remote_data_source.dart';
import '../../data/models/live_room.dart';
import '../../data/repositories/live_mock_repository.dart';
import '../../data/repositories/live_repository_impl.dart';
import '../../domain/repositories/live_repository.dart';

// 依赖链：ApiClient → DataSource → Repository → Controller → Page。
final liveRemoteDataSourceProvider = Provider<LiveRemoteDataSource>(
  (ref) => LiveRemoteDataSource(ref.watch(apiClientProvider)),
);

final liveRepositoryProvider = Provider<LiveRepository>((ref) {
  // Mock 只由编译参数显式打开，默认仍然使用真实后端，避免联调开关
  // 不小心影响测试包或生产包的数据来源。
  if (Environment.useMockLiveData) {
    return const LiveMockRepository();
  }
  return LiveRepositoryImpl(ref.watch(liveRemoteDataSourceProvider));
});

/// 首页直播列表的 Riverpod 状态入口。
final liveListControllerProvider =
    AsyncNotifierProvider<LiveListController, List<LiveRoom>>(
      LiveListController.new,
    );

class LiveListController extends AsyncNotifier<List<LiveRoom>> {
  LiveRepository get _repository => ref.read(liveRepositoryProvider);

  @override
  Future<List<LiveRoom>> build() {
    // AsyncNotifier 会自动把 Future 的过程转换为 loading/data/error 状态。
    return _repository.getLiveRooms();
  }

  Future<void> refreshRooms() async {
    // 下拉刷新沿用同一 Repository，不复制一套请求逻辑。
    state = const AsyncLoading();
    state = await AsyncValue.guard(_repository.getLiveRooms);
  }
}
