import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../auth/presentation/controllers/auth_controller.dart';

/// 我的 Tab：展示当前用户，未登录时跳转到登录页。
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 认证状态由 AuthController 统一恢复和修改，ProfilePage 只负责展示。
    final authState = ref.watch(authControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: authState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(child: Text('$error')),
        data: (session) {
          if (session == null) {
            return Center(
              child: FilledButton.icon(
                onPressed: () => context.push('/login'),
                icon: const Icon(Icons.login),
                label: const Text('登录 / 注册'),
              ),
            );
          }
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 34,
                  child: Text(
                    session.user.displayName.isEmpty
                        ? '?'
                        : session.user.displayName[0],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  session.user.displayName,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text('@${session.user.username}'),
                const SizedBox(height: 20),
                OutlinedButton(
                  onPressed: () =>
                      ref.read(authControllerProvider.notifier).logout(),
                  child: const Text('退出登录'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
