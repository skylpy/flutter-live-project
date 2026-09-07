import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../controllers/notification_controller.dart';

class NotificationPage extends ConsumerWidget {
  const NotificationPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTheme.tokens(context);
    final notifications = ref.watch(notificationControllerProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('通知'),
        actions: [
          TextButton(
            onPressed: () =>
                ref.read(notificationControllerProvider.notifier).markAllRead(),
            child: const Text('全部已读'),
          ),
        ],
      ),
      body: notifications.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: FilledButton.icon(
            onPressed: () => ref.invalidate(notificationControllerProvider),
            icon: const Icon(Icons.refresh),
            label: const Text('加载失败，重试'),
          ),
        ),
        data: (items) {
          if (items.isEmpty) return const Center(child: Text('暂时没有通知'));
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: items.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final item = items[index];
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: tokens.primary.withValues(alpha: 0.16),
                  child: Icon(
                    item.type == '新关注' ? Icons.person_add : Icons.favorite,
                    color: tokens.primary,
                  ),
                ),
                title: Text('${item.type} · ${item.title}'),
                subtitle: Text(item.body),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      item.timeLabel,
                      style: TextStyle(
                        color: tokens.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                    if (item.unread)
                      Container(
                        margin: const EdgeInsets.only(top: 6),
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: tokens.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
