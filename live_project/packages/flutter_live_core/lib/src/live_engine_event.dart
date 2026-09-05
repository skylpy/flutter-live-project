import 'package:meta/meta.dart';

/// 播放/推流引擎向 Flutter 汇报的状态类型。
enum LiveEngineEventType {
  initialized,
  playRequested,
  playing,
  buffering,
  completed,
  reconnecting,
  stopped,
  previewRequested,
  previewStarted,
  pushRequested,
  pushConnecting,
  pushStarted,
  pushStopped,
  error,
}

/// 一次引擎状态变化。
///
/// Flutter 不需要判断底层是 AVPlayer、ExoPlayer 还是其他 SDK，只根据
/// type 和 message 更新 UI 或业务状态。
@immutable
final class LiveEngineEvent {
  const LiveEngineEvent({required this.type, this.message, this.timestamp});

  final LiveEngineEventType type;
  final String? message;
  final DateTime? timestamp;

  @override
  String toString() {
    return 'LiveEngineEvent(type: $type, message: $message)';
  }
}
