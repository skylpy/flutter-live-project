import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dart:async';

import '../core/network/api_provider.dart';
import '../core/theme/app_theme.dart';
import 'router/app_router.dart';

/// App 根节点：Riverpod 管理主题，go_router 管理页面和导航栈。
class LiveApp extends ConsumerStatefulWidget {
  const LiveApp({super.key});

  @override
  ConsumerState<LiveApp> createState() => _LiveAppState();
}

class _LiveAppState extends ConsumerState<LiveApp> {
  StreamSubscription<void>? _authExpiredSubscription;
  bool _redirectingToLogin = false;

  @override
  void initState() {
    super.initState();
    _authExpiredSubscription = ref
        .read(authExpiredEventBusProvider)
        .events
        .listen((_) {
          debugPrint('[LiveApp] received auth-expired event');
          if (_redirectingToLogin) return;
          _redirectingToLogin = true;
          // 网络层事件可能发生在任意异步回调中，使用下一帧导航可以避免
          // 在当前 Widget 正在 build 时修改路由栈。
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            appRouter.go('/login?reason=session_expired');
            // 给后续重新发起的请求留出时间；登录成功后页面会离开登录页，
            // 下一次真正的 401 仍然可以再次触发跳转。
            Future<void>.delayed(const Duration(seconds: 1), () {
              _redirectingToLogin = false;
            });
          });
        });
  }

  @override
  void dispose() {
    _authExpiredSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Flutter Live',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.data(ref.watch(appThemeProvider)),
      routerConfig: appRouter,
    );
  }
}
