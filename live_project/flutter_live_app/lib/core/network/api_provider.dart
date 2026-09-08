import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'auth_expired_event_bus.dart';
import '../auth/token_storage.dart';
import '../realtime/realtime_notification_client.dart';

// Provider 是依赖注入入口，页面不需要自己创建 ApiClient 或 TokenStorage。
final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());

final authExpiredEventBusProvider = Provider<AuthExpiredEventBus>(
  (ref) => AuthExpiredEventBus(),
);

/// 全局复用 ApiClient，避免每个页面重复创建 Dio 和拦截器。
final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(
    ref.watch(tokenStorageProvider),
    ref.watch(authExpiredEventBusProvider),
  ),
);

final realtimeNotificationClientProvider = Provider<RealtimeNotificationClient>(
  (ref) {
    final client = RealtimeNotificationClient(ref.watch(tokenStorageProvider));
    ref.onDispose(() => client.dispose());
    return client;
  },
);
