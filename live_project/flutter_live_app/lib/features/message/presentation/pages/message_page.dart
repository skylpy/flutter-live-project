import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/models/message_conversation.dart';
import '../controllers/message_controller.dart';

/// 消息中心：数据从真实 `/messages/conversations` 读取，页面只负责状态展示。
class MessagePage extends ConsumerWidget {
  const MessagePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTheme.tokens(context);
    final messages = ref.watch(messageControllerProvider);
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => ref.invalidate(messageControllerProvider),
          child: messages.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) => Center(
              child: FilledButton.icon(
                onPressed: () => ref.invalidate(messageControllerProvider),
                icon: const Icon(Icons.refresh),
                label: const Text('加载失败，重试'),
              ),
            ),
            data: (items) => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              children: [
                const Text(
                  '消息',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _Entry(
                      icon: Icons.favorite,
                      title: '互动消息',
                      color: tokens.primary,
                    ),
                    _Entry(
                      icon: Icons.notifications,
                      title: '系统通知',
                      color: const Color(0xFF5B8DEF),
                      onTap: () => context.push('/notifications'),
                    ),
                    _Entry(
                      icon: Icons.headset_mic,
                      title: '官方客服',
                      color: tokens.secondary,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const Text(
                  '最近消息',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                if (items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(child: Text('暂时没有新消息')),
                  )
                else
                  for (final item in items)
                    _Tile(
                      item: item,
                      onTap: () => ref
                          .read(messageControllerProvider.notifier)
                          .markRead(item.userId),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Entry extends StatelessWidget {
  const _Entry({
    required this.icon,
    required this.title,
    required this.color,
    this.onTap,
  });
  final IconData icon;
  final String title;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            CircleAvatar(
              radius: 27,
              backgroundColor: color.withValues(alpha: 0.18),
              child: Icon(icon, color: color),
            ),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    ),
  );
}

class _Tile extends StatelessWidget {
  const _Tile({required this.item, required this.onTap});
  final MessageConversation item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTheme.tokens(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: tokens.secondary.withValues(alpha: 0.28),
              child: Text(item.userName.isEmpty ? '?' : item.userName[0]),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.userName,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: tokens.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  item.timeLabel,
                  style: TextStyle(color: tokens.textSecondary, fontSize: 11),
                ),
                if (item.unread > 0) ...[
                  const SizedBox(height: 6),
                  CircleAvatar(
                    radius: 9,
                    backgroundColor: tokens.primary,
                    child: Text(
                      '${item.unread}',
                      style: const TextStyle(color: Colors.white, fontSize: 10),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
