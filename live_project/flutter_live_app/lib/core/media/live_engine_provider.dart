import 'package:flutter_live_core/flutter_live_core.dart';
import 'package:flutter_live_media_plugin/flutter_live_media_plugin.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// App 级媒体引擎依赖入口。
///
/// 页面只依赖 [LiveEngine] 抽象，不直接依赖 ExoPlayer、AVPlayer 或 Pigeon。
/// Provider 被销毁时释放引擎，避免播放器、事件流和原生资源泄漏。
final liveEngineProvider = Provider<LiveEngine>((ref) {
  final engine = FlutterLiveMediaEngine();
  ref.onDispose(engine.dispose);
  return engine;
});
