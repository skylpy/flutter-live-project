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

/// Flutter 传给原生 GPU 管线的实时美颜参数，所有数值均为 0.0 到 1.0。
class LiveBeautyConfiguration {
  LiveBeautyConfiguration({
    required this.smoothing,
    required this.whitening,
    required this.rosiness,
    required this.faceSlimming,
    required this.filterStrength,
  });

  double smoothing;
  double whitening;
  double rosiness;
  double faceSlimming;
  double filterStrength;
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

  // Flutter → 原生：切换主播前后摄像头。
  @async
  bool switchCamera();

  // Flutter → 原生：更新编码前 GPU 美颜参数。
  @async
  bool setBeautySettings(LiveBeautyConfiguration configuration);

  @async
  bool stopPush();
}

@FlutterApi()
abstract class LiveMediaFlutterApi {
  // 原生 → Flutter：播放和推流状态回调。
  void onEvent(LiveMediaEvent event);
}
