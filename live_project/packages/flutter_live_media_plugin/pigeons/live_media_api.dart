import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/generated/live_media_api.g.dart',
    dartOptions: DartOptions(),
    swiftOut: 'ios/flutter_live_media_plugin/Sources/flutter_live_media_plugin/LiveMediaApi.g.swift',
    swiftOptions: SwiftOptions(),
    dartPackageName: 'flutter_live_media_plugin',
  ),
)
class LiveEngineConfiguration {
  LiveEngineConfiguration({this.enableHardwareAcceleration = true});

  bool? enableHardwareAcceleration;
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
