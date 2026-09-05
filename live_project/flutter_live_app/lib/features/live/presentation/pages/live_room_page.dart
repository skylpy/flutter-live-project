import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_live_core/flutter_live_core.dart';

import '../../data/models/live_room.dart';
import '../../data/datasources/live_chat_client.dart';
import '../../data/models/live_chat_message.dart';
import '../../../../core/network/api_provider.dart';
import '../../../../core/media/live_engine_provider.dart';
import '../controllers/live_room_controller.dart';
import '../widgets/live_room_player.dart';

/// 全屏直播间页面。
///
/// 页面同时展示三类内容：原生播放器视图、Flutter 叠加层（主播信息/弹幕/操作栏）
/// 和实时通道状态。三者分开后，替换播放器或 IM 实现不会影响布局。
class LiveRoomPage extends ConsumerWidget {
  const LiveRoomPage({required this.roomId, super.key});

  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 先按 roomId 请求详情，避免页面只依赖首页传来的旧快照。
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
  late final LiveEngine _engine;
  StreamSubscription<LiveEngineEvent>? _engineSubscription;
  String? _engineStatus;

  @override
  void initState() {
    super.initState();
    // 监听平台无关的 LiveEngineEvent，页面不直接认识 AVPlayer/ExoPlayer。
    _engine = ref.read(liveEngineProvider);
    _engineSubscription = _engine.events.listen((event) {
      if (!mounted || event.message == null) return;
      setState(() => _engineStatus = event.message);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _prepareEngine());
  }

  @override
  void dispose() {
    // 先取消事件订阅，再停止播放器，确保离开页面后没有异步回调更新已销毁 UI。
    _engineSubscription?.cancel();
    // dispose 阶段不能再通过 ref 查找 Provider；_engine 是 initState 中保存的
    // 同一个实例，既避免 Riverpod 生命周期断言，也保证停止的是当前播放器。
    unawaited(_engine.stop());
    super.dispose();
  }

  Future<void> _prepareEngine() async {
    // 初始化和播放请求放在首帧之后，避免在 Widget 尚未挂载完成时创建 PlatformView。
    await _engine.initialize();
    if (!mounted) return;
    if (widget.room.playUrl.isEmpty) {
      setState(() => _engineStatus = '未配置播放地址 · 等待原生播放器接入');
      return;
    }
    await _engine.play(widget.room.playUrl);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Stack(
        children: [
          Positioned.fill(child: LiveRoomPlayer(status: _engineStatus)),
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
  // 当前使用固定演示数据，后续可以替换为 WebSocket 消息列表。
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
    // 只有登录用户才建立弹幕连接；播放器播放和弹幕权限彼此独立。
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
    // 发送前在客户端做最基本的空值检查，服务端仍会再次校验长度和权限。
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

/// 直播间详情加载失败时的错误状态和重试入口。
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
