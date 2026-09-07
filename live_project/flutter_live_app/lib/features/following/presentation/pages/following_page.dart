import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../controllers/following_controller.dart';

class FollowingPage extends ConsumerWidget {
  const FollowingPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = ref.watch(followingControllerProvider);
    final tokens = AppTheme.tokens(context);
    return Scaffold(
      appBar: AppBar(title: const Text('我的关注')),
      body: users.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: FilledButton.icon(
            onPressed: () => ref.invalidate(followingControllerProvider),
            icon: const Icon(Icons.refresh),
            label: const Text('加载失败，重试'),
          ),
        ),
        data: (items) {
          if (items.isEmpty) return const Center(child: Text('还没有关注任何人'));
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: items.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final user = items[index];
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: tokens.secondary.withValues(alpha: 0.28),
                  child: Text(
                    user.displayName.isEmpty
                        ? '?'
                        : user.displayName.characters.first,
                  ),
                ),
                title: Text(user.displayName),
                subtitle: Text('@${user.username}'),
                trailing: const Icon(Icons.chevron_right),
              );
            },
          );
        },
      ),
    );
  }
}
