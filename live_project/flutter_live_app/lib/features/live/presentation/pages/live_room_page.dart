import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_live_core/flutter_live_core.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/live_room.dart';
import '../../data/datasources/live_chat_client.dart';
import '../../data/models/live_chat_message.dart';
import '../../../../core/network/api_provider.dart';
import '../../../../core/media/live_engine_provider.dart';
import '../controllers/live_room_controller.dart';
import '../controllers/live_list_controller.dart';
import '../widgets/live_danmaku_list.dart';
import '../widgets/live_gift_effect.dart';
import '../widgets/live_gift_sheet.dart';
import '../widgets/live_gift_stats_sheet.dart';
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
      extendBodyBehindAppBar: true,
      resizeToAvoidBottomInset: false,
      //AsyncValue 三态渲染（Riverpod 标准写法）
      body: room.when(
        //加载中
        loading: () =>
            const Center(child: CircularProgressIndicator(color: Colors.white)),
        //加载错误
        error: (error, stackTrace) => _RoomError(
          message: error.toString(),
          onRetry: () => ref.invalidate(liveRoomControllerProvider(roomId)),
        ),
        //拿到完整直播间实体 data，交给业务内容组件 _LiveRoomContent 渲染直播画面、弹幕、聊天、礼物等整套直播间 UI。
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
  final List<LiveChatMessage> _danmaku = [];
  bool _following = false;
  bool _liked = false;
  int _likeCount = 0;
  int _onlineCount = 0;
  int _heartBurstSeed = 0;
  bool _roomEnded = false;
  LiveGiftEvent? _activeGift;

  @override
  void initState() {
    super.initState();
    // 详情接口已经返回当前用户的历史互动状态，页面首帧直接使用它，
    // 避免按钮先显示默认值、随后又发生一次视觉跳变。
    _following = widget.room.following;
    _liked = widget.room.liked;
    _likeCount = widget.room.likeCount;
    _onlineCount = widget.room.onlineCount;
    _enterFullscreenLiveMode();
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
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    super.dispose();
  }

  void _enterFullscreenLiveMode() {
    // 视频层铺到系统栏下面，顶部和底部控件再根据安全区单独定位，确保
    // iOS 真机、iOS 模拟器和 Android 都不会在视频上下留下黑色条带。
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
    );
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

  void _appendDanmaku(LiveChatMessage message) {
    if (!mounted) return;
    setState(() {
      if (message.onlineCount != null) {
        _onlineCount = message.onlineCount!;
      }
      if (_isPublicLiveMessage(message)) {
        _danmaku.add(message);
        // 只限制内存中的历史长度，显示层会用固定高度窗口展示最近几条，
        // 用户仍可向上滚动查看更早的公屏消息。
        if (_danmaku.length > 120) _danmaku.removeAt(0);
      }
      if (message.type == 'gift' && message.gift != null) {
        _activeGift = message.gift;
      }
    });
  }

  void _handleRoomEnded(String message) {
    if (!mounted || _roomEnded) return;
    _roomEnded = true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(milliseconds: 1200),
      ),
    );
    Future<void>.delayed(const Duration(milliseconds: 1200), () async {
      if (!mounted) return;
      // 结束事件到达时，首页可能仍持有进入直播间前的列表快照。先主动
      // 拉取一次最新列表，再返回首页，避免已结束房间还显示“直播中”。
      await ref.read(liveListControllerProvider.notifier).refreshRooms();
      if (mounted) Navigator.of(context).pop(true);
    });
  }

  Future<void> _toggleFollow() async {
    final interaction = await ref
        .read(liveRepositoryProvider)
        .toggleFollow(widget.room.id.toString());
    if (mounted) setState(() => _following = interaction.active);
  }

  Future<void> _toggleLike() async {
    final interaction = await ref
        .read(liveRepositoryProvider)
        .toggleLike(widget.room.id.toString());
    if (mounted) {
      setState(() {
        _liked = interaction.active;
        _likeCount = interaction.count;
      });
    }
  }

  void _handleLike() {
    // 直播间点赞按“每次点击一组漂浮心心”反馈，网络请求仍由原来的
    // toggleLike 负责，动画不等待接口返回，避免弱网时点击没有即时反馈。
    setState(() => _heartBurstSeed++);
    unawaited(_toggleLike());
  }

  @override
  Widget build(BuildContext context) {
    final safePadding = MediaQuery.paddingOf(context);
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final keyboardVisible = keyboardInset > 0;
    return Stack(
      children: [
        // 直播视频铺满整个页面，标题、弹幕和互动栏全部作为透明叠加层，
        // 与短视频式直播间一致，不再被 SafeArea 留出上下黑边。
        const Positioned.fill(child: ColoredBox(color: Colors.black)),
        Positioned.fill(child: LiveRoomPlayer(status: _engineStatus)),
        Positioned(
          top: safePadding.top + 8,
          left: 16,
          right: 16,
          child: _RoomHeader(
            room: widget.room,
            following: _following,
            onlineCount: _onlineCount,
            onFollow: _toggleFollow,
            onOpenAnchorProfile: widget.room.anchorUserId == null
                ? null
                : () => context.push('/feed/users/${widget.room.anchorUserId}'),
          ),
        ),
        Positioned(
          left: 16,
          bottom: keyboardVisible
              ? keyboardInset + 132
              : safePadding.bottom + 92,
          child: LiveDanmakuList(messages: _danmaku),
        ),
        Positioned(
          right: 18,
          bottom: keyboardVisible
              ? keyboardInset + 188
              : safePadding.bottom + 148,
          child: IgnorePointer(
            child: _FloatingHeartOverlay(burstSeed: _heartBurstSeed),
          ),
        ),
        // 礼物层拥有整个直播画面：普通礼物只占局部，高级礼物可以使用
        // 近全屏舞台效果。组件自身 IgnorePointer，不会挡住评论和点赞操作。
        Positioned.fill(child: LiveGiftEffect(gift: _activeGift)),
        AnimatedPositioned(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          left: keyboardVisible ? 0 : 16,
          right: keyboardVisible ? 0 : 16,
          bottom: keyboardVisible ? keyboardInset : safePadding.bottom + 12,
          child: _RoomInputBar(
            roomId: widget.room.id.toString(),
            onMessage: _appendDanmaku,
            onRoomEnded: _handleRoomEnded,
            liked: _liked,
            likeCount: _likeCount,
            onLike: _handleLike,
            keyboardVisible: keyboardVisible,
          ),
        ),
      ],
    );
  }
}

