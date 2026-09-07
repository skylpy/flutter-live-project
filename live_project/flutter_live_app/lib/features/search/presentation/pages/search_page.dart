import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../controllers/search_controller.dart';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _queryController = TextEditingController();

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTheme.tokens(context);
    final result = ref.watch(searchControllerProvider);
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _queryController,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: '搜索主播、直播间或动态',
            border: InputBorder.none,
          ),
          onSubmitted: _submit,
        ),
        actions: [
          IconButton(
            tooltip: '搜索',
            onPressed: () => _submit(_queryController.text),
            icon: const Icon(Icons.search),
          ),
        ],
      ),
      body: result.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: FilledButton.icon(
            onPressed: () => _submit(_queryController.text),
            icon: const Icon(Icons.refresh),
            label: const Text('搜索失败，重试'),
          ),
        ),
        data: (data) {
          if (data == null) {
            return const Center(child: Text('输入关键词开始搜索'));
          }
          final empty =
              data.users.isEmpty && data.rooms.isEmpty && data.posts.isEmpty;
          if (empty) return const Center(child: Text('没有找到相关内容'));
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              if (data.rooms.isNotEmpty) ...[
                const _SectionTitle(title: '直播间'),
                for (final room in data.rooms)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: tokens.primary.withValues(alpha: 0.18),
                      child: const Icon(Icons.live_tv),
                    ),
                    title: Text(room.title),
                    subtitle: Text(
                      '${room.anchorName} · ${room.onlineCount} 人在线 · ${room.category}',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/live-room/${room.id}'),
                  ),
              ],
              if (data.users.isNotEmpty) ...[
                const _SectionTitle(title: '用户'),
                for (final user in data.users)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      child: Text(_initial(user.displayName)),
                    ),
                    title: Text(user.displayName),
                    subtitle: Text('@${user.username}'),
                  ),
              ],
              if (data.posts.isNotEmpty) ...[
                const _SectionTitle(title: '动态'),
                for (final post in data.posts)
                  Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      title: Text(post.body),
                      subtitle: Text('${post.author} · ${post.timeLabel}'),
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }

  void _submit(String value) {
    ref.read(searchControllerProvider.notifier).search(value);
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 6),
    child: Text(
      title,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
    ),
  );
}

String _initial(String value) => value.isEmpty ? '?' : value.characters.first;
