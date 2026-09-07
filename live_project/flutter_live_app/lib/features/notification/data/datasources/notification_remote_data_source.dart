import '../../../../core/network/api_client.dart';
import '../models/notification_item.dart';

class NotificationRemoteDataSource {
  const NotificationRemoteDataSource(this._apiClient);

  final ApiClient _apiClient;

  Future<List<NotificationItem>> getNotifications() async {
    final response = await _apiClient.get<List<NotificationItem>>(
      '/notifications',
      parseData: (value) {
        final items = value is List ? value : const <Object?>[];
        return items
            .whereType<Map>()
            .map(
              (item) =>
                  NotificationItem.fromJson(Map<String, Object?>.from(item)),
            )
            .toList(growable: false);
      },
    );
    return response.data;
  }

  Future<void> markAllRead() async {
    await _apiClient.post<Object?>(
      '/notifications/read',
      parseData: (_) => null,
    );
  }
}
