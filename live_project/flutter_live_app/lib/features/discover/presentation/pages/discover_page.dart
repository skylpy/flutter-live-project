import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/models/feed_post.dart';
import '../controllers/feed_controller.dart';

/// 动态广场：三种 Tab 共用真实 Feed Repository，页面只负责展示状态。
class DiscoverPage extends ConsumerStatefulWidget {
  const DiscoverPage({super.key});
  @override
  ConsumerState<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends ConsumerState<DiscoverPage> {
  static const _tabs = ['关注', '推荐', '最新'];
  int _selected = 1;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTheme.tokens(context);
    final posts = ref.watch(feedControllerProvider);
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => ref.invalidate(feedControllerProvider),
          child: posts.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) => Center(
              child: FilledButton.icon(
                onPressed: () => ref.invalidate(feedControllerProvider),
                icon: const Icon(Icons.refresh),
                label: const Text('加载失败，重试'),
              ),
            ),
            data: (items) => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              children: [
                Row(
                  children: [
                    const Text(
                      '动态',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.notifications_none),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    for (var i = 0; i < _tabs.length; i++) ...[
                      if (i > 0) const SizedBox(width: 24),
                      GestureDetector(
                        onTap: () {
                          setState(() => _selected = i);
                          ref
                              .read(feedControllerProvider.notifier)
                              .selectTab(_tabs[i]);
                        },
                        child: Column(
                          children: [
                            Text(
                              _tabs[i],
                              style: TextStyle(
                                fontWeight: i == _selected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: i == _selected
                                    ? tokens.textPrimary
                                    : tokens.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 7),
                            Container(
                              height: 3,
                              width: i == _selected ? 22 : 0,
                              decoration: BoxDecoration(
                                color: tokens.primary,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const Spacer(),
                    OutlinedButton(onPressed: () {}, child: const Text('关注动态')),
                  ],
                ),
                const SizedBox(height: 16),
                for (final post in items) ...[
                  _FeedPostCard(
                    post: post,
                    onLike: () => ref
                        .read(feedControllerProvider.notifier)
                        .toggleLike(post.id),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FeedPostCard extends StatelessWidget {
  const _FeedPostCard({required this.post, required this.onLike});
  final FeedPost post;
  final VoidCallback onLike;
  @override
  Widget build(BuildContext context) {
    final tokens = AppTheme.tokens(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: tokens.secondary.withValues(alpha: 0.3),
                  child: Text(
                    post.author.isEmpty ? '?' : post.author.substring(0, 1),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        post.author,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        post.timeLabel,
                        style: TextStyle(
                          color: tokens.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.more_horiz),
              ],
            ),
            const SizedBox(height: 12),
            Text(post.body, style: const TextStyle(height: 1.4)),
            if (post.mediaKind != FeedMediaKind.none) ...[
              const SizedBox(height: 12),
              _PostMedia(kind: post.mediaKind),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                _Action(
                  icon: post.liked ? Icons.favorite : Icons.favorite_border,
                  label: '${post.likes}',
                  color: post.liked ? tokens.primary : null,
                  onTap: onLike,
                ),
                const SizedBox(width: 22),
                _Action(
                  icon: Icons.chat_bubble_outline,
                  label: '${post.comments}',
                  onTap: () {},
                ),
                const SizedBox(width: 22),
                _Action(
                  icon: Icons.ios_share,
                  label: '${post.shares}',
                  onTap: () {},
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PostMedia extends StatelessWidget {
  const _PostMedia({required this.kind});
  final FeedMediaKind kind;
  @override
  Widget build(BuildContext context) {
    final tokens = AppTheme.tokens(context);
    return AspectRatio(
      aspectRatio: kind == FeedMediaKind.portrait ? 1.35 : 1.9,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: [
              tokens.secondary.withValues(alpha: 0.85),
              tokens.primary.withValues(alpha: 0.35),
            ],
          ),
        ),
        child: Center(
          child: Icon(
            kind == FeedMediaKind.landscape
                ? Icons.play_circle_fill
                : Icons.image,
            size: 48,
            color: Colors.white.withValues(alpha: 0.9),
          ),
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(color: color)),
        ],
      ),
    ),
  );
}
