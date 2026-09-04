import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/generated/live_media_api.g.dart',
    dartOptions: DartOptions(),
    kotlinOut: 'android/src/main/kotlin/com/skylpy/flutter_live_media_plugin/LiveMediaApi.g.kt',
    kotlinOptions: KotlinOptions(
      package: 'com.skylpy.flutter_live_media_plugin',
    ),
    swiftOut: 'ios/flutter_live_media_plugin/Sources/flutter_live_media_plugin/LiveMediaApi.g.swift',
    swiftOptions: SwiftOptions(),
    dartPackageName: 'flutter_live_media_plugin',
  ),
)
class LiveEngineConfiguration {
  LiveEngineConfiguration({this.enableHardwareAcceleration = true});

  bool? enableHardwareAcceleration;
}

enum LiveMediaEventType {
  initialized,
  playing,
  buffering,
  completed,
  reconnecting,
  stopped,
  error,
}

class LiveMediaEvent {
  LiveMediaEvent({required this.type, this.message, this.retryCount});

  LiveMediaEventType type;
  String? message;
  int? retryCount;
}

@HostApi()
abstract class LiveMediaHostApi {
  @async
  bool initialize(LiveEngineConfiguration configuration);

  @async
  bool play(String url);

  @async
  bool stop();
}

@FlutterApi()
abstract class LiveMediaFlutterApi {
  void onEvent(LiveMediaEvent event);
}
