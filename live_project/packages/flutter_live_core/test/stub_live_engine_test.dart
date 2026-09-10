import 'package:flutter_live_core/flutter_live_core.dart';
import 'package:test/test.dart';

void main() {
  test(
    'stub engine emits lifecycle events without opening a media stream',
    () async {
      final engine = StubLiveEngine();
      final events = <LiveEngineEvent>[];
      final subscription = engine.events.listen(events.add);

      await engine.initialize();
      const beauty = LiveBeautySettings(
        smoothing: 0.7,
        whitening: 0.4,
        rosiness: 0.2,
        faceSlimming: 0.3,
        filterStrength: 0.8,
      );
      await engine.setBeautySettings(beauty);
      await engine.play('');
      await engine.stop();
      await Future<void>.delayed(Duration.zero);

      expect(
        events.map((event) => event.type),
        containsAllInOrder([
          LiveEngineEventType.initialized,
          LiveEngineEventType.error,
          LiveEngineEventType.stopped,
        ]),
      );
      expect(engine.beautySettings, beauty);

      await subscription.cancel();
      await engine.dispose();
    },
  );
}
