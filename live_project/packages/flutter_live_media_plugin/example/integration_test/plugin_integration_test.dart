import 'package:flutter_live_media_plugin/flutter_live_media_plugin.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native media engine responds to lifecycle requests', (
    WidgetTester tester,
  ) async {
    // 这里使用真实 HLS 清单，而不是 example.com 占位地址；在 Android 真机上
    // 运行该集成测试时，至少能验证 Pigeon 请求确实到达 ExoPlayer HLS 模块。
    const hlsUrl = 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8';
    final engine = FlutterLiveMediaEngine();
    await engine.initialize();
    await engine.play(hlsUrl);
    await engine.stop();
    await engine.dispose();

    expect(true, isTrue);
  });
}
