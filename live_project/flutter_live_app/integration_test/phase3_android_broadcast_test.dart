import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_live_app/app/router/app_router.dart';
import 'package:flutter_live_app/main.dart' as app;

const phase3RoomTitle = 'Phase3 Android 真播验收';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android 主播闭环：登录、开播、等待媒体确认并结束', (tester) async {
    app.main();
    await tester.pump(const Duration(seconds: 2));

    appRouter.go('/login');
    await tester.pump(const Duration(seconds: 2));
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'phase2_smoke_1788695931');
    await tester.enterText(fields.at(1), 'phase2pass123');
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pump(const Duration(seconds: 4));
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump(const Duration(seconds: 1));
    await tester.tap(find.text('开始直播'));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('准备好后进入竖屏主播控制台'), findsOneWidget);

    final formFields = find.byType(TextField);
    await tester.enterText(formFields.at(0), phase3RoomTitle);
    await tester.tap(find.widgetWithText(FilledButton, '开始直播'));

    // 真机摄像头和 RTMP 建连不是 Flutter 动画，使用有界轮询等待
    // 原生 PUSH_STARTED -> 后端 SRS active -> living 的完整状态链路。
    for (var second = 0; second < 35; second++) {
      await tester.pump(const Duration(seconds: 1));
      if (find.textContaining('直播中 ·').evaluate().isNotEmpty) break;
    }
    expect(find.textContaining('直播中 ·'), findsOneWidget);

    // 保持测试帧循环运行，让原生 Surface/RTMP 连接持续收帧；集成测试的
    // pump 会推进 Flutter 时钟，但不会替代真实设备上的原生帧回调。
    // 这段有界窗口也给另一台设备完成构建、刷新列表并播放 HLS 留出时间。
    for (var second = 0; second < 65; second++) {
      await tester.pump(const Duration(seconds: 1));
    }

    await tester.tap(find.byTooltip('结束直播'));
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('直播已结束，可以再次开播'), findsOneWidget);
  });
}
