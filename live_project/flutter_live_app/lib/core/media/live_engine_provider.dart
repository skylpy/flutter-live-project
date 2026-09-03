import 'package:flutter_live_core/flutter_live_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shared media-engine boundary for the application.
///
/// Replace [StubLiveEngine] with a platform plugin implementation when the
/// native player and publisher are introduced.
final liveEngineProvider = Provider<LiveEngine>((ref) {
  final engine = StubLiveEngine();
  ref.onDispose(engine.dispose);
  return engine;
});
