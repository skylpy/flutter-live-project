import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_provider.dart';
import '../../../../core/realtime/realtime_notification_client.dart';
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
  Future<List<NotificationItem>> build() async {
    final client = ref.read(realtimeNotificationClientProvider);
    final subscription = client.events.listen(_handleRealtimeEvent);
    ref.onDispose(subscription.cancel);
    return ref.read(notificationRepositoryProvider).getNotifications();
  }

  void _handleRealtimeEvent(RealtimeNotificationEvent event) {
    if (event.type != 'notification') return;
    if (event.event == 'read_all') {
      final current = state.asData?.value;
      if (current == null) return;
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
      return;
    }
    final payload = event.notification;
    if (payload == null) return;
    final incoming = NotificationItem.fromJson(payload);
    final current = state.asData?.value ?? const <NotificationItem>[];
    if (current.any((item) => item.id == incoming.id)) return;
    state = AsyncData([incoming, ...current]);
  }

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
