import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dart:async';

import '../core/network/api_provider.dart';
import '../core/theme/app_theme.dart';
import '../features/auth/presentation/controllers/auth_controller.dart';
import 'router/app_router.dart';

final realtimeNotificationSessionProvider = Provider<void>((ref) {
  final authState = ref.watch(authControllerProvider);
  final client = ref.watch(realtimeNotificationClientProvider);
  final session = authState.asData?.value;
  if (session == null) {
    unawaited(client.disconnect());
  } else {
    unawaited(client.connect());
  }
});

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
    // 登录状态变化时自动建立/关闭用户级通知 WebSocket。
    ref.watch(realtimeNotificationSessionProvider);
    return MaterialApp.router(
      title: '心动直播',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.data(ref.watch(appThemeProvider)),
      routerConfig: appRouter,
      // Android 12+ 的系统启动页只能展示图标和纯色背景；这里在 Flutter 首帧后
      // 接续同一张启动图，确保 iOS/Android 均能看到完整的品牌启动画面。
      builder: (context, child) => _BrandLaunchGate(child: child),
    );
  }
}

class _BrandLaunchGate extends StatefulWidget {
  const _BrandLaunchGate({required this.child});

  final Widget? child;

  @override
  State<_BrandLaunchGate> createState() => _BrandLaunchGateState();
}

class _BrandLaunchGateState extends State<_BrandLaunchGate> {
  var _showLaunch = true;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _showLaunch = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_showLaunch) return widget.child ?? const SizedBox.shrink();
    return const ColoredBox(
      color: Color(0xFF300B35),
      child: SizedBox.expand(
        child: Image(
          image: AssetImage('assets/branding/xindong_live_launch.png'),
          fit: BoxFit.cover,
          excludeFromSemantics: true,
        ),
      ),
    );
  }
}
