import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_live_app/app/router/app_router.dart';
import 'package:flutter_live_app/main.dart' as app;

const phase3RoomTitle = 'Phase3 Android 真播验收';
const phase3ApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://192.168.0.111:8000/api/v1',
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android 观看端：刷新列表、进入主播房间并收到播放状态', (tester) async {
    app.main();
    await tester.pump(const Duration(seconds: 2));

    appRouter.go('/login');
    await tester.pump(const Duration(seconds: 2));
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'phase2_smoke_1788695931');
    await tester.enterText(fields.at(1), 'phase2pass123');
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    // 另一台设备可能在测试启动后才完成推流。这里轮询和首页相同的真实
    // /live/rooms Repository，验证动态房间会进入列表数据，再打开详情页。
    String? roomId;
    for (var second = 0; second < 60 && roomId == null; second++) {
      await tester.runAsync(() async {
        final client = HttpClient();
        try {
          final request = await client.getUrl(
            Uri.parse('$phase3ApiBaseUrl/live/rooms'),
          );
          final response = await request.close();
          if (response.statusCode != 200) return;
          final body = await response.transform(utf8.decoder).join();
          final payload = jsonDecode(body) as Map<String, dynamic>;
          final rooms = payload['data'] as List<dynamic>? ?? const [];
          for (final item in rooms) {
            final data = item as Map<String, dynamic>;
            if (data['title'] == phase3RoomTitle &&
                data['status'] == 'living') {
              roomId = '${data['id']}';
              break;
            }
          }
        } finally {
          client.close(force: true);
        }
      });
      if (roomId == null) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(seconds: 1)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
    }
    expect(roomId, isNotNull);
    appRouter.go('/live-room/$roomId');
    // 详情请求和 ExoPlayer 回调走真实异步 I/O；给设备墙上时间完成请求，
    // 再推进一帧检查真实 PlatformView 页面。
    for (var second = 0; second < 30; second++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 500)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byIcon(Icons.close).evaluate().isNotEmpty &&
          find.text('播放器区域').evaluate().isEmpty) {
        break;
      }
    }

    // 播放器状态从 ExoPlayer 回调后，等待地址占位文案应消失；同时详情页
    // 的真实主播控制仍然存在。视频画面本身由原生 SurfaceView 渲染。
    expect(find.text('播放器区域'), findsNothing);
    expect(find.byIcon(Icons.close), findsOneWidget);
  });
}
