import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_live_app/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('真机重新进入直播间时回填关注和点赞状态', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 真机首次安装可能没有保留登录态；测试发现登录页时自动使用本地验收账号。
    final textFields = find.byType(TextField);
    if (textFields.evaluate().isNotEmpty) {
      final usernameField = textFields.at(0);
      final passwordField = textFields.at(1);
      await tester.enterText(usernameField, 'phase2_smoke_1788695931');
      await tester.enterText(passwordField, 'phase2pass123');
      await tester.tap(find.widgetWithText(FilledButton, '登录'));
      await tester.pumpAndSettle(const Duration(seconds: 3));
    }

    // 首页房间卡片来自真实 /live/rooms 接口，点击后详情页会重新请求状态快照。
    final room = find.text('Flutter 插件开发');
    expect(room, findsOneWidget);
    await tester.tap(room);
    await tester.pumpAndSettle(const Duration(seconds: 5));

    // 这两个断言验证的是后端持久化关系，而不是页面本地默认值。
    expect(find.text('已关注'), findsOneWidget);
    expect(find.byTooltip('点赞 1'), findsOneWidget);
  });
}
