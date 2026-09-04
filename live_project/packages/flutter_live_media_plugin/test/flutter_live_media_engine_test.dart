import 'package:flutter_live_core/flutter_live_core.dart';
import 'package:flutter_live_media_plugin/flutter_live_media_plugin.dart';
import 'package:flutter_live_media_plugin/src/generated/live_media_api.g.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeLiveMediaHostApi extends LiveMediaHostApi {
  int initializeCalls = 0;
  int playCalls = 0;
  int stopCalls = 0;

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
}
