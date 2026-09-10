import 'package:flutter_live_core/flutter_live_core.dart';
import 'package:flutter_live_media_plugin/flutter_live_media_plugin.dart';
import 'package:flutter_live_media_plugin/src/generated/live_media_api.g.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeLiveMediaHostApi extends LiveMediaHostApi {
  _FakeLiveMediaHostApi({this.previewAccepted = true});

  final bool previewAccepted;
  int initializeCalls = 0;
  int playCalls = 0;
  int stopCalls = 0;
  int startPreviewCalls = 0;
  int startPushCalls = 0;
  int switchCameraCalls = 0;
  int setBeautySettingsCalls = 0;
  int stopPushCalls = 0;
  LiveBeautyConfiguration? lastBeautyConfiguration;

  @override
  Future<bool> initialize(LiveEngineConfiguration configuration) async {
    initializeCalls++;
    return true;
  }

  @override
  Future<bool> play(String url) async {
    playCalls++;
    return true;
  }

  @override
  Future<bool> stop() async {
    stopCalls++;
    return true;
  }

  @override
  Future<bool> startPreview() async {
    startPreviewCalls++;
    return previewAccepted;
  }

  @override
  Future<bool> startPush(String url) async {
    startPushCalls++;
    return true;
  }

  @override
  Future<bool> switchCamera() async {
    switchCameraCalls++;
    return true;
  }

  @override
  Future<bool> setBeautySettings(LiveBeautyConfiguration configuration) async {
    setBeautySettingsCalls++;
    lastBeautyConfiguration = configuration;
    return true;
  }

  @override
  Future<bool> stopPush() async {
    stopPushCalls++;
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('engine delegates playback lifecycle to the host API', () async {
    final api = _FakeLiveMediaHostApi();
    final engine = FlutterLiveMediaEngine(api: api);
    final events = <LiveEngineEvent>[];
    final subscription = engine.events.listen(events.add);

    await engine.initialize();
    await engine.play('https://example.com/live.m3u8');
    await engine.stop();
    await Future<void>.delayed(Duration.zero);

    expect(api.initializeCalls, 1);
    expect(api.playCalls, 1);
    expect(api.stopCalls, 1);
    expect(
      events.map((event) => event.type),
      containsAllInOrder([
        LiveEngineEventType.initialized,
        LiveEngineEventType.playRequested,
        LiveEngineEventType.stopped,
      ]),
    );

    await subscription.cancel();
    await engine.dispose();
  });

  test(
    'engine stops the broadcast flow when native capture setup is rejected',
    () async {
      final api = _FakeLiveMediaHostApi(previewAccepted: false);
      final engine = FlutterLiveMediaEngine(api: api);
      final events = <LiveEngineEvent>[];
      final subscription = engine.events.listen(events.add);

      await expectLater(engine.startPreview(), throwsA(isA<StateError>()));
      await Future<void>.delayed(Duration.zero);

      expect(api.startPreviewCalls, 1);
      expect(
        events.map((event) => event.type),
        contains(LiveEngineEventType.error),
      );

      await subscription.cancel();
      await engine.dispose();
    },
  );

  test(
    'engine forwards normalized beauty settings to the native GPU pipeline',
    () async {
      final api = _FakeLiveMediaHostApi();
      final engine = FlutterLiveMediaEngine(api: api);

      await engine.setBeautySettings(
        const LiveBeautySettings(
          smoothing: 1.2,
          whitening: 0.35,
          rosiness: -0.2,
          faceSlimming: 0.45,
          filterStrength: 0.6,
        ),
      );

      expect(api.setBeautySettingsCalls, 1);
      expect(api.lastBeautyConfiguration?.smoothing, 1);
      expect(api.lastBeautyConfiguration?.whitening, 0.35);
      expect(api.lastBeautyConfiguration?.rosiness, 0);
      expect(api.lastBeautyConfiguration?.faceSlimming, 0.45);
      expect(api.lastBeautyConfiguration?.filterStrength, 0.6);

      await engine.dispose();
    },
  );
}
