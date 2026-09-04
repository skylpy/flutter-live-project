import 'live_engine_event.dart';

/// Flutter 与各平台原生媒体实现共同遵守的“最小协议”。
///
/// Flutter App 只依赖这个接口，不直接依赖 AVPlayer、ExoPlayer 或未来的直播 SDK。
/// 这样 iOS、Android、HarmonyOS 可以分别实现原生细节，但页面调用方式保持一致。
abstract interface class LiveEngine {
  /// 初始化底层播放器、渲染器和平台通信资源。
  Future<void> initialize();

  /// 播放一个直播地址；协议适配由对应平台的原生层负责。
  Future<void> play(String url);

  /// 停止当前播放。
  Future<void> stop();

  /// 请求开启预览，未来用于主播开播前的摄像头画面。
  Future<void> startPreview();

  /// 请求推流，未来用于把摄像头和麦克风推到媒体服务。
  Future<void> startPush(String url);

  /// 停止推流。
  Future<void> stopPush();

  /// 原生播放器把状态通过这个事件流传回 Flutter。
  Stream<LiveEngineEvent> get events;

  /// 释放事件流和平台资源，页面或 Provider 销毁时必须调用。
  Future<void> dispose();
}
