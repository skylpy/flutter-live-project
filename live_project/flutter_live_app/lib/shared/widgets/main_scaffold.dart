import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';

/// 主壳保留四个真实 Tab，中央“+”是操作菜单而不是导航分支。
class MainScaffold extends StatelessWidget {
  const MainScaffold({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  static const _destinations = [
    NavigationDestination(
      icon: Icon(Icons.live_tv_outlined),
      selectedIcon: Icon(Icons.live_tv),
      label: '直播',
    ),
    NavigationDestination(
      icon: Icon(Icons.dynamic_feed_outlined),
      selectedIcon: Icon(Icons.dynamic_feed),
      label: '动态',
    ),
    NavigationDestination(
      icon: Icon(Icons.chat_bubble_outline),
      selectedIcon: Icon(Icons.chat_bubble),
      label: '消息',
    ),
    NavigationDestination(
      icon: Icon(Icons.person_outline),
      selectedIcon: Icon(Icons.person),
      label: '我的',
    ),
  ];

  void _openCreateMenu(BuildContext context) {
    final tokens = AppTheme.tokens(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: tokens.surface,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '创建内容',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: tokens.primary.withValues(alpha: 0.16),
                  child: Icon(Icons.videocam, color: tokens.primary),
                ),
                title: const Text('开始直播'),
                subtitle: const Text('创建直播间并进入竖屏主播控制台'),
                onTap: () {
                  Navigator.pop(context);
                  context.push('/create-live');
                },
              ),
              ListTile(
                leading: CircleAvatar(child: Icon(Icons.edit)),
                title: const Text('发布动态'),
                subtitle: const Text('图文或视频动态'),
                onTap: () {
                  Navigator.pop(context);
                  context.push('/create-post');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTheme.tokens(context);
    return Scaffold(
      body: navigationShell,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: FloatingActionButton(
        heroTag: 'main-create-action',
        onPressed: () => _openCreateMenu(context),
        backgroundColor: tokens.primary,
        foregroundColor: Colors.white,
        child: const Icon(Icons.add, size: 30),
      ),
      bottomNavigationBar: NavigationBar(
        height: 76,
        selectedIndex: navigationShell.currentIndex,
        destinations: _destinations,
        onDestinationSelected: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
      ),
    );
  }
}
