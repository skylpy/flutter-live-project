import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/create_live/presentation/pages/create_live_page.dart';
import '../../features/create_live/presentation/pages/live_broadcast_page.dart';
import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/home/presentation/pages/home_page.dart';
import '../../features/live/presentation/pages/live_page.dart';
import '../../features/live/presentation/pages/live_room_page.dart';
import '../../features/live/data/models/live_room.dart';
import '../../features/message/presentation/pages/message_page.dart';
import '../../features/profile/presentation/pages/profile_page.dart';
import '../../shared/widgets/main_scaffold.dart';

// 根 Navigator 承载不属于底部 Tab 的页面，例如全屏直播间和登录页。
final _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
final _homeNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'home');
final _discoverNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'discover');
final _createLiveNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'create-live',
);
final _messageNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'message');
final _profileNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'profile');

/// 全局路由表。
///
/// 五个 StatefulShellBranch 各自拥有 Navigator，所以切换 Tab 后仍能保留
/// 原来的子页面和返回栈。直播间指定 root navigator，因此不会显示底部栏。
final appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/home',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        return MainScaffold(navigationShell: navigationShell);
      },
      branches: [
        StatefulShellBranch(
          navigatorKey: _homeNavigatorKey,
          initialLocation: '/home',
          routes: [
            GoRoute(
              path: '/home',
              builder: (context, state) => const HomePage(),
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: _discoverNavigatorKey,
          initialLocation: '/discover',
          routes: [
            GoRoute(
              path: '/discover',
              builder: (context, state) => const LivePage(),
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: _createLiveNavigatorKey,
          initialLocation: '/create-live',
          routes: [
            GoRoute(
              path: '/create-live',
              builder: (context, state) => const CreateLivePage(),
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: _messageNavigatorKey,
          initialLocation: '/message',
          routes: [
            GoRoute(
              path: '/message',
              builder: (context, state) => const MessagePage(),
            ),
          ],
        ),
        StatefulShellBranch(
          navigatorKey: _profileNavigatorKey,
          initialLocation: '/profile',
          routes: [
            GoRoute(
              path: '/profile',
              builder: (context, state) => const ProfilePage(),
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: '/live-room/:roomId',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) =>
          LiveRoomPage(roomId: state.pathParameters['roomId']!),
    ),
    GoRoute(
      path: '/live-broadcast/:roomId',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
        // 主播页由开播表单通过 extra 传入刚创建的房间快照，里面包含服务端
        // 生成的 pushUrl。若用户直接输入深链接而没有 extra，给出明确提示，
        // 避免把一个没有推流地址的房间交给原生引擎。
        final room = state.extra;
        if (room is! LiveRoom) {
          return const Scaffold(
            body: Center(child: Text('主播房间信息不存在，请返回后重新开播')),
          );
        }
        return LiveBroadcastPage(room: room);
      },
    ),
    GoRoute(
      path: '/login',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const LoginPage(),
    ),
  ],
);
