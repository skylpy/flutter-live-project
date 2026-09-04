import 'package:flutter/material.dart';

import 'router/app_router.dart';
import '../core/theme/app_theme.dart';

/// App 根 Widget。
///
/// MaterialApp.router 负责组合 Material 主题、系统 Navigator 和 go_router。
/// 具体页面不在这里创建，而是交给 [appRouter] 根据当前 URL 生成。
class LiveApp extends StatelessWidget {
  const LiveApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 统一使用 routerConfig，深链接、返回栈和多 Tab 状态都交由 go_router 管理。
    return MaterialApp.router(
      title: 'Flutter Live',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: appRouter,
    );
  }
}
