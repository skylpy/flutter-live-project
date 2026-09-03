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

      await subscription.cancel();
      await engine.dispose();
    },
  );
}
