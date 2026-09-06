import 'dart:async';

import 'package:flutter/foundation.dart';

/// 全局登录过期事件总线。
///
/// 网络层不能直接依赖页面导航，否则 DataSource 会和 Flutter UI 强耦合。
/// 因此 ApiClient 只发布“登录已失效”事件，App 根节点再负责跳转登录页。
class AuthExpiredEventBus {
  final StreamController<void> _controller = StreamController<void>.broadcast();

  Stream<void> get events => _controller.stream;

  void emit() {
    if (!_controller.isClosed) {
      debugPrint('[AuthExpiredEventBus] 401 -> notify login redirect');
      _controller.add(null);
    }
  }
}
