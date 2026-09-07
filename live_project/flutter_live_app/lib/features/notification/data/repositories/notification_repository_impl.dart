import '../datasources/notification_remote_data_source.dart';
import '../models/notification_item.dart';
import 'notification_repository.dart';

class NotificationRepositoryImpl implements NotificationRepository {
  const NotificationRepositoryImpl(this._dataSource);

  final NotificationRemoteDataSource _dataSource;

  @override
  Future<List<NotificationItem>> getNotifications() =>
      _dataSource.getNotifications();

  @override
  Future<void> markAllRead() => _dataSource.markAllRead();
}
