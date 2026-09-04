import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_live_core/flutter_live_core.dart';

import 'src/generated/live_media_api.g.dart';

/// Embeds the registered native player view on Apple platforms.
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
    return const ColoredBox(
      color: Color(0xFF080808),
      child: Center(child: Text('原生播放器视图待支持当前平台')),
    );
  }
}

/// iOS media-engine adapter.
///
/// The native side owns an AVPlayer on Apple platforms. A different player
/// implementation can be introduced without changing the [LiveEngine]
/// contract used by the application.
final class FlutterLiveMediaEngine implements LiveEngine {
  FlutterLiveMediaEngine({LiveMediaHostApi? api})
    : _api = api ?? LiveMediaHostApi() {
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
    final initialized = await _api.initialize(LiveEngineConfiguration());
    if (!initialized) {
      _emit(LiveEngineEventType.error, '原生媒体引擎初始化失败');
      return;
    }
    _emit(LiveEngineEventType.initialized, '原生媒体引擎已初始化');
  }

  void _handleNativeEvent(LiveMediaEvent event) {
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
