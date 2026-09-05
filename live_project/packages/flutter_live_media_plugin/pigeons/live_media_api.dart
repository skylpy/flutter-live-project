import 'package:pigeon/pigeon.dart';

// 这是跨语言协议的唯一源文件。修改字段后重新运行 pigeon，生成 Dart、
// Swift 和 Kotlin 文件；不要直接修改生成文件，否则下次生成会被覆盖。
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
  previewStarted,
  pushConnecting,
  pushStarted,
  pushStopped,
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
  // Flutter → 原生：初始化、播放和停止请求。
  @async
  bool initialize(LiveEngineConfiguration configuration);

  @async
  bool play(String url);

  @async
  bool stop();

  // Flutter → 原生：主播端摄像头预览和 RTMP 推流请求。
  @async
  bool startPreview();

  @async
  bool startPush(String url);

  @async
  bool stopPush();
}

@FlutterApi()
abstract class LiveMediaFlutterApi {
  // 原生 → Flutter：播放和推流状态回调。
  void onEvent(LiveMediaEvent event);
}
