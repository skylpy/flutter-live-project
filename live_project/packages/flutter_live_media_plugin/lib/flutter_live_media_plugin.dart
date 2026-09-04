import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_live_core/flutter_live_core.dart';

import 'src/generated/live_media_api.g.dart';

/// Embeds the registered native player view on supported native platforms.
final class FlutterLiveMediaPlayerView extends StatelessWidget {
  const FlutterLiveMediaPlayerView({super.key});

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return const UiKitView(viewType: 'flutter_live_media_player_view');
    }
    if (defaultTargetPlatform == TargetPlatform.macOS) {
      return const AppKitView(viewType: 'flutter_live_media_player_view');
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return const AndroidView(viewType: 'flutter_live_media_player_view');
    }
    return const ColoredBox(
      color: Color(0xFF080808),
      child: Center(child: Text('原生播放器视图待支持当前平台')),
    );
  }
}

/// Flutter 侧的跨平台媒体引擎适配器。
///
/// 原生侧拥有真正的播放器对象：Apple 使用 AVPlayer，Android 使用 ExoPlayer。
/// 本类只负责调用生成的 Pigeon HostApi、接收事件并转换成 [LiveEngineEvent]，
/// 所以业务页面不需要知道具体原生 SDK。
final class FlutterLiveMediaEngine implements LiveEngine {
  FlutterLiveMediaEngine({LiveMediaHostApi? api})
    : _api = api ?? LiveMediaHostApi() {
    // 注册全局 FlutterApi 回调，让原生层可以把播放状态传回来。
    LiveMediaFlutterApi.setUp(_NativeEventHandler(_handleNativeEvent));
  }

  final LiveMediaHostApi _api;
  final StreamController<LiveEngineEvent> _events =
      StreamController<LiveEngineEvent>.broadcast();
  bool _disposed = false;

  @override
  Stream<LiveEngineEvent> get events => _events.stream;

  @override
  Future<void> initialize() async {
    _ensureUsable();
    // Pigeon 会把 Dart 对象编码成平台消息，再由原生实现执行初始化。
    final initialized = await _api.initialize(LiveEngineConfiguration());
    if (!initialized) {
      _emit(LiveEngineEventType.error, '原生媒体引擎初始化失败');
      return;
    }
    _emit(LiveEngineEventType.initialized, '原生媒体引擎已初始化');
  }

  void _handleNativeEvent(LiveMediaEvent event) {
    // 原生枚举和 core 枚举值分开定义，避免 core 包依赖任何平台代码。
    final type = switch (event.type) {
      LiveMediaEventType.initialized => LiveEngineEventType.initialized,
      LiveMediaEventType.playing => LiveEngineEventType.playing,
      LiveMediaEventType.buffering => LiveEngineEventType.buffering,
      LiveMediaEventType.completed => LiveEngineEventType.completed,
      LiveMediaEventType.reconnecting => LiveEngineEventType.reconnecting,
      LiveMediaEventType.stopped => LiveEngineEventType.stopped,
      LiveMediaEventType.error => LiveEngineEventType.error,
    };
    final message = event.message ?? '原生播放器状态已更新';
    final retryMessage = event.retryCount == null
        ? message
        : '$message（第 ${event.retryCount} 次）';
    _emit(type, retryMessage);
  }

  @override
  Future<void> play(String url) async {
    _ensureUsable();
    if (url.trim().isEmpty) {
      _emit(LiveEngineEventType.error, '播放地址为空');
      return;
    }
    // “请求已发送”和“真正开始播放”是两个状态；playing 由原生播放器回调。
    final accepted = await _api.play(url);
    if (!accepted) {
      _emit(LiveEngineEventType.error, '原生播放器不支持该播放地址');
      return;
    }
    _emit(LiveEngineEventType.playRequested, '已发送原生播放请求');
  }

  @override
  Future<void> stop() async {
    _ensureUsable();
    final stopped = await _api.stop();
    if (!stopped) {
      _emit(LiveEngineEventType.error, '停止原生播放器失败');
      return;
    }
    _emit(LiveEngineEventType.stopped, '已发送停止播放请求');
  }

  @override
  Future<void> startPreview() async {
    _ensureUsable();
    _emit(LiveEngineEventType.previewRequested, '预览能力待接入');
  }

  @override
  Future<void> startPush(String url) async {
    _ensureUsable();
    _emit(LiveEngineEventType.pushRequested, '推流能力待接入');
  }

  @override
  Future<void> stopPush() async {
    _ensureUsable();
    _emit(LiveEngineEventType.pushStopped, '停止推流能力待接入');
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    // 解除 Pigeon 回调并关闭事件流，防止原生异步事件继续访问已销毁对象。
    LiveMediaFlutterApi.setUp(null);
    await _events.close();
  }

  void _emit(LiveEngineEventType type, String message) {
    _events.add(
      LiveEngineEvent(type: type, message: message, timestamp: DateTime.now()),
    );
  }

  void _ensureUsable() {
    if (_disposed) throw StateError('FlutterLiveMediaEngine 已释放');
  }
}

final class _NativeEventHandler extends LiveMediaFlutterApi {
  _NativeEventHandler(this.callback);

  final void Function(LiveMediaEvent event) callback;

  @override
  void onEvent(LiveMediaEvent event) => callback(event);
}
