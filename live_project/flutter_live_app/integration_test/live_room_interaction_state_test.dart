import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_live_app/app/router/app_router.dart';
import 'package:flutter_live_app/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('真机重新进入直播间时回填关注和点赞状态', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // 首页本身允许游客浏览直播列表，因此测试必须显式进入登录页，才能验证
    // 当前用户的关注/点赞关系，而不是误把游客默认值当成历史状态。
    appRouter.go('/login');
    await tester.pumpAndSettle(const Duration(seconds: 2));
    final textFields = find.byType(TextField);
    await tester.enterText(textFields.at(0), 'phase2_smoke_1788695931');
    await tester.enterText(textFields.at(1), 'phase2pass123');
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // 首页房间卡片来自真实 /live/rooms 接口，点击后详情页会重新请求状态快照。
    final room = find.text('Flutter 插件开发');
    expect(room, findsOneWidget);
    await tester.tap(room);
    await tester.pumpAndSettle(const Duration(seconds: 5));

    // 首次进入直接回填后端历史关注状态。
    expect(find.text('已关注'), findsOneWidget);

    // 验收账号可能已被上一次运行取消点赞；先把它置为已点赞，再退出并重新
    // 进入，确保第二次显示来自详情接口，而不是直播间页面的临时状态。
    final unlikedButton = find.byTooltip('点赞 0');
    if (unlikedButton.evaluate().isNotEmpty) {
      await tester.tap(unlikedButton);
      await tester.pumpAndSettle(const Duration(seconds: 2));
    }
    expect(find.byTooltip('点赞 1'), findsOneWidget);

    await tester.tap(find.byTooltip('关闭直播间'));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await tester.tap(find.text('Flutter 插件开发'));
    await tester.pumpAndSettle(const Duration(seconds: 5));

    // 重新进入仍然是已关注、点赞 1，证明状态由后端详情快照回填。
    expect(find.text('已关注'), findsOneWidget);
    expect(find.byTooltip('点赞 1'), findsOneWidget);
  });
}
