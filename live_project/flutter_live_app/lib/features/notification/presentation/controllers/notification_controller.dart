import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_provider.dart';
import '../../data/datasources/notification_remote_data_source.dart';
import '../../data/models/notification_item.dart';
import '../../data/repositories/notification_repository.dart';
import '../../data/repositories/notification_repository_impl.dart';

final notificationRepositoryProvider = Provider<NotificationRepository>(
  (ref) => NotificationRepositoryImpl(
    NotificationRemoteDataSource(ref.watch(apiClientProvider)),
  ),
);

final notificationControllerProvider =
    AsyncNotifierProvider<NotificationController, List<NotificationItem>>(
      NotificationController.new,
    );

class NotificationController extends AsyncNotifier<List<NotificationItem>> {
  @override
  Future<List<NotificationItem>> build() =>
      ref.read(notificationRepositoryProvider).getNotifications();

  Future<void> markAllRead() async {
    final result = await AsyncValue.guard(
      () => ref.read(notificationRepositoryProvider).markAllRead(),
    );
    if (result.hasError) return;
    final current = state.asData?.value ?? const <NotificationItem>[];
    state = AsyncData([
      for (final item in current)
        NotificationItem(
          id: item.id,
          type: item.type,
          title: item.title,
          body: item.body,
          timeLabel: item.timeLabel,
          unread: false,
        ),
    ]);
  }
}
