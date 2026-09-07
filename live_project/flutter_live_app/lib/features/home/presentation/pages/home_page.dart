import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../live/presentation/controllers/live_list_controller.dart';
import '../../../live/presentation/widgets/live_room_card.dart';

/// 直播首页：分类、推荐 Banner 和两列直播卡片组成观众主路径。
class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});
  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  static const _categories = ['推荐', '颜值', '新秀', '才艺', '女团', 'PK', '语音'];
  int _selectedCategory = 0;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTheme.tokens(context);
    final rooms = ref.watch(liveListControllerProvider);
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () =>
              ref.read(liveListControllerProvider.notifier).refreshRooms(),
          child: rooms.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) => _ErrorView(
              message: '$error',
              onRetry: () => ref.invalidate(liveListControllerProvider),
            ),
            data: (items) => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Row(
                  children: [
                    const Text(
                      '直播',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => context.push('/search'),
                      icon: const Icon(Icons.search),
                      tooltip: '搜索',
                    ),
                    IconButton(
                      onPressed: () => context.push('/notifications'),
                      icon: const Icon(Icons.notifications_none),
                      tooltip: '通知',
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 38,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _categories.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: 22),
                    itemBuilder: (context, index) {
                      final selected = index == _selectedCategory;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedCategory = index),
                        child: Column(
                          children: [
                            Text(
                              _categories[index],
                              style: TextStyle(
                                color: selected
                                    ? tokens.textPrimary
                                    : tokens.textSecondary,
                                fontWeight: selected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                            const SizedBox(height: 7),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              height: 3,
                              width: selected ? 24 : 0,
                              decoration: BoxDecoration(
                                color: tokens.primary,
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                _LiveBanner(tokens: tokens),
                const SizedBox(height: 18),
                Row(
                  children: [
                    const Text(
                      '热门直播',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${items.length} 个房间',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 64),
                    child: Center(child: Text('暂时没有正在直播的房间')),
                  )
                else
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: items.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 0.66,
                        ),
                    itemBuilder: (context, index) {
                      final room = items[index];
                      return LiveRoomCard(
                        room: room,
                        onTap: () => context.push('/live-room/${room.id}'),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LiveBanner extends StatelessWidget {
  const _LiveBanner({required this.tokens});
  final LiveThemeExtension tokens;
  @override
  Widget build(BuildContext context) => Container(
    height: 138,
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: [tokens.secondary, tokens.primary]),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Stack(
      children: [
        Positioned(
          right: -8,
          bottom: -24,
          child: Icon(
            Icons.auto_awesome,
            size: 150,
            color: Colors.white.withValues(alpha: 0.13),
          ),
        ),
        const Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '遇见心动直播',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'Live for You · 发现正在发生的精彩',
                style: TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 160),
    children: [
      const Icon(Icons.cloud_off, size: 48),
      const SizedBox(height: 12),
      const Center(child: Text('直播列表加载失败')),
      const SizedBox(height: 8),
      Text(message, textAlign: TextAlign.center, maxLines: 3),
      const SizedBox(height: 16),
      Center(
        child: FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('重试'),
        ),
      ),
    ],
  );
}
