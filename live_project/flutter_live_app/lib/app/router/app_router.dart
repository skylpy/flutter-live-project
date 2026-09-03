import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/create_live/presentation/pages/create_live_page.dart';
import '../../features/home/presentation/pages/home_page.dart';
import '../../features/live/presentation/pages/live_page.dart';
import '../../features/live/presentation/pages/live_room_page.dart';
import '../../features/message/presentation/pages/message_page.dart';
import '../../features/profile/presentation/pages/profile_page.dart';
import '../../shared/widgets/main_scaffold.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
final _homeNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'home');
final _discoverNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'discover');
final _createLiveNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'create-live',
);
final _messageNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'message');
final _profileNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'profile');

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
  ],
);
