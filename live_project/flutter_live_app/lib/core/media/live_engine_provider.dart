import 'package:flutter_live_core/flutter_live_core.dart';
import 'package:flutter_live_media_plugin/flutter_live_media_plugin.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Shared media-engine boundary for the application.
///
/// The plugin currently talks to a native placeholder implementation. The
/// provider keeps that platform adapter out of feature widgets.
final liveEngineProvider = Provider<LiveEngine>((ref) {
  final engine = FlutterLiveMediaEngine();
  ref.onDispose(engine.dispose);
  return engine;
});
