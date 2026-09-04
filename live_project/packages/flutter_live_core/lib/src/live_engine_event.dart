import 'package:meta/meta.dart';

enum LiveEngineEventType {
  initialized,
  playRequested,
  playing,
  buffering,
  completed,
  reconnecting,
  stopped,
  previewRequested,
  pushRequested,
  pushStopped,
  error,
}

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
