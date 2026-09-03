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
/// The native side currently exposes a placeholder PlatformView and records
/// lifecycle requests only. A real player can be introduced without changing
/// the [LiveEngine] contract used by the application.
final class FlutterLiveMediaEngine implements LiveEngine {
  FlutterLiveMediaEngine({LiveMediaHostApi? api})
    : _api = api ?? LiveMediaHostApi();

  final LiveMediaHostApi _api;
  final StreamController<LiveEngineEvent> _events =
      StreamController<LiveEngineEvent>.broadcast();
  bool _disposed = false;

  @override
  Stream<LiveEngineEvent> get events => _events.stream;

  @override
  Future<void> initialize() async {
    _ensureUsable();
    await _api.initialize(LiveEngineConfiguration());
    _emit(LiveEngineEventType.initialized, '原生媒体引擎已初始化');
  }

  @override
  Future<void> play(String url) async {
    _ensureUsable();
    if (url.trim().isEmpty) {
      _emit(LiveEngineEventType.error, '播放地址为空');
      return;
    }
    await _api.play(url);
    _emit(LiveEngineEventType.playRequested, '已发送原生播放请求');
  }

  @override
  Future<void> stop() async {
    _ensureUsable();
    await _api.stop();
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
