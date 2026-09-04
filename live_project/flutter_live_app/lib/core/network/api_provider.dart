import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import '../auth/token_storage.dart';

// Provider 是依赖注入入口，页面不需要自己创建 ApiClient 或 TokenStorage。
final tokenStorageProvider = Provider<TokenStorage>((ref) => TokenStorage());

/// 全局复用 ApiClient，避免每个页面重复创建 Dio 和拦截器。
final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(ref.watch(tokenStorageProvider)),
);
