import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/models/feed_post.dart';
import '../controllers/feed_controller.dart';
import 'discover_page.dart';

/// 动态详情展示全部评论；信息流仅展示最近三条，避免列表被长评论淹没。
class PostDetailPage extends ConsumerStatefulWidget {
  const PostDetailPage({required this.postId, super.key});

  final int postId;

  @override
  ConsumerState<PostDetailPage> createState() => _PostDetailPageState();
}

class _PostDetailPageState extends ConsumerState<PostDetailPage> {
  final _commentController = TextEditingController();
  FeedPost? _post;
  List<FeedComment> _comments = const [];
  Object? _error;
  bool _loading = true;
  bool _sending = false;
  FeedComment? _replyingTo;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_load);
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repository = ref.read(feedRepositoryProvider);
      final result = await Future.wait([
        repository.getPost(widget.postId),
        repository.getComments(widget.postId),
      ]);
      if (mounted) {
        setState(() {
          _post = result[0] as FeedPost;
          _comments = result[1] as List<FeedComment>;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendComment() async {
    final body = _commentController.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final comment = await ref
          .read(feedRepositoryProvider)
          .createComment(
            postId: widget.postId,
            body: body,
            parentId: _replyingTo?.id,
          );
      if (!mounted) return;
      setState(() {
        _comments = [..._comments, comment];
        _post = _post?.copyWith(comments: _post!.comments + 1);
        _commentController.clear();
        _replyingTo = null;
      });
    } on ApiException catch (error) {
      _show(error.message);
    } catch (_) {
      _show('评论发送失败，请重试');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _toggleLike() async {
    final post = _post;
    if (post == null) return;
    try {
      final result = await ref.read(feedRepositoryProvider).toggleLike(post.id);
      if (mounted) {
        setState(
          () =>
              _post = post.copyWith(liked: result.active, likes: result.count),
        );
      }
    } on ApiException catch (error) {
      _show(error.message);
    }
  }

  void _show(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    if (_loading && _post == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null || _post == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('动态详情')),
        body: Center(
          child: FilledButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: const Text('加载失败，重试'),
          ),
        ),
      );
    }
    final post = _post!;
    final tokens = AppTheme.tokens(context);
    return Scaffold(
      appBar: AppBar(title: const Text('动态详情')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          children: [
            Row(
              children: [
                InkWell(
                  onTap: () => context.push('/feed/users/${post.authorId}'),
                  borderRadius: BorderRadius.circular(24),
                  child: CircleAvatar(
                    backgroundColor: tokens.secondary.withValues(alpha: 0.3),
                    child: Text(post.author.isEmpty ? '?' : post.author[0]),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    onTap: () => context.push('/feed/users/${post.authorId}'),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          post.author,
                          style: const TextStyle(fontWeight: FontWeight.w700),
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
              ],
            ),
            const SizedBox(height: 16),
            Text(post.body, style: const TextStyle(fontSize: 16, height: 1.5)),
            if (post.media.isNotEmpty) ...[
              const SizedBox(height: 14),
              FeedPostMediaGrid(media: post.media),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                IconButton(
                  onPressed: _toggleLike,
                  icon: Icon(
                    post.liked ? Icons.favorite : Icons.favorite_border,
                  ),
                  color: post.liked ? tokens.primary : null,
                ),
                Text('${post.likes}'),
                const SizedBox(width: 20),
                const Icon(Icons.chat_bubble_outline, size: 20),
                const SizedBox(width: 6),
                Text('${_comments.length} 条评论'),
              ],
            ),
            const Divider(height: 26),
            const Text('全部评论', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (_comments.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(child: Text('还没有评论，来说两句吧')),
              )
            else
              for (final comment in _comments)
                ListTile(
                  onTap: () => setState(() => _replyingTo = comment),
                  contentPadding: EdgeInsets.zero,
                  leading: InkWell(
                    onTap: () =>
                        context.push('/feed/users/${comment.authorId}'),
                    borderRadius: BorderRadius.circular(20),
                    child: CircleAvatar(
                      radius: 18,
                      child: Text(
                        comment.author.isEmpty ? '?' : comment.author[0],
                      ),
                    ),
                  ),
                  title: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          comment.author,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (comment.isVirtual) ...[
                        const SizedBox(width: 6),
                        Text(
                          '虚拟居民',
                          style: TextStyle(color: tokens.primary, fontSize: 11),
                        ),
                      ],
                    ],
                  ),
                  subtitle: Text(
                    comment.replyToAuthor == null
                        ? comment.body
                        : '回复 ${comment.replyToAuthor}：${comment.body}',
                  ),
                  trailing: Text(
                    comment.timeLabel,
                    style: TextStyle(color: tokens.textSecondary, fontSize: 11),
                  ),
                ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_replyingTo != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Expanded(child: Text('回复 ${_replyingTo!.author}')),
                      IconButton(
                        tooltip: '取消回复',
                        onPressed: () => setState(() => _replyingTo = null),
                        icon: const Icon(Icons.close, size: 18),
                      ),
                    ],
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _commentController,
                      maxLength: 500,
                      onSubmitted: (_) => _sendComment(),
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: _replyingTo == null
                            ? '写下你的评论…'
                            : '回复 ${_replyingTo!.author}…',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _sending ? null : _sendComment,
                    child: const Text('发送'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
