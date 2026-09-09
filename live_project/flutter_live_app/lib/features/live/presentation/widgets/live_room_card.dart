import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/models/live_room.dart';

/// 两列直播卡片。没有封面地址时使用本地渐变占位，不请求网络图片。
class LiveRoomCard extends StatelessWidget {
  const LiveRoomCard({
    required this.room,
    required this.onTap,
    this.onAnchorTap,
    super.key,
  });
  final LiveRoom room;
  final VoidCallback onTap;
  final VoidCallback? onAnchorTap;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTheme.tokens(context);
    return Card(
      // 用稳定的房间 ID 标识卡片，真机自动化和无障碍测试不依赖标题文案。
      key: ValueKey('live-room-${room.id}'),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _Cover(room: room),
                  Positioned(
                    top: 9,
                    left: 9,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: tokens.live,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 4,
                        ),
                        child: Text(
                          '直播中',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 9,
                    bottom: 8,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 4,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.people_alt_outlined,
                              size: 13,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              _formatCount(room.onlineCount),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(11, 9, 11, 11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    room.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      InkWell(
                        onTap: onAnchorTap,
                        borderRadius: BorderRadius.circular(16),
                        child: CircleAvatar(
                          radius: 11,
                          backgroundColor: tokens.primary.withValues(
                            alpha: 0.25,
                          ),
                          child: Text(
                            room.anchorName.isEmpty
                                ? '?'
                                : room.anchorName.substring(0, 1),
                            style: const TextStyle(fontSize: 11),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: InkWell(
                          onTap: onAnchorTap,
                          child: Text(
                            room.anchorName.isEmpty ? '匿名主播' : room.anchorName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: tokens.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (room.category.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      room.category,
                      style: TextStyle(
                        color: tokens.textSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatCount(int count) =>
      count >= 10000 ? '${(count / 10000).toStringAsFixed(1)}万' : '$count';
}

class _Cover extends StatelessWidget {
  const _Cover({required this.room});
  final LiveRoom room;
  @override
  Widget build(BuildContext context) => room.coverUrl.isEmpty
      ? _Placeholder(room: room)
      : Image.network(
          room.coverUrl,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stack) => _Placeholder(room: room),
        );
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.room});
  final LiveRoom room;
  @override
  Widget build(BuildContext context) {
    final tokens = AppTheme.tokens(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            tokens.secondary.withValues(alpha: 0.7),
            tokens.primary.withValues(alpha: 0.3),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(
          Icons.live_tv,
          size: 42,
          color: Colors.white.withValues(alpha: 0.9),
        ),
      ),
    );
  }
}