/// 直播间常见的连续点赞反馈：每次点心形按钮生成一小组向上漂浮、
/// 横向散开的心心，结束后自动移除，不会一直占住画面。
class _FloatingHeartOverlay extends StatefulWidget {
  const _FloatingHeartOverlay({required this.burstSeed});

  final int burstSeed;

  @override
  State<_FloatingHeartOverlay> createState() => _FloatingHeartOverlayState();
}

class _FloatingHeartOverlayState extends State<_FloatingHeartOverlay> {
  final List<_FloatingHeart> _hearts = <_FloatingHeart>[];
  int _nextId = 0;

  @override
  void didUpdateWidget(covariant _FloatingHeartOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.burstSeed != oldWidget.burstSeed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _spawnBurst();
      });
    }
  }

  void _spawnBurst() {
    final burst = <_FloatingHeart>[
      _FloatingHeart(
        id: _nextId++,
        horizontalOffset: -22,
        drift: -18,
        size: 30,
        duration: const Duration(milliseconds: 1450),
        color: const Color(0xffff5ca8),
        rotation: -0.12,
      ),
      _FloatingHeart(
        id: _nextId++,
        horizontalOffset: 4,
        drift: 9,
        size: 36,
        duration: const Duration(milliseconds: 1650),
        color: const Color(0xffff3d81),
        rotation: 0.08,
      ),
      _FloatingHeart(
        id: _nextId++,
        horizontalOffset: 26,
        drift: 20,
        size: 25,
        duration: const Duration(milliseconds: 1300),
        color: const Color(0xffff8ac3),
        rotation: 0.16,
      ),
    ];
    setState(() => _hearts.addAll(burst));
  }

  void _removeHeart(int id) {
    if (!mounted) return;
    setState(() => _hearts.removeWhere((heart) => heart.id == id));
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 92,
      height: 260,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          for (final heart in _hearts)
            Positioned(
              left: 46 + heart.horizontalOffset,
              bottom: 0,
              child: TweenAnimationBuilder<double>(
                key: ValueKey<int>(heart.id),
                duration: heart.duration,
                curve: Curves.easeOutCubic,
                tween: Tween<double>(begin: 0, end: 1),
                onEnd: () => _removeHeart(heart.id),
                builder: (context, progress, child) {
                  final opacity = (1 - progress).clamp(0.0, 1.0);
                  return Opacity(
                    opacity: opacity,
                    child: Transform.translate(
                      offset: Offset(heart.drift * progress, -220 * progress),
                      child: Transform.rotate(
                        angle: heart.rotation * (1 - progress),
                        child: Transform.scale(
                          scale: 0.72 + (progress * 0.45),
                          child: child,
                        ),
                      ),
                    ),
                  );
                },
                child: Icon(
                  Icons.favorite_rounded,
                  size: heart.size,
                  color: heart.color,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FloatingHeart {
  const _FloatingHeart({
    required this.id,
    required this.horizontalOffset,
    required this.drift,
    required this.size,
    required this.duration,
    required this.color,
    required this.rotation,
  });

  final int id;
  final double horizontalOffset;
  final double drift;
  final double size;
  final Duration duration;
  final Color color;
  final double rotation;
}

bool _isPublicLiveMessage(LiveChatMessage message) =>
    message.type == 'chat' ||
    message.type == 'presence' ||
    message.type == 'system' ||
    message.type == 'gift';

class _RoomHeader extends StatelessWidget {
  const _RoomHeader({
    required this.room,
    required this.following,
    required this.onlineCount,
    required this.onFollow,
    this.onOpenAnchorProfile,
  });

  final LiveRoom room;
  final bool following;
  final int onlineCount;
  final VoidCallback onFollow;
  final VoidCallback? onOpenAnchorProfile;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        InkWell(
          onTap: onOpenAnchorProfile,
          borderRadius: BorderRadius.circular(24),
          child: CircleAvatar(
            backgroundColor: Colors.white24,
            child: Text(
              room.anchorName.isEmpty ? '?' : room.anchorName[0],
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: InkWell(
            onTap: onOpenAnchorProfile,
            borderRadius: BorderRadius.circular(8),
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
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.25),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  ),
                  child: Text(
                    '$onlineCount 人在线',
                    key: ValueKey<int>(onlineCount),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
        OutlinedButton(
          onPressed: onFollow,
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: const BorderSide(color: Colors.white70),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            minimumSize: const Size(0, 36),
          ),
          child: Text(following ? '已关注' : '关注'),
        ),
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

class _RoomInputBar extends ConsumerStatefulWidget {
  const _RoomInputBar({
    required this.roomId,
    required this.onMessage,
    required this.onRoomEnded,
    required this.liked,
    required this.likeCount,
    required this.onLike,
    required this.keyboardVisible,
  });

  final String roomId;
  final ValueChanged<LiveChatMessage> onMessage;
  final ValueChanged<String> onRoomEnded;
  final bool liked;
  final int likeCount;
  final VoidCallback onLike;
  final bool keyboardVisible;

  @override
  ConsumerState<_RoomInputBar> createState() => _RoomInputBarState();
}

class _RoomInputBarState extends ConsumerState<_RoomInputBar> {
  final _textController = TextEditingController();
  final _inputFocusNode = FocusNode();
  final _chatClient = LiveChatClient();
  StreamSubscription<LiveChatMessage>? _subscription;
  StreamSubscription<LiveChatConnectionState>? _stateSubscription;
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
    _inputFocusNode.dispose();
    _subscription?.cancel();
    _stateSubscription?.cancel();
    unawaited(_chatClient.dispose());
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
    _subscription = _chatClient.messages.listen((message) {
      widget.onMessage(message);
      if (message.type == 'system' && message.event == 'room_ended') {
        widget.onRoomEnded(message.message);
      }
      if (mounted && message.type == 'error') {
        setState(() => _status = message.message);
      }
    });
    _stateSubscription = _chatClient.states.listen((state) {
      if (!mounted) return;
      setState(() {
        _connected = state == LiveChatConnectionState.connected;
        _status = switch (state) {
          LiveChatConnectionState.connecting => '弹幕连接中…',
          LiveChatConnectionState.reconnecting => '弹幕重连中…',
          LiveChatConnectionState.disconnected => '弹幕已断开',
          LiveChatConnectionState.connected => null,
        };
      });
    });
    try {
      await _chatClient.connect(widget.roomId, token);
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
    final isKeyboardVisible = widget.keyboardVisible;
    final textColor = isKeyboardVisible ? Colors.black87 : Colors.white;
    final hintColor = isKeyboardVisible ? Colors.black38 : Colors.white60;

    return Material(
      color: isKeyboardVisible ? Colors.white : Colors.transparent,
      elevation: isKeyboardVisible ? 8 : 0,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          isKeyboardVisible ? 16 : 0,
          isKeyboardVisible ? 10 : 0,
          isKeyboardVisible ? 16 : 0,
          isKeyboardVisible ? 8 : 0,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_status != null)
              Padding(
                padding: const EdgeInsets.only(left: 12, bottom: 5),
                child: Text(
                  _status!,
                  style: TextStyle(
                    color: isKeyboardVisible ? Colors.black45 : Colors.white60,
                    fontSize: 11,
                  ),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    focusNode: _inputFocusNode,
                    onSubmitted: (_) => _send(),
                    textInputAction: TextInputAction.send,
                    style: TextStyle(color: textColor),
                    decoration: InputDecoration(
                      hintText: '说点什么...',
                      hintStyle: TextStyle(color: hintColor),
                      filled: true,
                      fillColor: isKeyboardVisible
                          ? Colors.black.withValues(alpha: 0.06)
                          : Colors.white12,
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
                if (isKeyboardVisible) ...[
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: _send,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.pinkAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      minimumSize: const Size(0, 44),
                    ),
                    child: const Text('发送'),
                  ),
                ] else ...[
                  IconButton(
                    onPressed: _openGiftSheet,
                    color: Colors.white,
                    icon: const Icon(Icons.card_giftcard),
                    tooltip: '送礼物',
                  ),
                  IconButton(
                    onPressed: () => _showAction('直播间链接已准备分享'),
                    color: Colors.white,
                    icon: const Icon(Icons.ios_share_outlined),
                    tooltip: '分享直播间',
                  ),
                  IconButton(
                    onPressed: _openGiftStats,
                    color: Colors.white,
                    icon: const Icon(Icons.emoji_events_outlined),
                    tooltip: '礼物榜单',
                  ),
                  IconButton(
                    onPressed: widget.onLike,
                    color: widget.liked ? Colors.pinkAccent : Colors.white,
                    icon: const Icon(Icons.favorite),
                    tooltip: '点赞 ${widget.likeCount}',
                  ),
                  IconButton(
                    onPressed: _send,
                    color: Colors.pinkAccent,
                    icon: const Icon(Icons.send),
                    tooltip: '发送弹幕',
                  ),
                ],
              ],
            ),
            if (isKeyboardVisible) ...[
              const SizedBox(height: 6),
              SizedBox(
                height: 38,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _QuickChatAction(
                      label: '😂',
                      onTap: () => _insertQuickText('😂'),
                    ),
                    _QuickChatAction(
                      label: '❤️',
                      onTap: () => _insertQuickText('❤️'),
                    ),
                    _QuickChatAction(
                      label: '👏',
                      onTap: () => _insertQuickText('👏'),
                    ),
                    _QuickChatAction(
                      icon: Icons.alternate_email,
                      onTap: () => _insertQuickText('@'),
                    ),
                    _QuickChatAction(
                      icon: Icons.mic_none,
                      onTap: () => _showAction('语音功能即将开放'),
                    ),
                    _QuickChatAction(
                      icon: Icons.emoji_emotions_outlined,
                      onTap: _showEmojiKeyboard,
                    ),
                    _QuickChatAction(
                      icon: Icons.add_circle_outline,
                      onTap: () => _showAction('更多互动功能即将开放'),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _insertQuickText(String value) {
    final text = _textController.text;
    final selection = _textController.selection;
    final start = selection.isValid ? selection.start : text.length;
    final end = selection.isValid ? selection.end : text.length;
    _textController.value = TextEditingValue(
      text: text.replaceRange(start, end, value),
      selection: TextSelection.collapsed(offset: start + value.length),
    );
  }

  Future<void> _showEmojiKeyboard() async {
    // 先收起系统键盘，再打开独立的表情面板，避免两个面板同时争夺底部空间。
    FocusScope.of(context).unfocus();
    final selected = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (context) => const _EmojiKeyboard(),
    );
    if (!mounted) return;
    if (selected != null) {
      _insertQuickText(selected);
      _inputFocusNode.requestFocus();
    }
  }

  void _showAction(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(milliseconds: 900),
        ),
      );
  }

  Future<void> _openGiftSheet() async {
    final receipt = await showLiveGiftSheet(context, roomId: widget.roomId);
    if (!mounted || receipt == null) return;
    _showAction('已送出 ${receipt.giftName} × ${receipt.quantity}');
  }

  Future<void> _openGiftStats() =>
      showLiveGiftStatsSheet(context, roomId: widget.roomId);
}

class _QuickChatAction extends StatelessWidget {
  const _QuickChatAction({this.label, this.icon, required this.onTap});

  final String? label;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 22,
      child: SizedBox(
        width: 38,
        height: 38,
        child: Center(
          child: label != null
              ? Text(label!, style: const TextStyle(fontSize: 24))
              : Icon(icon, color: Colors.black87, size: 25),
        ),
      ),
    );
  }
}

class _EmojiKeyboard extends StatelessWidget {
  const _EmojiKeyboard();

  static const _emojis = <String>[
    '😀',
    '😂',
    '🤣',
    '😊',
    '😍',
    '🥰',
    '😘',
    '😎',
    '🤔',
    '😮',
    '😭',
    '😡',
    '👏',
    '🙌',
    '👍',
    '👎',
    '❤️',
    '🧡',
    '💛',
    '💚',
    '💙',
    '💜',
    '💖',
    '💯',
    '🔥',
    '🎉',
    '🎁',
    '🌹',
    '✨',
    '💔',
    '🙏',
    '👋',
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 300,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              '表情',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 8,
                childAspectRatio: 1.25,
              ),
              itemCount: _emojis.length,
              itemBuilder: (context, index) {
                final emoji = _emojis[index];
                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.of(context).pop(emoji),
                  child: Center(
                    child: Text(emoji, style: const TextStyle(fontSize: 25)),
                  ),
                );
              },
            ),
          ),
        ],
      ),
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
