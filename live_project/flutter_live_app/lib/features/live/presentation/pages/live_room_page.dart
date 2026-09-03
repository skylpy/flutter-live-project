import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_live_core/flutter_live_core.dart';
import 'package:flutter_live_media_plugin/flutter_live_media_plugin.dart';

import '../../data/models/live_room.dart';
import '../../data/datasources/live_chat_client.dart';
import '../../data/models/live_chat_message.dart';
import '../../../../core/network/api_provider.dart';
import '../../../../core/media/live_engine_provider.dart';
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

class _LiveRoomContent extends ConsumerStatefulWidget {
  const _LiveRoomContent({required this.room});

  final LiveRoom room;

  @override
  ConsumerState<_LiveRoomContent> createState() => _LiveRoomContentState();
}

class _LiveRoomContentState extends ConsumerState<_LiveRoomContent> {
  StreamSubscription<LiveEngineEvent>? _engineSubscription;
  String? _engineStatus;

  @override
  void initState() {
    super.initState();
    _engineSubscription = ref.read(liveEngineProvider).events.listen((event) {
      if (!mounted || event.message == null) return;
      setState(() => _engineStatus = event.message);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepareEngine());
  }

  @override
  void dispose() {
    _engineSubscription?.cancel();
    ref.read(liveEngineProvider).stop();
    super.dispose();
  }

  Future<void> _prepareEngine() async {
    final engine = ref.read(liveEngineProvider);
    await engine.initialize();
    if (!mounted) return;
    if (widget.room.playUrl.isEmpty) {
      setState(() => _engineStatus = '未配置播放地址 · 等待原生播放器接入');
      return;
    }
    await engine.play(widget.room.playUrl);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Stack(
        children: [
          Positioned.fill(child: _PlayerPlaceholder(status: _engineStatus)),
          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: _RoomHeader(room: widget.room),
          ),
          const Positioned(left: 16, bottom: 102, child: _DanmakuList()),
          Positioned(
            left: 16,
            right: 16,
            bottom: 18,
            child: _RoomInputBar(roomId: widget.room.id.toString()),
          ),
        ],
      ),
    );
  }
}

class _PlayerPlaceholder extends StatelessWidget {
  const _PlayerPlaceholder({this.status});

  final String? status;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned(
          left: 24,
          right: 24,
          top: 128,
          bottom: 176,
          child: ClipRRect(
            borderRadius: BorderRadius.all(Radius.circular(16)),
            child: FlutterLiveMediaPlayerView(),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: Center(
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
                    status ?? '媒体引擎抽象层已就绪',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
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

class _RoomInputBar extends ConsumerStatefulWidget {
  const _RoomInputBar({required this.roomId});

  final String roomId;

  @override
  ConsumerState<_RoomInputBar> createState() => _RoomInputBarState();
}

class _RoomInputBarState extends ConsumerState<_RoomInputBar> {
  final _textController = TextEditingController();
  final _chatClient = LiveChatClient();
  StreamSubscription<LiveChatMessage>? _subscription;
  bool _connected = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void dispose() {
    _textController.dispose();
    _subscription?.cancel();
    _chatClient.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final token = await ref.read(tokenStorageProvider).readToken();
    if (!mounted) return;
    if (token == null || token.isEmpty) {
      setState(() => _status = '登录后可发送弹幕');
      return;
    }
    try {
      await _chatClient.connect(widget.roomId, token);
      _subscription = _chatClient.messages.listen((message) {
        if (mounted && message.type == 'error') {
          setState(() => _status = message.message);
        }
      });
      if (mounted) setState(() => _connected = true);
    } catch (_) {
      if (mounted) setState(() => _status = '弹幕连接失败');
    }
  }

  void _send() {
    final message = _textController.text.trim();
    if (!_connected || message.isEmpty) return;
    _chatClient.sendMessage(message);
    _textController.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_status != null)
          Padding(
            padding: const EdgeInsets.only(left: 12, bottom: 5),
            child: Text(
              _status!,
              style: const TextStyle(color: Colors.white60, fontSize: 11),
            ),
          ),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _textController,
                onSubmitted: (_) => _send(),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: '说点什么...',
                  hintStyle: const TextStyle(color: Colors.white60),
                  filled: true,
                  fillColor: Colors.white12,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
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
              onPressed: _send,
              color: Colors.pinkAccent,
              icon: const Icon(Icons.send),
              tooltip: '发送弹幕',
            ),
          ],
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
