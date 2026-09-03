import 'live_engine_event.dart';

/// Platform-neutral contract for playback and publishing engines.
///
/// Implementations will live in platform plugins. The Flutter application
/// should depend on this contract instead of a concrete media SDK.
abstract interface class LiveEngine {
  Future<void> initialize();

  Future<void> play(String url);

  Future<void> stop();

  Future<void> startPreview();

  Future<void> startPush(String url);

  Future<void> stopPush();

  Stream<LiveEngineEvent> get events;

  Future<void> dispose();
}
