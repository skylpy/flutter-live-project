import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/pages/login_page.dart';
import '../../features/create_live/presentation/pages/create_live_page.dart';
import '../../features/create_live/presentation/pages/live_broadcast_page.dart';
import '../../features/discover/presentation/pages/discover_page.dart';
import '../../features/home/presentation/pages/home_page.dart';
import '../../features/live/data/models/live_room.dart';
import '../../features/live/presentation/pages/live_room_page.dart';
import '../../features/message/presentation/pages/message_page.dart';
import '../../features/notification/presentation/pages/notification_page.dart';
import '../../features/search/presentation/pages/search_page.dart';
import '../../features/following/presentation/pages/following_page.dart';
import '../../features/profile/presentation/pages/profile_page.dart';
import '../../features/profile/presentation/pages/settings_page.dart';
import '../../shared/widgets/main_scaffold.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
final _liveNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'live');
final _discoverNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'discover');
final _messageNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'message');
final _profileNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'profile');

/// 四个 StatefulShell 分支保存各自导航状态；直播间/设置/主播页使用 root navigator。
final appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/home',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          MainScaffold(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(
          navigatorKey: _liveNavigatorKey,
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
              builder: (context, state) => const DiscoverPage(),
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
      path: '/create-live',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const CreateLivePage(),
    ),
    GoRoute(
      path: '/live-broadcast/:roomId',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) {
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
      path: '/settings',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const SettingsPage(),
    ),
    GoRoute(
      path: '/search',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const SearchPage(),
    ),
    GoRoute(
      path: '/notifications',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const NotificationPage(),
    ),
    GoRoute(
      path: '/following',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const FollowingPage(),
    ),
    GoRoute(
      path: '/login',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (context, state) => const LoginPage(),
    ),
  ],
);
