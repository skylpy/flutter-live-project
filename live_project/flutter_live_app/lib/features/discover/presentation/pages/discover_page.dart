import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/models/feed_post.dart';
import '../controllers/feed_controller.dart';
import 'media_viewer_page.dart';

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
                    OutlinedButton(
                      onPressed: () => context.push('/create-post'),
                      child: const Text('发布动态'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                for (final post in items) ...[
                  FeedPostCard(
                    post: post,
                    onLike: () => ref
                        .read(feedControllerProvider.notifier)
                        .toggleLike(post.id),
                    onDelete: post.canDelete
                        ? () async {
                            await ref
                                .read(feedControllerProvider.notifier)
                                .deletePost(post.id);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('动态已删除')),
                              );
                            }
                          }
                        : null,
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

class FeedPostCard extends StatelessWidget {
  const FeedPostCard({
    required this.post,
    required this.onLike,
    this.onDelete,
    super.key,
  });
  final FeedPost post;
  final VoidCallback onLike;
  final Future<void> Function()? onDelete;

  void _openPost(BuildContext context) =>
      context.push('/feed/posts/${post.id}');

  void _openAuthor(BuildContext context) =>
      context.push('/feed/users/${post.authorId}');

  Future<void> _showPostMenu(BuildContext context) async {
    final action = await showMenu<_PostMenuAction>(
      context: context,
      position: const RelativeRect.fromLTRB(1000, 80, 12, 0),
      items: [
        if (onDelete != null)
          const PopupMenuItem(
            value: _PostMenuAction.delete,
            child: Text('删除动态'),
          )
        else
          const PopupMenuItem(value: _PostMenuAction.hide, child: Text('不感兴趣')),
        const PopupMenuItem(value: _PostMenuAction.report, child: Text('举报')),
      ],
    );
    if (!context.mounted || action == null) return;
    if (action == _PostMenuAction.delete && onDelete != null) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('删除这条动态？'),
          content: const Text('删除后，动态中的图片或视频也会被删除。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('删除'),
            ),
          ],
        ),
      );
      if (confirmed == true) await onDelete!();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(action == _PostMenuAction.hide ? '已减少此类动态' : '已收到举报'),
      ),
    );
  }

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
                InkWell(
                  onTap: () => _openAuthor(context),
                  borderRadius: BorderRadius.circular(24),
                  child: CircleAvatar(
                    backgroundColor: tokens.secondary.withValues(alpha: 0.3),
                    child: Text(
                      post.author.isEmpty ? '?' : post.author.substring(0, 1),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    onTap: () => _openAuthor(context),
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
                ),
                IconButton(
                  tooltip: '更多操作',
                  onPressed: () => _showPostMenu(context),
                  icon: const Icon(Icons.more_horiz),
                ),
              ],
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: () => _openPost(context),
              child: Text(post.body, style: const TextStyle(height: 1.4)),
            ),
            if (post.media.isNotEmpty) ...[
              const SizedBox(height: 12),
              FeedPostMediaGrid(media: post.media),
            ] else if (post.mediaKind != FeedMediaKind.none) ...[
              const SizedBox(height: 12),
              _LegacyPostMedia(kind: post.mediaKind),
            ],
            const SizedBox(height: 10),
            if (post.commentsPreview.isNotEmpty) ...[
              _CommentsPreview(post: post, onOpen: () => _openPost(context)),
              const SizedBox(height: 8),
            ],
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
                  onTap: () => _openPost(context),
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

class FeedPostMediaGrid extends StatelessWidget {
  const FeedPostMediaGrid({required this.media, super.key});
  final List<FeedMedia> media;

  @override
  Widget build(BuildContext context) {
    if (media.length == 1 && media.single.isVideo) {
      return _FeedVideo(
        media: media.single,
        onOpen: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => MediaViewerPage(media: media),
          ),
        ),
      );
    }
    final columns = media.length == 1
        ? 1
        : media.length == 2
        ? 2
        : 3;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: media.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: 5,
        crossAxisSpacing: 5,
        childAspectRatio: media.length == 1 ? 1.35 : 1,
      ),
      itemBuilder: (context, index) => _FeedImage(
        media: media[index],
        onOpen: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => MediaViewerPage(media: media, initialIndex: index),
          ),
        ),
      ),
    );
  }
}

class _FeedImage extends StatelessWidget {
  const _FeedImage({required this.media, required this.onOpen});
  final FeedMedia media;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onOpen,
    borderRadius: BorderRadius.circular(12),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.network(
        media.url,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stack) => const ColoredBox(
          color: Color(0x22000000),
          child: Center(child: Icon(Icons.broken_image_outlined)),
        ),
      ),
    ),
  );
}

class _FeedVideo extends StatefulWidget {
  const _FeedVideo({required this.media, required this.onOpen});
  final FeedMedia media;
  final VoidCallback onOpen;

  @override
  State<_FeedVideo> createState() => _FeedVideoState();
}

class _FeedVideoState extends State<_FeedVideo> {
  late final VideoPlayerController _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.media.url))
      ..setVolume(0)
      ..initialize()
          .then((_) {
            if (mounted) setState(() => _ready = true);
          })
          .catchError((_) {});
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final aspectRatio = _ready && _controller.value.aspectRatio > 0
        ? _controller.value.aspectRatio
        : 16 / 9;
    return InkWell(
      onTap: widget.onOpen,
      borderRadius: BorderRadius.circular(12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: Stack(
            alignment: Alignment.center,
            children: [
              const Positioned.fill(
                child: ColoredBox(color: Color(0x33000000)),
              ),
              if (_ready) VideoPlayer(_controller),
              IconButton.filled(
                tooltip: _controller.value.isPlaying ? '暂停视频' : '播放视频',
                onPressed: !_ready
                    ? null
                    : () => setState(() {
                        _controller.value.isPlaying
                            ? _controller.pause()
                            : _controller.play();
                      }),
                icon: Icon(
                  _controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommentsPreview extends StatelessWidget {
  const _CommentsPreview({required this.post, required this.onOpen});

  final FeedPost post;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTheme.tokens(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.textSecondary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final comment in post.commentsPreview)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text.rich(
                  TextSpan(
                    style: const TextStyle(fontSize: 13, height: 1.35),
                    children: [
                      TextSpan(
                        text: '${comment.author}：',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      TextSpan(text: comment.body),
                    ],
                  ),
                ),
              ),
            if (post.comments > post.commentsPreview.length)
              TextButton(
                onPressed: onOpen,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 28),
                ),
                child: Text('查看全部 ${post.comments} 条评论'),
              ),
          ],
        ),
      ),
    );
  }
}

enum _PostMenuAction { delete, hide, report }

class _LegacyPostMedia extends StatelessWidget {
  const _LegacyPostMedia({required this.kind});
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
