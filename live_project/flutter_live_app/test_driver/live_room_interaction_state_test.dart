import 'package:flutter_driver/flutter_driver.dart';
import 'package:test/test.dart';

/// iOS Profile 真机验收驱动。
///
/// 它通过 Flutter Driver 控制真实 App 页面，而不是直接调用 Repository，
/// 所以可以覆盖“启动 App → 请求房间列表 → 进入房间 → 回填后端状态”的完整链路。
void main() {
  late FlutterDriver driver;

  setUpAll(() async {
    driver = await FlutterDriver.connect();
  });

  tearDownAll(() async {
    await driver.close();
  });

  test('iOS 真机重新进入直播间时回填关注和点赞状态', () async {
    final room = find.byValueKey('live-room-4');
    await driver.waitFor(room, timeout: const Duration(seconds: 30));
    await driver.tap(room);

    // 详情页会重新请求 /live/rooms/:id，下面两个断言验证后端快照已回填到 UI。
    await driver.waitFor(
      find.text('已关注'),
      timeout: const Duration(seconds: 20),
    );
    await driver.waitFor(
      find.byTooltip('点赞 1'),
      timeout: const Duration(seconds: 20),
    );
  });
}
