import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/live_room.dart';
import '../controllers/live_room_controller.dart';

class LiveRoomPage extends ConsumerWidget {
  const LiveRoomPage({required this.roomId, super.key});

  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = ref.watch(liveRoomControllerProvider(roomId));
    return Scaffold(
      backgroundColor: Colors.black,
      body: room.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(color: Colors.white)),
        error: (error, stackTrace) => _RoomError(
          message: error.toString(),
          onRetry: () => ref.invalidate(liveRoomControllerProvider(roomId)),
        ),
        data: (data) => _LiveRoomContent(room: data),
      ),
    );
  }
}

class _LiveRoomContent extends StatelessWidget {
  const _LiveRoomContent({required this.room});

  final LiveRoom room;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Stack(
        children: [
          const Positioned.fill(child: _PlayerPlaceholder()),
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: _RoomHeader(room: room),
          ),
          const Positioned(left: 16, bottom: 102, child: _DanmakuList()),
          const Positioned(
            left: 16,
            right: 16,
            bottom: 18,
            child: _RoomInputBar(),
          ),
        ],
      ),
    );
  }
}

class _PlayerPlaceholder extends StatelessWidget {
  const _PlayerPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.live_tv,
            color: Colors.white.withValues(alpha: 0.55),
            size: 64,
          ),
          const SizedBox(height: 16),
          Text(
            '播放器区域',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '第二阶段接入原生播放器',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
          ),
        ],
      ),
    );
  }
}

class _RoomHeader extends StatelessWidget {
  const _RoomHeader({required this.room});

  final LiveRoom room;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          backgroundColor: Colors.white24,
          child: Text(
            room.anchorName.isEmpty ? '?' : room.anchorName[0],
            style: const TextStyle(color: Colors.white),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                room.anchorName,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '${room.onlineCount} 人在线',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
        OutlinedButton(onPressed: () {}, child: const Text('关注')),
        const SizedBox(width: 8),
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          color: Colors.white,
          icon: const Icon(Icons.close),
          tooltip: '关闭直播间',
        ),
      ],
    );
  }
}

class _DanmakuList extends StatelessWidget {
  const _DanmakuList();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DanmakuLine(name: '小明', message: '主播晚上好'),
        _DanmakuLine(name: 'Kevin', message: 'Flutter 666'),
        _DanmakuLine(name: 'Summer', message: '🌹 送出玫瑰 × 10'),
      ],
    );
  }
}

class _DanmakuLine extends StatelessWidget {
  const _DanmakuLine({required this.name, required this.message});

  final String name;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            '$name：$message',
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
        ),
      ),
    );
  }
}

class _RoomInputBar extends StatelessWidget {
  const _RoomInputBar();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white12,
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Text(
              '说点什么...',
              style: TextStyle(color: Colors.white60),
            ),
          ),
        ),
        IconButton(
          onPressed: () {},
          color: Colors.white,
          icon: const Icon(Icons.card_giftcard),
          tooltip: '礼物',
        ),
        IconButton(
          onPressed: () {},
          color: Colors.pinkAccent,
          icon: const Icon(Icons.favorite),
          tooltip: '点赞',
        ),
      ],
    );
  }
}

class _RoomError extends StatelessWidget {
  const _RoomError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 48),
            const SizedBox(height: 12),
            const Text('直播间加载失败', style: TextStyle(color: Colors.white)),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton(onPressed: onRetry, child: const Text('重试')),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('返回'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
