import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_provider.dart';
import '../../data/datasources/live_remote_data_source.dart';
import '../../data/models/live_room.dart';
import '../../data/repositories/live_repository_impl.dart';
import '../../domain/repositories/live_repository.dart';

final liveRemoteDataSourceProvider = Provider<LiveRemoteDataSource>(
  (ref) => LiveRemoteDataSource(ref.watch(apiClientProvider)),
);

final liveRepositoryProvider = Provider<LiveRepository>(
  (ref) => LiveRepositoryImpl(ref.watch(liveRemoteDataSourceProvider)),
);

final liveListControllerProvider =
    AsyncNotifierProvider<LiveListController, List<LiveRoom>>(
      LiveListController.new,
    );

class LiveListController extends AsyncNotifier<List<LiveRoom>> {
  LiveRepository get _repository => ref.read(liveRepositoryProvider);

  @override
  Future<List<LiveRoom>> build() => _repository.getLiveRooms();

  Future<void> refreshRooms() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_repository.getLiveRooms);
  }
}
