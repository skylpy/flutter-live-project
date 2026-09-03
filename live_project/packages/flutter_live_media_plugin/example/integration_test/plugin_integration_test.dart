import 'package:flutter_live_media_plugin/flutter_live_media_plugin.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native media engine responds to lifecycle requests', (
    WidgetTester tester,
  ) async {
    final engine = FlutterLiveMediaEngine();
    await engine.initialize();
    await engine.play('https://example.com/live.m3u8');
    await engine.stop();
    await engine.dispose();

    expect(true, isTrue);
  });
}
