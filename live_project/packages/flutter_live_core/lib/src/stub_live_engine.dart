import 'dart:async';

import 'live_engine.dart';
import 'live_engine_event.dart';

/// 不连接真实播放器的演示实现。
///
/// 它用于 Dart 单元测试和没有原生平台时的开发，帮助上层先验证生命周期，
/// 也说明真正的原生实现只需要遵守 [LiveEngine] 接口。
final class StubLiveEngine implements LiveEngine {
  final StreamController<LiveEngineEvent> _eventController =
      StreamController<LiveEngineEvent>.broadcast();
  bool _initialized = false;
  bool _disposed = false;

  @override
  Stream<LiveEngineEvent> get events => _eventController.stream;

  @override
  Future<void> initialize() async {
    // Stub 只发事件，不创建任何原生资源。
    _ensureUsable();
    if (_initialized) return;
    _initialized = true;
    _emit(LiveEngineEventType.initialized, 'StubLiveEngine 已初始化');
  }

  @override
  Future<void> play(String url) async {
    // 真实实现会把地址交给原生播放器；Stub 只验证参数和生命周期。
    _ensureUsable();
    await initialize();
    if (url.trim().isEmpty) {
      _emit(LiveEngineEventType.error, '播放地址为空');
      return;
    }
    _emit(LiveEngineEventType.playRequested, '已收到播放请求');
  }

  @override
  Future<void> stop() async {
    _ensureUsable();
    _emit(LiveEngineEventType.stopped, '已收到停止播放请求');
  }

  @override
  Future<void> startPreview() async {
    _ensureUsable();
    await initialize();
    _emit(LiveEngineEventType.previewRequested, '已收到预览请求');
  }

  @override
  Future<void> startPush(String url) async {
    _ensureUsable();
    await initialize();
    if (url.trim().isEmpty) {
      _emit(LiveEngineEventType.error, '推流地址为空');
      return;
    }
    _emit(LiveEngineEventType.pushRequested, '已收到推流请求');
  }

  @override
  Future<void> stopPush() async {
    _ensureUsable();
    _emit(LiveEngineEventType.pushStopped, '已收到停止推流请求');
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _eventController.close();
  }

  void _emit(LiveEngineEventType type, String message) {
    _eventController.add(
      LiveEngineEvent(type: type, message: message, timestamp: DateTime.now()),
    );
  }

  void _ensureUsable() {
    if (_disposed) {
      throw StateError('LiveEngine 已释放');
    }
  }
}
