import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_live_core/flutter_live_core.dart';

import 'src/generated/live_media_api.g.dart';
import 'src/player_view_stub.dart'
    if (dart.library.ohos) 'src/player_view_ohos.dart'
    as platform_view;

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
    return platform_view.buildLiveMediaPlayerView();
  }
}

/// 主播端摄像头预览视图。
///
/// Android 使用原生 SurfaceView 接收 Camera2 的画面；iOS 使用 HaishinKit 的
/// HKView 接收 AVCaptureVideoPreviewLayer。两个平台都把“采集预览”和“推流控制”
/// 放在插件内，Flutter 开播页只依赖统一的 LiveEngine 接口。
final class FlutterLiveMediaPublisherView extends StatelessWidget {
  const FlutterLiveMediaPublisherView({super.key});

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.android) {
      // 主播预览只负责显示摄像头画面，不需要接收触摸事件。
      // Android 的 SurfaceView 在部分真机上会把自身的原生布局区域报告得比
      // Flutter 约束更大；如果让它参与命中测试，可能挡住下面的标题输入框和
      // “开始直播”按钮。忽略它的触摸命中后，画面仍然渲染，但输入事件继续
      // 交给 Flutter 表单处理。
      return const IgnorePointer(
        child: AndroidView(viewType: 'flutter_live_media_publisher_view'),
      );
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      // iOS 使用 HaishinKit 的 HKView 显示同一个 RTMPStream 的采集画面。
      // 预览和推流共享采集会话，避免为了预览再创建第二个 AVCaptureSession。
      return const UiKitView(viewType: 'flutter_live_media_publisher_view');
    }
    return const ColoredBox(
      color: Color(0xFF111111),
      child: Center(
        child: Text(
          '摄像头预览将在原生推流模块中显示',
          style: TextStyle(color: Color(0xFFBDBDBD)),
        ),
      ),
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
    // 真机联调时把原生事件打印到 flutter run 控制台，便于确认 Pigeon
    // 回调是否经过“原生播放器 → 插件 → Flutter 页面”完整链路。
    debugPrint(
      '[FlutterLiveMedia] native event=${event.type} '
      'message=${event.message} retry=${event.retryCount}',
    );
    // 原生枚举和 core 枚举值分开定义，避免 core 包依赖任何平台代码。
    final type = switch (event.type) {
      LiveMediaEventType.initialized => LiveEngineEventType.initialized,
      LiveMediaEventType.playing => LiveEngineEventType.playing,
      LiveMediaEventType.buffering => LiveEngineEventType.buffering,
      LiveMediaEventType.completed => LiveEngineEventType.completed,
      LiveMediaEventType.reconnecting => LiveEngineEventType.reconnecting,
      LiveMediaEventType.stopped => LiveEngineEventType.stopped,
      LiveMediaEventType.previewStarted => LiveEngineEventType.previewStarted,
      LiveMediaEventType.pushConnecting => LiveEngineEventType.pushConnecting,
      LiveMediaEventType.pushStarted => LiveEngineEventType.pushStarted,
      LiveMediaEventType.pushStopped => LiveEngineEventType.pushStopped,
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
    final accepted = await _api.startPreview();
    if (!accepted) {
      _emit(LiveEngineEventType.error, '原生摄像头预览启动失败');
      return;
    }
    _emit(LiveEngineEventType.previewRequested, '已发送摄像头预览请求');
  }

  @override
  Future<void> startPush(String url) async {
    _ensureUsable();
    if (url.trim().isEmpty) {
      _emit(LiveEngineEventType.error, '推流地址为空');
      return;
    }
    final accepted = await _api.startPush(url);
    if (!accepted) {
      _emit(LiveEngineEventType.error, '原生推流启动失败');
      return;
    }
    _emit(LiveEngineEventType.pushRequested, '已发送原生推流请求');
  }

  @override
  Future<void> stopPush() async {
    _ensureUsable();
    final stopped = await _api.stopPush();
    if (!stopped) {
      _emit(LiveEngineEventType.error, '停止原生推流失败');
      return;
    }
    _emit(LiveEngineEventType.pushStopped, '已发送停止推流请求');
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
