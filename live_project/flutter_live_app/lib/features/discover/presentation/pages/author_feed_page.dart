import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_theme.dart';
import '../../data/models/feed_post.dart';
import '../controllers/feed_controller.dart';
import 'discover_page.dart';

/// 公开个人动态主页，和个人中心不同：访客可关注对方或直接发起私信。
class AuthorFeedPage extends ConsumerStatefulWidget {
  const AuthorFeedPage({required this.userId, super.key});

  final int userId;

  @override
  ConsumerState<AuthorFeedPage> createState() => _AuthorFeedPageState();
}

class _AuthorFeedPageState extends ConsumerState<AuthorFeedPage> {
  FeedAuthorProfile? _profile;
  Object? _error;
  bool _loading = true;
  bool _followingBusy = false;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_load);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final profile = await ref
          .read(feedRepositoryProvider)
          .getAuthorProfile(widget.userId);
      if (mounted) setState(() => _profile = profile);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleFollow() async {
    if (_followingBusy) return;
    setState(() => _followingBusy = true);
    try {
      await ref.read(feedRepositoryProvider).toggleUserFollow(widget.userId);
      await _load();
    } on ApiException catch (error) {
      _show(error.message);
    } catch (_) {
      _show('关注操作失败，请重试');
    } finally {
      if (mounted) setState(() => _followingBusy = false);
    }
  }

  void _openChat() {
    final profile = _profile;
    if (profile == null) return;
    context.push('/messages/${profile.id}', extra: profile.displayName);
  }

  Future<void> _deletePost(int postId) async {
    await ref.read(feedRepositoryProvider).deletePost(postId);
    await _load();
  }

  void _show(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    if (_loading && _profile == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null || _profile == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: FilledButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: const Text('加载失败，重试'),
          ),
        ),
      );
    }
    final profile = _profile!;
    final tokens = AppTheme.tokens(context);
    return Scaffold(
      appBar: AppBar(title: const Text('个人动态')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 31,
                  backgroundColor: tokens.secondary.withValues(alpha: 0.25),
                  child: Text(
                    profile.displayName.isEmpty ? '?' : profile.displayName[0],
                    style: const TextStyle(fontSize: 23),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.displayName,
                        style: const TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '@${profile.username}',
                        style: TextStyle(color: tokens.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                _Stat(label: '动态', value: '${profile.postCount}'),
                _Stat(label: '关注', value: '${profile.followingCount}'),
                _Stat(label: '粉丝', value: '${profile.followerCount}'),
              ],
            ),
            if (!profile.isSelf) ...[
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: _followingBusy ? null : _toggleFollow,
                      child: Text(profile.following ? '已关注' : '关注'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: _openChat,
                    icon: const Icon(Icons.chat_bubble_outline),
                    label: const Text('私信'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 22),
            const Text('TA 的动态', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            if (profile.posts.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: Text('还没有发布动态')),
              )
            else
              for (final post in profile.posts) ...[
                FeedPostCard(
                  post: post,
                  onLike: () async {
                    await ref.read(feedRepositoryProvider).toggleLike(post.id);
                    await _load();
                  },
                  onDelete: post.canDelete ? () => _deletePost(post.id) : null,
                ),
                const SizedBox(height: 12),
              ],
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 3),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    ),
  );
}
